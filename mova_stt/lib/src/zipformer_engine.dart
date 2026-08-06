import 'dart:async';
import 'dart:typed_data';

import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;
import 'package:mova/mova.dart';

/// A [MovaSttEngine] backed by sherpa-onnx's offline bilingual Zipformer
/// (`zipformer-zh-en-2023-11-22`; see
/// `mova/doc/notes/2026-08-04-stt-engine-decision.md` for the selection
/// rationale) — covers Chinese, English, and Chinese-English code-switching.
///
/// The Zipformer here is an *offline* (non-streaming) transducer, so it
/// cannot be handed a continuous audio stream directly — it needs
/// individually-bounded utterances. Segmentation is done by a
/// [sherpa.VoiceActivityDetector] (silero-vad): incoming samples are sliced
/// into fixed VAD-frame-sized windows (zero-copy — see [_vadLeftover]), the
/// VAD emits speech segments once it detects a silence boundary, and each
/// segment is decoded independently.
///
/// ⚠️ Real-device finding (2026-08-05): full-video batch transcription
/// reliably produced a cue for only the *first* detected speech segment and
/// silently dropped every one after it, even though VAD was correctly
/// detecting and decoding all of them (confirmed by tracing: every segment's
/// decoded text was correct and non-empty). The actual cause was [_cues]
/// being a non-`sync` broadcast [StreamController]: `stop()` decodes and
/// calls `_cues.add(...)` for several segments back-to-back with no `await`
/// between them, and a plain broadcast controller defers each event to a
/// later microtask — by the time `transcribeWavFile`'s `await stop()`
/// returned and it read its accumulated list, only the first delivery had
/// actually run. Constructing with `sync: true` delivers each event
/// synchronously inside `add()`, which is safe here since the only listener
/// is a plain `List.add`. (An earlier, now-superseded theory blamed
/// fixed-time-window chunking confusing the transducer's decoder — VAD-based
/// segmentation was adopted for that reason and is still the right design,
/// but it was never the actual fix for this symptom.)
///
/// 基于 sherpa-onnx 离线双语 Zipformer（`zipformer-zh-en-2023-11-22`；选型
/// 依据见 `mova/doc/notes/2026-08-04-stt-engine-decision.md`）的
/// [MovaSttEngine]——覆盖中文、英文及中英混说。
///
/// 这里用的 Zipformer 是**离线（非流式）** transducer，不能直接喂连续音频流——
/// 需要单独有边界的完整语句。分段交给 [sherpa.VoiceActivityDetector]
/// （silero-vad）完成：输入采样按 VAD 帧大小切成定长窗口（零拷贝，见
/// [_vadLeftover]），VAD 检测到静音边界就产出一段语音，每段独立解码。
///
/// ⚠️ 真机发现（2026-08-05）：完整视频批量转写一直只有**第一个**检测到的
/// 语音段能产出字幕，后面每一段都被悄悄丢掉——即便 VAD 其实正确检测并解码了
/// 全部语音段（追踪确认：每一段解码出的文本都正确、非空）。真正原因是
/// [_cues] 是一个非 `sync` 的广播 [StreamController]：`stop()` 里连续给好几个
/// 语音段解码、背靠背调用 `_cues.add(...)`，中间没有 `await`，而普通广播
/// controller 会把每次事件推迟到之后的微任务——等 `transcribeWavFile` 的
/// `await stop()` 返回、读取它累积的列表时，只有第一次投递真正跑完了。构造时
/// 传 `sync: true` 让每次事件在 `add()` 内同步投递，这里是安全的，因为唯一的
/// 监听者就是一个普通的 `List.add`。（之前一个现已推翻的猜测，怀疑是固定时长
/// 窗口切分让 transducer 的解码器犯糊涂——VAD 分段因此被采用，作为设计本身
/// 仍然是对的，但它从来不是这个症状的真正修复。）
class ZipformerSttEngine implements MovaSttEngine {
  /// Creates a Zipformer engine from already-downloaded model files.
  ///
  /// 从已下载好的模型文件创建 Zipformer 引擎。
  ///
  /// - [files]: resolved via `MovaSttModelProv.ensure(...)`, keyed by
  ///   filename (`'encoder.onnx'`/`'decoder.onnx'`/`'joiner.onnx'`/
  ///   `'tokens.txt'`) / 由 `MovaSttModelProv.ensure(...)` 解析得到，按文件名
  ///   （`'encoder.onnx'`/`'decoder.onnx'`/`'joiner.onnx'`/`'tokens.txt'`）索引
  /// - [vadModelPath]: absolute path to a silero-vad `.onnx` model (e.g. from
  ///   https://github.com/snakers4/silero-vad/blob/master/src/silero_vad/data/silero_vad.onnx)
  ///   / silero-vad `.onnx` 模型的绝对路径
  /// - [numThreads]: recognizer thread count / 识别器线程数
  /// - [maxSpeechDurationSeconds]: VAD caps a single speech segment at this
  ///   length even without a silence gap, so one long uninterrupted
  ///   utterance still gets split into decodable pieces / VAD
  ///   即使没有静音间隔，也会把单个语音段截断到这个时长，避免一句超长的
  ///   连续说话完全不分段
  /// - [speedFactor]: set this when the audio handed to [feed]/[start] has
  ///   itself been sped up before extraction (e.g. via ffmpeg's `atempo`,
  ///   to cut decode wall-clock roughly in proportion) — `2.0` for audio
  ///   played back at 2x. Cue timestamps are multiplied by this to report
  ///   positions in the *original* (real-speed) timeline; leave at the
  ///   default `1.0` for unmodified audio / 设置这个值的前提是喂给
  ///   [feed]/[start] 的音频本身在抽取前就被加速过了（比如用 ffmpeg 的
  ///   `atempo`，加速比例大致就是解码耗时的削减比例）——播放速度 2x 的音频
  ///   传 `2.0`。字幕时间戳会乘上这个值，换算回*原始*（正常速度）时间轴；
  ///   未加速的音频保持默认值 `1.0`
  ZipformerSttEngine({
    required this.files,
    required this.vadModelPath,
    this.numThreads = 1,
    this.maxSpeechDurationSeconds = 8.0,
    this.speedFactor = 1.0,
    this.provider = 'cpu',
  });

