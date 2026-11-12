import 'dart:async';
import 'dart:io';

import 'package:media_kit/media_kit.dart';
import 'package:path_provider/path_provider.dart';

import '../core/stt/audio_extractor.dart';

/// ⚠️ **Unverified spike, not a settled implementation.** A candidate
/// [MovaAudioPuller] built on mpv's `ao=pcm`/`ao-pcm-file` audio-output
/// driver (documented mpv behavior: it decodes straight to a WAV file
/// instead of a real audio device) via a second, headless media_kit
/// `Player` — the same "second hidden player" pattern [MovaFrameExtractor]
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
/// 候选 [MovaAudioPuller]——跟 [MovaFrameExtractor] 抽帧用的"第二个隐藏
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
class MovaAudioExtractor implements MovaAudioPuller {
  /// Creates an extractor; the hidden player is created lazily on first use.
  /// [playerFactory] creates the owned player, [tempDirectory] supplies output
  /// storage, and [timeout] bounds extraction; see the example below.
  ///
  /// 创建抽取器；隐藏播放器在首次使用时才惰性创建。
  /// [playerFactory] 创建独占播放器，[tempDirectory] 提供输出目录，
  /// [timeout] 约束整个抽取操作。返回抽取器；示例：`MovaAudioExtractor(timeout: Duration(minutes: 5))`。
  MovaAudioExtractor({
    Player Function()? playerFactory,
    Future<String> Function()? tempDirectory,
    this.timeout = const Duration(minutes: 30),
  }) : _playerFactory = playerFactory ?? Player.new,
       _tempDirectory = tempDirectory ?? _defaultDirectory;

  /// The hidden player factory.
  ///
  /// 隐藏播放器工厂。
  final Player Function() _playerFactory;

  /// The output directory resolver.
  ///
  /// 输出目录解析器。
  final Future<String> Function() _tempDirectory;

  /// The deadline for one extraction operation.
  ///
  /// 整次抽取的最长耗时。
  final Duration timeout;

  /// The currently owned player.
  ///
  /// 当前被独占持有的播放器。
  Player? _player;

  /// Pending native disposal shared by cancellation and extraction cleanup.
  ///
  /// 取消路径和抽取清理路径共同等待的原生释放操作。
  Future<void>? _releasePending;

  /// Whether this extractor has been disposed.
  ///
  /// 是否已销毁。
  bool _disposed = false;

  /// Cancellation signal that immediately wakes extraction on disposal.
  ///
  /// 当前抽取的取消信号，dispose 时立即唤醒等待。
  Completer<void>? _cancel;

  /// Serializes requests to preserve native resource ownership.
  ///
  /// 并发请求串行执行，避免覆盖原生资源所有权。
  Future<void> _queue = Future<void>.value();

  /// Returns the platform temporary directory.
  ///
  /// 返回平台临时目录。
  static Future<String> _defaultDirectory() async =>
      (await getTemporaryDirectory()).path;

  /// Extracts a WAV from [uri], returning null on failure, cancellation or timeout.
  /// Example: `await extractor.extractWav(uri)`.
  ///
  /// 抽取 [uri] 的 WAV 文件；异常、取消或超时返回 null。示例：`await extractor.extractWav(uri)`。
  @override
  Future<String?> extractWav(String uri) {
    final result = _queue.then((_) => _extractNow(uri));
    _queue = result.then<void>((_) {}, onError: (Object e, StackTrace st) {});
    return result;
  }

  /// Extracts [uri], cancelling subscriptions and releasing the player on every exit.
  ///
  /// 抽取 [uri]，所有退出路径都取消订阅并释放本次播放器。
  Future<String?> _extractNow(String uri) async {
    if (_disposed) return null;
    Player? owned;
    StreamSubscription<bool>? sub;
    // Output path created by this call; deleted unless ownership is handed over.
    // 本次创建的输出路径；未成功移交给调用方时在释放播放器后删除。
    String? createdPath;
    var handedOver = false;
    final cancelled = Completer<void>();
    _cancel = cancelled;
    try {
      final operation = () async {
        final dir = await _tempDirectory();
        if (_disposed || cancelled.isCompleted) return null;
        final outPath =
            '$dir${Platform.pathSeparator}mova_stt_audio_${DateTime.now().microsecondsSinceEpoch}.wav';
        createdPath = outPath;
        final player = owned = _player = _playerFactory();
        final native = player.platform;
        if (native is NativePlayer) {
          for (final property in <String, String>{
            'vid': 'no',
            'ao': 'pcm',
            'ao-pcm-file': outPath,
            'audio-samplerate': '16000',
            'audio-channels': 'mono',
            'untimed': 'yes',
          }.entries) {
            await native.setProperty(property.key, property.value);
            if (_disposed || cancelled.isCompleted) return null;
          }
        }
        final completed = Completer<void>();
        sub = player.stream.completed.listen((done) {
          if (done && !completed.isCompleted) completed.complete();
        });
        await player.open(Media(uri), play: true);
        if (_disposed || cancelled.isCompleted) return null;
        await Future.any([completed.future, cancelled.future]);
        if (_disposed || cancelled.isCompleted) return null;
        return outPath;
      }();
      final outPath =
          await Future.any<String?>([
            operation,
            cancelled.future.then<String?>((_) => null),
          ]).timeout(
            timeout,
            onTimeout: () {
              if (!cancelled.isCompleted) cancelled.complete();
              return null;
            },
          );
      // PCM output flushes its header on close; release before checking the file.
      //
      // PCM 输出在播放器关闭时刷新文件头，必须先释放再检查文件。
      await sub?.cancel();
      sub = null;
      await _release(owned);
      if (outPath == null || !await File(outPath).exists()) return null;
      handedOver = true;
      return outPath;
    } on Object {
      return null;
    } finally {
      if (!cancelled.isCompleted) cancelled.complete();
      await sub?.cancel();
      await _release(owned);
      // The player is gone, so nothing is still writing the partial file.
      // 播放器已释放，不会再有写入，可安全删除残留的半成品 WAV。
      final leftover = createdPath;
      if (!handedOver && leftover != null) {
        try {
          final f = File(leftover);
          if (await f.exists()) await f.delete();
        } on Object {
          // Cleanup failures do not affect the extraction result.
          //
          // 清理失败不影响返回值。
        }
      }
      if (identical(_cancel, cancelled)) _cancel = null;
    }
  }

  /// Releases [player] once, waiting if another path already owns disposal.
  ///
  /// 释放 [player] 恰好一次；其他路径已认领释放时等待同一次释放完成。
  Future<void> _release(Player? player) async {
    if (player == null) return;
    if (!identical(_player, player)) {
      await _releasePending;
      return;
    }
    _player = null;
    final released = Completer<void>();
    _releasePending = released.future;
    try {
      await player.dispose();
    } on Object {
      // Helper disposal failures must not surface as playback errors.
      //
      // 辅助资源回收失败不冒充播放错误。
    } finally {
      released.complete();
      _releasePending = null;
    }
  }

  /// Cancels extraction and releases native resources; no arguments or return value.
  /// Example: `await extractor.dispose()`.
  ///
  /// 取消当前抽取并释放原生资源；无参数、无返回值。示例：`await extractor.dispose()`。
  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    final cancel = _cancel;
    if (cancel != null && !cancel.isCompleted) cancel.complete();
    await _release(_player);
  }
}
