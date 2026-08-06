import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;
import 'package:mova/mova.dart';
import 'package:mova_stt/mova_stt.dart';

/// Fixed directory the model files (and a test wav) are seeded into for this
/// spike — bypasses [MovaSttModelLoader] entirely since
/// `zipformerZhEnModelSpec`'s default `baseUrl` is a placeholder with no real
/// host behind it yet (see `mova_stt/lib/src/model_specs.dart`).
/// Windows gets a local path (fast iteration, no adb round-trip); Android
/// gets the app-specific external files dir seeded via `adb push` (note:
/// `flutter install`'s uninstall-before-install step wipes this directory,
/// so it must be re-pushed after every reinstall).
///
/// 本 spike 用固定目录 seed 模型文件（和一段测试 wav），完全绕开
/// [MovaSttModelLoader]——因为 `zipformerZhEnModelSpec` 的默认 `baseUrl`
/// 还只是个占位地址，没有真实主机。Windows 用本机路径（迭代快，不用走 adb）；
/// Android 用 `adb push` 到应用专属外部文件目录（注意：`flutter install` 的
/// 卸载步骤会清空这个目录，每次重装后都要重新推送）。
final _seedDir = Platform.isWindows
    ? r'C:\Users\jelon\AppData\Local\mova_stt_spike'
    : '/storage/emulated/0/Android/data/com.icodejoo.mova.mova_example/files/stt_spike';

/// The sherpa-onnx official test wav (`test_wavs/0.wav` from the
/// `zipformer-zh-en-2023-11-22` release asset) pushed alongside the model
/// files — known-good input to isolate "does the engine work" from "does
/// mova's audio pipeline feed it real samples" (the latter has no
/// implementation yet, see chat).
///
/// sherpa-onnx 官方测试 wav（`zipformer-zh-en-2023-11-22` release 资产里的
/// `test_wavs/0.wav`），随模型文件一起推送——用已知良好的输入，把"引擎本身
/// 能不能跑"和"mova 的音频管线能不能喂给它真实采样"（后者目前还没有
/// 实现，见对话记录）这两件事分开验证。
final _testWavPath = '$_seedDir${Platform.pathSeparator}test.wav';

/// Hardcoded path to whichever diagnostic wav is under investigation right
/// now — auto-tested on open alongside the other fixed-path checks, no
/// file-picker interaction needed since the path is already known.
///
/// 当前正在排查的诊断 wav 的硬编码路径——打开即随其余固定路径检查一起自动
/// 测试，不需要文件选择器交互，因为路径已经是已知的。
const _diagWavPath =
    r'C:\Users\jelon\AppData\Local\mova_stt_spike\real_video.wav';

/// [_diagWavPath] is extracted at 1x — real-device A/B testing (2026-08-05)
/// found `atempo`-sped-up audio measurably hurts recognition accuracy (see
/// [recommendedSttParallelism]'s doc comment), so the speedup path is no
/// longer used; parallel decode is the only speed lever now.
///
/// [_diagWavPath] 按 1 倍速抽取——真机 A/B 对比测试（2026-08-05）发现
/// `atempo` 加速过的音频会实打实拖累识别准确率（详见
/// [recommendedSttParallelism] 的文档注释），所以不再走加速这条路，现在只用
/// 并行解码这一个提速手段。
const _diagSpeedFactor = 1.0;

/// Path to the silero-vad model [ZipformerSttEngine] now requires for
/// speech-segment detection (see its class doc for why fixed-window
/// chunking was replaced) — from
/// https://github.com/snakers4/silero-vad/blob/master/src/silero_vad/data/silero_vad.onnx,
/// seeded alongside the Zipformer model files.
///
/// [ZipformerSttEngine] 现在做语音段检测所需的 silero-vad 模型路径（为什么
/// 固定窗口切分被替换掉，见该类的文档注释）——来自
/// https://github.com/snakers4/silero-vad/blob/master/src/silero_vad/data/silero_vad.onnx，
/// 和 Zipformer 模型文件一起 seed 在同一目录。
final _vadModelPath = '$_seedDir${Platform.pathSeparator}silero_vad.onnx';

