import 'package:flutter/widgets.dart';

import 'overlay_manager.dart';

/// Feeds real navigation into [Layerman.setContext]'s `route` key
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
///   navigatorObservers: [LayermanNavigatorObserver(manager)],
///   ...
/// )
/// ```
///
/// Uses [NavigatorObserver.didChangeTop] rather than the legacy
/// `didPush`/`didPop`/`didRemove`/`didReplace` quartet: it's the one hook
/// Flutter documents as reporting the CURRENT topmost route directly,
/// covering the initial route on cold start, declarative `Navigator(pages:)`
/// rebuilds (the underlying model for routers like go_router) that don't map
/// cleanly onto push/pop/replace/remove, and — critically — it avoids a real
/// bug the legacy quartet has: `didRemove`/`didReplace` report the route at
/// the position that changed, which is NOT necessarily the topmost/displayed
/// route if the change happened to a route buried in history while something
/// else remains on top.
///
/// The path defaults to `route.settings.name`; provide [pathOf] if your
/// router stores the path elsewhere (e.g. some go_router setups). A route
/// with no resolvable path (anonymous `MaterialPageRoute(builder: ...)` with
/// no `settings.name`) reports `null` — `route`-conditioned overlays simply
/// don't match `null`, they don't silently keep matching a stale path.
///
/// **Two things Flutter itself does that are easy to miss:**
/// * `MaterialApp.home`'s implicit route reports `'/'` (Flutter's own
///   `Navigator.defaultRouteName`), not `null` and not a name you chose —
///   give it an explicit name via `initialRoute`/`routes` (or a named
///   `RouteSettings`) if you want to gate on it by a different string.
/// * A route-backed dialog/bottom-sheet pushed onto the SAME `Navigator` this
///   observer watches (e.g. the `showDialog`/`Get.dialog` external-presenter
///   recipe, which needs its own unique route name for targeted close) IS,
///   correctly, the topmost route while it's shown — `route` will reflect
///   its name for that window, not the page underneath. This isn't a bug in
///   this class (Flutter's own model says the dialog route is on top); it's
///   a real interaction to know about if you combine route-backed dialogs
///   with `route`-gated overlays or `pauseOnRoutes` elsewhere in the app.
///
/// If [pathOf] throws, the error is reported via [FlutterError.reportError]
/// and the route is treated as unresolvable (`null`) rather than crashing
/// navigation or propagating the exception.
///
/// Once attached, treat this as the sole writer of the `route` context key:
/// a manual `setContext({'route': ...})` call is only overwritten by the next
/// navigation event, so it has no lasting effect.
///
/// The actual `setContext` call is deferred to a post-frame callback: some
/// routers (e.g. declarative ones rebuilding on state changes) can trigger
/// this mid-build, and `setContext` synchronously notifies listeners and may
/// insert `OverlayEntry`s — doing that mid-build throws (`setState()/
/// markNeedsBuild() called during build`). Deferring here means callers never
/// have to work around this themselves. [Layerman.isDisposed] is
/// checked both before scheduling and inside the deferred callback, so a
/// manager disposed between a navigation event and the next frame (e.g. an
/// app-level restart that swaps managers) is never called after disposal.
class LayermanNavigatorObserver extends NavigatorObserver {
  LayermanNavigatorObserver(this.manager, {String? Function(Route<dynamic> route)? pathOf})
      : _pathOf = pathOf ?? _defaultPathOf;

  final Layerman manager;
  final String? Function(Route<dynamic> route) _pathOf;

  static String? _defaultPathOf(Route<dynamic> route) => route.settings.name;

  @override
  void didChangeTop(Route<dynamic> topRoute, Route<dynamic>? previousTopRoute) {
    super.didChangeTop(topRoute, previousTopRoute);
    if (manager.isDisposed) return;

    String? path;
    try {
      path = _pathOf(topRoute);
    } catch (error, stack) {
      FlutterError.reportError(FlutterErrorDetails(
        exception: error,
        stack: stack,
        library: 'layerman',
        context: ErrorDescription(
          'while extracting the path for LayermanNavigatorObserver',
        ),
      ));
      path = null; // treat an extraction failure like an unresolvable route
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (manager.isDisposed) return;
      manager.setContext({'route': path});
    });
    // A post-frame callback only fires once a frame actually runs. Navigation
    // itself usually schedules one (the incoming/outgoing route's transition
    // animation), but don't rely on that: without this, a route change that
    // happens to coincide with an otherwise-idle frame (nothing else dirty)
    // could leave the callback pending indefinitely.
    WidgetsBinding.instance.scheduleFrame();
  }
}
