import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/widgets.dart';

import '../../core/api.dart';
import '../../core/guard/auto_pause.dart';
import '../../core/model/source.dart';
import '../../core/keep_alive/keep_alive.dart';
import '../../core/state/state.dart';

/// Pauses [api] while [child] is hidden — scrolled out of its viewport, in an
/// inactive tab/`Offstage`, covered by another route, or with the app in the
/// background — and resumes it afterwards if it was playing. Uses only the
/// Flutter SDK (no visibility package).
///
/// Limits worth knowing:
/// - Viewport detection walks the ancestor `Scrollable`s only; it does not see
///   arbitrary `ClipRect`/`Transform`/`Overlay` occlusion.
/// - A *translucent* route (dialog, transparent page) pushed on an outer
///   navigator is invisible to `ModalRoute.isCurrentOf`; pass [routeObservers],
///   one per navigator, to catch it. (An opaque outer route is already caught
///   through `TickerMode`, once its transition has finished.)
/// - A lazy list may dispose the card before this guard can pause; the
///   engine then belongs to whoever owns it.
/// - Not for `MovaFeedPlayer` pages: the feed pool already decides which page
///   plays.
///
/// 在 [child] 被隐藏时暂停 [api]——滚出视口、处于非活跃 Tab/`Offstage`、被其他路由
/// 盖住、或应用进入后台——之后若隐藏前在播则恢复。只用 Flutter SDK（不依赖任何可见性
/// 三方包）。
///
/// 值得知道的局限：
/// - 视口检测只沿祖先 `Scrollable` 计算，看不到任意 `ClipRect`/`Transform`/`Overlay`
///   造成的遮挡。
/// - 推到外层 navigator 的**半透明**路由（对话框、透明页）对 `ModalRoute.isCurrentOf`
///   不可见；传入 [routeObservers]（每个 navigator 一个）才能察觉。（不透明的外层路由在
///   转场结束后已能经 `TickerMode` 察觉。）
/// - 懒加载列表可能在守卫来得及暂停之前就销毁卡片；此后引擎归持有者管。
/// - 不要用于 `MovaFeedPlayer` 的页面：feed 池已经在决定哪一页播放。
///
/// Example / 示例:
/// ```dart
/// // A NavigatorObserver can only serve ONE navigator: make one per navigator.
/// final rootObs = RouteObserver<ModalRoute<dynamic>>();
/// final branchObs = RouteObserver<ModalRoute<dynamic>>();
/// // GoRouter(observers: [rootObs], ...) and StatefulShellBranch(observers: [branchObs], ...)
/// MovaAutoPause(api: engine, routeObservers: [rootObs, branchObs], child: MovaPlayer(api: engine))
/// ```
class MovaAutoPause extends StatefulWidget {
  /// Creates the guard.
  ///
  /// 创建守卫。
  ///
  /// - [api]: the engine to pause/resume / 要暂停/恢复的引擎
  /// - [config]: which kinds of hiding count, and how to resume / 哪些隐藏算数、如何恢复
  /// - [routeObservers]: see [MovaAutoPause.routeObservers] / 见 [MovaAutoPause.routeObservers]
  /// - [onChanged]: called whenever the hide-reason set changes / 隐藏原因集合变化时回调
  /// - [child]: the player (or anything) whose visibility is watched / 被监视可见性的播放器（或任意组件）
  const MovaAutoPause({
    super.key,
    required this.api,
    this.config = const MovaAutoPauseConfig(),
    this.routeObservers = const [],
    this.onChanged,
    required this.child,
  });

  /// The engine to pause/resume.
  ///
  /// 要暂停/恢复的引擎。
  final MovaApi api;

  /// Which kinds of hiding count, and how to resume.
  ///
  /// 哪些隐藏算数、如何恢复。
  final MovaAutoPauseConfig config;

