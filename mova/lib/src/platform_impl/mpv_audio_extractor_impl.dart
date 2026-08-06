import 'dart:async';
import 'dart:io';

import 'package:media_kit/media_kit.dart';
import 'package:path_provider/path_provider.dart';

import '../core/stt/audio_extractor.dart';

/// ⚠️ **Unverified spike, not a settled implementation.** A candidate
/// [MovaAudioPuller] built on mpv's `ao=pcm`/`ao-pcm-file` audio-output
/// driver (documented mpv behavior: it decodes straight to a WAV file
/// instead of a real audio device) via a second, headless media_kit
/// `Player` — the same "second hidden player" pattern [MpvFrameExtractor]
/// uses for frame extraction, just for audio.
///
/// What is **not** verified (no real device/build has run this):
/// - Whether `ao`/`ao-pcm-file` are settable as *runtime* properties via
///   `NativePlayer.setProperty` after `Player()` construction, or whether
///   they must be passed as mpv *startup* options before the first `open()`
///   — if the latter, this implementation is wrong as written and needs
///   `media_kit`'s lower-level player-construction API instead (if one
///   exists).
/// - Whether mpv decode-through to a file sink actually runs faster than
///   real-time (no audio-hardware clock to pace against), or still throttles
///   to playback speed — if it throttles, a two-hour movie takes two hours
///   to extract, which would sink the whole "batch pre-transcribe" premise.
/// - Whether `vid=no` (disabling video decode) is honored together with a
///   PCM-file audio sink, or whether mpv still insists on a video output
///   target for some container/codec combinations.
///
/// Until spiked on a real device/desktop build, treat every call as
/// possibly wrong — this is here so the shape exists to iterate on, not
/// because it's known to work.
///
/// ⚠️ **未验证的 spike，不是定案实现。** 基于 mpv 的 `ao=pcm`/
/// `ao-pcm-file` 音频输出驱动（mpv 文档记录的行为：直接把解码结果写成 WAV
/// 文件，而非送到真实音频设备）、借助第二个无头 media_kit `Player` 构建的
/// 候选 [MovaAudioPuller]——跟 [MpvFrameExtractor] 抽帧用的"第二个隐藏
/// player"是同一套打法，只是这次抽的是音频。
///
/// **没有验证过**的地方（从未在真实设备/真实构建上跑过）：
/// - `ao`/`ao-pcm-file` 能不能在 `Player()` 构造之后，通过
///   `NativePlayer.setProperty` 当作**运行时属性**设置；还是必须在第一次
///   `open()` 之前作为 mpv **启动选项**传入——如果是后者，这份实现按目前写法
///   是错的，需要用 `media_kit` 更底层的播放器构造 API（如果有的话）。
/// - mpv 解码写到文件 sink 是否真的比实时快（没有音频硬件时钟节拍约束），
///   还是仍然按播放速度节流——如果节流，一部两小时的电影抽音频就要两小时，
///   会直接推翻"批量预转写"这整个前提。
/// - `vid=no`（关闭视频解码）能不能和 PCM 文件音频 sink 一起生效，还是某些
///   容器/编码组合下 mpv 仍然坚持要一个视频输出目标。
///
/// 在真实设备/桌面构建上跑过 spike 之前，每次调用都可能是错的——写出这个
/// 形状是为了有东西可以迭代，不是因为已知它能跑通。
class MpvAudioExtractor implements MovaAudioPuller {
  /// Creates an extractor; the hidden player is created lazily on first use.
  ///
  /// 创建抽取器；隐藏播放器在首次使用时才惰性创建。
  MpvAudioExtractor();

  Player? _player;
  bool _disposed = false;

  @override
  Future<String?> extractWav(String uri) async {
    if (_disposed) return null;
    try {
      final dir = await getTemporaryDirectory();
      final outPath =
          '${dir.path}${Platform.pathSeparator}mova_stt_audio_${DateTime.now().microsecondsSinceEpoch}.wav';

      final player = Player();
      final native = player.platform;
      if (native is NativePlayer) {
        await native.setProperty('vid', 'no');
        await native.setProperty('ao', 'pcm');
        await native.setProperty('ao-pcm-file', outPath);
        // Disables real-time pacing so decode-through runs as fast as I/O
        // allows rather than at 1x playback speed — unverified whether this
        // actually applies to a file-sink `ao=pcm` output (see class doc).
        //
        // 关闭实时节拍，让解码尽可能快而不是按 1x 播放速度走——这个设置对
        // 文件 sink 的 `ao=pcm` 输出是否真的生效未经验证（见类文档注释）。
        await native.setProperty('untimed', 'yes');
      }

      final completer = Completer<void>();
      final sub = player.stream.completed.listen((done) {
        if (done && !completer.isCompleted) completer.complete();
      });
      await player.open(Media(uri), play: true);
      await completer.future.timeout(const Duration(minutes: 30));
      await sub.cancel();
      await player.dispose();

      if (!await File(outPath).exists()) return null;
      return outPath;
    } on Object {
      return null;
    }
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    final player = _player;
    _player = null;
    if (player != null) {
      try {
        await player.dispose();
      } on Object {
        // Disposing a hidden helper must never surface as a playback error.
        //
        // 释放隐藏辅助播放器时的异常绝不能冒充成播放错误。
      }
    }
  }
}