  /// Resolved local paths for the model's four files.
  ///
  /// 模型四个文件的已解析本地路径。
  final MovaSttModelFiles files;

  /// Absolute path to the silero-vad `.onnx` model.
  ///
  /// silero-vad `.onnx` 模型的绝对路径。
  final String vadModelPath;

  /// Recognizer thread count.
  ///
  /// 识别器线程数。
  final int numThreads;

  /// Upper bound on a single VAD-emitted speech segment's length.
  ///
  /// VAD 产出的单个语音段的时长上限。
  final double maxSpeechDurationSeconds;

  /// Playback-speed multiplier of the audio fed to this engine, relative to
  /// real time — see the constructor doc.
  ///
  /// 喂给本引擎的音频相对真实时间的播放倍速——见构造函数文档。
  final double speedFactor;

  /// ONNX Runtime execution provider passed straight through to
  /// `OfflineModelConfig.provider` — `'cpu'` (default), or a hardware
  /// backend such as `'nnapi'` (Android) / `'coreml'` (iOS) for benchmarking.
  /// Falls back to CPU silently if the backend isn't available on the
  /// device, per sherpa-onnx's own behavior.
  ///
  /// 原样透传给 `OfflineModelConfig.provider` 的 ONNX Runtime 执行后端——
  /// 默认 `'cpu'`，或用于测速对比的硬件后端如 `'nnapi'`（Android）/
  /// `'coreml'`（iOS）。设备不支持对应后端时会按 sherpa-onnx 自身行为静默
  /// 回退到 CPU。
  final String provider;

  /// How many seconds of speech the VAD's internal result queue can hold
  /// before [feed] must drain it — generous enough that a burst of detected
  /// segments between drains never overflows it.
  ///
  /// VAD 内部结果队列在 [feed] 必须清空它之前能容纳的语音秒数——留有余量，
  /// 使两次清空之间一连串检测到的语音段不会把它撑爆。
  static const double _bufferSizeInSeconds = 30;

  sherpa.OfflineRecognizer? _recognizer;
  sherpa.VoiceActivityDetector? _vad;
  final _cues = StreamController<MovaSttCue>.broadcast(sync: true);

