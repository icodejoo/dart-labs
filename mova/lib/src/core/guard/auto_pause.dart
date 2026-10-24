/// Why a player mount is currently considered hidden.
///
/// 某个播放器挂载点当前被视为隐藏的原因。
enum MovaHideReason {
  /// Scrolled out of its viewport (see `MovaAutoPauseConfig.viewport`).
  ///
  /// 滚出了所在视口（见 `MovaAutoPauseConfig.viewport`）。
  offscreen,

  /// Inside an inactive tab / `Offstage` (`TickerMode` disabled).
  ///
  /// 处于非活跃 Tab / `Offstage` 之中（`TickerMode` 被禁用）。
  tickerOff,

  /// Covered by another route.
  ///
  /// 被其他路由盖住。
  routeCovered,

  /// The app is in the background.
  ///
  /// 应用在后台。
  background,
}

/// How a live source resumes after being hidden.
///
/// 直播源隐藏后如何恢复。
enum MovaLiveResume {
  /// Plain `play()` from where it paused.
  ///
  /// 从暂停点普通续播。
  resume,

  /// Jump back to the live edge (`backToLiveEdge()`), then play. A paused live
  /// stream's position may have slid out of the playlist window, or the server
  /// may have dropped the connection.
  ///
  /// 回到直播边缘（`backToLiveEdge()`）再播放。暂停的直播流其位置可能已滑出播放列表
  /// 窗口，服务端也可能已断开连接。
  reloadEdge,
}

/// Which visibility changes pause a player, and how it resumes. A pure value
/// used by the `MovaAutoPause` widget; not part of `MovaOpts` because it
/// describes one mount point, while an engine may be mounted twice (page and
/// mini window).
///
/// 哪些可见性变化会暂停播放器，以及如何恢复。供 `MovaAutoPause` 组件使用的纯值；
/// 不放进 `MovaOpts`，因为它描述的是某个挂载点，而一个引擎可能同时挂在两处（页面和
/// 小窗）。
///
/// Example / 示例:
/// ```dart
/// MovaAutoPause(api: engine, config: const MovaAutoPauseConfig(minVisibleFraction: 0.5), child: player)
/// ```
class MovaAutoPauseConfig {
  /// Pause when scrolled out of the viewport.
  ///
  /// 滚出视口时暂停。
  final bool viewport;

  /// Pause when the visible fraction is at or below this; 0 means only when
  /// fully off-screen.
  ///
  /// 可见比例小于等于此值时暂停；0 表示完全滚出才暂停。
  final double minVisibleFraction;

  /// Pause inside an inactive tab / `Offstage`.
  ///
  /// 处于非活跃 Tab / `Offstage` 时暂停。
  final bool tickerMode;

  /// Pause while covered by another route.
  ///
  /// 被其他路由盖住时暂停。
  final bool route;

  /// Pause while the app is in the background.
  ///
  /// 应用进后台时暂停。
  final bool background;

  /// Resume (if it was playing before) once visible again.
  ///
  /// 重新可见后恢复播放（仅限隐藏前在播）。
  final bool resumeOnShow;

  /// How a live source resumes.
  ///
  /// 直播源如何恢复。
  final MovaLiveResume liveResume;

  /// Hidden for less than this, a live source simply resumes.
  ///
  /// 隐藏不足此时长的直播源直接续播。
  final Duration liveResumeGrace;

  /// Creates the config; the defaults pause on every kind of hiding and
  /// resume afterwards.
  ///
  /// 创建配置；默认对所有隐藏情形都暂停，并在之后恢复。
  const MovaAutoPauseConfig({
    this.viewport = true,
    this.minVisibleFraction = 0.0,
    this.tickerMode = true,
    this.route = true,
    this.background = true,
    this.resumeOnShow = true,
    this.liveResume = MovaLiveResume.reloadEdge,
    this.liveResumeGrace = const Duration(seconds: 3),
  }) : assert(
         minVisibleFraction >= 0 && minVisibleFraction < 1,
         'minVisibleFraction must be in [0, 1)',
       );

