import 'dart:async';

import '../api.dart';
import '../events/events.dart';
import '../model/ad.dart';
import '../model/source.dart';
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
      : _breaks = _api.options.ads.breaks,
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

  /// Whether an ad is currently on screen.
  ///
  /// 当前是否正在播放广告。
  bool get isShowingAd => _phase == _Phase.ad;

  /// The ad break currently playing, or null when none is.
  ///
  /// 当前正在播放的广告位；无则为 null。
  MovaAdBreak? get currentBreak => _current;

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
    if (_phase != _Phase.content) return;
    _contentResumeAt = _lastContentPosition;
    await _playAd(ad);
  }

  /// Skips the current ad if it is skippable right now; no-op otherwise.
  ///
  /// 若当前广告此刻可跳过则跳过；否则为空操作。
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
  MovaAdBreak? _firstOfKind(MovaAdBreakKind kind) {
    for (final b in _breaks) {
      if (b.kind == kind && !_played.contains(b)) return b;
    }
    return null;
  }

  /// Switches playback to ad break [b].
  ///
  /// 把播放切换到广告位 [b]。
  Future<void> _playAd(MovaAdBreak b) async {
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
    _phase = _Phase.content;
    _current = null;
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
    } else if (_phase == _Phase.content) {
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
    _phase = _Phase.idle;
    _current = null;
    _changes.add(null);
    _contentEnded.add(null);
  }

  /// Resumes the right thing after ad [finished] ends: pre → content from the
  /// start, mid → content at the saved position, post → idle (done).
  ///
  /// 广告 [finished] 结束后续播正确内容：前贴片 → 正片从头，中插 → 正片从保存
  /// 位置，后贴片 → 空闲（结束）。
  Future<void> _resumeAfterAd(MovaAdBreak finished) async {
    switch (finished.kind) {
      case MovaAdBreakKind.pre:
        // Ad pod: chain any further pre-rolls before the content starts.
        //
        // 广告 pod：正片开始前，依次连播其余前贴片。
        final nextPre = _firstOfKind(MovaAdBreakKind.pre);
        if (nextPre != null) {
          await _playAd(nextPre);
        } else {
          await _playContent();
        }
      case MovaAdBreakKind.mid:
        await _playContent(at: _contentResumeAt);
      case MovaAdBreakKind.post:
        // Ad pod: chain any further post-rolls before going idle.
        //
        // 广告 pod：转入空闲前，依次连播其余后贴片。
        final nextPost = _firstOfKind(MovaAdBreakKind.post);
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
    if (_phase == _Phase.content) {
      _lastContentPosition = p.position;
      if (_enabled) {
        final due = dueMidRoll(_breaks, p.position, _played);
        if (due != null) {
          _contentResumeAt = p.position;
          unawaited(_playAd(due));
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
    await _eventSub?.cancel();
    await _progressSub?.cancel();
    await _swap?.abandon();
    await _changes.close();
    await _contentEnded.close();
    await _contentError.close();
  }
}
