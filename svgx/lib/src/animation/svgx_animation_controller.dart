import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'shared_animation_clock.dart';
import 'svg_document_parser.dart';
import 'svgx_animation_info.dart';
import 'svgx_animation_quality.dart';
import 'timeline_events.dart';

/// Playback state of a document. / 文档播放状态。
enum SvgxPlaybackStatus {
  /// Awaiting a ready document. / 等待文档就绪。
  loading,

  /// Playback is requested. / 已请求播放。
  playing,

  /// Playback is paused. / 播放已暂停。
  paused,

  /// A playback boundary was reached. / 已到达播放边界。
  completed,

  /// Loading failed. / 加载失败。
  error,
}

/// Behavior at a selected range boundary. / 片段边界的播放行为。
enum SvgxRangeMode {
  /// Complete at the next boundary. / 到下一边界完成。
  once,

  /// Wrap to the opposite boundary. / 回绕到另一边界。
  loop,

  /// Reverse at each boundary. / 每次到边界时反向。
  pingPong,
}

/// A playback or identified-element event. / 播放事件或有标识元素事件。
sealed class SvgxAnimationEvent {
  /// Creates an event. / 创建事件。
  const SvgxAnimationEvent();
}

/// The primary document is ready. / 主文档已经就绪。
final class SvgxAnimationLoaded extends SvgxAnimationEvent {
  /// Carries the loaded document's information. / 携带就绪文档信息。
  const SvgxAnimationLoaded(this.info);

  /// Ready document information. / 就绪文档信息。
  final SvgxAnimationInfo info;
}

/// The first playback tick has arrived. / 首个播放 tick 已到达。
final class SvgxAnimationStarted extends SvgxAnimationEvent {
  /// Creates a start event. / 创建开始事件。
  const SvgxAnimationStarted();
}

/// Playback reached its directional boundary. / 播放到达当前方向的边界。
final class SvgxAnimationCompleted extends SvgxAnimationEvent {
  /// Reports whether a finite document naturally ended in forward playback.
  /// 指示是否为有限文档正向自然播放结束。
  const SvgxAnimationCompleted({this.natural = false});

  /// True only for forward completion without a selected range.
  /// 仅无选定片段的正向自然结束为 true。
  final bool natural;
}

/// A steady-state document period was crossed. / 穿越了文档稳态周期。
final class SvgxAnimationLooped extends SvgxAnimationEvent {
  /// Carries the positive period number. / 携带正数周期序号。
  const SvgxAnimationLooped(this.iteration);

  /// One-based document period number. / 从一开始的文档周期序号。
  final int iteration;
}

/// A selected range wrapped around. / 选定片段发生回绕。
final class SvgxAnimationRangeLooped extends SvgxAnimationEvent {
  /// Carries the wrap count since range selection. / 携带选定片段后的回绕次数。
  const SvgxAnimationRangeLooped(this.iteration);

  /// One-based range wrap count. / 从一开始的片段回绕次数。
  final int iteration;
}

/// An identified animation began. / 有标识的动画开始。
final class SvgxAnimationElementBegin extends SvgxAnimationEvent {
  /// Carries the animation's identifier. / 携带动画标识。
  const SvgxAnimationElementBegin(this.id);

  /// Animation identifier. / 动画标识。
  final String id;

  /// Animation identifier alias. / 动画标识别名。
  String get elementId => id;
}

/// An identified animation ended. / 有标识的动画结束。
final class SvgxAnimationElementEnd extends SvgxAnimationEvent {
  /// Carries the animation's identifier. / 携带动画标识。
  const SvgxAnimationElementEnd(this.id);

  /// Animation identifier. / 动画标识。
  final String id;

  /// Animation identifier alias. / 动画标识别名。
  String get elementId => id;
}

/// An identified animation repeated. / 有标识的动画重复。
final class SvgxAnimationElementRepeat extends SvgxAnimationEvent {
  /// Carries the identifier and SMIL repeat detail. / 携带标识和 SMIL 重复序号。
  const SvgxAnimationElementRepeat(this.id, this.iteration);

  /// Animation identifier. / 动画标识。
  final String id;