  /// Samples carried over from the previous [feed] call because they didn't
  /// fill a whole VAD frame ([sherpa.SileroVadModelConfig.windowSize]) —
  /// real-device profiling on an 11-hour file found the original design
  /// (push every sample through a `sherpa.CircularBuffer`, then `get()` one
  /// frame at a time) too slow: `push` and `get` each round-trip through FFI
  /// and copy the whole frame, on top of `CircularBuffer` doing its own
  /// internal copy — millions of times over for an hours-long file. This
  /// leftover buffer plus [Float32List.sublistView] in [feed] let most
  /// frames go straight from the caller's array to `acceptWaveform` with
  /// zero Dart-side copies; only a frame that spans the boundary between two
  /// `feed` calls needs an actual copy.
  ///
  /// 上一次 [feed] 调用里凑不满一整个 VAD 帧
  /// （[sherpa.SileroVadModelConfig.windowSize]）而结转下来的采样——真机在
  /// 11 小时文件上实测发现原设计（把每个采样点推进 `sherpa.CircularBuffer`，
  /// 再一帧一帧 `get()` 出来）太慢：`push`/`get` 各自要过一次 FFI 往返并
  /// 拷贝整帧数据，`CircularBuffer` 自己内部还要再拷一次——对一个几小时的
  /// 文件这是几百万次的重复开销。这个结转缓冲配合 [feed] 里的
  /// [Float32List.sublistView]，让大多数帧能零拷贝地从调用方数组直接送进
  /// `acceptWaveform`；只有跨两次 [feed] 调用边界的帧才需要真正拷贝一次。
  Float32List _vadLeftover = Float32List(0);

  /// The playback position [feed]'s first sample corresponds to — every
  /// emitted cue's timestamp is this plus the VAD segment's own offset.
  ///
  /// [feed] 第一个采样对应的播放位置——每条产出字幕的时间戳都是这个值加上
  /// VAD 语音段自身的偏移。
  Duration _basePosition = Duration.zero;

  int _sampleRateHz = 16000;
  bool _running = false;

  @override
  List<String> get languages => const ['zh', 'en'];

  @override
  Stream<MovaSttCue> get cues => _cues.stream;

  @override
  Future<void> start(Duration atPosition) async {
    // Only the (expensive) recognizer/VAD construction is skipped on repeat
    // calls — the session state below must reset every time, or a second
    // start()/feed()/stop() cycle on the same instance (e.g. a second
    // `transcribeWavFile` call) would resume mid-buffer instead of starting
    // clean.
    //
    // 只有（开销较大的）recognizer/VAD 构造在重复调用时跳过——下面的会话
    // 状态每次都必须重置，否则同一个实例上第二轮 start()/feed()/stop()
    // （比如第二次调用 `transcribeWavFile`）会从上次的缓冲状态里接着走，
    // 而不是干净地重新开始。
    sherpa.initBindings();
    _recognizer ??= _buildRecognizer();
    if (_vad == null) {
      // VAD measures silence/speech/max-duration entirely in the timeline of
      // the audio it's actually fed — it has no notion of `speedFactor`. If
      // that audio has been sped up, every one of these durations needs
      // dividing by `speedFactor` first, or VAD ends up using real-world-
      // calibrated thresholds against compressed audio: a genuine 0.5s pause
      // shrinks to 0.25s at 2x, under the (unscaled) 0.5s minSilenceDuration
      // default, so VAD never sees it as silence at all and merges what
      // should have been two separate sentences into one long segment.
      //
      // VAD 衡量静音/语音/最长时长，完全是在它实际收到的这段音频自己的
      // 时间轴上量的——它不知道外面有个 `speedFactor`。如果这段音频被加速
      // 过，这几个时长都要先除以 `speedFactor`，否则就是拿按真实速度校准的
      // 门槛去衡量压缩过的音频：真实世界里 0.5 秒的自然停顿，2 倍速下缩水成
      // 0.25 秒，比（没缩放的）0.5 秒 `minSilenceDuration` 默认值还短，VAD
      // 压根不会当成静音，于是把本该是两句话的内容合并成一个长语音段。
      final vadConfig = sherpa.VadModelConfig(
        sileroVad: sherpa.SileroVadModelConfig(
          model: vadModelPath,
          minSilenceDuration: 0.5 / speedFactor,
          minSpeechDuration: 0.25 / speedFactor,
          maxSpeechDuration: maxSpeechDurationSeconds / speedFactor,
        ),
        sampleRate: _sampleRateHz,
        debug: false,
      );
      _vad = sherpa.VoiceActivityDetector(
        config: vadConfig,
        bufferSizeInSeconds: _bufferSizeInSeconds,
      );
    } else {
      _vad!.reset();
    }
    _vadLeftover = Float32List(0);
    _basePosition = atPosition;
    _running = true;
  }

  /// Builds a fresh native `OfflineRecognizer` from [files].
  ///
  /// 从 [files] 构建一个全新的原生 `OfflineRecognizer`。
  sherpa.OfflineRecognizer _buildRecognizer() =>
      buildZipformerRecognizer(files: files, numThreads: numThreads, provider: provider);

