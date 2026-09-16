import 'dart:async';

import '../api.dart';
import '../events/events.dart';
import '../model/ad.dart';
import '../model/source.dart';
import '../options/ad_config.dart';
import '../state/progress.dart';
import '../swap/ctl.dart';
import '../swap/trigger.dart';

/// Returns the first not-yet-played mid-roll break whose [MovaAdBreak.offset] has
/// been reached at [position]; null when none is due.
///
/// Pure so the mid-roll trigger rule is unit-testable in isolation. Earliest
/// due break wins; the caller marks it played so the next tick surfaces the
/// following one.
///
/// 返回首个尚未播放、且 [MovaAdBreak.offset] 在 [position] 处已到达的中插广告位；
/// 没有到期的则返回 null。
///
/// 纯函数，使中插触发规则可单独单测。最早到期者优先；调用方将其标记为已播，
/// 下一个 tick 便浮现下一条。
MovaAdBreak? dueMidRoll(
  List<MovaAdBreak> breaks,
  Duration position,
  Set<MovaAdBreak> played,
) {
  for (final b in breaks) {
    if (b.kind == MovaAdBreakKind.mid &&
        !played.contains(b) &&
        b.offset <= position) {
      return b;
    }
  }
  return null;
}

/// Playback phase the ad controller is currently in.
///
/// 广告控制器当前所处的播放阶段。
enum _Phase {
  /// Nothing loaded, or content finished with all ads played.
  ///
  /// 未加载，或正片连同所有广告都已播完。
  idle,

  /// A mid-roll is due but has not taken over yet, while the content
  /// deliberately keeps playing — either because its [MovaAdBreak.delay]
  /// countdown is running, or because the ad is being warmed up in the
  /// background and is not ready to be shown, or both. Distinct from [content]
  /// because no *further* mid-roll may be triggered here, and distinct from
  /// [ad] because nothing has interrupted the viewer yet.
  ///
  /// 一条中插已到期但尚未接管，而正片刻意继续播放——可能是其
  /// [MovaAdBreak.delay] 倒计时正在走，可能是广告正在后台预热、还不能见人，
  /// 也可能两者同时。与 [content] 不同之处在于此阶段不得再触发*别的*中插；
  /// 与 [ad] 不同之处在于观众此刻还没有被打断。
  pending,

  /// An ad break is playing.
  ///
  /// 正在播放一个广告位。
  ad,

  /// The main content is playing.
  ///
  /// 正在播放正片。
  content,
}

/// Orchestrates pre/mid/post-roll ads on top of a [MovaApi] by swapping the
/// playing source between the content and each ad break.
///
/// Pure Dart (no Flutter dependency) so it stays unit-testable and lives in the
/// core layer. Host-constructed and injected — call [load] instead of
/// [MovaApi.open] to start content with its ads. Mid-roll saves the content
/// position and resumes there after the ad (relying on the engine's parked-seek
/// so the resume lands even before the resumed source reports a duration).
/// Click-through is never navigated here — it is surfaced via
/// [MovaAdConfig.onAdEvent].
///
/// **Composing with a `MovaPlistCtrl`:** both react to [MovaDone], so
/// naively wiring both to the same player makes them race on the next
/// `open()`. To combine them, set the playlist's `autoPlayNext: false` and
/// advance it from [contentEnded] (which fires only after the content *and* its
/// post-rolls finish) instead.
///
/// 在 [MovaApi] 之上编排前/中/后贴片广告：在正片与各广告位之间切换正在播放的源。
///
/// 纯 Dart（无 Flutter 依赖），可单测并归属核心层。由宿主构造并注入——用 [load]
/// 代替 [MovaApi.open] 来带广告地起播正片。中插会保存正片位置并在广告后从该处续播
/// （依赖 engine 的 seek 寄存，使续播位置在被续播源尚未报告时长前也能落地）。
/// 点击跳转不会在此处执行——经 [MovaAdConfig.onAdEvent] 暴露给宿主。
///
/// **与 `MovaPlistCtrl` 组合：** 二者都响应 [MovaDone]，裸挂到同一播放器
/// 会争抢 `open()`。组合时应把播放列表的 `autoPlayNext` 设为 `false`，改由本控制器的
/// [contentEnded]（只在正片**及其**后贴片都播完后才触发）来驱动换集。
class MovaAdCtrl {
  /// Creates a controller bound to [api], seeded from [MovaOpts.ads].
  ///
  /// [swap] enables seamless ad→content swaps: it should be the same
  /// [MovaSwapEngine] passed as [api], so the controller can drive it to
  /// warm the content up before the ad ends. Omit it (or pass an [api] that
  /// is not a swap engine) to keep today's plain `open()` behaviour.
  ///
  /// 创建绑定到 [api] 的控制器，初值取自 [MovaOpts.ads]。
  ///
  /// [swap] 用于开启广告→正片的无缝切换：它应当就是同时作为 [api] 传入的那个
  /// `MovaSwapEngine`，使控制器能驱动它在广告结束前预热正片。省略它（或传入
  /// 非切换引擎的 [api]）即保持今天的普通 `open()` 行为。
  ///
  /// - [api]: the player capability surface to drive / 要驱动的播放器能力面
  /// - [swap]: optional seamless-swap capability, same instance as [api] /
  ///   可选的无缝切换能力面，与 [api] 是同一实例
  ///
  /// Example / 示例:
  /// ```dart
  /// final api = MovaSwapEngine(engineFactory: createMovaEngine);
  /// final ads = MovaAdCtrl(api, swap: api);
  /// await ads.load(const MovaSource('https://host/movie.m3u8'));
  /// ```
  MovaAdCtrl(this._api, {MovaSwapCtl? swap})
      : _cfg = _api.options.ads,
        _breaks = _api.options.ads.breaks,
        _onAdEvent = _api.options.ads.onAdEvent,
        _enabled = _api.options.ads.enabled,
        // The public parameter name (`swap`) must stay distinct from the
        // private field it seeds (`_swap`).
        // ignore: prefer_initializing_formals
        _swap = swap {
    _eventSub = _api.events.listen(_onEvent);
    _progressSub = _api.progress.listen(_onProgress);
  }

