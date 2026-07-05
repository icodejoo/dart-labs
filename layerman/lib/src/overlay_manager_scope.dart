import 'package:flutter/widgets.dart';

import 'overlay_manager.dart';

/// Wires an [OverlayManager] to a dedicated [Overlay] layer that sits above
/// [child], and exposes the manager to descendants via [OverlayManagerScope.of].
///
/// Mount it once near the app root (e.g. as `MaterialApp.builder`'s result, or
/// as `home`). Because it owns its own [Overlay], managed overlays render in a
/// layer that is independent of the [Navigator]'s route stack.
///
/// ```dart
/// final manager = OverlayManager(gap: Duration(milliseconds: 300));
///
/// MaterialApp(
///   builder: (context, child) =>
///       OverlayManagerScope(manager: manager, child: child!),
/// );
/// ```
class OverlayManagerScope extends StatefulWidget {
  const OverlayManagerScope({
    super.key,
    required this.manager,
    required this.child,
  });

  final OverlayManager manager;
  final Widget child;

  /// The nearest manager provided by an [OverlayManagerScope] ancestor.
  static OverlayManager of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<_OverlayManagerInherited>();
    assert(scope != null, 'No OverlayManagerScope found in context');
    return scope!.manager;
  }

  /// Like [of], but returns `null` instead of asserting when absent.
  static OverlayManager? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<_OverlayManagerInherited>()
        ?.manager;
  }

  @override
  State<OverlayManagerScope> createState() => _OverlayManagerScopeState();
}

class _OverlayManagerScopeState extends State<OverlayManagerScope> {
  final GlobalKey<OverlayState> _overlayKey = GlobalKey<OverlayState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _attach());
  }

  void _attach() {
    final overlay = _overlayKey.currentState;
    if (overlay != null && mounted) widget.manager.attach(overlay);
  }

  @override
  void didUpdateWidget(covariant OverlayManagerScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.manager != widget.manager) {
      oldWidget.manager.detach();
      _attach();
    }
  }

  @override
  void dispose() {
    widget.manager.detach();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _OverlayManagerInherited(
      manager: widget.manager,
      child: Overlay(
        key: _overlayKey,
        initialEntries: <OverlayEntry>[
          OverlayEntry(builder: (context) => widget.child),
        ],
      ),
    );
  }
}

class _OverlayManagerInherited extends InheritedWidget {
  const _OverlayManagerInherited({
    required this.manager,
    required super.child,
  });

  final OverlayManager manager;

  @override
  bool updateShouldNotify(_OverlayManagerInherited oldWidget) =>
      oldWidget.manager != manager;
}
