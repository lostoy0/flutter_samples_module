import 'dart:async';

import 'package:flutter/services.dart';

typedef Decoder<T> = T Function(Object?);
typedef Encoder<T> = Object? Function(T);

String stringValue(Object? value) {
  if (value is String) return value;
  throw const FormatException('Expected a string');
}

Map<String, Object?> mapValue(Object? value) {
  if (value is Map && value.keys.every((key) => key is String)) {
    return Map<String, Object?>.from(value);
  }
  throw const FormatException('Expected a map with string keys');
}

T _decode<T>(Decoder<T> decoder, Object? value, String code) {
  try {
    return decoder(value);
  } on FormatException catch (error) {
    throw PlatformException(code: code, message: error.message);
  }
}

class BridgeMethod<A, R> {
  const BridgeMethod(
    this.name,
    this.decodeArgs,
    this.decodeResult, {
    this.encodeArgs,
    this.encodeResult,
  });

  final String name;
  final Decoder<A> decodeArgs;
  final Decoder<R> decodeResult;
  final Encoder<A>? encodeArgs;
  final Encoder<R>? encodeResult;

  BridgeBinding bind(FutureOr<R> Function(A) handler) =>
      BridgeBinding(name, (payload) async {
        final result = await handler(
          _decode(decodeArgs, payload, 'invalid_argument'),
        );
        final encode = encodeResult;
        return encode == null ? result : encode(result);
      });
}

class BridgeBinding {
  const BridgeBinding(this.name, this.handle);

  final String name;
  final Future<Object?> Function(Object?) handle;
}

class BridgePlugin {
  const BridgePlugin(this.methods);

  final List<BridgeBinding> methods;
}

class BridgeRegistry {
  BridgeRegistry(Iterable<BridgePlugin> plugins) {
    for (final plugin in plugins) {
      for (final method in plugin.methods) {
        if (_methods.containsKey(method.name)) {
          throw ArgumentError('Duplicate bridge method: ${method.name}');
        }
        _methods[method.name] = method;
      }
    }
  }

  final _methods = <String, BridgeBinding>{};

  Future<Object?> dispatch(String name, Object? arguments) async {
    final method = _methods[name];
    if (method == null) throw MissingPluginException(name);
    return method.handle(arguments);
  }
}

class BridgeClient {
  BridgeClient(
    BridgeRegistry registry, {
    this.timeout = const Duration(seconds: 5),
  }) {
    _control.setMethodCallHandler((call) async {
      if (call.method != 'back') throw MissingPluginException(call.method);
      _requireConnection();
      return onBack?.call() ?? false;
    });
    _rpc.setMethodCallHandler((call) {
      _requireConnection();
      return _withTimeout(registry.dispatch(call.method, call.arguments));
    });
    _messages.setMessageHandler((payload) async {
      try {
        _requireConnection();
        final handler = onMessage;
        if (handler == null) throw PlatformException(code: 'not_implemented');
        final reply = await _withTimeout(
          Future.sync(() => handler(mapValue(payload))),
        );
        return {'value': reply};
      } on PlatformException catch (error) {
        return {'error': error.code, 'message': error.message};
      } on FormatException catch (error) {
        return {'error': 'invalid_argument', 'message': error.message};
      } catch (_) {
        return {'error': 'handler_error'};
      }
    });
  }

  static const _prefix = 'android_samples/bridge/v1';
  static const _control = MethodChannel('$_prefix/control');
  static const _rpc = MethodChannel('$_prefix/rpc');
  static const _messages = BasicMessageChannel<Object?>(
    '$_prefix/message',
    StandardMessageCodec(),
  );
  static const _events = EventChannel('$_prefix/events');

  final Duration timeout;
  Future<void>? _connection;
  final _pending = <Completer<Object?>>{};
  bool _rendered = false;
  bool _connected = false;
  bool _closed = false;

  FutureOr<Map<String, Object?>> Function(Map<String, Object?>)? onMessage;
  Future<bool> Function()? onBack;

  Future<void> markUiReady() async {
    if (_closed) throw PlatformException(code: 'closed');
    if (_connected) return;
    _rendered = true;
    final attempt = _connection ??= _connect();
    try {
      await attempt;
    } finally {
      if (identical(_connection, attempt)) _connection = null;
    }
  }

  Future<void> _connect() async {
    final accepted = await _track(() => _control.invokeMethod<bool>('ready'));
    if (_closed) throw PlatformException(code: 'closed');
    if (accepted != true) throw PlatformException(code: 'not_ready');
    _connected = true;
  }

  void _requireConnection() {
    if (_closed) throw PlatformException(code: 'closed');
    if (!_connected) throw PlatformException(code: 'not_ready');
  }

  Future<T> _withTimeout<T>(Future<T> operation) => operation.timeout(
    timeout,
    onTimeout: () => throw PlatformException(code: 'timeout'),
  );

  Future<Object?> _request(Future<Object?> Function() operation) async {
    if (_rendered && !_connected) await markUiReady();
    _requireConnection();
    return _track(operation);
  }

  Future<Object?> _track(Future<Object?> Function() operation) async {
    final reply = Completer<Object?>();
    _pending.add(reply);
    try {
      return await _withTimeout(
        Future.any([Future.sync(operation), reply.future]),
      );
    } finally {
      _pending.remove(reply);
    }
  }

  Future<R> invoke<A, R>(BridgeMethod<A, R> method, A args) async {
    final encode = method.encodeArgs;
    final result = await _request(
      () => _rpc.invokeMethod<Object?>(
        method.name,
        encode == null ? args : encode(args),
      ),
    );
    return _decode(method.decodeResult, result, 'invalid_result');
  }

  Future<String> openRoute(String url) async => _decode(
    stringValue,
    await _request(() => _control.invokeMethod<Object?>('openRoute', url)),
    'invalid_result',
  );

  Future<Map<String, Object?>> send(Map<String, Object?> payload) async {
    final reply = _decode(
      mapValue,
      await _request(() => _messages.send(payload)),
      'invalid_result',
    );
    final error = reply['error'];
    if (error is String) {
      throw PlatformException(
        code: error,
        message: reply['message']?.toString(),
      );
    }
    return _decode(mapValue, reply['value'], 'invalid_result');
  }

  late final Stream<Map<String, Object?>> events = _events
      .receiveBroadcastStream()
      .map((value) => _decode(mapValue, value, 'invalid_result'));

  void close() {
    if (_closed) return;
    _closed = true;
    _control.setMethodCallHandler(null);
    _rpc.setMethodCallHandler(null);
    _messages.setMessageHandler(null);
    onMessage = null;
    onBack = null;
    for (final call in _pending) {
      call.completeError(PlatformException(code: 'closed'));
    }
    _pending.clear();
  }
}