  /// SMIL repeat detail, starting at one. / 从一开始的 SMIL 重复序号。
  final int iteration;

  /// Animation identifier alias. / 动画标识别名。
  String get elementId => id;
}

/// Loading or parsing failed. / 加载或解析失败。
final class SvgxAnimationError extends SvgxAnimationEvent {
  /// Carries the error and its stack. / 携带错误与调用栈。
  const SvgxAnimationError(this.error, this.stack);

  /// Original failure. / 原始错误。
  final Object error;

  /// Original failure stack. / 原始错误调用栈。
  final StackTrace stack;
}

/// Debug-only timeline query count for allocation-free-path tests.
/// 仅调试时累加的时间线查询次数，用于验证无监听者路径。
@visibleForTesting
int debugTimelineEventQueryCount = 0;

/// Safe document-time ceiling, matching SMIL's approximately 115 days.
/// 文档时间安全上限，与 SMIL 约 115 天的上限一致。
const _maxTimeMicros = 10000000 * Duration.microsecondsPerSecond;

/// One microsecond for inclusive/exclusive timeline endpoint conversion.
/// 一微秒，用于时间线开闭端点转换。
const _microsecond = Duration(microseconds: 1);

/// Default requested playback multiplier. / 默认请求播放倍率。
const _normalPlaybackRate = 1.0;

/// Unreflected range direction. / 尚未反射的片段方向。
const _forwardRangeDirection = 1;

/// Controls one document time shared by any number of animated widgets.
/// 控制可供任意多个动画控件共享的文档时间。
///
/// Use `seek(Duration(seconds: 1))` to redraw at a specific document time.
/// 使用 `seek(Duration(seconds: 1))` 可在指定文档时刻立即重绘。
class SvgxAnimationController extends ChangeNotifier {
  /// Creates a controller; [playbackRate] must be finite, and zero pauses.
  /// 创建控制器；[playbackRate] 必须有限，零表示暂停。
  SvgxAnimationController({
    bool autoplay = true,
    double playbackRate = _normalPlaybackRate,
  }) : assert(playbackRate.isFinite),
       _externallyDriven = false,
       _rate = playbackRate,
       _wantsPlay = autoplay && playbackRate != 0;

  /// Creates a clock-free controller for widget animation adaptation.
  /// 创建无时钟控制器，供控件适配外部动画。
  @internal
  SvgxAnimationController.externallyDriven()
    : _externallyDriven = true,
      _rate = _normalPlaybackRate,
      _wantsPlay = false;

  /// Whether document time comes exclusively from driveTo.
  /// 文档时间是否完全来自 driveTo。
  final bool _externallyDriven;

  /// Current document time notifier. / 当前文档时间通知器。
  final _time = ValueNotifier(Duration.zero);

  /// Ready widgets in readiness order. / 按就绪次序排列的控件。
  final _attachments = <Object, _Attachment>{};

  /// Cue callbacks grouped by document time. / 按文档时刻分组的 cue 回调。
  final _cues = <Duration, List<VoidCallback>>{};

  /// Explicit event subscribers. / 显式事件订阅者。
  final _eventListeners = <ValueChanged<SvgxAnimationEvent>>[];

  /// Shared-clock registration. / 共享时钟注册。
  ClockSubscription? _subscription;

  /// First sampled global time for this baseline. / 当前基线的首个全局采样时间。
  Duration? _anchorGlobal;

  /// Document time at the baseline. / 基线处的文档时间。
  Duration _anchorTime = Duration.zero;

  /// Current playback state. / 当前播放状态。
  SvgxPlaybackStatus _status = SvgxPlaybackStatus.loading;

  /// Primary ready document. / 第一个就绪的主文档。
  SvgDocument? _document;

  /// Requested playback direction and scale. / 请求的播放方向与倍率。
  double _rate;

  /// Reflection relative to the requested rate, reset on range selection.
  /// 相对请求倍率的反射方向，选择片段时复位。
  int _rangeDirection = _forwardRangeDirection;

  /// Effective signed speed including ping-pong reflection.
  /// 包含往返反射的有效有符号速率。
  double get _effectiveRate => _rate * _rangeDirection;

