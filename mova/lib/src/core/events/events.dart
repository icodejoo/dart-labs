import '../model/fit.dart';
import '../model/orientation.dart';
import '../model/quality.dart';
import '../model/source.dart';
import '../options/preview_config.dart';
import '../options/stt_config.dart';
import '../recovery/fail.dart';
import '../render/first_frame.dart';
import '../standby/standby.dart';
import '../swap/ctl.dart';

/// Base type of everything broadcast on [MovaApi.events].
///
/// [MovaApi.events] 上广播的所有事件的基类。
sealed class MovaEvent {
  /// Base constructor.
  ///
  /// 基类构造。
  const MovaEvent();
}

/// The player finished opening a source and is ready to play.
///
/// 播放器已打开源、可以播放。
class MovaReady extends MovaEvent {
  /// Creates the event.
  ///
  /// 创建事件。
  const MovaReady();
}

/// A new source was opened.
///
/// 打开了新的媒体源。
class MovaSourceChange extends MovaEvent {
  /// The source that was opened.
  ///
  /// 被打开的源。
  final MovaSource source;

  /// Creates the event with [source].
  ///
  /// 用 [source] 创建事件。
  const MovaSourceChange(this.source);
}

/// Playback started or resumed.
///
/// 播放开始或恢复。
class MovaPlay extends MovaEvent {
  /// Creates the event.
  ///
  /// 创建事件。
  const MovaPlay();
}

/// Playback was paused.
///
/// 播放已暂停。
class MovaPause extends MovaEvent {
  /// Creates the event.
  ///
  /// 创建事件。
  const MovaPause();
}

/// Playback reached the end of the media.
///
/// 播放到达媒体末尾。
class MovaDone extends MovaEvent {
  /// Creates the event.
  ///
  /// 创建事件。
  const MovaDone();
}

/// A seek was requested and is in flight.
///
/// 已发起跳转、尚未完成。
class MovaSeek extends MovaEvent {
  /// Requested target position.
  ///
  /// 请求的目标位置。
  final Duration target;

  /// Creates the event with [target].
  ///
  /// 用 [target] 创建事件。
  const MovaSeek(this.target);
}

/// A seek finished landing at [position].
///
/// 跳转完成，落点为 [position]。
class MovaSeeked extends MovaEvent {
  /// The position reached after the seek.
  ///
  /// 跳转完成后到达的位置。
  final Duration position;

  /// Creates the event with [position].
  ///
  /// 用 [position] 创建事件。
  const MovaSeeked(this.position);
}

/// Buffering state toggled.
///
/// 缓冲状态发生变化。
class MovaBufferChange extends MovaEvent {
  /// Whether the player is currently buffering.
  ///
  /// 播放器当前是否处于缓冲中。
  final bool buffering;

  /// Creates the event with [buffering].
  ///
  /// 用 [buffering] 创建事件。
  const MovaBufferChange(this.buffering);
}

/// The media's total duration became known or changed.
///
/// 媒体总时长已知或发生变化。
class MovaDurationChange extends MovaEvent {
  /// The new total duration.
  ///
  /// 新的总时长。
  final Duration duration;

  /// Creates the event with [duration].
  ///
  /// 用 [duration] 创建事件。
  const MovaDurationChange(this.duration);
}

/// The current source presented its first frame (or first audio).
///
/// Fires once per `open()`, every time — the repeatable counterpart of
/// media_kit's one-shot `waitUntilFirstFrameRendered`.
///
/// 当前源呈现了首帧（或首段音频）。
///
/// 每次 `open()` 都会触发一次——是 media_kit 一次性
/// `waitUntilFirstFrameRendered` 的可重复版本。
///
/// Example / 示例:
/// ```dart
/// api.events
///     .where((e) => e is MovaFirstFrame)
///     .cast<MovaFirstFrame>()
///     .listen((e) => log('ttff ${e.sinceOpen} via ${e.signal}'));
/// ```
class MovaFirstFrame extends MovaEvent {
  /// Elapsed time since the `open()` call that started this source.
  ///
  /// 距开始本源的那次 `open()` 调用的耗时。
  final Duration sinceOpen;

  /// Which observation landed it.
  ///
  /// 由哪种观测落地。
  final MovaFirstFrameSignal signal;

