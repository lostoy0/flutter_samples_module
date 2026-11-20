import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'bridge.dart';
import 'hybrid_router.dart';

const _formatText = BridgeMethod<String, String>(
  'demo.formatText',
  stringValue,
  stringValue,
);
const _deviceInfo = BridgeMethod<String, Map<String, Object?>>(
  'device.getInfo',
  stringValue,
  mapValue,
);
const _greet = BridgeMethod<String, String>(
  'device.greet',
  stringValue,
  stringValue,
);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final initialRoute =
      WidgetsBinding.instance.platformDispatcher.defaultRouteName;
  runApp(MyApp(initialRoute: initialRoute));
}

class MyApp extends StatefulWidget {
  const MyApp({super.key, this.initialRoute = '/'});

  final String initialRoute;

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final _navigator = GlobalKey<NavigatorState>();
  BridgeClient? _bridge;
  HybridRouter? _router;

  @override
  void initState() {
    super.initState();
    if (widget.initialRoute == '/') return;
    final bridge = BridgeClient(
      BridgeRegistry([
        BridgePlugin([
          _formatText.bind((value) => 'Dart: ${value.toUpperCase()}'),
        ]),
      ]),
    );
    bridge.onMessage = (payload) => {
      'echo': 'Dart: ${stringValue(payload['text'])}',
    };
    bridge.onBack = () async =>
        await _navigator.currentState?.maybePop() ?? false;
    _bridge = bridge;
    _router = HybridRouter(bridge, _navigator);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await bridge.markUiReady();
      } catch (error) {
        debugPrint('Hybrid bridge handshake: ${_error(error)}');
      }
    });
  }

  @override
  void dispose() {
    _bridge?.close();
    super.dispose();
  }

  Route<void> _route(RouteSettings settings) {
    final uri = Uri.tryParse(settings.name ?? '/');
    Widget page = const Scaffold(body: Center(child: Text('找不到页面')));
    if (uri != null && uri.path == '/' && _router == null) {
      page = const SamplePage(title: 'Flutter Demo', buttons: []);
    } else if (uri != null &&
        uri.scheme == 'samples' &&
        uri.host == 'flutter' &&
        _router != null) {
      final router = _router!;
      final parts = uri.pathSegments;
      if (uri.path == '/tab') {
        page = SamplePage(
          title: 'Flutter 首页',
          buttons: [
            (
              '在 Tab 内打开 Flutter 详情',
              () => router.open(_url('flutter', ['detail', '42'], 'Tab 内详情')),
            ),
            (
              '从 Tab 打开原生详情',
              () =>
                  router.open(_url('native', ['demo', '42'], '来自 Flutter Tab')),
            ),
            (
              '打开桥接通信示例',
              () => router.open(_url('flutter', ['communications'])),
            ),
          ],
        );
      } else if (parts.length == 2 && parts.first == 'detail') {
        final id = int.tryParse(parts.last);
        if (id != null && id > 0 && id <= 2147483647) {
          page = SamplePage(
            title: 'Flutter 详情',
            details: 'ID $id：${uri.queryParameters['title'] ?? ''}',
            allowHostBack: widget.initialRoute != 'samples://flutter/tab',
            buttons: [
              (
                '打开原生详情',
                () => router.open(
                  _url('native', ['demo', '$id'], '来自 Flutter 中+&/'),
                ),
              ),
              if (id < 2147483647)
                (
                  '打开 Flutter 子页',
                  () => router.open(
                    _url('flutter', ['detail', '${id + 1}'], 'Flutter 子页'),
                  ),
                ),
              (
                '打开桥接通信示例',
                () => router.open(_url('flutter', ['communications'])),
              ),
            ],
          );
        }
      } else if (uri.path == '/communications') {
        page = CommunicationsPage(
          bridge: _bridge!,
          allowHostBack: widget.initialRoute != 'samples://flutter/tab',
        );
      }
    }
    return MaterialPageRoute<void>(settings: settings, builder: (_) => page);
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData(colorSchemeSeed: Colors.indigo),
    restorationScopeId: 'android-samples',
    navigatorKey: _navigator,
    initialRoute: widget.initialRoute,
    onGenerateInitialRoutes: (route) => [_route(RouteSettings(name: route))],
    onGenerateRoute: _route,
  );
}

String _url(String host, List<String> path, [String? title]) => Uri(
  scheme: 'samples',
  host: host,
  pathSegments: path,
  queryParameters: title == null ? null : {'title': title},
).toString();

