/// Decodes a media source's entire audio track to a WAV file on disk, for
/// one-shot batch transcription of VOD content (see
/// `doc/notes/2026-08-04-stt-engine-decision.md`'s "批量预转写" section).
///
/// A port rather than a concrete class for the same reason as
/// [VmFrameExtractor]: the only implementation spins a second, headless
/// media_kit player, and `lib/src/core/**` must stay media_kit-free — the
/// implementation lives in
/// `lib/src/platform_impl/mpv_audio_extractor_impl.dart`.
///
/// ⚠️ Unlike [VmFrameExtractor] (a settled, shipped implementation), the
/// platform_impl backing this port is an **unverified spike** — see that
/// file's doc comment. Nothing in `core/` or `videoman_stt` depends on it
/// working yet.
///
/// 把媒体源的完整音轨解码为磁盘上的 WAV 文件，供点播内容一次性批量转写用
/// （见 `doc/notes/2026-08-04-stt-engine-decision.md` 的"批量预转写"一节）。
///
/// 做成端口而非具体类的原因与 [VmFrameExtractor] 相同：唯一的实现会另起一个
/// 无头的 media_kit 播放器，而 `lib/src/core/**` 必须与 media_kit
/// 解耦——实现放在 `lib/src/platform_impl/mpv_audio_extractor_impl.dart`。
///
/// ⚠️ 与 [VmFrameExtractor]（已落地、已上线的实现）不同，撑起这个端口的
/// platform_impl 是一个**未验证的 spike**——见该文件的文档注释。目前
/// `core/` 与 `videoman_stt` 里没有任何代码依赖它真的能跑通。
abstract class VmAudioExtractor {
  /// Decodes [uri]'s entire audio track to a mono 16kHz WAV file.
  ///
  /// 把 [uri] 的完整音轨解码为单声道 16kHz 的 WAV 文件。
  ///
  /// - [uri]: the media address / 媒体地址
  ///
  /// Returns the absolute path of the written WAV file, or null on failure.
  ///
  /// 返回写出的 WAV 文件绝对路径；失败时返回 null。
  Future<String?> extractWav(String uri);

  /// Releases everything permanently.
  ///
  /// 永久释放全部资源。
  Future<void> dispose();
}