/// Spike page for verifying [ZipformerSttEngine] in isolation: feeds it a
/// known-good WAV sample directly via [ZipformerSttEngine.transcribeWavFile],
/// with no video playback or live audio tap involved. Confirms whether the
/// sherpa_onnx native binding loads and produces cues on a real device — the
/// engine's own doc comment flags it as "⚠️ never run against a real device".
///
/// 用来独立验证 [ZipformerSttEngine] 的 spike 页面：直接用
/// [ZipformerSttEngine.transcribeWavFile] 喂一段已知良好的 WAV 样本，不涉及
/// 视频播放或实时音频抓取。用于确认 sherpa_onnx 原生绑定能否在真机上加载并
/// 产出字幕——该引擎自己的文档注释标注"⚠️ 从未在真实设备上跑过"。
class SttEngineSpikePage extends StatefulWidget {
  /// Creates the STT engine spike page.
  ///
  /// 创建 STT 引擎 spike 页面。
  const SttEngineSpikePage({super.key});

  @override
  State<SttEngineSpikePage> createState() => _SttEngineSpikePageState();
}

/// State for [SttEngineSpikePage]; owns the engine under test and the last
/// run's outcome for display.
///
/// [SttEngineSpikePage] 的状态；持有被测引擎与最近一次运行结果的展示状态。
class _SttEngineSpikePageState extends State<SttEngineSpikePage> {
  /// The engine under test, built from the model files seeded at [_seedDir].
  /// Rebuilt per-provider by [_run] so the CPU/NNAPI benchmark buttons each
  /// get a freshly-constructed native recognizer for that backend.
  ///
  /// 被测引擎，从 [_seedDir] 下已 seed 好的模型文件构建。由 [_run] 按后端
  /// 重建，使 CPU/NNAPI 测速按钮各自拿到该后端全新构造的原生识别器。
  late ZipformerSttEngine _engine;

  /// Whether a recognition run is currently in flight.
  ///
  /// 当前是否有一次识别正在进行。
  bool _running = false;

  /// Recognized cues from the most recent run, or empty before any run /
  /// after one that produced nothing.
  ///
  /// 最近一次运行识别出的字幕；未运行过或识别为空时为空列表。
  List<MovaSttCue> _cues = const [];

  /// The most recent error, or null if the last run (if any) succeeded.
  ///
  /// 最近一次错误；若上次运行（如果有）成功则为 null。
  Object? _error;

  /// Progress text for the real-video pick-and-transcribe flow (extraction
  /// vs. decoding stage), shown so a multi-minute run isn't silently stuck.
  ///
  /// "选文件抽音频转文字"流程的进度文案（抽取阶段/识别阶段），避免几分钟的
  /// 运行看起来像卡死。
  String? _videoStatus;

  String _seeded(String name) => '$_seedDir${Platform.pathSeparator}$name';

  /// Builds a fresh [ZipformerSttEngine] against the given ONNX Runtime
  /// execution provider (`'cpu'`, `'nnapi'`, `'coreml'`, ...) — used to A/B
  /// hardware-acceleration backends against plain CPU inference.
  ///
  /// 用指定 ONNX Runtime 执行后端（`'cpu'`/`'nnapi'`/`'coreml'` 等）构建一个
  /// 全新的 [ZipformerSttEngine]——用来对比硬件加速后端与纯 CPU 推理。
  ZipformerSttEngine _buildEngine(String provider) => ZipformerSttEngine(
    files: MovaSttModelFiles({
      'encoder.onnx': _seeded('encoder.onnx'),
      'decoder.onnx': _seeded('decoder.onnx'),
      'joiner.onnx': _seeded('joiner.onnx'),
      'tokens.txt': _seeded('tokens.txt'),
    }),
    vadModelPath: _vadModelPath,
    provider: provider,
  );

  @override
  void initState() {
    super.initState();
    _engine = _buildEngine('cpu');
    // Auto-run on open — this spike has no GUI-automation harness driving
    // it, so a manual button tap would require a human at the device for
    // every iteration. Firing automatically means results are observable
    // purely from `flutter run`'s console output (debugPrint below).
    //
    // 打开即自动跑——本 spike 没有 GUI 自动化工具驱动，手动点按钮意味着每次
    // 迭代都要有人守在设备旁。自动触发使得结果单靠 `flutter run` 的控制台
    // 输出（下面的 debugPrint）就能观察到。
    //
    // Runs the baseline check, then the current diagnostic path — no
    // file-picker interaction needed, since [_diagWavPath] is a fixed,
    // already-known on-disk path.
    //
    // 先跑基线检查，再跑当前诊断路径——不需要文件选择器交互，因为
    // [_diagWavPath] 是固定、已知的磁盘路径。
    _run('cpu').then((_) => _transcribePath(_diagWavPath));
  }