  /// Observers already attached to the navigators between this widget and the
  /// root, one per navigator — a `NavigatorObserver` can only serve one
  /// navigator, so the same instance must not be reused. Lets the guard notice
  /// translucent routes pushed on an outer navigator, which
  /// `ModalRoute.isCurrentOf` cannot see. Empty by default.
  ///
  /// 已经挂在本组件到根之间各个 navigator 上的观察者，每个 navigator 一个——
  /// `NavigatorObserver` 只能服务一个 navigator，不能复用同一个实例。让守卫能察觉推到
  /// 外层 navigator 上的半透明路由——这是 `ModalRoute.isCurrentOf` 看不到的。默认为空。
  final List<RouteObserver<ModalRoute<dynamic>>> routeObservers;

  /// Called whenever the hide-reason set changes.
  ///
  /// 隐藏原因集合变化时回调。
  final void Function(Set<MovaHideReason> reasons)? onChanged;

  /// The widget whose visibility is watched.
  ///
  /// 被监视可见性的组件。
  final Widget child;

  @override
  State<MovaAutoPause> createState() => _MovaAutoPauseState();
}

/// Tracks one ancestor route layer for the route observer.
///
/// 为路由观察者跟踪一层祖先路由。
class _RouteLayer with RouteAware {
  /// Creates a layer for [route] reporting through [onChange].
  ///
  /// 为 [route] 创建一层，经 [onChange] 上报。
  _RouteLayer(this.route, this.observer, this.onChange);

  /// The route this layer watches.
  ///
  /// 本层监视的路由。
  final ModalRoute<dynamic> route;

  /// The observer subscribed for [route].
  ///
  /// 为 [route] 订阅的观察者。
  final RouteObserver<ModalRoute<dynamic>> observer;

  /// Called when [covered] flips.
  ///
  /// [covered] 翻转时调用。
  final VoidCallback onChange;

  /// Whether another route sits on top of [route].
  ///
  /// 是否有别的路由盖在 [route] 上面。
  bool covered = false;

  @override
  void didPushNext() {
    covered = true;
    onChange();
  }

  @override
  void didPopNext() {
    covered = false;
    onChange();
  }
}

/// State of [MovaAutoPause]: collects the four visibility signals and feeds
/// them to a [MovaAutoPauseGate].
///
/// [MovaAutoPause] 的状态：收集四类可见性信号并喂给 [MovaAutoPauseGate]。
class _MovaAutoPauseState extends State<MovaAutoPause> {
  late final MovaAutoPauseGate _gate = MovaAutoPauseGate(widget.config);
  AppLifecycleListener? _lifecycle;
  ValueListenable<TickerModeData>? _ticker;
  final List<ScrollPosition> _positions = <ScrollPosition>[];
  final List<ScrollableState> _scrollables = <ScrollableState>[];
  final List<_RouteLayer> _layers = <_RouteLayer>[];
  bool _viewportScheduled = false;
  bool _disposed = false;
  StreamSubscription<MovaState>? _stateSub;
  int _resumeGen = 0;