  final MovaApi _api;
  final MovaSwapCtl? _swap;

  /// The ad configuration snapshot this controller runs on.
  ///
  /// 本控制器运行所依据的广告配置快照。
  final MovaAdConfig _cfg;
  final List<MovaAdBreak> _breaks;
  final void Function(MovaAdEvent)? _onAdEvent;
  final bool _enabled;
  StreamSubscription<MovaEvent>? _eventSub;
  StreamSubscription<MovaProg>? _progressSub;
  final StreamController<void> _changes = StreamController<void>.broadcast();
  final StreamController<void> _contentEnded = StreamController<void>.broadcast();
  final StreamController<Object> _contentError = StreamController<Object>.broadcast();

  /// The resolved content source, memoised; null until it has been resolved.
  ///
  /// 已解析的正片源缓存；解析前为 null。
  MovaSource? _content;

  /// The pending resolver for a [loadDeferred] call; null on the plain [load]
  /// path.
  ///
  /// [loadDeferred] 调用留下的待解析器；普通 [load] 路径上为 null。
  MovaSourceResolver? _resolve;

  /// The in-flight resolution, shared by every caller until it settles.
  ///
  /// 在途的解析，在其结算前由所有调用方共享。
  Future<MovaSource?>? _resolving;
  _Phase _phase = _Phase.idle;
  MovaAdBreak? _current;
  final Set<MovaAdBreak> _played = <MovaAdBreak>{};
  Duration _contentResumeAt = Duration.zero;
  Duration _adPosition = Duration.zero;

  /// The most recent content position seen on the progress stream; the resume
  /// point for a runtime-inserted ad ([playAdNow]).
  ///
  /// 进度流上最近看到的正片位置；运行时插播广告（[playAdNow]）的续播点。
  Duration _lastContentPosition = Duration.zero;

  /// Whether STT recognition was running when the current ad began, so it is
  /// restored only if the host actually had it on.
  ///
  /// 当前广告开始时 STT 识别是否在运行，以便只在宿主本就开启时才恢复。
  bool _sttWasRunning = false;

  /// Enforces [MovaAdBreak.duration] for the ad on screen; null when the
  /// current break has no fixed slot length.
  ///
  /// 为屏幕上的广告落实 [MovaAdBreak.duration]；当前广告位没有固定时长时为 null。
  Timer? _slotTimer;

  /// Guards against two resume paths firing in the same tick.
  ///
  /// The slot timer expiring, the media's own [MovaDone] and the viewer's
  /// [skip] are now three independent clocks that can land together; without
  /// this the content would be opened twice.
  ///
  /// 防止两条续播路径在同一 tick 内同时触发。
  ///
  /// 广告位定时器到期、素材自身的 [MovaDone]、观众的 [skip]，如今是三个可能撞在
  /// 一起的独立时钟；没有这道守卫，正片会被 open 两次。
  bool _resuming = false;

  /// The break counting down / warming up in [_Phase.pending].
  ///
  /// [_Phase.pending] 阶段正在倒计时 / 预热中的广告位。
  MovaAdBreak? _pending;

  /// Fires when the pending break's [MovaAdBreak.delay] runs out; null when
  /// the pending break has no visible countdown.
  ///
  /// 待播广告位的 [MovaAdBreak.delay] 走完时触发；该广告位没有可见倒计时时为 null。
  Timer? _delayTimer;

  /// The content position the pending phase began at, used to render the
  /// countdown.
  ///
  /// Derived from the progress stream rather than a wall clock on purpose: the
  /// countdown is a *display* value, and the content position is the one
  /// number that is already ticking in front of the viewer. Expiry itself is
  /// still driven by [_delayTimer], never by this.
  ///
  /// 进入待播阶段时的正片位置，用于渲染倒计时。
  ///
  /// 刻意取自进度流而非墙钟：倒计时是一个*展示*值，而正片位置正是此刻已经在
  /// 观众眼前走动的那个数。到期判定本身仍由 [_delayTimer] 驱动，绝不由它决定。
  Duration _pendingFrom = Duration.zero;