  /// Runs the seeded test wav through [ZipformerSttEngine.feed] on the given
  /// [provider] backend and records the outcome for display — rebuilds
  /// [_engine] against that provider first, so consecutive CPU/NNAPI runs
  /// each get an independently-constructed native recognizer.
  ///
  /// 用给定 [provider] 后端对已 seed 的测试 wav 跑一次识别，并记录结果用于
  /// 展示——先按该 provider 重建 [_engine]，使连续的 CPU/NNAPI 测速各自拿到
  /// 独立构造的原生识别器。
  Future<void> _run(String provider) async {
    setState(() {
      _running = true;
      _error = null;
      _cues = const [];
    });
    _engine.dispose();
    _engine = _buildEngine(provider);
    try {
      // Dart-level existence/size check first — isolates "does Dart/the OS
      // see these files at all" from "does the native sherpa-onnx library's
      // own file check pass", since the two have disagreed on Android before
      // (native reported one file "does not exist" despite `adb shell ls`
      // showing it present with the right size).
      //
      // 先做 Dart 层的存在性/大小检查——把"Dart/操作系统层面能不能看到这些
      // 文件"和"sherpa-onnx 原生库自己的文件检查能不能通过"分开看，因为
      // Android 上这两者出现过不一致（原生库报告某个文件"不存在"，但
      // `adb shell ls` 明明显示它存在且大小正确）。
      final report = StringBuffer();
      for (final name in ['encoder.onnx', 'decoder.onnx', 'joiner.onnx', 'tokens.txt']) {
        final path = _engine.files[name]!;
        final file = File(path);
        final exists = file.existsSync();
        report.writeln('$name: exists=$exists'
            '${exists ? ' size=${file.lengthSync()}' : ''} path=$path');
      }
      debugPrint('=== STT SPIKE: Dart-level file check ===\n$report');

      // Tile the 3.4s test clip up to ~60s so the RTF measurement below
      // covers several of the engine's 6s decode windows and amortizes
      // one-time model-load cost — a single 3.4s clip mostly measures
      // startup overhead, not steady-state decode speed.
      //
      // 把 3.4 秒的测试片段拼接到约 60 秒，使下面的 RTF 测量覆盖引擎多个
      // 6 秒解码窗口、摊掉一次性模型加载开销——单独一段 3.4 秒主要测的是
      // 启动开销，不是稳态解码速度。
      sherpa.initBindings();
      final wave = sherpa.readWave(_testWavPath);
      final tiles = (60 * wave.sampleRate) ~/ wave.samples.length + 1;
      final tiled = Float32List(wave.samples.length * tiles);
      for (var i = 0; i < tiles; i++) {
        tiled.setRange(i * wave.samples.length, (i + 1) * wave.samples.length, wave.samples);
      }
      final audioSeconds = tiled.length / wave.sampleRate;
      debugPrint('=== STT SPIKE: measuring RTF over ${audioSeconds.toStringAsFixed(1)}s '
          'of tiled audio ($tiles× the 3.4s clip) ===');

      // Subscribe before start()/feed()/stop() — `cues` is a broadcast
      // stream with no replay, so a listener attached afterwards would miss
      // everything emitted synchronously inside `_flush()`.
      //
      // 在 start()/feed()/stop() 之前订阅——`cues` 是无重放的广播流，
      // 事后才订阅会错过 `_flush()` 内部同步发出的一切。
      final cues = <MovaSttCue>[];
      final sub = _engine.cues.listen(cues.add);
      final sw = Stopwatch()..start();
      await _engine.start(Duration.zero);
      _engine.feed(tiled, wave.sampleRate);
      await _engine.stop();
      sw.stop();
      await sub.cancel();
      final rtf = sw.elapsedMilliseconds / (audioSeconds * 1000);
      final twoHoursMinutes = (rtf * 120).round();
      debugPrint('=== STT SPIKE [provider=$provider]: ${sw.elapsedMilliseconds}ms wall clock '
          'for ${audioSeconds.toStringAsFixed(1)}s audio → RTF=${rtf.toStringAsFixed(3)} '
          '→ 2h video ≈ ${twoHoursMinutes}min single-threaded ===');
      for (final cue in cues) {
        debugPrint('  [${cue.start} -> ${cue.end}] ${cue.text}');
      }
      setState(() => _cues = cues);
    } catch (e, st) {
      debugPrint('=== STT SPIKE: FAILED: $e ===\n$st');
      setState(() => _error = e);
    } finally {
      setState(() => _running = false);
    }
  }