  @override
  void initState() {
    super.initState();
    _bindState();
    _lifecycle = AppLifecycleListener(onStateChange: _onLifecycle);
    final now = WidgetsBinding.instance.lifecycleState;
    if (now == AppLifecycleState.hidden || now == AppLifecycleState.paused) {
      _set(MovaHideReason.background, true);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _bindTicker();
    _bindRoute();
    _bindScrollables();
    _scheduleViewport();
  }

  @override
  void didUpdateWidget(MovaAutoPause old) {
    super.didUpdateWidget(old);
    if (old.config != widget.config) {
      final s = widget.api.state;
      _act(
        _gate.reconfigure(
          widget.config,
          playing: s.playbackIntent || s.playing,
          live: s.type == MovaStreamType.live,
          exempt: s.pip || s.mini,
          now: DateTime.now(),
          keepAliveCapable: widget.api is MovaKeepAlive,
        ),
      );
      _bindTicker();
      _bindRoute();
    }
    if (!identical(old.api, widget.api)) {
      _resumeGen++;
      _bindState();
      final s = widget.api.state;
      _act(
        _gate.observe(
          playing: s.playbackIntent || s.playing,
          exempt: s.pip || s.mini,
          live: s.type == MovaStreamType.live,
          keepAliveCapable: widget.api is MovaKeepAlive,
        ),
      );
    }
    if (!_sameObservers(old.routeObservers, widget.routeObservers)) {
      _bindRoute();
    }
    _scheduleViewport();
  }

  @override
  void dispose() {
    _disposed = true;
    _resumeGen++;
    unawaited(_stateSub?.cancel());
    _lifecycle?.dispose();
    _ticker?.removeListener(_onTicker);
    for (final p in _positions) {
      p.removeListener(_scheduleViewport);
    }
    _unobserve();
    super.dispose();
  }

  /// Feeds one reason change to the gate and performs the action it returns.
  ///
  /// 把一次原因变化喂给守卫，并执行它返回的动作。
  void _set(MovaHideReason reason, bool active) {
    if (_disposed) return;
    final api = widget.api;
    final s = api.state;
    final before = _gate.reasons;
    final action = _gate.update(
      reason,
      active,
      playing: s.playbackIntent || s.playing,
      live: s.type == MovaStreamType.live,
      exempt: s.pip || s.mini,
      now: DateTime.now(),
      keepAliveCapable: api is MovaKeepAlive,
    );
    final after = _gate.reasons;
    if (before.length != after.length || !before.containsAll(after)) {
      widget.onChanged?.call(after);
    }
    if (_gate.hidden) _resumeGen++;
    _act(action);
  }

  /// Rebinds playback observations when the engine changes.
  ///
  /// 引擎变化时重新绑定播放观测。
  void _bindState() {
    unawaited(_stateSub?.cancel());
    final api = widget.api;
    var last = (
      api.state.playbackIntent,
      api.state.playing,
      api.state.pip,
      api.state.mini,
    );
    _stateSub = api.states.listen((s) {
      if (_disposed || !identical(api, widget.api)) return;
      final next = (s.playbackIntent, s.playing, s.pip, s.mini);
      if (next == last) return;
      final started = (!last.$1 && next.$1) || (!last.$2 && next.$2);
      final lostExemption = (last.$3 || last.$4) && !(next.$3 || next.$4);
      last = next;
      if (started || lostExemption) {
        _act(
          _gate.observe(
            playing: s.playbackIntent || s.playing,
            exempt: s.pip || s.mini,
            live: s.type == MovaStreamType.live,
            keepAliveCapable: api is MovaKeepAlive,
          ),
        );
      }
    });
  }

  /// Executes a gate decision against the current engine.
  ///
  /// 对当前引擎执行守卫决策。
  void _act(MovaGuardAction action) {
    final api = widget.api;
    switch (action) {
      case MovaGuardAction.none:
        break;
      case MovaGuardAction.pause:
        unawaited(api.pause().catchError((Object _) {}));
      case MovaGuardAction.resume:
        unawaited(api.play().catchError((Object _) {}));
      case MovaGuardAction.reloadEdge:
        unawaited(_reloadEdge(api));
      case MovaGuardAction.keepAlive:
        unawaited(_keepAlive(api, true));
      case MovaGuardAction.wake:
        unawaited(_keepAlive(api, false));
    }
  }

  /// Puts [api] into keepAlive ([on]) or wakes it. An engine without the
  /// capability degrades to `pause()`/`play()`.
  ///
  /// 让 [api] 进入待机（[on]）或唤醒。不具备该能力的引擎退化为 `pause()`/`play()`。
  Future<void> _keepAlive(MovaApi api, bool on) async {
    try {
      if (api is MovaKeepAlive) {
        await (api as MovaKeepAlive).setKeepAlive(on);
        // It became visible again while the hold was being set up: the wake the
        // gate issued queues behind this call inside the engine, and this makes
        // sure nothing is left held if the engine answered late.
        //
        // 设置待机途中又变可见了：守卫发出的唤醒在引擎里排在本次调用之后；这里再补一次，
        // 保证引擎答复得晚时也不会残留待机。
        if (on &&
            !_disposed &&
            !_gate.hidden &&
            identical(api, widget.api)) {
          await (api as MovaKeepAlive).setKeepAlive(false);
        }
      } else if (on) {
        await api.pause();
      } else {
        await api.play();
      }
    } on Object {
      // A failing engine call must not surface from a visibility callback.
      //
      // 引擎调用失败不能从可见性回调里冒出来。
    }
  }

  /// Back to the live edge, then play if that alone did not start playback
  /// (the `seekEnd` strategy only seeks).
  ///
  /// 回直播边缘，若这一步没让播放起来（`seekEnd` 策略只 seek）再补一次 play。
  Future<void> _reloadEdge(MovaApi api) async {
    final gen = ++_resumeGen;
    bool current() =>
        !_disposed &&
        gen == _resumeGen &&
        !_gate.hidden &&
        identical(api, widget.api);
    try {
      await api.backToLiveEdge();
      if (!current()) {
        if (!_disposed) await api.pause();
        return;
      }
      if (!api.state.playing) {
        await api.play();
        if (!current() && !_disposed) await api.pause();
      }
    } on Object {
      // A failing engine call must not surface from a visibility callback.
      //
      // 引擎调用失败不能从可见性回调里冒出来。
    }
  }

  // ---- background ----------------------------------------------------

  void _onLifecycle(AppLifecycleState s) {
    switch (s) {
      case AppLifecycleState.inactive:
        // Visible but not focused (system PiP, notification shade): do not
        // pause, but remember the intent before the system pauses libmpv.
        //
        // 可见但失焦（系统画中画、下拉通知栏）：不暂停，但在系统先把 libmpv 暂停之前记下
        // 播放意图。
        if (!_gate.reasons.contains(MovaHideReason.background)) {
          _gate.onInactive(
            playing:
                widget.api.state.playbackIntent || widget.api.state.playing,
          );
        } else {
          _set(MovaHideReason.background, false);
        }
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        _set(MovaHideReason.background, true);
      case AppLifecycleState.resumed:
        _set(MovaHideReason.background, false);
        _gate.onResumed();
    }
  }

  // ---- ticker mode (inactive tab / Offstage) ---------------------------

  void _bindTicker() {
    final next = TickerMode.getValuesNotifier(context);
    if (!identical(next, _ticker)) {
      _ticker?.removeListener(_onTicker);
      _ticker = next..addListener(_onTicker);
    }
    _onTicker();
  }

  void _onTicker() =>
      _set(MovaHideReason.tickerOff, !(_ticker?.value.enabled ?? true));

  // ---- routes ----------------------------------------------------------

  void _bindRoute() {
    final route = ModalRoute.of(context);
    _set(MovaHideReason.routeCovered, _routeCovered(route));
    // Walk outward: this route, then the route hosting its navigator, and so
    // on; each layer is observed by whichever observer serves that navigator.
    //
    // 由内向外走：本路由，再到承载其 navigator 的路由，依此类推；每一层由服务该
    // navigator 的那个观察者来观察。
    final wanted =
        <(ModalRoute<dynamic>, RouteObserver<ModalRoute<dynamic>>)>[];
    if (widget.routeObservers.isNotEmpty) {
      final seen = <ModalRoute<dynamic>>[];
      var r = route;
      while (r != null && !seen.contains(r)) {
        seen.add(r);
        final nav = r.navigator;
        if (nav == null) break;
        for (final o in widget.routeObservers) {
          if (identical(o.navigator, nav)) wanted.add((r, o));
        }
        r = ModalRoute.of(nav.context);
      }
    }
    final same =
        wanted.length == _layers.length &&
        [
          for (var i = 0; i < wanted.length; i++)
            identical(wanted[i].$1, _layers[i].route) &&
                identical(wanted[i].$2, _layers[i].observer),
        ].every((e) => e);
    if (same) return;
    _unobserve();
    for (final (r, o) in wanted) {
      final layer = _RouteLayer(r, o, _onLayer)..covered = !r.isCurrent;
      _layers.add(layer);
      o.subscribe(layer, r);
    }
    _onLayer();
  }

  static bool _sameObservers(
    List<RouteObserver<ModalRoute<dynamic>>> a,
    List<RouteObserver<ModalRoute<dynamic>>> b,
  ) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!identical(a[i], b[i])) return false;
    }
    return true;
  }

  void _unobserve() {
    for (final l in _layers) {
      l.observer.unsubscribe(l);
    }
    _layers.clear();
  }

  void _onLayer() =>
      _set(MovaHideReason.routeCovered, _routeCovered(ModalRoute.of(context)));

  bool _routeCovered(ModalRoute<dynamic>? route) {
    if (route != null && !route.isCurrent) return true;
    return _layers.any((l) => l.covered);
  }

  // ---- viewport --------------------------------------------------------

  void _bindScrollables() {
    final found = <ScrollableState>[];
    var s = Scrollable.maybeOf(context);
    while (s != null && !found.contains(s)) {
      found.add(s);
      s = Scrollable.maybeOf(s.context);
    }
    final positions = [for (final f in found) f.position];
    final same =
        positions.length == _positions.length &&
        [
          for (var i = 0; i < positions.length; i++)
            identical(positions[i], _positions[i]),
        ].every((e) => e);
    if (same) return;
    for (final p in _positions) {
      p.removeListener(_scheduleViewport);
    }
    _positions
      ..clear()
      ..addAll(positions);
    _scrollables
      ..clear()
      ..addAll(found);
    for (final p in _positions) {
      p.addListener(_scheduleViewport);
    }
  }

  /// Re-measures once after the next frame, however many scroll ticks arrive.
  ///
  /// 不管来多少次滚动回调，都只在下一帧之后重新测量一次。
  void _scheduleViewport() {
    if (_viewportScheduled || _disposed) return;
    _viewportScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _viewportScheduled = false;
      if (!_disposed && mounted) _measureViewport();
    });
  }

  void _measureViewport() {
    if (_scrollables.isEmpty) {
      _set(MovaHideReason.offscreen, false);
      return;
    }
    final fraction = _visibleFraction();
    if (fraction == null) return;
    _set(
      MovaHideReason.offscreen,
      fraction <= widget.config.minVisibleFraction,
    );
  }

  /// Visible share of this widget inside every ancestor scroll viewport, or
  /// `null` when it cannot be measured yet (not laid out).
  ///
  /// 本组件在各层祖先滚动视口内的可见比例；尚无法测量（未布局）时返回 `null`。
  double? _visibleFraction() {
    final box = context.findRenderObject();
    if (box is! RenderBox ||
        !box.attached ||
        !box.hasSize ||
        box.size.isEmpty) {
      return null;
    }
    final full = MatrixUtils.transformRect(
      box.getTransformTo(null),
      Offset.zero & box.size,
    );
    final fullArea = full.width * full.height;
    if (fullArea <= 0) return null;
    var clipped = full;
    for (final s in _scrollables) {
      final vp = s.context.findRenderObject();
      if (vp is! RenderBox || !vp.attached || !vp.hasSize) continue;
      final vr = MatrixUtils.transformRect(
        vp.getTransformTo(null),
        Offset.zero & vp.size,
      );
      clipped = clipped.intersect(vr);
      if (clipped.width <= 0 || clipped.height <= 0) return 0;
    }
    return (clipped.width * clipped.height) / fullArea;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