Widget? _backButton(BuildContext context, bool allowHostBack) {
  if (Navigator.canPop(context)) return const BackButton();
  if (allowHostBack) return BackButton(onPressed: SystemNavigator.pop);
  return null;
}

class SamplePage extends StatefulWidget {
  const SamplePage({
    super.key,
    required this.title,
    required this.buttons,
    this.details,
    this.allowHostBack = false,
  });

  final String title;
  final String? details;
  final bool allowHostBack;
  final List<(String, Future<void> Function())> buttons;

  @override
  State<SamplePage> createState() => _SamplePageState();
}

class _SamplePageState extends State<SamplePage> with RestorationMixin {
  final _counter = RestorableInt(0);
  bool _routing = false;

  @override
  String get restorationId => 'sample-page';

  @override
  void restoreState(RestorationBucket? oldBucket, bool initialRestore) =>
      registerForRestoration(_counter, 'counter');

  @override
  void dispose() {
    _counter.dispose();
    super.dispose();
  }

  Future<void> _open(Future<void> Function() route) async {
    if (_routing) return;
    setState(() => _routing = true);
    try {
      await route();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_error(error))));
      }
    } finally {
      if (mounted) setState(() => _routing = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.title),
      leading: _backButton(context, widget.allowHostBack),
    ),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        if (widget.details != null) Text(widget.details!),
        Text(
          '${_counter.value}',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 12),
        for (final (label, route) in widget.buttons)
          OutlinedButton(
            onPressed: _routing ? null : () => _open(route),
            child: Text(label),
          ),
      ],
    ),
    floatingActionButton: FloatingActionButton(
      tooltip: 'Increment',
      onPressed: () => setState(() => _counter.value++),
      child: const Icon(Icons.add),
    ),
  );
}

class CommunicationsPage extends StatefulWidget {
  const CommunicationsPage({
    super.key,
    required this.bridge,
    required this.allowHostBack,
  });

  final BridgeClient bridge;
  final bool allowHostBack;

  @override
  State<CommunicationsPage> createState() => _CommunicationsPageState();
}

class _CommunicationsPageState extends State<CommunicationsPage> {
  final _text = TextEditingController(text: 'Flutter');
  StreamSubscription<Map<String, Object?>>? _subscription;
  String _rpc = '';
  String _message = '';
  String _event = '';
  bool _calling = false;
  bool _sending = false;

  Future<void> _readDevice() async {
    setState(() => _calling = true);
    try {
      final info = await widget.bridge.invoke(_deviceInfo, _text.text);
      final greeting = await widget.bridge.invoke(_greet, _text.text);
      if (mounted) {
        setState(
          () => _rpc = '$greeting · ${info['model']} · API ${info['sdk']}',
        );
      }
    } catch (error) {
      if (mounted) setState(() => _rpc = _error(error));
    } finally {
      if (mounted) setState(() => _calling = false);
    }
  }

  Future<void> _send() async {
    setState(() => _sending = true);
    try {
      final reply = await widget.bridge.send({'text': _text.text});
      if (mounted) setState(() => _message = stringValue(reply['echo']));
    } catch (error) {
      if (mounted) setState(() => _message = _error(error));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _toggleEvents() async {
    final current = _subscription;
    if (current != null) {
      setState(() {
        _subscription = null;
        _event = '已取消';
      });
      await current.cancel();
      return;
    }
    setState(() {
      _event = '等待事件';
      _subscription = widget.bridge.events.listen(
        (event) {
          if (mounted) setState(() => _event = "Tick ${event['tick']}");
        },
        onError: (Object error) {
          if (mounted) setState(() => _event = _error(error));
        },
        onDone: () {
          if (mounted) setState(() => _subscription = null);
        },
      );
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('桥接通信'),
      leading: _backButton(context, widget.allowHostBack),
    ),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        TextField(
          controller: _text,
          decoration: const InputDecoration(labelText: '消息内容'),
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: _calling ? null : _readDevice,
          child: const Text('调用 Android 方法'),
        ),
        if (_rpc.isNotEmpty) Text(_rpc),
        OutlinedButton(
          onPressed: _sending ? null : _send,
          child: const Text('发送消息给 Android'),
        ),
        if (_message.isNotEmpty) Text(_message),
        OutlinedButton(
          onPressed: _toggleEvents,
          child: Text(_subscription == null ? '订阅 Native 计时' : '取消订阅'),
        ),
        if (_event.isNotEmpty) Text(_event),
      ],
    ),
  );
}

String _error(Object error) => switch (error) {
  PlatformException(:final code, :final message) =>
    message == null ? code : '$code · $message',
  MissingPluginException() => '方法未注册',
  _ => error.toString(),
};