  /// Whether [reason] is switched on in this config.
  ///
  /// [reason] 在本配置里是否开启。
  ///
  /// - [reason]: the hide reason to look up / 要查询的隐藏原因
  bool watches(MovaHideReason reason) => switch (reason) {
    MovaHideReason.offscreen => viewport,
    MovaHideReason.tickerOff => tickerMode,
    MovaHideReason.routeCovered => route,
    MovaHideReason.background => background,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MovaAutoPauseConfig &&
          viewport == other.viewport &&
          minVisibleFraction == other.minVisibleFraction &&
          tickerMode == other.tickerMode &&
          route == other.route &&
          background == other.background &&
          resumeOnShow == other.resumeOnShow &&
          liveResume == other.liveResume &&
          liveResumeGrace == other.liveResumeGrace;

  @override
  int get hashCode => Object.hash(
    viewport,
    minVisibleFraction,
    tickerMode,
    route,
    background,
    resumeOnShow,
    liveResume,
    liveResumeGrace,
  );
}

/// What the widget should do after a visibility change.
///
/// 可见性变化后组件应执行的动作。
enum MovaGuardAction {
  /// Nothing.
  ///
  /// 什么都不做。
  none,

  /// Pause playback.
  ///
  /// 暂停播放。
  pause,

  /// Plain `play()`.
  ///
  /// 普通 `play()`。
  resume,

  /// `backToLiveEdge()`, then `play()` if it is still not playing.
  ///
  /// `backToLiveEdge()`，之后若仍未在播再 `play()`。
  reloadEdge,
}

/// Pure decision core of the auto-pause guard: tracks the set of active hide
/// reasons and decides when to pause and when to resume. No clock, no
/// Flutter — the caller passes the time in.
///
/// 自动暂停守卫的纯决策核心：维护当前生效的隐藏原因集合，决定何时暂停、何时恢复。
/// 没有时钟、不依赖 Flutter——时间由调用方传入。
///
/// Example / 示例:
/// ```dart
/// final gate = MovaAutoPauseGate(const MovaAutoPauseConfig());
/// final a = gate.update(MovaHideReason.offscreen, true,
///     playing: true, live: false, exempt: false, now: DateTime.now()); // pause
/// ```
class MovaAutoPauseGate {
  /// Creates a gate for [config].
  ///
  /// 为 [config] 创建一个守卫。
  MovaAutoPauseGate(this.config);

  /// The configuration this gate follows.
  ///
  /// 本守卫遵循的配置。
  MovaAutoPauseConfig config;

  final Set<MovaHideReason> _active = <MovaHideReason>{};
  final Set<MovaHideReason> _reasons = <MovaHideReason>{};

  /// Playing intent captured at the first sign of backgrounding.
  ///
  /// 在进后台的第一个迹象时捕获的播放意图。
  bool? _inactiveSnapshot;

  /// Whether this gate paused the player for the current hidden period, i.e.
  /// whether it owes a resume.
  ///
  /// 本守卫是否在当前这段隐藏期里暂停了播放器，即是否欠一次恢复。
  bool _pausedByGate = false;

  /// When the current hidden period began.
  ///
  /// 当前这段隐藏期的开始时刻。
  DateTime? _hiddenAt;

  /// Current hide reasons (already filtered by [config]).
  ///
  /// 当前的隐藏原因（已按 [config] 过滤）。
  Set<MovaHideReason> get reasons => Set<MovaHideReason>.unmodifiable(_reasons);

  /// Whether at least one hide reason is active.
  ///
  /// 是否至少有一个隐藏原因生效。
  bool get hidden => _reasons.isNotEmpty;

  /// Snapshots playing intent at the first sign of backgrounding (`inactive`).
  /// Android may pause libmpv by itself when the surface is reclaimed, so by
  /// the time `hidden` arrives `playing` can already be false.
  ///
  /// 在进后台的第一个迹象（`inactive`）时快照播放意图。Android 回收渲染面时 libmpv 会
  /// 自己先暂停，等 `hidden` 到达时 `playing` 可能已经是 false。
  ///
  /// - [playing]: playing intent right now / 此刻的播放意图
  void onInactive({required bool playing}) => _inactiveSnapshot = playing;