  /// Whether an ad is currently on screen.
  ///
  /// 当前是否正在播放广告。
  bool get isShowingAd => _phase == _Phase.ad;

  /// The ad break currently playing, or null when none is.
  ///
  /// 当前正在播放的广告位；无则为 null。
  MovaAdBreak? get currentBreak => _current;

  /// Whether an ad is counting down to take over while the content still
  /// plays.
  ///
  /// 是否有一条广告正在倒计时、即将接管，而正片仍在播放。
  bool get isAdPending => _phase == _Phase.pending;

  /// The break that is counting down, or null when none is.
  ///
  /// 正在倒计时的广告位；没有则为 null。
  MovaAdBreak? get pendingBreak => _pending;

  /// Time left before the pending ad takes over, or null when none is pending
  /// or the pending break has no visible countdown.
  ///
  /// Null for the default mid-roll shape (`delay == 0`, waiting silently for
  /// readiness): that wait is meant to be invisible, so there is nothing to
  /// render.
  ///
  /// 距待播广告接管还剩的时长；没有待播广告、或待播广告位没有可见倒计时时为 null。
  ///
  /// 中插的默认形态（`delay == 0`、静默等待就绪）下返回 null：那段等待本就该是
  /// 用户无感的，没有任何东西需要渲染。
  Duration? get delayRemaining {
    final b = _pending;
    if (b == null || b.delay <= Duration.zero) return null;
    final elapsed = _lastContentPosition - _pendingFrom;
    final left = b.delay - elapsed;
    return left > Duration.zero ? left : Duration.zero;
  }

  /// Elapsed time into the current ad (from zero).
  ///
  /// 当前广告已播放的时长（从零开始）。
  Duration get adPosition => _adPosition;

  /// Whether the current ad may be skipped right now.
  ///
  /// 当前广告此刻是否可跳过。
  bool get canSkip {
    final after = _current?.skippableAfter;
    return after != null && _adPosition >= after;
  }

  /// Time remaining until the current ad becomes skippable, or null when the
  /// ad is not skippable at all.
  ///
  /// 距当前广告可跳过还剩的时长；广告完全不可跳过时为 null。
  Duration? get skipIn {
    final after = _current?.skippableAfter;
    if (after == null) return null;
    final remaining = after - _adPosition;
    return remaining > Duration.zero ? remaining : Duration.zero;
  }

  /// Fires whenever the ad phase or current break changes (start/end/skip);
  /// UI can rebuild off this in addition to the progress stream.
  ///
  /// 每当广告阶段或当前广告位变化（开始/结束/跳过）时发出；UI 可据此（外加进度流）
  /// 重建。
  Stream<void> get changes => _changes.stream;

  /// Fires once the content has fully finished — after it completes and any
  /// post-rolls have played. The composition seam for advancing a
  /// `MovaPlistCtrl` (with its own `autoPlayNext` off) without racing on
  /// [MovaDone].
  ///
  /// 在正片彻底结束后触发一次——即正片播完且所有后贴片也播完之后。用作在不与
  /// [MovaDone] 争抢的前提下推进 `MovaPlistCtrl`（其 `autoPlayNext` 关闭）
  /// 的组合接缝。
  Stream<void> get contentEnded => _contentEnded.stream;

  /// Fires when the content source resolver passed to [loadDeferred] failed;
  /// carries the thrown object.
  ///
  /// 当传给 [loadDeferred] 的正片源解析器失败时触发；携带抛出的对象。
  Stream<Object> get contentError => _contentError.stream;

  /// Loads [content] with its scheduled ads: plays a pre-roll first when one is
  /// configured, otherwise starts the content directly.
  ///
  /// 带排期广告地加载 [content]：配置了前贴片则先播它，否则直接起播正片。
  ///
  /// - [content]: the main content source / 正片源
  Future<void> load(MovaSource content) async {
    _content = content;
    _resolve = null;
    await _beginLoad();
  }

  /// Loads content whose source is resolved lazily, with its scheduled ads.
  ///
  /// Behaves exactly like [load] except that [resolve] is not called until the
  /// content is actually about to be opened — after every pre-roll has
  /// finished, or (when seamless swapping is on) a couple of seconds before
  /// the last pre-roll ends, when the content starts warming up. The result is
  /// memoised: [resolve] is called at most once per [loadDeferred].
  ///
  /// If [resolve] throws or rejects, the controller goes idle and the error is
  /// reported on [contentError]; the host decides whether to call
  /// [loadDeferred] again.
  ///
  /// 带排期广告地加载一段"源需要惰性解析"的正片。
  ///
  /// 与 [load] 完全相同，区别只在于 [resolve] 直到正片真的要被打开时才调用——
  /// 即所有前贴片播完之后，或（开启无缝切换时）最后一条前贴片结束前一两秒、
  /// 正片开始预热之时。结果会被记忆化：每次 [loadDeferred] 最多调用一次
  /// [resolve]。
  ///
  /// [resolve] 抛出或 reject 时，控制器转入空闲，错误经 [contentError] 上报；
  /// 是否重新调用 [loadDeferred] 由宿主决定。
  ///
  /// - [resolve]: resolves the content source on demand / 按需解析正片源
  ///
  /// Example / 示例:
  /// ```dart
  /// await ads.loadDeferred(() async {
  ///   final play = await api.requestPlayback(videoId);  // DRM / signed URL
  ///   return MovaSource(play.url, title: play.title);
  /// });
  /// ```
  Future<void> loadDeferred(MovaSourceResolver resolve) async {
    _content = null;
    _resolve = resolve;
    await _beginLoad();
  }