  /// Creates the event.
  ///
  /// 创建事件。
  const MovaFirstFrame({required this.sinceOpen, required this.signal});
}

/// The decoded video frame size changed.
///
/// 解码后的视频帧尺寸发生变化。
class MovaSizeChange extends MovaEvent {
  /// Frame pixel width.
  ///
  /// 帧像素宽。
  final int width;

  /// Frame pixel height.
  ///
  /// 帧像素高。
  final int height;

  /// Creates the event with [width] and [height].
  ///
  /// 用 [width]、[height] 创建事件。
  const MovaSizeChange(this.width, this.height);
}

/// The volume level changed.
///
/// 音量发生变化。
class MovaVolumeChange extends MovaEvent {
  /// New volume, typically in `0.0`–`1.0`.
  ///
  /// 新音量，通常在 `0.0`–`1.0` 之间。
  final double value;

  /// Creates the event with [value].
  ///
  /// 用 [value] 创建事件。
  const MovaVolumeChange(this.value);
}

/// The brightness overlay level changed.
///
/// 亮度遮罩层级发生变化。
class MovaBrightChange extends MovaEvent {
  /// New brightness, typically in `0.0`–`1.0`.
  ///
  /// 新亮度，通常在 `0.0`–`1.0` 之间。
  final double value;

  /// Creates the event with [value].
  ///
  /// 用 [value] 创建事件。
  const MovaBrightChange(this.value);
}

/// The playback rate changed.
///
/// 播放速率发生变化。
class MovaRateChange extends MovaEvent {
  /// New playback rate, where `1.0` is normal speed.
  ///
  /// 新播放速率，`1.0` 为正常速度。
  final double value;

  /// Creates the event with [value].
  ///
  /// 用 [value] 创建事件。
  const MovaRateChange(this.value);
}

/// The available quality list was (re)extracted.
///
/// 可选清晰度列表被（重新）提取。
class MovaQualityListChange extends MovaEvent {
  /// The extracted quality list.
  ///
  /// 提取出的清晰度列表。
  final List<MovaQuality> qualities;

  /// Creates the event with [qualities].
  ///
  /// 用 [qualities] 创建事件。
  const MovaQualityListChange(this.qualities);
}

/// The active quality selection changed.
///
/// 当前选中的清晰度发生变化。
class MovaQualityChange extends MovaEvent {
  /// The now-active quality.
  ///
  /// 当前生效的清晰度。
  final MovaQuality quality;

  /// Creates the event with [quality].
  ///
  /// 用 [quality] 创建事件。
  const MovaQualityChange(this.quality);
}

/// ABR downgraded the quality due to buffering pressure.
///
/// 因缓冲压力，ABR 自动降低了清晰度档位。
class MovaAbrDownShift extends MovaEvent {
  /// The quality downgraded from.
  ///
  /// 降档前的清晰度。
  final MovaQuality from;

  /// The quality downgraded to.
  ///
  /// 降档后的清晰度。
  final MovaQuality to;

  /// Creates the event with [from] and [to].
  ///
  /// 用 [from]、[to] 创建事件。
  const MovaAbrDownShift(this.from, this.to);
}

/// The video surface fill mode changed.
///
/// 画面填充模式发生变化。
class MovaFitChange extends MovaEvent {
  /// The new fill mode.
  ///
  /// 新的填充模式。
  final MovaFit fit;

  /// Creates the event with [fit].
  ///
  /// 用 [fit] 创建事件。
  const MovaFitChange(this.fit);
}

/// The pinch-zoom scale changed.
///
/// 双指缩放比例发生变化。
class MovaZoomChange extends MovaEvent {
  /// New zoom scale, where `1.0` is unzoomed.
  ///
  /// 新的缩放比例，`1.0` 为未缩放。
  final double zoom;

  /// Creates the event with [zoom].
  ///
  /// 用 [zoom] 创建事件。
  const MovaZoomChange(this.zoom);
}

/// The gesture-lock state changed.
///
/// 手势锁定状态发生变化。
class MovaLockChange extends MovaEvent {
  /// Whether gestures are now locked.
  ///
  /// 手势当前是否已锁定。
  final bool value;

  /// Creates the event with [value].
  ///
  /// 用 [value] 创建事件。
  const MovaLockChange(this.value);
}

