import '../standby/standby.dart';

/// Whether the current media has audio that is actually being decoded.
///
/// 当前媒体是否有**正在解码**的音频。
enum MovaAudioPresence {
  /// Not known yet: tracks not loaded, or an audio track exists but its
  /// decoder has not produced output (it may still be starting, or the
  /// codec may be unsupported by a slim libmpv build).
  ///
  /// 尚不知道：轨道未加载；或有音轨但解码器还没输出（可能仍在起播，也可能瘦身版
  /// libmpv 不支持该编码）。
  unknown,

  /// An audio track is selected and decoding.
  ///
  /// 有选中的音轨且正在解码。
  present,

  /// Tracks are loaded and there is no usable audio.
  ///
  /// 轨道已加载，且没有可用音频。
  absent,
}

/// Facts about the current media that decide whether and how to hold it.
///
/// 决定当前媒体能否待机、以何种方式待机的事实。
class MovaStandbyMedia {
  /// Creates the facts.
  ///
  /// 创建事实。
  ///
  /// - [audio]: audio presence / 音频存在性
  /// - [format]: mpv `file-format`, null when unreadable / mpv 的 `file-format`，读不到为 null
  const MovaStandbyMedia({required this.audio, this.format});

  /// Audio presence, see [MovaAudioPresence].
  ///
  /// 音频存在性，见 [MovaAudioPresence]。
  final MovaAudioPresence audio;

  /// mpv's `file-format` (demuxer name, e.g. `flv`, `hls`); `null` when unreadable.
  ///
  /// mpv 的 `file-format`（demuxer 名，如 `flv`、`hls`）；读不到时为 `null`。
  final String? format;
}

/// Optional kernel capability: hold the stream with video and/or sound off.
/// Never throws; a kernel that lacks it simply makes standby fall back to a pause.
///
/// 可选的内核能力：在关掉画面和/或声音的情况下维持流。绝不抛异常；不具备此能力的内核
/// 只会让待机退回为普通暂停。
abstract class MovaStandbyKernel {
  /// Reads the facts standby decides on.
  ///
  /// 读取待机决策所需的事实。
  Future<MovaStandbyMedia> inspectStandby();

  /// Applies [mode], saving every property it changes. Returns false (after
  /// rolling back) when a write failed or timed out.
  ///
  /// 应用 [mode]，并保存它改动的每一个属性。写入失败或超时则回滚并返回 false。
  Future<bool> enterStandby(MovaStandbyMode mode);

  /// Restores exactly what [enterStandby] changed. Returns whether video
  /// decoding was restarted (so a fresh first frame is coming). Idempotent.
  ///
  /// 精确还原 [enterStandby] 改动的内容。返回视频解码是否被重新启动（即接下来会有新的
  /// 首帧）。幂等。
  Future<bool> exitStandby();
}

/// Classifies audio presence from plain track facts. Pure; see [MovaAudioPresence].
///
/// 用朴素的轨道事实判定音频存在性。纯函数；见 [MovaAudioPresence]。
///
/// - [audioIds]: audio track ids from mpv's track list (`auto`/`no` are pseudo tracks) / mpv 轨道表里的音轨 id（`auto`/`no` 是伪轨）
/// - [videoIds]: video track ids / 视频轨 id
/// - [selectedAudio]: the selected audio id / 当前选中的音轨 id
/// - [sampleRate]: from `audio-params`; null until the audio decoder outputs / 来自 `audio-params`；音频解码器有输出前为 null
///
/// Returns the presence / 返回存在性。
MovaAudioPresence movaAudioPresence({
  required Iterable<String> audioIds,
  required Iterable<String> videoIds,
  required String selectedAudio,
  required int? sampleRate,
}) {
  bool real(String id) => id != 'auto' && id != 'no';
  final audio = audioIds.where(real).toList();
  final loaded = audio.isNotEmpty || videoIds.any(real);
  if (!loaded) return MovaAudioPresence.unknown;
  if (selectedAudio == 'no' || audio.isEmpty) return MovaAudioPresence.absent;
  return (sampleRate ?? 0) > 0 ? MovaAudioPresence.present : MovaAudioPresence.unknown;
}
