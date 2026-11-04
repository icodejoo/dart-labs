import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/state/state.dart';
import '../guard/guard_scope.dart';
import '../snapshot_guard.dart';
import '../style/style.dart';
import 'ownership.dart';

/// 包内：把现有全屏状态映射成一个借用同一 API 的路由。
class MovaFullscreenHost extends StatefulWidget {
  const MovaFullscreenHost({
    super.key,
    required this.api,
    required this.fullscreen,
    required this.onExit,
    required this.child,
  });

  final MovaApi api;
  final Widget fullscreen;
  final VoidCallback onExit;
  final Widget child;

  @override
  State<MovaFullscreenHost> createState() => _MovaFullscreenHostState();
}

class _MovaFullscreenHostState extends State<MovaFullscreenHost> {
  StreamSubscription<MovaState>? _subscription;
  Route<void>? _route;
  bool _scheduled = false;
  // 路由持有宿主媒体组件期间，内联侧让出，直到退出动画完成。
  bool _yieldInline = false;
  String _unlock = '';
  late final ValueNotifier<Widget> _content = ValueNotifier(widget.fullscreen);

  @override
  void initState() {
    super.initState();
    _listen();
  }

  void _listen() {
    _subscription = widget.api.states.listen((_) => _schedule());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _schedule();
  }

  @override
  void didUpdateWidget(MovaFullscreenHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.api, widget.api)) {
      unawaited(_subscription?.cancel());
      final owned = _route != null;
      _close(oldWidget.api, notify: false, deferred: true);
      if (owned && oldWidget.api.state.fullscreen) {
        unawaited(oldWidget.api.setFullscreen(false));
      }
      _listen();
    }
    _schedule();
  }

  void _schedule() {
    if (_scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!mounted) return;
      _content.value = widget.fullscreen;
      _unlock = MovaPlayerStyle.stringsOf(context).unlock;
      final state = widget.api.state;
      if (!state.fullscreen || state.pip || state.mini) {
        _close(widget.api);
      } else if (_route == null &&
          movaFullscreenRoutes[widget.api] == null &&
          (ModalRoute.isCurrentOf(context) ?? true)) {
        _open();
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _open() {
    final api = widget.api;
    final navigator = Navigator.of(context, rootNavigator: true);
    final guard = context.getInheritedWidgetOfExactType<MovaGuardScope>();
    Widget page = ValueListenableBuilder<Widget>(
      valueListenable: _content,
      builder: (context, child, _) => child,
    );
    if (guard != null) {
      page = MovaGuardScope(api: guard.api, parent: guard.parent, child: page);
    }
    page = InheritedTheme.captureAll(context, page);
    final content = page;
    final route = PageRouteBuilder<void>(
      settings: const RouteSettings(name: 'mova/fullscreen'),
      // 保留内联视图 ticker；自己的路由遮挡由 ownership 标记豁免。
      opaque: false,
      pageBuilder: (context, animation, secondaryAnimation) =>
          MovaSnapshotGuard(
            enabled: movaSnapshotGuardNeeded(),
            child: Scaffold(
              backgroundColor: Colors.black,
              body: Builder(
                builder: (scaffoldContext) => PopScope<void>(
                  canPop: false,
                  onPopInvokedWithResult: (didPop, result) {
                    if (didPop) return;
                    if (api.state.locked) {
                      ScaffoldMessenger.of(
                        scaffoldContext,
                      ).showSnackBar(SnackBar(content: Text(_unlock)));
                      return;
                    }
                    unawaited(api.setFullscreen(false));
                  },
                  child: content,
                ),
              ),
            ),
          ),
    );
    setState(() => _yieldInline = true);
    unawaited(route.completed.then((_) {
      if (mounted && _route == null) setState(() => _yieldInline = false);
    }));
    _route = route;
    movaFullscreenRoutes[api] = route;
    unawaited(
      navigator.push(route).then((_) {
        if (!identical(_route, route)) return;
        _route = null;
        movaFullscreenRoutes[api] = null;
        if (api.state.fullscreen) unawaited(api.setFullscreen(false));
        if (mounted) widget.onExit();
      }),
    );
  }

  void _close(MovaApi api, {bool notify = true, bool deferred = false}) {
    final route = _route;
    if (route == null) return;
    _route = null;
    movaFullscreenRoutes[api] = null;
    final navigator = route.navigator;
    void remove() {
      if (navigator != null && navigator.mounted && route.isActive) {
        if (route.isCurrent && !deferred) {
          navigator.pop();
        } else {
          navigator.removeRoute(route);
        }
      }
    }

    if (deferred) {
      WidgetsBinding.instance.addPostFrameCallback((_) => remove());
    } else {
      remove();
    }
    if (notify && mounted) widget.onExit();
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    final owned = _route != null;
    _close(widget.api, notify: false, deferred: true);
    if (owned && widget.api.state.fullscreen) {
      unawaited(widget.api.setFullscreen(false));
    }
    _content.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MovaSnapshotGuard(
    enabled: movaSnapshotGuardNeeded(),
    child: _yieldInline ? const SizedBox.expand() : widget.child,
  );
}