/// The fullscreen state changed.
///
/// 全屏状态发生变化。
class MovaFullScreenChange extends MovaEvent {
  /// Whether the player is now fullscreen.
  ///
  /// 播放器当前是否处于全屏。
  final bool value;

  /// Creates the event with [value].
  ///
  /// 用 [value] 创建事件。
  const MovaFullScreenChange(this.value);
}

/// The forced screen-orientation override changed.
///
/// 强制屏幕方向覆盖发生变化。
class MovaOrientationChange extends MovaEvent {
  /// The new forced-orientation override.
  ///
  /// 新的强制方向覆盖值。
  final MovaOrientation orientation;

  /// Creates the event with [orientation].
  ///
  /// 用 [orientation] 创建事件。
  const MovaOrientationChange(this.orientation);
}

/// The picture-in-picture state changed.
///
/// 画中画状态发生变化。
class MovaPipChange extends MovaEvent {
  /// Whether picture-in-picture is now active.
  ///
  /// 画中画当前是否处于激活状态。
  final bool value;

  /// Creates the event with [value].
  ///
  /// 用 [value] 创建事件。
  const MovaPipChange(this.value);
}

/// The in-app mini window state changed.
///
/// App 内小窗状态发生变化。
class MovaMiniChange extends MovaEvent {
  /// Whether the mini window is now active.
  ///
  /// 小窗当前是否处于激活状态。
  final bool mini;

  /// Creates the event with [mini].
  ///
  /// 用 [mini] 创建事件。
  const MovaMiniChange(this.mini);
}

/// The live timeshift offset changed.
///
/// 直播时移偏移量发生变化。
class MovaTimeShiftChange extends MovaEvent {
  /// How far behind the live edge playback currently is.
  ///
  /// 当前播放位置落后直播边缘的时长。
  final Duration behind;

  /// Creates the event with [behind].
  ///
  /// 用 [behind] 创建事件。
  const MovaTimeShiftChange(this.behind);
}

/// Playback caught back up to the live edge.
///
/// 播放已追上直播边缘。
class MovaLiveEdgeReach extends MovaEvent {
  /// Creates the event.
  ///
  /// 创建事件。
  const MovaLiveEdgeReach();
}

/// A scrub-preview request was refused before any work happened.
///
/// 一次拖动预览请求在真正开工前被拒绝。
class MovaPreviewBlock extends MovaEvent {
  /// Why the request was refused.
  ///
  /// 被拒绝的原因。
  final MovaPreviewBlockReason reason;

  /// Creates the event with [reason].
  ///
  /// 用 [reason] 创建事件。
  const MovaPreviewBlock(this.reason);
}

/// An STT `start()` request was refused before any recognition happened.
///
/// 一次 STT 启动请求在真正开始识别前被拒绝。
class MovaSttBlock extends MovaEvent {
  /// Why the request was refused.
  ///
  /// 被拒绝的原因。
  final MovaSttBlockReason reason;

  /// Creates the event with [reason].
  ///
  /// 用 [reason] 创建事件。
  const MovaSttBlock(this.reason);
}

/// A seamless engine swap transitioned to a new phase.
///
/// 无缝引擎切换迁移到了新的阶段。
class MovaSwapChange extends MovaEvent {
  /// The phase now in effect.
  ///
  /// 当前生效的阶段。
  final MovaSwapPhase phase;

  /// Creates the event with [phase].
  ///
  /// 用 [phase] 创建事件。
  const MovaSwapChange(this.phase);
}

/// A playback error occurred.
///
/// 发生了播放错误。
class MovaErrorEvent extends MovaEvent {
  /// The error object.
  ///
  /// 错误对象。
  final Object error;

  /// The associated stack trace, if available.
  ///
  /// 关联的调用栈，若可用。
  final StackTrace? stack;

  /// Creates the event with [error] and optional [stack].
  ///
  /// 用 [error] 及可选的 [stack] 创建事件。
  const MovaErrorEvent(this.error, [this.stack]);
}