  /// The shared start-of-playback path for [load] and [loadDeferred]: resets
  /// per-load bookkeeping, then plays the first pre-roll or the content.
  ///
  /// [load] 与 [loadDeferred] 共用的起播路径：重置每次加载的簿记，然后播放第一条
  /// 前贴片或正片。
  Future<void> _beginLoad() async {
    _played.clear();
    _contentResumeAt = Duration.zero;
    _lastContentPosition = Duration.zero;
    // Fail loudly on a misconfigured schedule, on developer machines only.
    //
    // 配错的排期要大声失败，且只在开发者机器上。
    for (final b in _breaks) {
      b.assertValid();
    }
    if (_enabled) {
      final pre = _firstOfKind(MovaAdBreakKind.pre);
      if (pre != null) {
        await _playAd(pre);
        return;
      }
    }
    await _playContent();
  }

  /// Returns the content source, resolving and memoising it on first use.
  ///
  /// Returns null when there is nothing to resolve, or when the host's
  /// resolver failed — in which case the failure has already been reported on
  /// [contentError] and the lazy slot has been reset so a later
  /// [loadDeferred] can retry.
  ///
  /// 返回正片源，首次使用时解析并记忆化。
  ///
  /// 无可解析内容、或宿主的解析器失败时返回 null——后者已经把失败上报到
  /// [contentError]，并重置了惰性槽，使之后的 [loadDeferred] 能重试。
  Future<MovaSource?> _contentSource() {
    final cached = _content;
    if (cached != null) return Future<MovaSource?>.value(cached);
    final resolve = _resolve;
    if (resolve == null) return Future<MovaSource?>.value(null);
    // Share one in-flight resolution: the warm-up path calls this on every
    // progress tick, and the host's resolver must still be called exactly once.
    //
    // 共享同一次在途解析：预热路径每个进度 tick 都会调用本方法，而宿主的解析器
    // 仍必须恰好只被调用一次。
    return _resolving ??= _doResolve(resolve);
  }

  /// Runs [resolve] once, memoising the result and clearing the in-flight slot.
  ///
  /// 执行一次 [resolve]，记忆化结果并清空在途槽位。
  Future<MovaSource?> _doResolve(MovaSourceResolver resolve) async {
    try {
      final resolved = await resolve();
      _content = resolved;
      return resolved;
    } catch (e) {
      _resolve = null;
      if (!_contentError.isClosed) _contentError.add(e);
      return null;
    } finally {
      _resolving = null;
    }
  }

  /// Immediately interrupts the content to play [ad] at an arbitrary point,
  /// then resumes the content where it was interrupted. For ads scheduled at
  /// runtime rather than pre-configured in [MovaAdConfig.breaks]; only fires
  /// while content is actually playing. [ad] should be a
  /// [MovaAdBreakKind.mid] break — its own [MovaAdBreak.offset] is ignored, "now"
  /// is the current content position.
  ///
  /// 立即打断正片，在任意时点插播 [ad]，播完回到打断处续播。用于运行时（而非
  /// 在 [MovaAdConfig.breaks] 预配置）插播的广告；仅在正片确实在播放时生效。[ad]
  /// 应为 [MovaAdBreakKind.mid]——其自身的 [MovaAdBreak.offset] 被忽略，"当下"即当前
  /// 正片位置。
  ///
  /// - [ad]: the ad break to insert now / 要即时插入的广告位
  ///
  /// Example / 示例:
  /// ```dart
  /// ads.playAdNow(const MovaAdBreak(
  ///   kind: MovaAdBreakKind.mid,
  ///   source: MovaSource('https://host/flash-sale.mp4'),
  ///   skippableAfter: Duration(seconds: 5),
  /// ));
  /// ```
  Future<void> playAdNow(MovaAdBreak ad) async {
    // A no-op while one is already queued: only one ad may be pending at a
    // time, and cancelling a queued ad is a host product decision, not the
    // player's.
    //
    // 已经有一条在排队时为空操作：同一时刻只允许一条待播广告，而取消一条已排队
    // 的广告是宿主的产品决策，不是播放器的。
    if (_phase != _Phase.content) return;
    _contentResumeAt = _lastContentPosition;
    if (ad.delay > Duration.zero || _wantsWait(ad)) {
      _beginDelay(ad);
      return;
    }
    await _playAd(ad);
  }

