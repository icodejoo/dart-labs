import 'dart:async';

import '../api.dart';
import '../events/events.dart';
import '../model/ad.dart';
import '../model/source.dart';
import '../state/progress.dart';

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
  /// 创建绑定到 [api] 的控制器，初值取自 [MovaOpts.ads]。
  ///
  /// - [api]: the player capability surface to drive / 要驱动的播放器能力面
  ///
  /// Example / 示例:
  /// ```dart
  /// final ads = MovaAdCtrl(api);
  /// await ads.load(const MovaSource('https://host/movie.m3u8'));
  /// ```
  MovaAdCtrl(this._api)
      : _breaks = _api.options.ads.breaks,
        _onAdEvent = _api.options.ads.onAdEvent,
        _enabled = _api.options.ads.enabled {
    _eventSub = _api.events.listen(_onEvent);
    _progressSub = _api.progress.listen(_onProgress);
  }

  final MovaApi _api;
  final List<MovaAdBreak> _breaks;
  final void Function(MovaAdEvent)? _onAdEvent;
  final bool _enabled;
  StreamSubscription<MovaEvent>? _eventSub;
  StreamSubscription<MovaProg>? _progressSub;
  final StreamController<void> _changes = StreamController<void>.broadcast();
  final StreamController<void> _contentEnded = StreamController<void>.broadcast();

  MovaSource? _content;
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

  /// Loads [content] with its scheduled ads: plays a pre-roll first when one is
  /// configured, otherwise starts the content directly.
  ///
  /// 带排期广告地加载 [content]：配置了前贴片则先播它，否则直接起播正片。
  ///
  /// - [content]: the main content source / 正片源
  Future<void> load(MovaSource content) async {
    _content = content;
    _played.clear();
    _contentResumeAt = Duration.zero;
    _lastContentPosition = Duration.zero;
    if (_enabled) {
      final pre = _firstOfKind(MovaAdBreakKind.pre);
      if (pre != null) {
        await _playAd(pre);
        return;
      }
    }
    await _playContent();
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
    await _api.open(b.source);
  }

  /// Switches playback to the content, optionally resuming at [at].
  ///
  /// 把播放切换回正片，可选地从 [at] 续播。
  Future<void> _playContent({Duration at = Duration.zero}) async {
    _phase = _Phase.content;
    _current = null;
    _changes.add(null);
    final c = _content;
    if (c == null) return;
    await _api.open(c);
    if (at > Duration.zero) await _api.seek(at);
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
    await _changes.close();
    await _contentEnded.close();
  }
}