  /// Whether playback is requested independently of visibility. / 是否请求播放，不受可见性影响。
  bool _wantsPlay;

  /// Whether the current run already emitted started. / 当前播放是否已发出 started。
  bool _started = false;

  /// Selected range start, or null for the natural timeline. / 片段起点，null 表示自然时间线。
  Duration? _rangeStart;

  /// Selected range end. / 片段终点。
  Duration? _rangeEnd;

  /// Selected boundary behavior. / 选定的边界行为。
  SvgxRangeMode _rangeMode = SvgxRangeMode.once;

  /// Range wrap sequence. / 片段回绕序号。
  int _rangeIteration = 0;

  /// Revision used to stop dispatch after a reentrant control call. / 控制调用重入后停止派发的版本号。
  int _revision = 0;

  /// Whether resources have been disposed. / 资源是否已释放。
  bool _disposed = false;

  /// Current document time, immediately updated by [seek].
  /// 当前文档时间；[seek] 会立即更新。
  ValueListenable<Duration> get time {
    _assertAlive();
    return _time;
  }

  /// Current playback state. / 当前播放状态。
  SvgxPlaybackStatus get status {
    _assertAlive();
    return _status;
  }

  /// Information from the first ready attached document, or null.
  /// 第一个就绪挂载文档的信息，未就绪时为 null。
  SvgxAnimationInfo? get info {
    _assertAlive();
    return _document?.info;
  }

  /// Finite playback multiplier; negative reverses and zero pauses.
  /// 有限播放倍率；负数倒放，零暂停。
  double get playbackRate {
    _assertAlive();
    return _rate;
  }

  /// Changes speed continuously, without changing the displayed time.
  /// 连续改变速率，不改变当前显示时间。
  set playbackRate(double value) {
    _assertAlive();
    assert(value.isFinite);
    if (value == _rate) return;
    _revision++;
    _rebase();
    _rate = value;
    if (value == 0) _wantsPlay = false;
    if (_status == SvgxPlaybackStatus.completed) {
      _status = SvgxPlaybackStatus.paused;
    }
    _refreshStatus();
    _syncSubscription();
    notifyListeners();
  }

  /// Starts playback; at its directional boundary, restarts from the other end.
  /// 开始播放；已到当前方向边界时，从另一端重新开始。
  /// An unbounded loop has no reverse restart endpoint: at zero, first seek
  /// to a positive time or select a range to play backwards.
  /// 无上界循环没有倒放重播终点；在零时须先跳到正时间或选择片段再倒放。
  /// Ping-pong resumes its current reflected direction, including after pause.
  /// 往返模式沿当前反射方向恢复，暂停后也保留方向。
  void play() {
    _assertAlive();
    final revision = ++_revision;
    if (_atBoundary && _rate != 0) {
      final unboundedReverse =
          _effectiveRate < 0 &&
          _rangeEnd == null &&
          _document?.info.loops == true;
      _time.value = _effectiveRate < 0 && !unboundedReverse ? _upper : _lower;
      if (_disposed || revision != _revision) return;
      _started = false;
    }
    _wantsPlay = _rate != 0;
    if (_status == SvgxPlaybackStatus.completed) {
      _status = SvgxPlaybackStatus.paused;
    }
    _rebase();
    _refreshStatus();
    _syncSubscription();
    notifyListeners();
  }

  /// Pauses at the current sampled time. / 在当前采样时间暂停。
  void pause() {
    _assertAlive();
    _revision++;
    _wantsPlay = false;
    _refreshStatus();
    _syncSubscription();
    notifyListeners();
  }

  /// Pauses and seeks to the selected range start, or zero.
  /// 暂停并跳到选定片段起点，无片段时跳到零。
  void stop() {
    _assertAlive();
    pause();
    if (_disposed) return;
    seek(_lower);
  }

