import 'dart:typed_data';

import '../model/quality.dart';

/// Abstraction over the underlying playback engine (media_kit/mpv today).
///
/// It isolates the rest of the codebase from the concrete engine so upper
/// layers (controls, gestures, state) never import `package:media_kit`
/// directly.
///
/// 播放引擎（当前为 media_kit/mpv）的抽象层。
///
/// 它把代码库其余部分与具体引擎隔离开，使上层（控件、手势、状态）永远不需要
/// 直接引入 `package:media_kit`。
abstract class MovaKernel {
  /// Opens a media resource by URI and optionally starts playback immediately.
  ///
  /// [uri] is the media resource location (file path, http(s) or hls URL).
  ///
  /// [play] controls whether playback starts right after opening; defaults
  /// to implementation-defined behavior when omitted.
  ///
  /// Returns a future that completes once the open request has been issued.
  ///
  /// 通过 URI 打开一个媒体资源，并可选择立即开始播放。
  ///
  /// [uri] 为媒体资源地址（文件路径、http(s) 或 hls 链接）。
  ///
  /// [play] 控制打开后是否立即开始播放；省略时由具体实现决定默认行为。
  ///
  /// 返回一个在打开请求发出后完成的 Future。
  Future<void> open(String uri, {bool play});

  /// Starts or resumes playback.
  ///
  /// Returns a future that completes once the play request has been issued.
  ///
  /// 开始或恢复播放。
  ///
  /// 返回一个在播放请求发出后完成的 Future。
  Future<void> play();

  /// Pauses playback.
  ///
  /// Returns a future that completes once the pause request has been issued.
  ///
  /// 暂停播放。
  ///
  /// 返回一个在暂停请求发出后完成的 Future。
  Future<void> pause();

  /// Seeks to the given [position] within the current media.
  ///
  /// Returns a future that completes once the seek request has been issued.
  ///
  /// 跳转到当前媒体中的指定 [position]。
  ///
  /// 返回一个在跳转请求发出后完成的 Future。
  Future<void> seek(Duration position);

  /// Sets the playback volume.
  ///
  /// [volume] ranges from 0 to 100.
  ///
  /// Returns a future that completes once the volume has been applied.
  ///
  /// 设置播放音量。
  ///
  /// [volume] 取值范围为 0 到 100。
  ///
  /// 返回一个在音量应用后完成的 Future。
  Future<void> setVolume(double volume);

  /// Sets the playback speed rate, where `1.0` is normal speed.
  ///
  /// Returns a future that completes once the rate has been applied.
  ///
  /// 设置播放速率，`1.0` 表示正常速度。
  ///
  /// 返回一个在速率应用后完成的 Future。
  Future<void> setRate(double rate);

  /// Captures the current video frame as an encoded image.
  ///
  /// Returns the encoded image bytes, or `null` if a screenshot could not be
  /// captured.
  ///
  /// 截取当前视频帧并编码为图片。
  ///
  /// 返回编码后的图片字节；若无法截图则返回 `null`。
  Future<Uint8List?> screenshot();

  /// Releases all resources held by this kernel instance.
  ///
  /// Returns a future that completes once disposal has finished.
  ///
  /// 释放该内核实例持有的全部资源。
  ///
  /// 返回一个在释放完成后完成的 Future。
  Future<void> dispose();

  /// Emits the current playing/paused state whenever it changes.
  ///
  /// 播放/暂停状态发生变化时推送最新值。
  Stream<bool> get playing;

  /// Emits the current buffering state whenever it changes.
  ///
  /// 缓冲状态发生变化时推送最新值。
  Stream<bool> get buffering;

  /// Emits `true` when playback of the current media has completed.
  ///
  /// 当前媒体播放完成时推送 `true`。
  Stream<bool> get completed;

  /// Emits the current playback position whenever it changes.
  ///
  /// 播放进度发生变化时推送最新值。
  Stream<Duration> get position;

  /// Emits the total duration of the current media whenever it becomes known
  /// or changes.
  ///
  /// 当前媒体总时长确定或发生变化时推送最新值。
  Stream<Duration> get duration;

  /// Emits the buffered position (how far ahead has been downloaded)
  /// whenever it changes.
  ///
  /// 已缓冲位置（提前下载到的进度）发生变化时推送最新值。
  Stream<Duration> get buffer;

  /// Emits the current video frame size whenever it changes.
  ///
  /// 视频帧尺寸发生变化时推送最新值。
  Stream<MovaSize> get size;

  /// Emits playback errors as they occur.
  ///
  /// 播放过程中出现的错误。
  Stream<Object> get error;

  /// The underlying render handle to be attached to a video widget (e.g. a
  /// `VideoController`). Its concrete type is engine-specific and opaque to
  /// callers outside the core layer.
  ///
  /// 供视频渲染组件使用的底层渲染句柄（如 `VideoController`）。
  /// 其具体类型由引擎决定，对核心层之外的调用者不透明。
  Object get renderHandle;

  /// Emits the native video tracks available in the currently open media
  /// (e.g. HLS/DASH variants) whenever the set changes.
  ///
  /// 当前打开媒体可用的原生视频轨（如 HLS/DASH 变体）发生变化时推送最新列表。
  Stream<List<MovaVideoTrack>> get videoTracks;

  /// Emits the currently selected native video track whenever it changes.
  ///
  /// 当前选中的原生视频轨发生变化时推送最新值。
  Stream<MovaVideoTrack> get videoTrack;

  /// Switches the native video track within the current playback session
  /// (no reopen).
  ///
  /// [track] must be one of the entries most recently emitted by
  /// [videoTracks].
  ///
  /// Returns a future that completes once the switch request has been
  /// issued.
  ///
  /// 在当前会话内切换原生视频轨（不重开）。
  ///
  /// [track] 必须是 [videoTracks] 最近一次推送的条目之一。
  ///
  /// 返回一个在切换请求发出后完成的 Future。
  Future<void> setVideoTrack(MovaVideoTrack track);
}

/// An immutable, value-comparable video frame size.
///
/// 一个不可变、按值比较的视频帧尺寸。
class MovaSize {
  /// Creates a video frame size.
  ///
  /// [width] is the frame width in pixels.
  ///
  /// [height] is the frame height in pixels.
  ///
  /// 创建一个视频帧尺寸。
  ///
  /// [width] 为帧宽度（像素）。
  ///
  /// [height] 为帧高度（像素）。
  const MovaSize({required this.width, required this.height});

  /// The frame width in pixels.
  ///
  /// 帧宽度（像素）。
  final int width;

  /// The frame height in pixels.
  ///
  /// 帧高度（像素）。
  final int height;

  @override
  bool operator ==(Object other) =>
      other is MovaSize && other.width == width && other.height == height;

  @override
  int get hashCode => Object.hash(width, height);

  @override
  String toString() => 'MovaSize($width x $height)';
}