  @override
  void feed(Float32List samples, int sampleRateHz) {
    final vad = _vad;
    if (!_running || _recognizer == null || vad == null) return;
    _sampleRateHz = sampleRateHz;
    final windowSize = vad.config.sileroVad.windowSize;

    // Combine the previous leftover with the new samples only if there IS a
    // leftover — the common case (leftover empty) skips the copy entirely
    // and windows are sliced directly out of `samples` via `sublistView`.
    //
    // 只有存在结转数据时才把它和新采样合并——常见情况（结转为空）完全跳过
    // 这次拷贝，窗口直接用 `sublistView` 从 `samples` 里切出来。
    Float32List pending;
    if (_vadLeftover.isEmpty) {
      pending = samples;
    } else {
      pending = Float32List(_vadLeftover.length + samples.length)
        ..setRange(0, _vadLeftover.length, _vadLeftover)
        ..setRange(_vadLeftover.length, _vadLeftover.length + samples.length, samples);
    }

    var offset = 0;
    while (pending.length - offset >= windowSize) {
      vad.acceptWaveform(Float32List.sublistView(pending, offset, offset + windowSize));
      _drainSegments();
      offset += windowSize;
    }
    _vadLeftover = offset == pending.length
        ? Float32List(0)
        : Float32List.sublistView(pending, offset);
  }

  /// Decodes every VAD-detected speech segment currently queued, emitting a
  /// cue for each one with non-empty recognized text.
  ///
  /// 解码当前排队的每一段 VAD 检测到的语音，为每一段有非空识别文本的语音
  /// 产出一条字幕。
  void _drainSegments() {
    final vad = _vad;
    final recognizer = _recognizer;
    if (vad == null || recognizer == null) return;
    while (!vad.isEmpty()) {
      final segment = vad.front();
      _decodeSegment(recognizer, segment);
      vad.pop();
    }
  }

  /// Decodes one VAD [segment] as a complete utterance and emits a cue if
  /// the recognized text is non-empty.
  ///
  /// [segment.start] is the segment's offset in samples within this VAD
  /// instance's own continuous stream (reset in [start]), so the cue's
  /// timestamp is [_basePosition] plus that offset — not derived from how
  /// much audio [feed] has been given overall, since VAD-internal buffering
  /// means the two can drift apart by design.
  ///
  /// 把一段 VAD [segment] 当作一句完整的话解码，识别文本非空时产出一条
  /// 字幕。
  ///
  /// [segment.start] 是该分段在本 VAD 实例自身连续采样流（在 [start] 里
  /// reset）中的采样偏移，所以字幕时间戳是 [_basePosition] 加上这个偏移——
  /// 不是按 [feed] 总共喂了多少音频推算，因为 VAD 内部缓冲本来就会让二者
  /// 出现偏差。
  ///
  /// - [recognizer]: the recognizer to decode with / 用于解码的识别器
  /// - [segment]: the detected speech segment / 检测到的语音段
  void _decodeSegment(sherpa.OfflineRecognizer recognizer, sherpa.SpeechSegment segment) {
    if (segment.samples.isEmpty) return;
    final stream = recognizer.createStream();
    stream.acceptWaveform(samples: segment.samples, sampleRate: _sampleRateHz);
    recognizer.decode(stream);
    final text = recognizer.getResult(stream).text.trim();
    stream.free();
    if (text.isEmpty || _cues.isClosed) return;
    // segment.start/samples.length are offsets into the (possibly sped-up)
    // audio actually fed in; scaling by speedFactor maps them back onto the
    // original, real-speed timeline before adding the (already real-time)
    // basePosition.
    //
    // segment.start/samples.length 是相对于实际喂入的（可能加速过的）音频的
    // 偏移；乘上 speedFactor 换算回原始、正常速度的时间轴，再加上
    // （本就是真实时间的）basePosition。
    final start = _basePosition +
        Duration(
          microseconds: (segment.start /
                  _sampleRateHz *
                  Duration.microsecondsPerSecond *
                  speedFactor)
              .round(),
        );
    final end = start +
        Duration(
          microseconds: (segment.samples.length /
                  _sampleRateHz *
                  Duration.microsecondsPerSecond *
                  speedFactor)
              .round(),
        );
    _cues.add(MovaSttCue(text: text, start: start, end: end));
  }

