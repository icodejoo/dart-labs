import 'dart:convert';
import 'dart:io';

import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../videoman_platform_interface.dart';
import 'source.dart';
import 'quality.dart';

/// Thin playback controller wrapping media_kit's [Player] + [VideoController].
///
/// This is the "core" layer of videoman: pure playback, no UI. Feed its
/// [videoController] to a media_kit [Video] widget (or videoman's own player).
///
/// 对 media_kit 的 [Player] 与 [VideoController] 的薄封装。
///
/// 这是 videoman 的“内核”层：只管播放、不含 UI。把 [videoController] 交给
/// media_kit 的 [Video] 组件（或 videoman 自己的播放器）即可渲染。
class VmController {
  /// Underlying media_kit player (libmpv/ffmpeg backend).
  ///
  /// 底层 media_kit 播放器（libmpv/ffmpeg 内核）。
  final Player player;

  /// Video render controller bound to [player].
  ///
  /// 绑定到 [player] 的视频渲染控制器。
  late final VideoController videoController;

  VmSource? _source;
  List<VmQuality> _qualities = [];
  VmQuality? _currentQuality;

  /// Creates a controller and its video render pipeline.
  ///
  /// 创建控制器及其视频渲染管线。
  ///
  /// Example / 示例:
  /// ```dart
  /// final c = VmController();
  /// await c.open(VmSource('https://host/a.mp4'));
  /// ```
  VmController() : player = Player() {
    videoController = VideoController(player);
  }

  /// One-time global init; call before creating any controller.
  ///
  /// 全局一次性初始化；创建任何控制器前调用。
  static void ensureInitialized() => MediaKit.ensureInitialized();

  /// The currently opened source, or null before [open].
  ///
  /// 当前已打开的源；[open] 之前为 null。
  VmSource? get source => _source;

  /// Whether the current source is a live stream.
  ///
  /// 当前源是否为直播流。
  bool get isLive => _source?.type == VmStreamType.live;

  /// Available quality variants (empty until [loadQualities] resolves an
  /// HLS master playlist). "Auto" is first when present.
  ///
  /// 可用清晰度档位（在 [loadQualities] 解析出 HLS master 前为空）。存在时"自动"在首位。
  List<VmQuality> get qualities => List.unmodifiable(_qualities);

  /// The currently selected quality, or null when unknown.
  ///
  /// 当前选中的清晰度；未知时为 null。
  VmQuality? get currentQuality => _currentQuality;

  /// Opens [source] and (by default) starts playing.
  ///
  /// 打开 [source] 并（默认）开始播放。
  ///
  /// - [source]: what to play / 要播放的源
  /// - [autoPlay]: play immediately, default true / 是否立即播放，默认是
  Future<void> open(VmSource source, {bool autoPlay = true}) async {
    _source = source;
    _qualities = [];
    _currentQuality = null;
    await player.open(Media(source.uri), play: autoPlay);
  }

  /// Fetches and parses quality variants from an HLS master playlist.
  /// No-op (clears the list) for non-HLS sources or on any network error.
  ///
  /// 从 HLS master playlist 拉取并解析清晰度档位。非 HLS 源或网络出错时清空列表。
  Future<void> loadQualities() async {
    final s = _source;
    if (s == null || !s.uri.toLowerCase().contains('.m3u8')) {
      _qualities = [];
      _currentQuality = null;
      return;
    }
    try {
      final content = await _httpGetString(s.uri);
      _qualities = parseHlsMasterPlaylist(content, base: Uri.parse(s.uri));
      _currentQuality = _qualities.isNotEmpty ? _qualities.first : null;
    } catch (_) {
      _qualities = [];
      _currentQuality = null;
    }
  }

  /// Switches to quality [q], preserving position (VOD) and play state.
  ///
  /// 切换到清晰度 [q]，保留进度（点播）与播放状态。
  Future<void> switchQuality(VmQuality q) async {
    final playUri = q.isAuto ? (_source?.uri ?? '') : q.uri;
    if (playUri.isEmpty) return;
    final pos = player.state.position;
    final wasPlaying = player.state.playing;
    await player.open(Media(playUri), play: wasPlaying);
    if (!isLive) await player.seek(pos);
    _currentQuality = q;
  }

  /// Steps down one variant (used by the ABR monitor). No-op in auto mode,
  /// at the lowest variant, or with fewer than two variants.
  ///
  /// 下降一档（供 ABR 监测调用）。自动模式、已是最低档或档位不足两个时无操作。
  Future<void> downshiftQuality() async {
    final cur = _currentQuality;
    if (cur == null || cur.isAuto) return;
    final variants = _qualities.where((q) => !q.isAuto).toList();
    final idx = variants.indexWhere((q) => q.uri == cur.uri);
    if (idx < 0 || idx + 1 >= variants.length) return;
    await switchQuality(variants[idx + 1]);
  }

  /// GETs [url] as a UTF-8 string via a one-shot HTTP client.
  ///
  /// 用一次性 HTTP 客户端以 UTF-8 拉取 [url] 文本。
  Future<String> _httpGetString(String url) async {
    final client = HttpClient();
    try {
      final req = await client.getUrl(Uri.parse(url));
      final resp = await req.close();
      return await resp.transform(const Utf8Decoder()).join();
    } finally {
      client.close();
    }
  }

  /// Re-opens the current source from scratch (used as the live "go to edge").
  ///
  /// 重新打开当前源（用作直播"回到边缘"）。
  Future<void> reload() async {
    final s = _source;
    if (s != null) await open(s);
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

  /// Whether the platform supports system picture-in-picture (Android only
  /// today; iOS/desktop return false — see ROADMAP technical risks).
  ///
  /// 平台是否支持系统画中画（目前仅 Android；iOS/桌面返回 false，见 ROADMAP 风险）。
  Future<bool> isPipSupported() => VmPlatform.instance.isPipSupported();

  /// Requests system PiP using the current video's aspect ratio.
  /// Returns whether PiP was entered.
  ///
  /// 用当前视频宽高比请求系统画中画。返回是否成功进入。
  Future<bool> enterPip() => VmPlatform.instance.enterPip(
        width: player.state.width,
        height: player.state.height,
      );

  /// Releases the player and its resources.
  ///
  /// 释放播放器及其资源。
  Future<void> dispose() => player.dispose();
}
