import '../model/fit.dart';
import '../model/quality.dart';
import '../model/source.dart';

/// Immutable snapshot of player state at a point in time.
///
/// This is the core layer's value type for "everything about playback
/// except progress" — playback flags, geometry, volume/brightness/rate/zoom,
/// quality list and current selection, and live-stream specific fields.
///
/// 播放器状态在某一时刻的不可变快照。
///
/// 这是 core 层"除进度外的一切播放相关信息"的值类型——播放标志位、几何尺寸、
/// 音量/亮度/倍速/缩放、清晰度列表与当前选择，以及直播特有字段。
class VmState {
  /// Whether the engine is currently playing (not paused).
  ///
  /// 内核当前是否处于播放（非暂停）状态。
  final bool playing;

  /// Whether the engine is buffering (stalled waiting for data).
  ///
  /// 内核是否正在缓冲（因数据不足而卡顿）。
  final bool buffering;

  /// Whether playback has reached the end of the media.
  ///
  /// 播放是否已到达媒体末尾。
  final bool completed;

  /// Whether gesture/control interaction is locked.
  ///
  /// 手势/控制交互是否已锁定。
  final bool locked;

  /// Whether the player is currently in fullscreen mode.
  ///
  /// 播放器当前是否处于全屏模式。
  final bool fullscreen;

  /// Whether the player is currently in picture-in-picture mode.
  ///
  /// 播放器当前是否处于画中画模式。
  final bool pip;

  /// Total media duration; `Duration.zero` if unknown (e.g. live).
  ///
  /// 媒体总时长；未知时（如直播）为 `Duration.zero`。
  final Duration duration;

  /// Video frame width in pixels; 0 if unknown.
  ///
  /// 视频帧宽度（像素）；未知时为 0。
  final int width;

  /// Video frame height in pixels; 0 if unknown.
  ///
  /// 视频帧高度（像素）；未知时为 0。
  final int height;

  /// Playback volume, 0.0–100.0.
  ///
  /// 播放音量，范围 0.0–100.0。
  final double volume;

  /// Screen brightness override, 0.0–1.0.
  ///
  /// 屏幕亮度覆盖值，范围 0.0–1.0。
  final double brightness;

  /// Playback rate multiplier, e.g. 1.0 for normal speed.
  ///
  /// 播放速率倍数，如 1.0 为正常速度。
  final double rate;

  /// Video zoom factor, 1.0 for no zoom.
  ///
  /// 视频缩放系数，1.0 为不缩放。
  final double zoom;

  /// Current surface fill mode.
  ///
  /// 当前画面填充模式。
  final VmFit fit;

  /// Available quality variants for the current source (empty for
  /// non-adaptive sources).
  ///
  /// 当前源可选的清晰度档位列表（非自适应源时为空）。
  final List<VmQuality> qualities;

  /// The currently selected quality, if any.
  ///
  /// 当前选中的清晰度档位（若有）。
  final VmQuality? currentQuality;

  /// Stream type: VOD or live.
  ///
  /// 流类型：点播或直播。
  final VmStreamType type;

  /// Whether a live stream supports seeking within its buffered window.
  ///
  /// 直播流是否支持在其缓冲窗口内拖动。
  final bool liveSeekable;

  /// How far the live playhead is allowed to seek behind the live edge.
  ///
  /// 直播播放头允许回退到直播边缘之后的最大时长窗口。
  final Duration seekableWindow;

  /// How far behind the live edge the current playhead is, if timeshifting.
  ///
  /// 若正在时移，当前播放头落后直播边缘的时长。
  final Duration? timeshiftBehind;

  /// The last playback error, if any.
  ///
  /// 最近一次的播放错误（若有）。
  final Object? error;

  /// Title of the currently open source, or null before [VmState] has any
  /// source opened / when the source provides no title.
  ///
  /// Tracked as a first-class state field (rather than outside [VmState])
  /// so [VmSelector]s can react directly to title changes, independent of
  /// whether [type] also changed in the same [open] call (e.g. re-opening a
  /// different source of the same stream type).
  ///
  /// 当前已打开源的标题；未打开过源，或源未提供标题时为 null。
  ///
  /// 作为状态的一等字段跟踪（而非放在 [VmState] 之外），使 [VmSelector] 能
  /// 直接响应标题变化，不依赖同一次 [open] 调用中 [type] 是否也发生了变化
  /// （例如重新打开同一流类型的另一个源）。
  final String? sourceTitle;