  /// Skips the current ad if it is skippable right now; no-op otherwise.
  ///
  /// Also a no-op in [_Phase.pending]: there is no ad on screen to skip yet,
  /// and cancelling an ad that is about to play is a host product decision.
  ///
  /// 若当前广告此刻可跳过则跳过；否则为空操作。
  ///
  /// 在 [_Phase.pending] 阶段同样是空操作：屏幕上还没有广告可跳，而"取消一条
  /// 即将播放的广告"是宿主的产品决策。
  void skip() {
    if (_phase != _Phase.ad || !canSkip) return;
    final b = _current!;
    _fire(MovaAdEventType.skipped, b);
    unawaited(_resumeAfterAd(b));
  }

  /// Reports a click on the current ad; the host acts on
  /// [MovaAdBreak.clickThroughUrl], the library does not navigate.
  ///
  /// 上报一次对当前广告的点击；由宿主处理 [MovaAdBreak.clickThroughUrl]，库不跳转。
  void notifyClicked() {
    final b = _current;
    if (b != null) _fire(MovaAdEventType.clicked, b);
  }

  /// Returns the first not-yet-played break of [kind], or null.
  ///
  /// 返回首个尚未播放的、类型为 [kind] 的广告位；没有则为 null。
  /// Returns the next unplayed mid-roll inserted at the same point as the one
  /// that just finished, or null when the pod is exhausted.
  ///
  /// "The same point" means an offset at or before the current resume
  /// position — that is what makes two breaks one pod. Later mid-rolls are
  /// deliberately excluded: chaining into those would not be a pod, it would
  /// be playing the rest of the schedule back to back.
  ///
  /// 返回与刚播完那条插在同一位置的下一条未播中插；pod 已耗尽时返回 null。
  ///
  /// "同一位置"指 offset 不晚于当前续播点——这正是两条广告算作同一个 pod 的
  /// 定义。更晚的中插被刻意排除：串到那些上去就不是 pod 了，而是把剩下的排期
  /// 一口气连播完。
  MovaAdBreak? _nextPodMid() {
    for (final b in _breaks) {
      if (b.kind == MovaAdBreakKind.mid &&
          !_played.contains(b) &&
          b.offset <= _contentResumeAt) {
        return b;
      }
    }
    return null;
  }

  MovaAdBreak? _firstOfKind(MovaAdBreakKind kind) {
    for (final b in _breaks) {
      if (b.kind == kind && !_played.contains(b)) return b;
    }
    return null;
  }

  /// Whether [b] should be warmed up and cut to only once it is ready.
  ///
  /// Waiting needs somewhere to warm up in; with no swap engine the whole
  /// question is moot and the per-kind default never even gets consulted. The
  /// three-layer override (break → injected policy → per-kind default) lives
  /// entirely inside [MovaAdConfig.waitsFor] — this controller must never
  /// branch on [MovaAdBreakKind] itself, or the host's override would become
  /// unreachable.
  ///
  /// [b] 是否应当先预热、待其就绪后才切入。
  ///
  /// 等待需要一个可供预热之处；没有切换引擎时这个问题根本不成立，按类型的
  /// 默认值压根不会被查询。三层覆盖（广告位 → 注入策略 → 按 kind 默认）完全封在
  /// [MovaAdConfig.waitsFor] 里——本控制器绝不自行对 [MovaAdBreakKind] 分支，
  /// 否则宿主的覆盖就绕不过去了。
  bool _wantsWait(MovaAdBreak b) {
    final swap = _swap;
    return swap != null && swap.swapEnabled && _cfg.waitsFor(b);
  }

  /// Enters [_Phase.pending] for [b]: the content plays on while the countdown
  /// runs and/or the ad warms up in the background.
  ///
  /// [b] is marked played immediately so the countdown window cannot keep
  /// re-matching it on every tick.
  ///
  /// 为 [b] 进入 [_Phase.pending]：倒计时走动和/或广告后台预热期间，正片继续播放。
  ///
  /// [b] 会被立刻标记为已播，使倒计时窗口内不会每个 tick 都重复命中它。
  void _beginDelay(MovaAdBreak b) {
    _phase = _Phase.pending;
    _pending = b;
    _pendingFrom = _lastContentPosition;
    _played.add(b);
    _cancelDelayTimer();
    _fire(MovaAdEventType.pending, b);
    _changes.add(null);
    // Only a host-configured delay produces a countdown timer. With no delay
    // the pending phase is entered and left in one go, and the readiness wait
    // (if any) happens inside [_beginAd] — so "at least the countdown, at most
    // the countdown plus the readiness timeout" holds either way.
    //
    // 只有宿主配置的 delay 才会起倒计时定时器。没有 delay 时待播阶段进入即离开，
    // 就绪等待（若有）发生在 [_beginAd] 内部——因此"至少走完倒计时、最多再加一个
    // 就绪超时"这条在两种情形下都成立。
    if (b.delay > Duration.zero) {
      _delayTimer = Timer(b.delay, () {
        if (_phase != _Phase.pending || !identical(_pending, b)) return;
        unawaited(_beginAd(b));
      });
    } else {
      unawaited(_beginAd(b));
    }
  }