  /// Immediately seeks without firing crossed cues or element events.
  /// 立即跳转，不触发跨越的 cue 或元素事件。
  /// Seeking a completed run leaves it paused; call [play] to resume.
  /// 已完成时跳转会进入暂停状态；调用 [play] 可恢复播放。
  ///
  /// Clamps to the active bounds and an approximately 115-day safety ceiling.
  /// Large forward seeks can incur one-time work (about 9.5 ms for a measured
  /// 600 s to 3600 s jump in a three-dot animation).
  /// 钳位到当前边界与约 115 天安全上限；大幅前跳可能产生一次性开销
  /// （三点环实测从 600 秒跳到 3600 秒约需 9.5 毫秒）。
  void seek(Duration t) {
    _assertAlive();
    final revision = ++_revision;
    if (_status == SvgxPlaybackStatus.completed) {
      _wantsPlay = false;
      _status = SvgxPlaybackStatus.paused;
    }
    _time.value = _clamp(t);
    if (_disposed || revision != _revision) return;
    _rebase();
    _refreshStatus();
    _syncSubscription();
    notifyListeners();
  }

  /// Pushes external document time, clamping only below zero; emits crossings
  /// but never started/completed. Requires an externally driven controller.
  /// With [emitCrossings] false the jump behaves like [seek]: no cues or events.
  /// 推送外部文档时间，仅钳位负值；派发穿越事件但不发 started/completed。
  /// 要求使用外部驱动控制器。[emitCrossings] 为 false 时等同 [seek]，不派发
  /// cue 与事件。
  @internal
  void driveTo(Duration t, {bool emitCrossings = true}) {
    _assertAlive();
    assert(_externallyDriven);
    if (_document == null || _status == SvgxPlaybackStatus.error) return;
    final revision = ++_revision;
    final previous = _time.value;
    final next = t < Duration.zero ? Duration.zero : t;
    if (next == previous) return;
    _time.value = next;
    if (!emitCrossings || _disposed || revision != _revision) return;
    _dispatchCrossing(previous, next, revision);
  }

  /// Reverses the playback rate; a completed run resumes in the new direction.
  /// 反转播放倍率；已完成的播放会沿新方向恢复。
  /// Retains ping-pong reflection, reversing the current travel direction.
  /// 保留往返反射状态，反转当前实际行进方向。
  void reverse() {
    _assertAlive();
    final completed = _status == SvgxPlaybackStatus.completed;
    playbackRate = -_rate;
    if (!_disposed && completed) play();
  }

  /// Selects a nonempty, nonnegative range and its boundary behavior.
  /// 选择非空、非负片段及其边界行为。
  /// A completed run becomes paused. / 已完成的播放恢复为暂停状态。
  /// Resets ping-pong reflection to the sign of playbackRate.
  /// 将往返反射方向复位为 playbackRate 的符号方向。
  void setRange(
    Duration start,
    Duration end, {
    SvgxRangeMode mode = SvgxRangeMode.once,
  }) {
    _assertAlive();
    if (start < Duration.zero ||
        end <= start ||
        end.inMicroseconds > _maxTimeMicros) {
      throw ArgumentError('Expected 0 <= start < end within the time ceiling');
    }
    _revision++;
    _rangeStart = start;
    _rangeEnd = end;
    _rangeMode = mode;
    _rangeIteration = 0;
    _rangeDirection = _forwardRangeDirection;
    _recoverRange();
  }

  /// Restores the document's natural playback bounds.
  /// 恢复文档自然播放边界。
  /// Discards ping-pong reflection and uses the requested playbackRate.
  /// 丢弃往返反射方向，沿请求的 playbackRate 播放。
  void clearRange() {
    _assertAlive();
    _revision++;
    _rangeStart = null;
    _rangeEnd = null;
    _rangeIteration = 0;
    _rangeDirection = _forwardRangeDirection;
    _recoverRange();
  }

  /// Sets a forward rate fitting the natural duration into positive [target].
  /// 将正向倍率设为自然时长与正数 [target] 的比值。
  /// Throws [StateError] if no natural duration is known.
  /// 自然时长未知时抛出 [StateError]。
  void fitDuration(Duration target) {
    _assertAlive();
    if (target <= Duration.zero) throw ArgumentError.value(target, 'target');
    final natural = _document?.info.naturalDuration;
    if (natural == null) {
      throw StateError('No known natural animation duration');
    }
    playbackRate = natural.inMicroseconds / target.inMicroseconds;
  }

