import 'dart:async';
import 'dart:typed_data';

import '../core/kernel/kernel.dart';
import '../core/kernel/source_options_kernel.dart';
import '../core/kernel/keep_alive_kernel.dart';
import '../core/report/stats_probe.dart';
import '../core/keep_alive/keep_alive.dart';

/// A scriptable [MovaKernel] (+ [MovaStatsProbe]) for widget tests: records
/// calls and lets the test push any kernel signal, so a real `MovaEngine` can
/// run without ever touching media_kit.
///
/// 供 widget 测试使用的可编程 [MovaKernel]（兼 [MovaStatsProbe]）：记录调用，并允许
/// 测试推送任意内核信号，使真实的 `MovaEngine` 完全不碰 media_kit 也能运行。
///
/// Example / 示例:
/// ```dart
/// final k = MovaTesting.lastKernel!;
/// k.emitSize(1280, 720);
/// k.emitRestart(); // MovaState.rendered → true
/// ```
class MovaTestKernel implements MovaKernel, MovaStatsProbe, MovaKeepAliveKernel, MovaSourceOptionsKernel {
  /// Creates a test kernel.
  ///
  /// 创建一个测试内核。
  ///
  /// - [renderHandle]: what the engine reports as its render handle; `null`
  ///   (default) makes `MovaPlayer` draw its placeholder / 引擎对外报告的渲染句柄；
  ///   默认 `null`，此时 `MovaPlayer` 绘制占位
  /// - [nativeRestartAvailable]: pretend the native restart subscription is
  ///   live. `false` (default) makes buffering/position fallbacks land the
  ///   first frame immediately, with no grace timer left pending / 假装原生 RESTART
  ///   订阅在工作。默认 `false`：buffering/位置兜底会立刻落地首帧，不会留下挂起的宽限计时器
  MovaTestKernel({this.renderHandle, this.nativeRestartAvailable = false});

  /// Names of the methods called on this kernel, in order (`open`, `play`, ...).
  ///
  /// 在本内核上被调用的方法名，按调用顺序。
  final List<String> calls = <String>[];

  /// The uri of the most recent `open()`.
  ///
  /// 最近一次 `open()` 的 uri。
  String? lastUri;

  /// The `play` flag of the most recent `open()`.
  ///
  /// 最近一次 `open()` 的 `play` 标志。
  bool? lastPlay;

  /// The target of the most recent `seek()`.
  ///
  /// 最近一次 `seek()` 的目标。
  Duration? lastSeek;

  /// The mpv options the engine staged for each `open()`, in order (an empty map
  /// when the source had none). Lets host tests assert `MovaSource.mpvOptions`
  /// / `whepMediaTimeout` reach the kernel.
  ///
  /// 引擎为每次 `open()` 暂存的 mpv 选项，按顺序（源没有选项时为空 Map）。供宿主测试断言
  /// `MovaSource.mpvOptions` / `whepMediaTimeout` 确实到达了内核。
  final List<Map<String, String>> stagedSourceOptions = <Map<String, String>>[];

  @override
  void stageSourceOptions(Map<String, String> options) => stagedSourceOptions.add(Map.of(options));

  /// When non-null, `open()` throws it (after recording the call).
  ///
  /// 非空时，`open()` 会（在记录调用之后）抛出它。
  Object? openError;

  /// Whether the scripted media has decodable audio: true/false, or null for
  /// "not known yet" (the default — keepAlive then falls back to a pause).
  ///
  /// 编排的媒体是否有可解码的音频：true/false；null 表示"尚不知道"（默认——此时待机会退回暂停）。
  bool? hasAudio;

  /// The demuxer reported to keepAlive, e.g. `flv` (default) or `hls`.
  ///
  /// 报告给待机的 demuxer，例如 `flv`（默认）或 `hls`。
  String? fileFormat = 'flv';

  /// The keepAlive mode currently held, or null.
  ///
  /// 当前持有的待机组合；没有则为 null。
  MovaKeepAliveMode? _heldMode;

  @override
  Future<MovaKeepAliveMedia> inspectKeepAlive() async {
    calls.add('inspectKeepAlive');
    final audio = hasAudio;
    return MovaKeepAliveMedia(
      audio: audio == null
          ? MovaAudioPresence.unknown
          : (audio ? MovaAudioPresence.present : MovaAudioPresence.absent),
      format: fileFormat,
    );
  }

  @override
  Future<bool> enterKeepAlive(MovaKeepAliveMode mode) async {
    calls.add('enterKeepAlive:${mode.name}');
    _heldMode = mode;
    return true;
  }

  @override
  Future<bool> exitKeepAlive() async {
    calls.add('exitKeepAlive');
    final was = _heldMode;
    _heldMode = null;
    return was == MovaKeepAliveMode.muted;
  }

  @override
  Object? renderHandle;

  @override
  bool nativeRestartAvailable;