/// A playback attempt failed and recovery decided what to do. Only fires when
/// `MovaRecoveryConfig.enabled`. Not an error by itself — `MovaState.error` is
/// set only once recovery gives up.
///
/// 一次播放尝试失败，recovery 已决定如何处理。仅在 `MovaRecoveryConfig.enabled`
/// 时触发。它本身不是错误——只有 recovery 放弃时才写 `MovaState.error`。
///
/// Example / 示例:
/// ```dart
/// api.events.listen((e) {
///   if (e is MovaPlayFailure && e.fail.kind == MovaPlayFailKind.startTimeout) {
///     showToast('连接超时，正在重试…');
///   }
/// });
/// ```
class MovaPlayFailure extends MovaEvent {
  /// What failed and how often.
  ///
  /// 失败的是什么、第几次。
  final MovaPlayFail fail;

  /// What the engine does next.
  ///
  /// 引擎接下来要做什么。
  final MovaRecoveryAction action;

  /// Creates the event.
  ///
  /// 创建事件。
  const MovaPlayFailure(this.fail, this.action);
}

/// Playback showed a frame again after [attempts] consecutive failures.
///
/// 连续失败 [attempts] 次之后重新出画面。
class MovaRecovered extends MovaEvent {
  /// How many consecutive failures preceded the recovery.
  ///
  /// 恢复之前连续失败了几次。
  final int attempts;

  /// Creates the event.
  ///
  /// 创建事件。
  const MovaRecovered(this.attempts);
}

/// Playback moved to another address of the same source.
///
/// 播放切到了同一个源的另一个地址。
class MovaFailover extends MovaEvent {
  /// Index (into `MovaSource.uris`) left behind.
  ///
  /// 被放弃的地址下标。
  final int from;

  /// Index now playing.
  ///
  /// 当前播放的地址下标。
  final int to;

  /// The address now playing.
  ///
  /// 当前播放的地址。
  final String uri;

  /// Creates the event.
  ///
  /// 创建事件。
  const MovaFailover({required this.from, required this.to, required this.uri});
}

/// The standby phase changed.
///
/// 待机阶段发生变化。
///
/// Example / 示例:
/// ```dart
/// api.events.listen((e) {
///   if (e is MovaStandbyChange && e.phase == MovaStandbyPhase.fallback) {
///     log('standby fell back to pause: ${e.reason.name}');
///   }
/// });
/// ```
class MovaStandbyChange extends MovaEvent {
  /// Creates the event.
  ///
  /// 创建事件。
  const MovaStandbyChange({required this.phase, required this.reason, this.mode});

  /// The new phase.
  ///
  /// 新阶段。
  final MovaStandbyPhase phase;

  /// Why it changed.
  ///
  /// 变化原因。
  final MovaStandbyReason reason;

  /// The hold mode: set when entering [MovaStandbyPhase.holding], and on the
  /// `resuming` that follows it; null otherwise.
  ///
  /// 待机组合：进入 holding 时、以及紧随其后的 resuming 时有值；其余为 null。
  final MovaStandbyMode? mode;
}

/// Standby ended and playback is presenting again: how long it took from the
/// wake-up call to the first fresh frame.
///
/// 待机结束、重新出画面：从唤醒调用到第一帧新画面花了多久。
///
/// Example / 示例:
/// ```dart
/// api.events.listen((e) {
///   if (e is MovaStandbyResume) {
///     log('back in ${e.elapsed.inMilliseconds}ms via ${e.signal?.name ?? 'none'}');
///   }
/// });
/// ```
class MovaStandbyResume extends MovaEvent {
  /// Creates the event.
  ///
  /// 创建事件。
  const MovaStandbyResume({required this.elapsed, this.signal, this.from});

  /// From `setStandby(false)` to the landing.
  ///
  /// 从 `setStandby(false)` 到落地的耗时。
  final Duration elapsed;

  /// What landed it: `restart`/`size` (precise), `buffering`/`progress`
  /// (after a reconnect), `grace` (nothing within `resumeTimeout` — elapsed is
  /// then the timeout, not a measurement), or null (decoding never stopped).
  ///
  /// 由什么落地：`restart`/`size`（精确）、`buffering`/`progress`（重连之后）、`grace`
  /// （`resumeTimeout` 内什么都没等到——此时 elapsed 就是超时值，不是测量值），或 null
  /// （解码从未停过）。
  final MovaFirstFrameSignal? signal;

  /// The hold mode woken from; null when woken from a [MovaStandbyPhase.fallback] pause.
  ///
  /// 从哪种待机组合醒来；从 fallback 暂停醒来时为 null。
  final MovaStandbyMode? from;
}