  /// Cancels the delay countdown timer, if one is running.
  ///
  /// 取消倒计时定时器（若有）。
  void _cancelDelayTimer() {
    _delayTimer?.cancel();
    _delayTimer = null;
  }

  /// Hands the screen over to [b] once its pending phase is done.
  ///
  /// 待播阶段结束后，把画面交给 [b]。
  Future<void> _beginAd(MovaAdBreak b) async {
    _cancelDelayTimer();
    _pending = null;
    await _playAd(b);
  }

  /// Switches playback to ad break [b].
  ///
  /// 把播放切换到广告位 [b]。
  Future<void> _playAd(MovaAdBreak b) async {
    _cancelSlotTimer();
    // Suppress content-side STT while the ad plays; restore it on resume only
    // if the host actually had it running (attach() does not reset it).
    //
    // 广告播放期间抑制正片侧 STT；仅当宿主本就在运行时才在续播时恢复
    // （attach() 不会重置它）。
    _sttWasRunning = _api.stt.isRunning;
    if (_sttWasRunning) unawaited(_api.stt.stop());
    _phase = _Phase.ad;
    _current = b;
    _adPosition = Duration.zero;
    _played.add(b);
    _changes.add(null);
    _fire(MovaAdEventType.started, b);
    // Drop any shadow warmed for a previous ad in the same pod — it targeted
    // the wrong resume point (or the content, mid-pod) and is no longer
    // useful.
    //
    // 丢弃为同一 pod 里上一条广告预热的影子——它的落点已经不对（或者压根
    // 预热的是正片，而这里正是 pod 连播中途），不再有用。
    unawaited(_swap?.abandon());
    await _api.open(b.source);
    // With durationFromFirstFrame off the slot is counted from open(); with it
    // on, the first progress tick arms the timer instead.
    //
    // durationFromFirstFrame 关闭时广告位从 open() 起算；开启时改由第一个进度
    // tick 起表。
    if (!_cfg.durationFromFirstFrame) _armSlotTimer(b);
  }

  /// Starts the fixed-length slot timer for [b], if it has a
  /// [MovaAdBreak.duration] and one is not already running.
  ///
  /// The deadline is a plain [Timer]: the media timeline is never consulted
  /// and never seeked, because a large file's duration can take a long time to
  /// resolve on a real mobile network and a seek near the real EOF reliably
  /// wedges the player on device.
  ///
  /// 为 [b] 起固定时长的广告位定时器——前提是它有 [MovaAdBreak.duration] 且尚未
  /// 起表。
  ///
  /// 到期判定是一个普通 [Timer]：完全不查询、不 seek 媒体时间轴，因为大文件的
  /// 时长在真机移动网络下可能很久解析不出来，而靠近真实 EOF 的 seek 在真机上会
  /// 可靠地把播放器卡死。
  void _armSlotTimer(MovaAdBreak b) {
    final d = b.duration;
    if (d == null || _slotTimer != null) return;
    _slotTimer = Timer(d, () {
      if (_phase != _Phase.ad || !identical(_current, b)) return;
      // The slot the advertiser bought has been delivered in full, so this is
      // a completion, not a skip.
      //
      // 广告主买下的这段时长已经足额交付，因此这是"播完"，不是"跳过"。
      _fire(MovaAdEventType.completed, b);
      unawaited(_resumeAfterAd(b));
    });
  }

  /// Cancels any running slot timer.
  ///
  /// 取消正在运行的广告位定时器（若有）。
  void _cancelSlotTimer() {
    _slotTimer?.cancel();
    _slotTimer = null;
  }