  /// Calls [callback] whenever playback crosses nonnegative document time [at].
  /// 播放穿越非负文档时刻 [at] 时调用 [callback]。
  void addCue(Duration at, VoidCallback callback) {
    _assertAlive();
    if (at < Duration.zero) throw ArgumentError.value(at, 'at');
    (_cues[at] ??= []).add(callback);
  }

  /// Removes one matching cue registration. / 移除一个匹配的 cue 注册。
  void removeCue(Duration at, VoidCallback callback) {
    _assertAlive();
    final callbacks = _cues[at];
    callbacks?.remove(callback);
    if (callbacks?.isEmpty ?? false) _cues.remove(at);
  }

  /// Adds an event listener. / 添加事件监听者。
  void addEventListener(ValueChanged<SvgxAnimationEvent> listener) {
    _assertAlive();
    _eventListeners.add(listener);
  }

  /// Removes one matching event listener. / 移除一个匹配的事件监听者。
  void removeEventListener(ValueChanged<SvgxAnimationEvent> listener) {
    _assertAlive();
    _eventListeners.remove(listener);
  }

  /// Adds a listener for controller state changes. / 添加控制器状态监听者。
  @override
  void addListener(VoidCallback listener) {
    _assertAlive();
    super.addListener(listener);
  }

  /// Removes a controller state listener. / 移除控制器状态监听者。
  @override
  void removeListener(VoidCallback listener) {
    _assertAlive();
    super.removeListener(listener);
  }

  /// Registers a ready widget without changing the controller's current time.
  /// 注册就绪控件，不改变控制器当前时间。
  @internal
  void attach(
    Object owner, {
    required SvgDocument document,
    required bool visible,
    required SvgxAnimationQuality Function() quality,
    required int Function() fpsDivisor,
  }) {
    _assertAlive();
    final revision = ++_revision;
    _attachments[owner] = _Attachment(document, visible, quality, fpsDivisor);
    if (_status == SvgxPlaybackStatus.error) {
      _status = SvgxPlaybackStatus.loading;
    }
    _selectDocument();
    if (_disposed || revision != _revision) return;
    _refreshStatus();
    _syncSubscription();
    notifyListeners();
  }

  /// Unregisters a widget, preserving document time.
  /// 取消注册控件，保留文档时间。
  @internal
  void detach(Object owner) {
    _assertAlive();
    final revision = ++_revision;
    _attachments.remove(owner);
    _selectDocument();
    if (_disposed || revision != _revision) return;
    _syncSubscription();
  }

  /// Updates a widget's TickerMode eligibility. / 更新控件的 TickerMode 可见性。
  @internal
  void setVisible(Object owner, bool visible) {
    _assertAlive();
    _attachments[owner]?.visible = visible;
    _syncSubscription();
  }

  /// Suspends this widget's document while a replacement loads.
  /// 替换文档加载期间暂停此控件的文档注册。
  @internal
  void documentLoading(Object owner) {
    _assertAlive();
    final expectedRevision = _revision + 1;
    detach(owner);
    if (_disposed || expectedRevision != _revision) return;
    if (_document == null) {
      _status = SvgxPlaybackStatus.loading;
      notifyListeners();
    }
  }

  /// Reports a widget loading failure to controller listeners.
  /// 向控制器监听者报告控件加载失败。
  @internal
  void documentError(Object owner, Object error, StackTrace stack) {
    _assertAlive();
    final expectedRevision = _revision + 1;
    detach(owner);
    if (_disposed || expectedRevision != _revision) return;
    _status = SvgxPlaybackStatus.error;
    _syncSubscription();
    notifyListeners();
    _emit(SvgxAnimationError(error, stack));
  }

  /// Releases this controller; later method calls assert in debug builds.
  /// 释放控制器；调试构建中后续方法调用触发断言。
  @override
  void dispose() {
    _assertAlive();
    _unsubscribe();
    _disposed = true;
    _revision++;
    _attachments.clear();
    _eventListeners.clear();
    _cues.clear();
    _time.dispose();
    super.dispose();
  }