  final StreamController<bool> _playing = StreamController<bool>.broadcast();
  final StreamController<bool> _buffering = StreamController<bool>.broadcast();
  final StreamController<bool> _completed = StreamController<bool>.broadcast();
  final StreamController<Duration> _position = StreamController<Duration>.broadcast();
  final StreamController<Duration> _duration = StreamController<Duration>.broadcast();
  final StreamController<Duration> _buffer = StreamController<Duration>.broadcast();
  final StreamController<MovaSize> _size = StreamController<MovaSize>.broadcast();
  final StreamController<Object> _error = StreamController<Object>.broadcast();
  final StreamController<bool> _stalling = StreamController<bool>.broadcast();
  final StreamController<MovaLogLine> _logs = StreamController<MovaLogLine>.broadcast();
  final StreamController<void> _restarts = StreamController<void>.broadcast();
  final StreamController<MovaEndFileReason> _endFiles = StreamController<MovaEndFileReason>.broadcast();

  // ---- MovaKernel verbs ----

  @override
  Future<void> open(String uri, {bool play = true}) async {
    calls.add('open');
    lastUri = uri;
    lastPlay = play;
    final err = openError;
    if (err != null) throw err;
  }

  @override
  Future<void> play() async => calls.add('play');

  @override
  Future<void> pause() async => calls.add('pause');

  @override
  Future<void> seek(Duration position) async {
    calls.add('seek');
    lastSeek = position;
  }

  @override
  Future<void> setVolume(double volume) async => calls.add('setVolume');

  @override
  Future<void> setRate(double rate) async => calls.add('setRate');

  @override
  Future<Uint8List?> screenshot() async {
    calls.add('screenshot');
    return null;
  }

  @override
  Future<void> dispose() async {
    calls.add('dispose');
    for (final c in <StreamController<Object?>>[
      _playing,
      _buffering,
      _completed,
      _position,
      _duration,
      _buffer,
      _size,
      _error,
      _stalling,
      _logs,
      _restarts,
      _endFiles,
    ]) {
      await c.close();
    }
  }

  // ---- MovaKernel streams ----

  @override
  Stream<bool> get playing => _playing.stream;

  @override
  Stream<bool> get buffering => _buffering.stream;

  @override
  Stream<bool> get completed => _completed.stream;

  @override
  Stream<Duration> get position => _position.stream;

  @override
  Stream<Duration> get duration => _duration.stream;

  @override
  Stream<Duration> get buffer => _buffer.stream;

  @override
  Stream<MovaSize> get size => _size.stream;

  @override
  Stream<Object> get error => _error.stream;

  // ---- MovaStatsProbe ----

  @override
  Stream<bool> get stalling => _stalling.stream;

  @override
  Stream<MovaLogLine> get logs => _logs.stream;

  @override
  Stream<void> get playbackRestarts => _restarts.stream;

  @override
  Stream<MovaEndFileReason> get endFiles => _endFiles.stream;

  @override
  Future<MovaStatsSnapshot?> sample() async => null;

  // ---- test-side pushes ----

  /// Pushes a playing/paused state.
  ///
  /// 推送一个播放/暂停状态。
  void emitPlaying(bool v) => _playing.add(v);

  /// Pushes a buffering state.
  ///
  /// 推送一个缓冲状态。
  void emitBuffering(bool v) => _buffering.add(v);

  /// Pushes a completed state.
  ///
  /// 推送一个播放完成状态。
  void emitCompleted(bool v) => _completed.add(v);

  /// Pushes a playback position.
  ///
  /// 推送一个播放位置。
  void emitPosition(Duration v) => _position.add(v);

  /// Pushes the media duration.
  ///
  /// 推送媒体时长。
  void emitDuration(Duration v) => _duration.add(v);

  /// Pushes the buffered position.
  ///
  /// 推送已缓冲位置。
  void emitBuffer(Duration v) => _buffer.add(v);

  /// Pushes a video frame size.
  ///
  /// 推送视频帧尺寸。
  void emitSize(int w, int h) => _size.add(MovaSize(width: w, height: h));

  /// Pushes a kernel error.
  ///
  /// 推送一个内核错误。
  void emitError(Object e) => _error.add(e);

  /// Pushes a native `PLAYBACK_RESTART` (lands the first frame regardless of
  /// [nativeRestartAvailable]).
  ///
  /// 推送一次原生 `PLAYBACK_RESTART`（不论 [nativeRestartAvailable] 如何都会落地首帧）。
  void emitRestart() => _restarts.add(null);

  /// Pushes a native `END_FILE` reason.
  ///
  /// 推送一次原生 `END_FILE` 原因。
  void emitEndFile(MovaEndFileReason r) => _endFiles.add(r);

  /// Pushes a `paused-for-cache` state.
  ///
  /// 推送一个 `paused-for-cache` 状态。
  void emitStalling(bool v) => _stalling.add(v);
}