  /// Switches playback to the content, optionally resuming at [at]. Tries a
  /// seamless swap first when [_swap] is configured; falls back to the plain
  /// `open()`/`seek()` path when swapping is disabled, was never warmed, or
  /// failed.
  ///
  /// Uses `commit(waitForReady: true)` rather than a bare `commit()`: the ad
  /// ending (`MovaDone`) and the shadow's readiness policy reporting `ready`
  /// are two independent clocks, and by design the shadow is only asked to
  /// warm up in the ad's last couple of seconds (see [MovaLeadWarm]) — so it
  /// is common for the shadow to still be `warming`, not yet `ready`, at the
  /// exact instant the ad's last frame plays. A bare `commit()` would treat
  /// that near-miss as an outright failure and fall back to a full `open()`
  /// rebuild, defeating the swap almost every time. Waiting lets the commit
  /// succeed as soon as the shadow catches up, bounded by the readiness
  /// policy's own timeout — worst case it degrades to the same fallback, just
  /// a little later.
  ///
  /// 把播放切换回正片，可选地从 [at] 续播。配置了 [_swap] 时先尝试无缝切换；
  /// 切换被禁用、从未预热过、或切换失败时回落到普通 `open()`/`seek()` 路径。
  ///
  /// 用 `commit(waitForReady: true)` 而非裸 `commit()`：广告结束（`MovaDone`）
  /// 和影子引擎的就绪判据报告 `ready` 是两个独立的时钟——按设计，影子只在广告
  /// 最后一两秒才被要求预热（见 [MovaLeadWarm]），所以广告最后一帧播放的那个
  /// 精确瞬间，影子往往还处于 `warming`、尚未 `ready`，是很常见的情况。裸
  /// `commit()` 会把这种"差一点点"直接判为失败、回落到完整的 `open()` 重建，
  /// 导致无缝切换几乎每次都落空。等待能让影子一追上就立刻提交成功，且受就绪
  /// 判据自身的超时约束——最坏情况也只是稍晚一点退化到同样的回落路径。
  Future<void> _playContent({Duration at = Duration.zero}) async {
    _cancelSlotTimer();
    _cancelDelayTimer();
    _phase = _Phase.content;
    _current = null;
    _pending = null;
    _changes.add(null);
    final c = await _contentSource();
    if (c == null) return;
    final swap = _swap;
    if (swap != null && await swap.commit(waitForReady: true)) {
      // Already seamlessly switched to the content by the warmed shadow;
      // no open/seek needed.
      //
      // 已由预热好的影子无缝切到正片；无需再 open/seek。
    } else {
      await _api.open(c);
      if (at > Duration.zero) await _api.seek(at);
    }
    // Restore STT only if it was running before the ad interrupted content.
    //
    // 仅当广告打断正片前 STT 在运行时才恢复。
    if (_sttWasRunning) {
      _sttWasRunning = false;
      unawaited(_api.stt.start());
    }
  }

  /// Reacts to end-of-media: an ad completing resumes content; content
  /// completing plays a post-roll (if any) then goes idle.
  ///
  /// 响应媒体播放结束：广告播完则续播正片；正片播完则播后贴片（若有）再转空闲。
  void _onEvent(MovaEvent e) {
    if (e is! MovaDone) return;
    if (_phase == _Phase.ad) {
      final finished = _current;
      if (finished == null) return;
      _fire(MovaAdEventType.completed, finished);
      unawaited(_resumeAfterAd(finished));
    } else if (_phase == _Phase.content || _phase == _Phase.pending) {
      // The content ended while a mid-roll was queued behind it: that break is
      // scheduled *inside* the content, so with the content gone it is moot.
      //
      // 正片在一条中插排队期间播完了：那条广告位是排在正片*内部*的，正片没了
      // 它也就没有意义了。
      if (_phase == _Phase.pending) {
        _cancelDelayTimer();
        _pending = null;
        unawaited(_swap?.abandon());
      }
      final post = _enabled ? _firstOfKind(MovaAdBreakKind.post) : null;
      if (post != null) {
        unawaited(_playAd(post));
      } else {
        _goIdleAfterContent();
      }
    }
  }

  /// Transitions to idle after the content (and its post-rolls) finished, and
  /// signals [contentEnded] for playlist composition.
  ///
  /// 在正片（及其后贴片）播完后转入空闲，并触发 [contentEnded] 供播放列表组合使用。
  void _goIdleAfterContent() {
    _cancelSlotTimer();
    _cancelDelayTimer();
    _phase = _Phase.idle;
    _current = null;
    _pending = null;
    _changes.add(null);
    _contentEnded.add(null);
  }

  /// Resumes the right thing after ad [finished] ends: pre → content from the
  /// start, mid → content at the saved position, post → idle (done).
  ///
  /// 广告 [finished] 结束后续播正确内容：前贴片 → 正片从头，中插 → 正片从保存
  /// 位置，后贴片 → 空闲（结束）。
  Future<void> _resumeAfterAd(MovaAdBreak finished) async {
    if (_resuming) return;
    _resuming = true;
    _cancelSlotTimer();
    switch (finished.kind) {
      case MovaAdBreakKind.pre:
        // Ad pod: chain any further pre-rolls before the content starts.
        //
        // 广告 pod：正片开始前，依次连播其余前贴片。
        final nextPre = _firstOfKind(MovaAdBreakKind.pre);
        _resuming = false;
        if (nextPre != null) {
          await _playAd(nextPre);
        } else {
          await _playContent();
        }
      case MovaAdBreakKind.mid:
        // Ad pod: chain straight into the next mid-roll inserted at the same
        // point. Without this the second break of a pod only plays after the
        // content has been resumed and ticked once — which flashes the content
        // between two ads and, now that pending exists, would pop a second
        // countdown. Only the *first* break of a pod ever goes through
        // [_beginDelay]; chained ones go straight to [_playAd].
        //
        // 广告 pod：直接串到插在同一位置的下一条中插。没有这一步，pod 的第二条
        // 要等正片被续播、再 tick 一次才播——这会在两条广告之间闪一下正片，而且
        // 在有了待播阶段之后还会再弹一次倒计时。一个 pod 里只有*第一条*会经过
        // [_beginDelay]，被串联的后续几条一律直接走 [_playAd]。
        final nextMid = _nextPodMid();
        _resuming = false;
        if (nextMid != null) {
          await _playAd(nextMid);
        } else {
          await _playContent(at: _contentResumeAt);
        }
      case MovaAdBreakKind.post:
        // Ad pod: chain any further post-rolls before going idle.
        //
        // 广告 pod：转入空闲前，依次连播其余后贴片。
        final nextPost = _firstOfKind(MovaAdBreakKind.post);
        _resuming = false;
        if (nextPost != null) {
          await _playAd(nextPost);
        } else {
          _goIdleAfterContent();
        }
    }
  }