  /// Clears the inactive snapshot (`resumed` without ever hiding).
  ///
  /// 清掉 inactive 快照（未曾隐藏就回到 resumed）。
  void onResumed() => _inactiveSnapshot = null;

  /// Rechecks playback or exemption changes during an existing hidden period.
  /// Returns a pause action when [playing] and not [exempt].
  /// Example: `gate.observe(playing: true, exempt: false)`.
  ///
  /// 隐藏期间重新检查播放或豁免变化；有播放意图且未豁免时返回暂停。
  MovaGuardAction observe({required bool playing, required bool exempt}) {
    if (!hidden || !playing || exempt) return MovaGuardAction.none;
    _pausedByGate = true;
    return MovaGuardAction.pause;
  }

  /// Applies [next] while preserving the hidden cycle; returns the next action.
  /// Other arguments have the same meaning as [update].
  /// Example: `gate.reconfigure(config, playing: false, live: true,
  /// exempt: false, now: DateTime.now())`.
  ///
  /// 应用新配置并保留隐藏周期，返回下一动作；其余参数含义同 update。
  MovaGuardAction reconfigure(
    MovaAutoPauseConfig next, {
    required bool playing,
    required bool live,
    required bool exempt,
    required DateTime now,
  }) {
    final wasHidden = hidden;
    config = next;
    _reasons
      ..clear()
      ..addAll(_active.where(config.watches));
    return _transition(wasHidden, playing, live, exempt, now, null);
  }

  /// Sets one reason on/off and returns the action to take.
  ///
  /// 置位/清除一个原因，返回应执行的动作。
  ///
  /// - [reason]: which reason changed / 哪个原因变了
  /// - [active]: whether it is now in effect / 现在是否生效
  /// - [playing]: playing intent right now (buffering counts as playing) / 此刻的播放意图（缓冲中也算在播）
  /// - [live]: whether the source is live / 是否直播源
  /// - [exempt]: the picture lives on in system PiP / in-app mini window, never pause for it / 画面在系统画中画/小窗里继续，不因它暂停
  /// - [now]: the current time / 当前时间
  ///
  /// Returns what the caller should do; repeating the same call returns [MovaGuardAction.none].
  ///
  /// 返回调用方应执行的动作；重复同一次调用返回 [MovaGuardAction.none]。
  MovaGuardAction update(
    MovaHideReason reason,
    bool active, {
    required bool playing,
    required bool live,
    required bool exempt,
    required DateTime now,
  }) {
    active ? _active.add(reason) : _active.remove(reason);
    if (!config.watches(reason)) return MovaGuardAction.none;
    final wasHidden = hidden;
    final changed = active ? _reasons.add(reason) : _reasons.remove(reason);
    if (!changed) return MovaGuardAction.none;

    return _transition(wasHidden, playing, live, exempt, now, reason);
  }

  /// Decides after the effective reason set changes.
  ///
  /// 在生效原因集合变化后决策。
  MovaGuardAction _transition(
    bool wasHidden,
    bool playing,
    bool live,
    bool exempt,
    DateTime now,
    MovaHideReason? reason,
  ) {
    if (!wasHidden && hidden) {
      final snapshot = reason == MovaHideReason.background
          ? _inactiveSnapshot
          : null;
      _inactiveSnapshot = null;
      final intent = snapshot ?? playing;
      _hiddenAt = now;
      _pausedByGate = intent && !exempt;
      return _pausedByGate ? MovaGuardAction.pause : MovaGuardAction.none;
    }

    if (wasHidden && !hidden) {
      final owed = _pausedByGate;
      final since = _hiddenAt;
      _pausedByGate = false;
      _hiddenAt = null;
      if (!owed || !config.resumeOnShow) return MovaGuardAction.none;
      final away = since == null ? Duration.zero : now.difference(since);
      if (live &&
          config.liveResume == MovaLiveResume.reloadEdge &&
          away >= config.liveResumeGrace) {
        return MovaGuardAction.reloadEdge;
      }
      return MovaGuardAction.resume;
    }
    return MovaGuardAction.none;
  }
}