  /// Verifies this instance's lifetime. / 验证实例仍存活。
  void _assertAlive() {
    assert(!_disposed, 'SvgxAnimationController was used after dispose');
  }

  /// Lower active bound. / 当前下界。
  Duration get _lower => _rangeStart ?? Duration.zero;

  /// Upper active bound, including the numeric safety ceiling. / 当前上界，包含数值安全上限。
  Duration get _upper {
    final natural = _document?.info.loops == false
        ? _document!.info.settleTime.inMicroseconds
        : _maxTimeMicros;
    return _rangeEnd ??
        Duration(microseconds: math.min(natural, _maxTimeMicros));
  }

  /// Whether time has reached the endpoint in the effective direction.
  /// 时间是否已到有效方向的端点。
  bool get _atBoundary =>
      _effectiveRate < 0 ? _time.value <= _lower : _time.value >= _upper;

  /// Restricts a time to active bounds. / 将时刻限制到当前边界内。
  Duration _clamp(Duration t) => t < _lower
      ? _lower
      : t > _upper
      ? _upper
      : t;

  /// Rebases against the latest global sample, preserving displayed time.
  /// 按最近的全局采样重设基线，保留显示时间。
  void _rebase() {
    _anchorTime = _time.value;
    if (_subscription != null && _anchorGlobal != null) {
      _anchorGlobal = SharedAnimationClock.instance.elapsed;
    }
  }

  /// Revalidates range selection and recovers reversible completion.
  /// 校验片段选择，并恢复可逆的完成状态。
  void _recoverRange() {
    final revision = _revision;
    if (_status == SvgxPlaybackStatus.completed) {
      _status = SvgxPlaybackStatus.paused;
      _wantsPlay = false;
    }
    _time.value = _clamp(_time.value);
    if (_disposed || revision != _revision) return;
    _rebase();
    _refreshStatus();
    _syncSubscription();
    notifyListeners();
  }

  /// Updates loading/playing/paused while preserving terminal states.
  /// 更新加载、播放或暂停状态，保留终止状态。
  void _refreshStatus() {
    if (_status == SvgxPlaybackStatus.error ||
        _status == SvgxPlaybackStatus.completed) {
      return;
    }
    if (_document == null) {
      _status = SvgxPlaybackStatus.loading;
    } else {
      _status = _wantsPlay && _rate != 0
          ? SvgxPlaybackStatus.playing
          : SvgxPlaybackStatus.paused;
    }
  }

  /// Selects the first ready document and reports a primary-document change.
  /// 选择第一个就绪文档，并报告主文档变更。
  void _selectDocument() {
    final next = _attachments.isEmpty
        ? null
        : _attachments.values.first.document;
    if (identical(next, _document)) return;
    _document = next;
    if (next != null) {
      if (_status == SvgxPlaybackStatus.error) {
        _status = SvgxPlaybackStatus.loading;
      }
      _emit(SvgxAnimationLoaded(next.info));
    }
  }

  /// Joins the shared clock only while requested and at least one widget is visible.
  /// 仅请求播放且至少一个控件可见时订阅共享时钟。
  void _syncSubscription() {
    final eligible =
        !_externallyDriven &&
        _status == SvgxPlaybackStatus.playing &&
        _rate != 0 &&
        _attachments.values.any((attachment) => attachment.visible);
    if (!eligible) {
      _unsubscribe();
    } else if (_subscription == null) {
      _anchorTime = _time.value;
      _anchorGlobal = null;
      _subscription = SharedAnimationClock.instance.subscribe(
        _onGlobalTick,
        frameDivisor: _frameDivisor,
      );
    }
  }

  /// Releases the clock subscription while preserving sampled progress.
  /// 释放时钟订阅并保留采样进度。
  void _unsubscribe() {
    final subscription = _subscription;
    if (subscription == null) return;
    SharedAnimationClock.instance.unsubscribe(subscription);
    _subscription = null;
    _anchorGlobal = null;
    _anchorTime = _time.value;
  }

