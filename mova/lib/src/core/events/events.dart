import '../model/fit.dart';
import '../model/orientation.dart';
import '../model/quality.dart';
import '../model/source.dart';
import '../options/preview_config.dart';
import '../options/stt_config.dart';

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
class MovaSourceChg extends MovaEvent {
  /// The source that was opened.
  ///
  /// 被打开的源。
  final MovaSource source;

  /// Creates the event with [source].
  ///
  /// 用 [source] 创建事件。
  const MovaSourceChg(this.source);
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
class MovaBufferChg extends MovaEvent {
  /// Whether the player is currently buffering.
  ///
  /// 播放器当前是否处于缓冲中。
  final bool buffering;

  /// Creates the event with [buffering].
  ///
  /// 用 [buffering] 创建事件。
  const MovaBufferChg(this.buffering);
}

/// The media's total duration became known or changed.
///
/// 媒体总时长已知或发生变化。
class MovaDurChg extends MovaEvent {
  /// The new total duration.
  ///
  /// 新的总时长。
  final Duration duration;

  /// Creates the event with [duration].
  ///
  /// 用 [duration] 创建事件。
  const MovaDurChg(this.duration);
}

/// The decoded video frame size changed.
///
/// 解码后的视频帧尺寸发生变化。
class MovaSizeChg extends MovaEvent {
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
  const MovaSizeChg(this.width, this.height);
}

/// The volume level changed.
///
/// 音量发生变化。
class MovaVolumeChg extends MovaEvent {
  /// New volume, typically in `0.0`–`1.0`.
  ///
  /// 新音量，通常在 `0.0`–`1.0` 之间。
  final double value;

  /// Creates the event with [value].
  ///
  /// 用 [value] 创建事件。
  const MovaVolumeChg(this.value);
}

/// The brightness overlay level changed.
///
/// 亮度遮罩层级发生变化。
class MovaBrightChg extends MovaEvent {
  /// New brightness, typically in `0.0`–`1.0`.
  ///
  /// 新亮度，通常在 `0.0`–`1.0` 之间。
  final double value;

  /// Creates the event with [value].
  ///
  /// 用 [value] 创建事件。
  const MovaBrightChg(this.value);
}

/// The playback rate changed.
///
/// 播放速率发生变化。
class MovaRateChg extends MovaEvent {
  /// New playback rate, where `1.0` is normal speed.
  ///
  /// 新播放速率，`1.0` 为正常速度。
  final double value;

  /// Creates the event with [value].
  ///
  /// 用 [value] 创建事件。
  const MovaRateChg(this.value);
}

/// The available quality list was (re)extracted.
///
/// 可选清晰度列表被（重新）提取。
class MovaQualListChg extends MovaEvent {
  /// The extracted quality list.
  ///
  /// 提取出的清晰度列表。
  final List<MovaQual> qualities;

  /// Creates the event with [qualities].
  ///
  /// 用 [qualities] 创建事件。
  const MovaQualListChg(this.qualities);
}

/// The active quality selection changed.
///
/// 当前选中的清晰度发生变化。
class MovaQualChg extends MovaEvent {
  /// The now-active quality.
  ///
  /// 当前生效的清晰度。
  final MovaQual quality;

  /// Creates the event with [quality].
  ///
  /// 用 [quality] 创建事件。
  const MovaQualChg(this.quality);
}

/// ABR downgraded the quality due to buffering pressure.
///
/// 因缓冲压力，ABR 自动降低了清晰度档位。
class MovaAbrDownShift extends MovaEvent {
  /// The quality downgraded from.
  ///
  /// 降档前的清晰度。
  final MovaQual from;

  /// The quality downgraded to.
  ///
  /// 降档后的清晰度。
  final MovaQual to;

  /// Creates the event with [from] and [to].
  ///
  /// 用 [from]、[to] 创建事件。
  const MovaAbrDownShift(this.from, this.to);
}

/// The video surface fill mode changed.
///
/// 画面填充模式发生变化。
class MovaFitChg extends MovaEvent {
  /// The new fill mode.
  ///
  /// 新的填充模式。
  final MovaFit fit;

  /// Creates the event with [fit].
  ///
  /// 用 [fit] 创建事件。
  const MovaFitChg(this.fit);
}

/// The pinch-zoom scale changed.
///
/// 双指缩放比例发生变化。
class MovaZoomChg extends MovaEvent {
  /// New zoom scale, where `1.0` is unzoomed.
  ///
  /// 新的缩放比例，`1.0` 为未缩放。
  final double zoom;

  /// Creates the event with [zoom].
  ///
  /// 用 [zoom] 创建事件。
  const MovaZoomChg(this.zoom);
}

/// The gesture-lock state changed.
///
/// 手势锁定状态发生变化。
class MovaLockChg extends MovaEvent {
  /// Whether gestures are now locked.
  ///
  /// 手势当前是否已锁定。
  final bool value;

  /// Creates the event with [value].
  ///
  /// 用 [value] 创建事件。
  const MovaLockChg(this.value);
}

/// The fullscreen state changed.
///
/// 全屏状态发生变化。
class MovaFullScreenChg extends MovaEvent {
  /// Whether the player is now fullscreen.
  ///
  /// 播放器当前是否处于全屏。
  final bool value;

  /// Creates the event with [value].
  ///
  /// 用 [value] 创建事件。
  const MovaFullScreenChg(this.value);
}

/// The forced screen-orientation override changed.
///
/// 强制屏幕方向覆盖发生变化。
class MovaOrientChg extends MovaEvent {
  /// The new forced-orientation override.
  ///
  /// 新的强制方向覆盖值。
  final MovaOrient orientation;

  /// Creates the event with [orientation].
  ///
  /// 用 [orientation] 创建事件。
  const MovaOrientChg(this.orientation);
}

/// The picture-in-picture state changed.
///
/// 画中画状态发生变化。
class MovaPipChg extends MovaEvent {
  /// Whether picture-in-picture is now active.
  ///
  /// 画中画当前是否处于激活状态。
  final bool value;

  /// Creates the event with [value].
  ///
  /// 用 [value] 创建事件。
  const MovaPipChg(this.value);
}

/// The live timeshift offset changed.
///
/// 直播时移偏移量发生变化。
class MovaTimeShiftChg extends MovaEvent {
  /// How far behind the live edge playback currently is.
  ///
  /// 当前播放位置落后直播边缘的时长。
  final Duration behind;

  /// Creates the event with [behind].
  ///
  /// 用 [behind] 创建事件。
  const MovaTimeShiftChg(this.behind);
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
class MovaPrevBlock extends MovaEvent {
  /// Why the request was refused.
  ///
  /// 被拒绝的原因。
  final MovaPrevBlockReason reason;

  /// Creates the event with [reason].
  ///
  /// 用 [reason] 创建事件。
  const MovaPrevBlock(this.reason);
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
