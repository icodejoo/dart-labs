import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'fvideo_source.dart';

/// Thin playback controller wrapping media_kit's [Player] + [VideoController].
///
/// This is the "core" layer of fvideo: pure playback, no UI. Feed its
/// [videoController] to a media_kit [Video] widget (or fvideo's own player).
///
/// 对 media_kit 的 [Player] 与 [VideoController] 的薄封装。
///
/// 这是 fvideo 的“内核”层：只管播放、不含 UI。把 [videoController] 交给
/// media_kit 的 [Video] 组件（或 fvideo 自己的播放器）即可渲染。
class FvideoController {
  /// Underlying media_kit player (libmpv/ffmpeg backend).
  ///
  /// 底层 media_kit 播放器（libmpv/ffmpeg 内核）。
  final Player player;

  /// Video render controller bound to [player].
  ///
  /// 绑定到 [player] 的视频渲染控制器。
  late final VideoController videoController;

  FvideoSource? _source;

  /// Creates a controller and its video render pipeline.
  ///
  /// 创建控制器及其视频渲染管线。
  ///
  /// Example / 示例:
  /// ```dart
  /// final c = FvideoController();
  /// await c.open(FvideoSource('https://host/a.mp4'));
  /// ```
  FvideoController() : player = Player() {
    videoController = VideoController(player);
  }

  /// One-time global init; call before creating any controller.
  ///
  /// 全局一次性初始化；创建任何控制器前调用。
  static void ensureInitialized() => MediaKit.ensureInitialized();

  /// The currently opened source, or null before [open].
  ///
  /// 当前已打开的源；[open] 之前为 null。
  FvideoSource? get source => _source;

  /// Whether the current source is a live stream.
  ///
  /// 当前源是否为直播流。
  bool get isLive => _source?.type == FvideoStreamType.live;

  /// Opens [source] and (by default) starts playing.
  ///
  /// 打开 [source] 并（默认）开始播放。
  ///
  /// - [source]: what to play / 要播放的源
  /// - [autoPlay]: play immediately, default true / 是否立即播放，默认是
  Future<void> open(FvideoSource source, {bool autoPlay = true}) async {
    _source = source;
    await player.open(Media(source.uri), play: autoPlay);
  }

  /// Resumes playback.
  ///
  /// 恢复播放。
  Future<void> play() => player.play();

  /// Pauses playback.
  ///
  /// 暂停播放。
  Future<void> pause() => player.pause();

  /// Toggles play/pause.
  ///
  /// 切换播放/暂停。
  Future<void> playOrPause() => player.playOrPause();

  /// Seeks to an absolute [position]; ignored for live streams.
  ///
  /// 跳转到绝对 [position]；直播流下忽略。
  Future<void> seek(Duration position) async {
    if (isLive) return;
    await player.seek(position);
  }

  /// Sets volume in the range 0–100.
  ///
  /// 设置音量，范围 0–100。
  Future<void> setVolume(double volume) =>
      player.setVolume(volume.clamp(0, 100));

  /// Sets playback speed (1.0 = normal).
  ///
  /// 设置播放倍速（1.0 为正常）。
  Future<void> setRate(double rate) => player.setRate(rate);

  /// Releases the player and its resources.
  ///
  /// 释放播放器及其资源。
  Future<void> dispose() => player.dispose();
}