  /// Chooses the least degrading quality and FPS divisors across attached widgets.
  /// 在挂载控件间选择降级最少的画质与 FPS 除数。
  int _frameDivisor(int concurrency) {
    final offscreen = _attachments.values.any(
      (a) => a.document.usesOffscreenLayers,
    );
    int? qualityDivisor;
    int? fpsDivisor;
    for (final attachment in _attachments.values) {
      final divisor = attachment.quality().frameDivisorFor(
        concurrency: concurrency,
        usesOffscreenLayers: offscreen,
      );
      qualityDivisor = qualityDivisor == null
          ? divisor
          : math.min(qualityDivisor, divisor);
      final fps = attachment.fpsDivisor();
      fpsDivisor = fpsDivisor == null ? fps : math.min(fpsDivisor, fps);
    }
    return math.max(qualityDivisor ?? 1, fpsDivisor ?? 1);
  }

  /// Maps a global sample to local time, splitting every range traversal.
  /// 将全局采样映射为本地时间，并拆分每段片段穿越。
  void _onGlobalTick(Duration global) {
    if (_disposed || _subscription == null) return;
    if (_anchorGlobal == null) {
      _anchorGlobal = global;
      _anchorTime = _time.value;
      if (!_started) {
        _started = true;
        _emit(const SvgxAnimationStarted());
      }
      return;
    }
    final revision = _revision;
    final raw =
        _anchorTime.inMicroseconds +
        (global - _anchorGlobal!).inMicroseconds * _effectiveRate;
    var remaining =
        raw.clamp(-_maxTimeMicros, _maxTimeMicros).round() -
        _time.value.inMicroseconds;
    if (remaining == 0) return;
    var current = _clamp(_time.value);
    var crossedRangeBoundary = false;
    while (remaining != 0 && !_disposed && revision == _revision) {
      final forward = remaining > 0;
      final boundary = forward ? _upper : _lower;
      final distance = boundary.inMicroseconds - current.inMicroseconds;
      final reachesBoundary = forward
          ? remaining >= distance
          : remaining <= distance;
      final next = reachesBoundary
          ? boundary
          : Duration(microseconds: current.inMicroseconds + remaining);
      _time.value = next;
      if (_disposed || revision != _revision) return;
      _dispatchCrossing(current, next, revision);
      if (_disposed || revision != _revision) return;
      remaining -= next.inMicroseconds - current.inMicroseconds;
      current = next;
      if (!reachesBoundary) break;
      if (_rangeStart != null && _rangeMode == SvgxRangeMode.loop) {
        crossedRangeBoundary = true;
        _emit(SvgxAnimationRangeLooped(++_rangeIteration));
        if (_disposed || revision != _revision) return;
        current = forward ? _lower : _upper;
        _time.value = current;
        if (_disposed || revision != _revision) return;
        _dispatchCrossing(
          current,
          current,
          revision,
          includeFrom: true,
          forwardOverride: forward,
        );
      } else if (_rangeStart != null && _rangeMode == SvgxRangeMode.pingPong) {
        crossedRangeBoundary = true;
        _rangeDirection = -_rangeDirection;
        remaining = -remaining;
      } else if (!forward ||
          _rangeStart != null ||
          _document?.info.loops == false) {
        _wantsPlay = false;
        _status = SvgxPlaybackStatus.completed;
        _unsubscribe();
        notifyListeners();
        _emit(
          SvgxAnimationCompleted(
            natural:
                forward &&
                _rangeStart == null &&
                _document?.info.loops == false,
          ),
        );
        return;
      } else {
        remaining = 0;
      }
    }
    if (_disposed || revision != _revision) return;
    // Rebase after wrapping/reflection so the next sample uses the new direction.
    // 回绕或反射后重新锚定，令下次采样使用新的方向。
    if (crossedRangeBoundary) {
      _anchorGlobal = global;
      _anchorTime = _time.value;
    }
  }

