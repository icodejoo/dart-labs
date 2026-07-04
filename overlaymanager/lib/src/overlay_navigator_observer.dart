import 'package:flutter/widgets.dart';

import 'overlay_manager.dart';

/// Feeds real navigation into [OverlayManager.setContext]'s `route` key
/// automatically, so `route`/`when`/`dismissWhenUnmet` conditions and
/// `pauseOnRoutes` react to actual navigation without the host writing
/// `setContext({'route': ...})` by hand in every page's lifecycle.
///
/// Add it to `navigatorObservers` alongside (or instead of) any other
/// observer — it works under vanilla `Navigator`, GetX and go_router alike,
/// since all three ultimately drive a real Flutter `Navigator` and this class
/// only implements the standard [NavigatorObserver] callbacks. It never
/// pushes, pops, or otherwise touches navigation — purely observational.
///
/// ```dart
/// MaterialApp(
///   navigatorObservers: [OverlayNavigatorObserver(manager)],
///   ...
/// )
/// ```
///
/// The path defaults to `route.settings.name`; provide [pathOf] if your
/// router stores the path elsewhere (e.g. some go_router setups). A route
/// with no resolvable path (anonymous `MaterialPageRoute(builder: ...)` with
/// no `settings.name`) reports `null` — `route`-conditioned overlays simply
/// don't match `null`, they don't silently keep matching a stale path.
///
/// Once attached, treat this as the sole writer of the `route` context key:
/// a manual `setContext({'route': ...})` call is only overwritten by the next
/// navigation event, so it has no lasting effect.
///
/// The actual `setContext` call is deferred to a post-frame callback: some
/// routers (e.g. declarative ones rebuilding on state changes) can trigger
/// `didPush`/`didPop` mid-build, and `setContext` synchronously notifies
/// listeners and may insert `OverlayEntry`s — doing that mid-build throws
/// (`setState()/markNeedsBuild() called during build`). Deferring here means
/// callers never have to work around this themselves.
class OverlayNavigatorObserver extends NavigatorObserver {
  OverlayNavigatorObserver(this.manager, {String? Function(Route<dynamic> route)? pathOf})
      : _pathOf = pathOf ?? _defaultPathOf;

  final OverlayManager manager;
  final String? Function(Route<dynamic> route) _pathOf;

  static String? _defaultPathOf(Route<dynamic> route) => route.settings.name;

  void _update(Route<dynamic>? current) {
    final path = current == null ? null : _pathOf(current);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      manager.setContext({'route': path});
    });
    // A post-frame callback only fires once a frame actually runs. Navigation
    // itself usually schedules one (the incoming/outgoing route's transition
    // animation), but don't rely on that: without this, a route change that
    // happens to coincide with an otherwise-idle frame (nothing else dirty)
    // could leave the callback pending indefinitely.
    WidgetsBinding.instance.scheduleFrame();
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    _update(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    _update(previousRoute);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didRemove(route, previousRoute);
    _update(previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    _update(newRoute);
  }
}