  @override
  Future<void> stop() async {
    if (!_running) return;
    _running = false;
    final vad = _vad;
    if (vad == null) return;
    // Forces out whatever speech VAD was still accumulating (below
    // `minSpeechDuration`/waiting for a silence gap that never came because
    // the audio simply ended).
    //
    // 强制把 VAD 还在累积的语音吐出来（不足 `minSpeechDuration`，或者在
    // 等一个永远不会来的静音间隔，因为音频到这里就结束了）。
    vad.flush();
    _drainSegments();
  }

  @override
  Future<void> dispose() async {
    _recognizer?.free();
    _recognizer = null;
    _vad?.free();
    _vad = null;
    await _cues.close();
  }

  /// Batch-transcribes an entire WAV file in one call, for VOD's one-shot
  /// pre-transcription path (see
  /// `doc/notes/2026-08-04-stt-engine-decision.md`'s "批量预转写" section) —
  /// as opposed to [feed]'s live, playback-paced loop.
  ///
  /// Reuses this engine's own [start]/[feed]/[stop] loop internally, so a
  /// single `ZipformerSttEngine` instance must not be used for live [feed]
  /// calls concurrently with a [transcribeWavFile] call.
  ///
  /// - [wavPath]: absolute path to a mono WAV file, as produced by
  ///   `MovaAudioPuller.extractWav` / 单声道 WAV 文件的绝对路径，由
  ///   `MovaAudioPuller.extractWav` 产出
  ///
  /// Returns every cue recognized, in chronological order.
  ///
  /// 批量转写一整个 WAV 文件，用于点播的一次性预转写路径（见
  /// `doc/notes/2026-08-04-stt-engine-decision.md` 的"批量预转写"一节）——
  /// 相对于 [feed] 那套按播放节奏走的实时循环。
  ///
  /// 内部复用了本引擎自己的 [start]/[feed]/[stop] 循环，因此同一个
  /// `ZipformerSttEngine` 实例不能一边被实时 [feed] 调用、一边又跑
  /// [transcribeWavFile]。
  ///
  /// 返回按时间顺序排列的全部识别字幕。
  Future<List<MovaSttCue>> transcribeWavFile(String wavPath) async {
    final cues = <MovaSttCue>[];
    final sub = _cues.stream.listen(cues.add);
    try {
      // `start()` calls `initBindings()`, which `readWave` also requires —
      // must run first, not just because we need the model config ready.
      //
      // `start()` 会调用 `initBindings()`，`readWave` 同样需要它——必须先跑,
      // 不只是因为要先备好模型配置。
      await start(Duration.zero);
      final wave = sherpa.readWave(wavPath);
      feed(wave.samples, wave.sampleRate);
      await stop();
    } finally {
      await sub.cancel();
    }
    return cues;
  }
}

/// Builds a fresh native `OfflineRecognizer` for the bilingual Zipformer
/// model from plain file paths — a top-level function (not a
/// [ZipformerSttEngine] method) specifically so it can run standalone inside
/// a worker [Isolate] for [transcribeWavFileParallel], since an instance
/// method implicitly captures `this` (including non-sendable FFI state),
/// which can't cross an isolate boundary.
///
/// - [files]: resolved model file paths, keyed by filename / 已解析的模型
///   文件路径，按文件名索引
/// - [numThreads]: recognizer thread count / 识别器线程数
///
/// 从纯文件路径构建一个全新的双语 Zipformer 原生 `OfflineRecognizer`——
/// 单独做成顶层函数（不是 [ZipformerSttEngine] 的方法），专门是为了能在
/// [transcribeWavFileParallel] 的工作 [Isolate] 里独立运行，因为实例方法会
/// 隐式捕获 `this`（包括不能跨 isolate 的 FFI 状态）。
sherpa.OfflineRecognizer buildZipformerRecognizer({
  required MovaSttModelFiles files,
  int numThreads = 1,
  String provider = 'cpu',
}) {
  final encoder = files['encoder.onnx'];
  final decoder = files['decoder.onnx'];
  final joiner = files['joiner.onnx'];
  final tokens = files['tokens.txt'];
  if (encoder == null || decoder == null || joiner == null || tokens == null) {
    throw StateError('buildZipformerRecognizer: missing one or more model files in $files');
  }
  final config = sherpa.OfflineRecognizerConfig(
    model: sherpa.OfflineModelConfig(
      transducer: sherpa.OfflineTransducerModelConfig(
        encoder: encoder,
        decoder: decoder,
        joiner: joiner,
      ),
      tokens: tokens,
      numThreads: numThreads,
      debug: false,
      modelType: 'transducer',
      provider: provider,
    ),
  );
  return sherpa.OfflineRecognizer(config);
}
