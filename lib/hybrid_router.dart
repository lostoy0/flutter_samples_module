import 'package:flutter/widgets.dart';

import 'bridge.dart';

class HybridRouter {
  HybridRouter(this.bridge, this.navigator);

  final BridgeClient bridge;
  final GlobalKey<NavigatorState> navigator;

  Future<void> open(String url) async {
    final localRoute = await bridge.openRoute(url);
    if (localRoute.isEmpty) return;
    final state = navigator.currentState;
    if (state == null) throw StateError('Flutter navigator is not mounted');
    state.restorablePushNamed<void>(localRoute);
  }
}