  /// Tracks ad elapsed time, and while playing content triggers a due mid-roll,
  /// saving the content position to resume at afterwards.
  ///
  /// 跟踪广告已播时长；播放正片期间触发到期的中插，并保存正片位置以便之后续播。
  void _onProgress(MovaProg p) {
    if (_phase == _Phase.ad) {
      _adPosition = p.position;
      // First rendered frame of this ad: the slot the advertiser bought is
      // *visible* seconds, so a slow load must not eat into it.
      //
      // 这条广告的首个已渲染帧：广告主买的是*可见*秒数，加载慢不应该吃掉这段时长。
      final playing = _current;
      if (_cfg.durationFromFirstFrame && playing != null) _armSlotTimer(playing);
      // Ask the configured trigger whether it is time to start warming the
      // content up in the background; the trigger (not this controller)
      // decides based on how much of the ad is left and how long it is.
      //
      // 询问已配置的触发策略此刻是否该开始在后台预热正片；由触发策略（而非
      // 本控制器）根据广告剩余时长与广告总时长决定。
      final swap = _swap;
      if (swap != null && swap.swapEnabled) {
        final adDuration = _api.state.duration;
        unawaited(_warmContentBehindAd(
          swap,
          MovaWarmCue(remaining: adDuration - _adPosition, total: adDuration),
        ));
      }
      return;
    }
    if (_phase == _Phase.pending) {
      // The content deliberately plays on. The resume point tracks the live
      // position, so it ends up being where the ad *actually* takes over — not
      // where the countdown started. No further mid-roll may be triggered from
      // here: one pending ad at a time.
      //
      // 正片刻意继续播放。续播点跟随实时位置，因此最终取到的是广告*真正*接管
      // 那一刻的位置，而不是倒计时开始那一刻。此阶段不得再触发别的中插：
      // 同一时刻只排队一条待播广告。
      _lastContentPosition = p.position;
      _contentResumeAt = p.position;
      return;
    }
    if (_phase == _Phase.content) {
      _lastContentPosition = p.position;
      if (_enabled) {
        final due = dueMidRoll(_breaks, p.position, _played);
        if (due != null) {
          _contentResumeAt = p.position;
          // A countdown, a background warm-up, or both, put the break through
          // the pending phase first; otherwise it takes over immediately, the
          // way it always has.
          //
          // 有倒计时、有后台预热、或两者兼有时，先让该广告位走一遍待播阶段；
          // 否则立刻接管，与一贯行为相同。
          if (due.delay > Duration.zero || _wantsWait(due)) {
            _beginDelay(due);
          } else {
            unawaited(_playAd(due));
          }
        }
      }
    }
  }

  /// Warms the content up behind the currently playing ad, resolving the
  /// content source first when it was deferred.
  ///
  /// Uses the default [MovaWarmPlan]: the ad→content direction keeps the
  /// shadow rolling and is lead-timed, exactly as in 0.4.0.
  ///
  /// 在正在播放的广告背后预热正片；正片源是延迟解析的则先解析。
  ///
  /// 使用默认的 [MovaWarmPlan]：ad→content 方向的影子一路播着、按提前量触发，
  /// 与 0.4.0 完全一致。
  Future<void> _warmContentBehindAd(MovaSwapCtl swap, MovaWarmCue cue) async {
    final content = await _contentSource();
    if (content == null) return;
    if (_phase != _Phase.ad) return;
    await swap.prepare(content, at: _contentResumeAt, cue: cue);
  }

  /// Notifies the host hook of an ad lifecycle [type] for break [b].
  ///
  /// 就广告位 [b] 的生命周期 [type] 通知宿主钩子。
  void _fire(MovaAdEventType type, MovaAdBreak b) => _onAdEvent?.call(MovaAdEvent(type, b));

  /// Releases subscriptions and closes the change stream; call once on
  /// teardown.
  ///
  /// 释放订阅并关闭变更流；销毁时调用一次。
  Future<void> dispose() async {
    _cancelSlotTimer();
    _cancelDelayTimer();
    await _eventSub?.cancel();
    await _progressSub?.cancel();
    await _swap?.abandon();
    await _changes.close();
    await _contentEnded.close();
    await _contentError.close();
  }
}
