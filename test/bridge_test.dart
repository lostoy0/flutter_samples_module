import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_samples_module/bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final method = BridgeMethod<String, String>(
    'demo.echo',
    stringValue,
    stringValue,
  );
  test('duplicate methods are rejected during registry construction', () {
    final plugin = BridgePlugin([(method.bind((value) async => value))]);
    expect(() => BridgeRegistry([plugin, plugin]), throwsArgumentError);
  });

  test(
    'registered methods decode arguments and report unknown methods',
    () async {
      final registry = BridgeRegistry([
        BridgePlugin([method.bind((value) async => 'echo: $value')]),
      ]);
      expect(await registry.dispatch(method.name, 'hello'), 'echo: hello');
      await expectLater(
        registry.dispatch(method.name, 1),
        throwsA(
          isA<PlatformException>().having(
            (e) => e.code,
            'code',
            'invalid_argument',
          ),
        ),
      );
      await expectLater(
        registry.dispatch('missing.method', null),
        throwsA(isA<MissingPluginException>()),
      );
    },
  );

  const rpc = MethodChannel('android_samples/bridge/v1/rpc');
  const control = MethodChannel('android_samples/bridge/v1/control');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  Future<void> attach(BridgeClient client) async {
    messenger.setMockMethodCallHandler(control, (call) async {
      expect(call.method, 'ready');
      return true;
    });
    await client.markUiReady();
  }

  Matcher hasCode(String code) =>
      isA<PlatformException>().having((e) => e.code, 'code', code);

  test('client gates calls until handshake and decodes replies', () async {
    final client = BridgeClient(BridgeRegistry([]));
    addTearDown(client.close);
    messenger.setMockMethodCallHandler(rpc, (call) async {
      expect(call.method, method.name);
      expect(call.arguments, 'hello');
      return 'echo: hello';
    });
    await expectLater(
      client.invoke(method, 'hello'),
      throwsA(hasCode('not_ready')),
    );
    await attach(client);
    expect(await client.invoke(method, 'hello'), 'echo: hello');
  });

  test('client times out if the peer remains silent', () async {
    final client = BridgeClient(
      BridgeRegistry([]),
      timeout: const Duration(milliseconds: 20),
    );
    addTearDown(client.close);
    final reply = Completer<String>();
    addTearDown(() => reply.complete('late'));
    messenger.setMockMethodCallHandler(rpc, (_) => reply.future);
    await attach(client);
    await expectLater(
      client.invoke(method, 'hello'),
      throwsA(hasCode('timeout')),
    );
  });

  test('closing the client rejects calls already in flight', () async {
    final client = BridgeClient(BridgeRegistry([]));
    final reply = Completer<String>();
    addTearDown(() => reply.complete('late'));
    messenger.setMockMethodCallHandler(rpc, (_) => reply.future);
    await attach(client);
    final check = expectLater(
      client.invoke(method, 'hello'),
      throwsA(hasCode('closed')),
    );
    client.close();
    await check;
  });

  test('handshake can retry after a native reply is lost', () async {
    final client = BridgeClient(
      BridgeRegistry([]),
      timeout: const Duration(milliseconds: 20),
    );
    addTearDown(client.close);
    final reply = Completer<bool>();
    addTearDown(() => reply.complete(true));
    messenger.setMockMethodCallHandler(control, (_) => reply.future);
    await expectLater(client.markUiReady(), throwsA(hasCode('timeout')));
    await attach(client);
  });

  test(
    'closing during startup rejects calls waiting for the handshake',
    () async {
      final client = BridgeClient(BridgeRegistry([]));
      final reply = Completer<bool>();
      addTearDown(() => reply.complete(true));
      messenger.setMockMethodCallHandler(control, (_) => reply.future);
      final connecting = expectLater(
        client.markUiReady(),
        throwsA(hasCode('closed')),
      );
      final invoking = expectLater(
        client.invoke(method, 'hello'),
        throwsA(hasCode('closed')),
      );
      client.close();
      await Future.wait([
        connecting,
        invoking,
      ]).timeout(const Duration(milliseconds: 100));
    },
  );
}