  /// Lets the user pick a real video file from disk (not bundled as a
  /// Flutter asset — read from its absolute filesystem path at runtime, to
  /// simulate a real deployment where the source video is arbitrary user
  /// content), extracts its audio via [MpvAudioExtractor] (the previously
  /// "⚠️ unverified spike" second-hidden-player WAV extractor), then feeds
  /// the result into [ZipformerSttEngine], timing both stages.
  ///
  /// 让用户从磁盘选一个真实视频文件（不打包成 Flutter 资源——运行时按绝对
  /// 路径读取，模拟真实部署中源视频是任意用户内容的场景），用
  /// [MpvAudioExtractor]（此前"⚠️ 未验证 spike"的第二隐藏播放器 WAV 抽取器）
  /// 抽取音频，再喂给 [ZipformerSttEngine]，两个阶段都计时。
  Future<void> _pickAndTranscribeVideo() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['mp4', 'mkv', 'mov', 'wav'],
      dialogTitle: '选择一个视频文件（或已经提取好的 wav）',
    );
    final path = result?.files.single.path;
    if (path == null) return;
    await _transcribePath(path);
  }

  /// Same pipeline as [_pickAndTranscribeVideo], but for a path already
  /// known ahead of time — used both by the picker flow and by the
  /// no-picker-needed auto-run diagnostics (see [_diagWavPath]), since a
  /// fixed on-disk path never needs a human to pick it via a dialog.
  ///
  /// 和 [_pickAndTranscribeVideo] 一样的流程，但用于事先已知的路径——同时
  /// 供文件选择器流程和无需选择器的自动诊断跑（见 [_diagWavPath]）使用，
  /// 因为固定的磁盘路径从不需要人去弹窗选。
  Future<void> _transcribePath(String path) async {
    // A `.wav` is treated as already-extracted audio and fed straight to the
    // engine — lets this flow be pointed at output from an external
    // extractor (e.g. `ffmpeg`) to isolate decode-speed measurement from
    // `MpvAudioExtractor`'s own extraction step.
    //
    // `.wav`视为已经抽取好的音频，直接喂给引擎——这样这条流程也能指向外部
    // 抽取器（如 `ffmpeg`）的产物，把解码速度测量和 `MpvAudioExtractor`
    // 自己的抽取步骤分开看。
    final isPreExtracted = path.toLowerCase().endsWith('.wav');

    setState(() {
      _running = true;
      _error = null;
      _cues = const [];
      _videoStatus = isPreExtracted ? '已是 wav，跳过抽取，识别中…' : '抽取音频中…（$path）';
    });
    final extractor = MpvAudioExtractor();
    try {
      String wavPath;
      int extractMs;
      if (isPreExtracted) {
        wavPath = path;
        extractMs = 0;
        debugPrint('=== STT SPIKE (real video): using pre-extracted wav → $wavPath ===');
      } else {
        final extractSw = Stopwatch()..start();
        final extracted = await extractor.extractWav(path);
        extractSw.stop();
        if (extracted == null) {
          throw StateError('MpvAudioExtractor.extractWav returned null — extraction failed');
        }
        wavPath = extracted;
        extractMs = extractSw.elapsedMilliseconds;
        debugPrint('=== STT SPIKE (real video): extraction took '
            '${extractSw.elapsed} → $wavPath ===');
      }

      sherpa.initBindings();
      final wave = sherpa.readWave(wavPath);
      final audioSeconds = wave.samples.length / wave.sampleRate;
      final extractRtf = extractMs / (audioSeconds * 1000);
      if (!isPreExtracted) {
        debugPrint('=== STT SPIKE (real video): extracted ${audioSeconds.toStringAsFixed(1)}s '
            'of audio, extraction RTF=${extractRtf.toStringAsFixed(3)} '
            '(${extractRtf < 1 ? 'faster' : 'slower'} than real-time — resolves the '
            '"does mpv decode-through throttle to 1x?" question MpvAudioExtractor\'s '
            'doc comment flagged as unverified) ===');
      }

      setState(() => _videoStatus = isPreExtracted
          ? '使用预抽取 wav（${audioSeconds.toStringAsFixed(0)}s），识别中…'
          : '音频已抽取（${audioSeconds.toStringAsFixed(0)}s，用时 ${extractMs}ms），识别中…');

      // Decode via the parallel path, using `recommendedSttParallelism()`'s
      // balance point rather than a hand-picked number — this is exactly
      // what a real caller should do too.
      //
      // 走并行路径解码，用 `recommendedSttParallelism()` 给的平衡点而不是
      // 手选的数字——真实调用方也该这么做。
      final decodeSw = Stopwatch()..start();
      final rawCues = await transcribeWavFileParallel(
        files: _engine.files,
        vadModelPath: _vadModelPath,
        wavPath: wavPath,
        speedFactor: _diagSpeedFactor,
        parallelism: recommendedSttParallelism(),
      );
      decodeSw.stop();
      final cues = insertPauseBasedPunctuation(rawCues);

      final decodeRtf = decodeSw.elapsedMilliseconds / (audioSeconds * 1000);
      final totalRtf = extractRtf + decodeRtf;
      final videoHours = audioSeconds / 3600;
      final totalMinutesForThisVideo = (totalRtf * audioSeconds / 60).round();
      debugPrint('=== STT SPIKE (real video): decode took ${decodeSw.elapsed} '
          '(RTF=${decodeRtf.toStringAsFixed(3)}); combined extract+decode RTF='
          '${totalRtf.toStringAsFixed(3)} → this '
          '${videoHours.toStringAsFixed(2)}h video end-to-end ≈ '
          '${totalMinutesForThisVideo}min single-threaded on this CPU ===');
      for (final cue in cues) {
        debugPrint('  [${cue.start} -> ${cue.end}] ${cue.text}');
      }

      // Write the full-video deliverable out as a real .srt file next to the
      // source wav, using mova's own `formatSrt` — this is the actual
      // shippable artifact a batch pre-transcription pipeline would produce,
      // not just console output.
      //
      // 用 mova 自带的 `formatSrt` 把结果写成真正的 .srt 文件，落在源
      // wav 旁边——这才是批量预转写流程该产出的可交付物，不只是控制台输出。
      final srtPath = '$wavPath.srt';
      await File(srtPath).writeAsString(formatSrt(cues));
      debugPrint('=== STT SPIKE (real video): wrote ${cues.length} cue(s) to $srtPath ===');

      setState(() {
        _cues = cues;
        _videoStatus = '完成：${audioSeconds.toStringAsFixed(0)}s 音频，抽取 '
            '${extractMs}ms + 识别 ${decodeSw.elapsed}，已写出 $srtPath';
      });
    } catch (e, st) {
      debugPrint('=== STT SPIKE (real video): FAILED: $e ===\n$st');
      setState(() {
        _error = e;
        _videoStatus = null;
      });
    } finally {
      await extractor.dispose();
      setState(() => _running = false);
    }
  }

  @override
  void dispose() {
    _engine.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('STT 引擎 spike（ZipformerSttEngine 隔离验证）')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('模型/wav 期望路径: $_seedDir', style: const TextStyle(fontSize: 12)),
              const SizedBox(height: 12),
              Row(
                children: [
                  ElevatedButton(
                    onPressed: _running ? null : () => _run('cpu'),
                    child: Text(_running ? '识别中…' : 'CPU 测速'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _running ? null : () => _run('nnapi'),
                    child: Text(_running ? '识别中…' : 'NNAPI 测速'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _running ? null : () => _run('xnnpack'),
                    child: Text(_running ? '识别中…' : 'XNNPACK 测速'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: _running ? null : _pickAndTranscribeVideo,
                child: const Text('选择真实视频文件 → 抽音频 → 转文字'),
              ),
              if (_videoStatus != null) ...[
                const SizedBox(height: 8),
                Text(_videoStatus!, key: const Key('sttSpikeVideoStatus')),
              ],
              const SizedBox(height: 16),
              if (_error != null)
                SelectableText(
                  '错误: $_error',
                  key: const Key('sttSpikeError'),
                  style: const TextStyle(color: Colors.redAccent),
                ),
              if (_error == null)
                Expanded(
                  child: ListView(
                    key: const Key('sttSpikeCues'),
                    children: [
                      if (_cues.isEmpty && !_running) const Text('（尚无结果）'),
                      for (final cue in _cues)
                        ListTile(
                          dense: true,
                          title: Text(cue.text),
                          subtitle: Text('${cue.start} → ${cue.end}'),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