  /// Dispatches cue, document-loop, and element events in traversal order.
  /// 按穿越次序派发 cue、文档循环与元素事件。
  void _dispatchCrossing(
    Duration from,
    Duration to,
    int revision, {
    bool includeFrom = false,
    bool? forwardOverride,
  }) {
    if (_cues.isEmpty && _eventListeners.isEmpty) return;
    final forward = forwardOverride ?? to >= from;
    bool crossed(Duration at) => forward
        ? (includeFrom ? at >= from : at > from) && at <= to
        : at >= to && (includeFrom ? at <= from : at < from);
    final pending = <_PendingEvent>[];
    for (final entry in _cues.entries) {
      if (!crossed(entry.key)) continue;
      for (final callback in entry.value) {
        pending.add(_PendingEvent(entry.key, callback));
      }
    }
    final document = _document;
    if (_eventListeners.isNotEmpty && document != null) {
      assert(() {
        debugTimelineEventQueryCount++;
        return true;
      }());
      final events = forward
          ? timelineEventsBetween(
              document,
              includeFrom ? from - _microsecond : from,
              to,
            )
          : timelineEventsBetween(
              document,
              to - _microsecond,
              includeFrom ? from : from - _microsecond,
            ).reversed;
      for (final event in events) {
        final SvgxAnimationEvent playbackEvent = switch (event.kind) {
          SvgxTimelineEventKind.begin => SvgxAnimationElementBegin(
            event.elementId,
          ),
          SvgxTimelineEventKind.end => SvgxAnimationElementEnd(event.elementId),
          SvgxTimelineEventKind.repeat => SvgxAnimationElementRepeat(
            event.elementId,
            event.iteration,
          ),
        };
        pending.add(_PendingEvent(event.time, () => _emit(playbackEvent)));
      }
      final period = document.info.loopPeriod?.inMicroseconds;
      if (document.info.loops && period != null && period > 0) {
        final settle = document.info.settleTime.inMicroseconds;
        final low = math.min(from.inMicroseconds, to.inMicroseconds);
        final high = math.max(from.inMicroseconds, to.inMicroseconds);
        final first = math.max(1, (low - settle) ~/ period);
        final last = (high - settle) ~/ period;
        for (var iteration = first; iteration <= last; iteration++) {
          final at = Duration(microseconds: settle + iteration * period);
          if (!crossed(at)) continue;
          final event = SvgxAnimationLooped(iteration);
          pending.add(_PendingEvent(at, () => _emit(event)));
        }
      }
    }
    final ordered = pending.indexed.toList()
      ..sort((a, b) {
        final compare = a.$2.at.compareTo(b.$2.at);
        return compare == 0
            ? a.$1.compareTo(b.$1)
            : forward
            ? compare
            : -compare;
      });
    for (final (_, event) in ordered) {
      if (_disposed || revision != _revision) return;
      event.callback();
    }
  }

  /// Emits an event from a listener snapshot safe against removal or disposal.
  /// 从可安全移除监听者或释放控制器的快照派发事件。
  void _emit(SvgxAnimationEvent event) {
    if (_eventListeners.isEmpty || _disposed) return;
    final revision = _revision;
    for (final listener in List<ValueChanged<SvgxAnimationEvent>>.of(
      _eventListeners,
    )) {
      if (_disposed || revision != _revision) return;
      if (_eventListeners.contains(listener)) listener(event);
    }
  }
}

/// One ready widget's live playback preferences. / 一个就绪控件的实时播放偏好。
final class _Attachment {
  /// Creates a widget attachment. / 创建控件挂载记录。
  _Attachment(this.document, this.visible, this.quality, this.fpsDivisor);

  /// Ready document. / 就绪文档。
  final SvgDocument document;

  /// Current TickerMode eligibility. / 当前 TickerMode 可见性。
  bool visible;

  /// Live quality preference. / 实时画质偏好。
  final SvgxAnimationQuality Function() quality;

  /// Live FPS cap divisor. / 实时 FPS 上限除数。
  final int Function() fpsDivisor;
}

/// A deferred callback positioned on the document timeline.
/// 放在文档时间线上的延迟派发回调。
final class _PendingEvent {
  /// Creates a positioned callback. / 创建带时刻的回调。
  const _PendingEvent(this.at, this.callback);

  /// Crossing time. / 穿越时刻。
  final Duration at;

  /// Callback to dispatch. / 待派发回调。
  final VoidCallback callback;
}