  /// Creates a state snapshot; all fields default to the 0.1.0 baseline
  /// behaviour (stopped, full volume/brightness/rate/zoom, contain fit,
  /// VOD, not seekable-live).
  ///
  /// 创建一个状态快照；所有字段默认对齐 0.1.0 基线行为（停止、满音量/亮度/
  /// 倍速/缩放、contain 填充、点播、直播不可拖动）。
  const VmState({
    this.playing = false,
    this.buffering = false,
    this.completed = false,
    this.locked = false,
    this.fullscreen = false,
    this.pip = false,
    this.duration = Duration.zero,
    this.width = 0,
    this.height = 0,
    this.volume = 100.0,
    this.brightness = 1.0,
    this.rate = 1.0,
    this.zoom = 1.0,
    this.fit = VmFit.contain,
    this.qualities = const <VmQuality>[],
    this.currentQuality,
    this.type = VmStreamType.vod,
    this.liveSeekable = false,
    this.seekableWindow = Duration.zero,
    this.timeshiftBehind,
    this.error,
    this.sourceTitle,
  });

  /// Returns a copy with the given fields replaced.
  ///
  /// [clearQuality], [clearTimeshift], [clearError], and [clearSourceTitle]
  /// explicitly null out [currentQuality], [timeshiftBehind], [error], and
  /// [sourceTitle] respectively — passing a nullable field as `null` is
  /// otherwise indistinguishable from "keep".
  ///
  /// 返回一个替换了指定字段的副本。
  ///
  /// [clearQuality]、[clearTimeshift]、[clearError]、[clearSourceTitle]
  /// 用于显式清空 [currentQuality]、[timeshiftBehind]、[error]、
  /// [sourceTitle]——否则可空字段传 `null` 无法与"保持原值"区分。
  VmState copyWith({
    bool? playing,
    bool? buffering,
    bool? completed,
    bool? locked,
    bool? fullscreen,
    bool? pip,
    Duration? duration,
    int? width,
    int? height,
    double? volume,
    double? brightness,
    double? rate,
    double? zoom,
    VmFit? fit,
    List<VmQuality>? qualities,
    VmQuality? currentQuality,
    VmStreamType? type,
    bool? liveSeekable,
    Duration? seekableWindow,
    Duration? timeshiftBehind,
    Object? error,
    String? sourceTitle,
    bool clearQuality = false,
    bool clearTimeshift = false,
    bool clearError = false,
    bool clearSourceTitle = false,
  }) {
    return VmState(
      playing: playing ?? this.playing,
      buffering: buffering ?? this.buffering,
      completed: completed ?? this.completed,
      locked: locked ?? this.locked,
      fullscreen: fullscreen ?? this.fullscreen,
      pip: pip ?? this.pip,
      duration: duration ?? this.duration,
      width: width ?? this.width,
      height: height ?? this.height,
      volume: volume ?? this.volume,
      brightness: brightness ?? this.brightness,
      rate: rate ?? this.rate,
      zoom: zoom ?? this.zoom,
      fit: fit ?? this.fit,
      qualities: qualities ?? this.qualities,
      currentQuality: clearQuality ? null : (currentQuality ?? this.currentQuality),
      type: type ?? this.type,
      liveSeekable: liveSeekable ?? this.liveSeekable,
      seekableWindow: seekableWindow ?? this.seekableWindow,
      timeshiftBehind: clearTimeshift ? null : (timeshiftBehind ?? this.timeshiftBehind),
      error: clearError ? null : (error ?? this.error),
      sourceTitle: clearSourceTitle ? null : (sourceTitle ?? this.sourceTitle),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is VmState &&
        other.playing == playing &&
        other.buffering == buffering &&
        other.completed == completed &&
        other.locked == locked &&
        other.fullscreen == fullscreen &&
        other.pip == pip &&
        other.duration == duration &&
        other.width == width &&
        other.height == height &&
        other.volume == volume &&
        other.brightness == brightness &&
        other.rate == rate &&
        other.zoom == zoom &&
        other.fit == fit &&
        _listEq(other.qualities, qualities) &&
        other.currentQuality == currentQuality &&
        other.type == type &&
        other.liveSeekable == liveSeekable &&
        other.seekableWindow == seekableWindow &&
        other.timeshiftBehind == timeshiftBehind &&
        other.error == error &&
        other.sourceTitle == sourceTitle;
  }

  @override
  int get hashCode => Object.hash(
        Object.hash(playing, buffering, completed, locked, fullscreen, pip),
        Object.hash(duration, width, height, volume, brightness, rate, zoom),
        fit,
        Object.hashAll(qualities),
        currentQuality,
        type,
        liveSeekable,
        seekableWindow,
        timeshiftBehind,
        error,
        sourceTitle,
      );
}

/// Value-equality check for lists, without depending on
/// `package:flutter/foundation.dart` (the core layer must stay Flutter-free).
///
/// 列表的按值相等判断，不依赖 `package:flutter/foundation.dart`
/// （core 层不能依赖 Flutter）。
bool _listEq<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
