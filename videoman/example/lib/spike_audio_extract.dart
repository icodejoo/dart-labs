import 'dart:io';

import 'package:flutter/material.dart';
import 'package:videoman/videoman.dart';

/// A short, known-duration test clip for the spike: Big Buck Bunny's
/// standard 10-second trailer excerpt hosted by Google's sample bucket.
///
/// spike 用的短时长已知测试片段：Google 样本存储桶托管的《big buck bunny》
/// 标准 10 秒预告片段。
const _spikeSourceUri =
    'https://storage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4';

/// A verification harness for [MpvAudioExtractor] — the unverified spike
/// documented in `doc/notes/2026-08-04-stt-engine-decision.md`'s "批量预
/// 转写" section. Answers three open questions on real hardware instead of
/// guessing:
///
/// 1. Does `extractWav` return a non-null path at all (i.e. do
///    `ao=pcm`/`ao-pcm-file` actually work as *runtime* properties set via
///    `NativePlayer.setProperty` after `Player()` construction, rather than
///    needing to be mpv *startup* options)?
/// 2. Is the wall-clock extraction time close to the source's real duration
///    (real-time-paced, sinking the whole "batch pre-transcribe once, then
///    just read a file" premise) or much shorter (`untimed` actually worked)?
/// 3. Is the resulting WAV file non-trivially sized (a sign real audio was
///    decoded into it, not an empty/near-empty stub)?
///
/// Not a demo and not shipped behaviour — exists purely to read real
/// numbers off real hardware.
///
/// [MpvAudioExtractor] 的验证装置——对应
/// `doc/notes/2026-08-04-stt-engine-decision.md`"批量预转写"一节里标注的
/// 未验证 spike。在真机上回答三个悬而未决的问题，而不是靠猜：
///
/// 1. `extractWav` 到底能不能返回非空路径（即 `ao`/`ao-pcm-file` 能不能在
///    `Player()` 构造之后当**运行时属性**通过 `NativePlayer.setProperty`
///    设置生效，而不是必须作为 mpv **启动选项**）？
/// 2. 抽取耗时是接近源视频真实时长（按实时节拍走，会推翻整个"批量转写一次、
///    以后只读文件"的前提），还是明显更短（`untimed` 真的生效了）？
/// 3. 产出的 WAV 文件体积是否有实质内容（说明确实解出了真实音频，而非
///    空的/近乎空的占位文件）？
///
/// 不是演示，也不是要发布的行为——存在的唯一目的是从真机上读出真实数字。
class AudioExtractSpikePage extends StatefulWidget {
  /// Creates the audio-extraction spike page.
  ///
  /// 创建音频抽取 spike 页面。
  const AudioExtractSpikePage({super.key});

  @override
  State<AudioExtractSpikePage> createState() => _AudioExtractSpikePageState();
}

/// State for [AudioExtractSpikePage]; owns the extractor under test and the
/// human-readable result of the most recent run.
///
/// [AudioExtractSpikePage] 的状态；持有被测试的抽取器，以及最近一次运行的
/// 可读结果。
class _AudioExtractSpikePageState extends State<AudioExtractSpikePage> {
  final MpvAudioExtractor _extractor = MpvAudioExtractor();

  /// Human-readable result of the most recent [_runExtraction], shown on
  /// screen so a screenshot alone captures the full outcome.
  ///
  /// 最近一次 [_runExtraction] 的可读结果，显示在屏幕上，使单看截图就能拿到
  /// 完整结果。
  String _result = 'not run yet';

  bool _running = false;

  @override
  void initState() {
    super.initState();
    // Auto-run on open — avoids needing a real-device tap to kick off the
    // spike; the result also lands in this run's console via debugPrint
    // (below) since the on-screen text isn't readable from a headless
    // `flutter run` session.
    //
    // 打开就自动跑一次——不需要在真机上手动点按钮；结果也会通过下面的
    // debugPrint 落到本次运行的控制台，因为屏幕上的文字在无头 `flutter run`
    // 会话里看不到。
    WidgetsBinding.instance.addPostFrameCallback((_) => _runExtraction());
  }

  Future<void> _runExtraction() async {
    setState(() {
      _running = true;
      _result = 'extracting…';
    });
    debugPrint('=== AUDIO EXTRACT SPIKE: starting extractWav($_spikeSourceUri) ===');
    final stopwatch = Stopwatch()..start();
    String outcome;
    try {
      // Cut down from extractWav's internal 30-minute timeout — if this spike
      // hasn't finished in 60s, `player.stream.completed` almost certainly
      // never fired (the exact unverified risk flagged on
      // MpvAudioExtractor), and there's no reason to wait half an hour to
      // find that out.
      //
      // 从 extractWav 内部的 30 分钟超时砍下来——如果这个 spike 60 秒内没跑完，
      // 几乎可以肯定是 `player.stream.completed` 根本没触发（正是
      // MpvAudioExtractor 上标注的那个未验证风险），没理由等半小时才知道这点。
      final path = await _extractor.extractWav(_spikeSourceUri).timeout(
        const Duration(seconds: 60),
        onTimeout: () {
          debugPrint('=== AUDIO EXTRACT SPIKE: 60s watchdog fired, no completion signal ===');
          return null;
        },
      );
      stopwatch.stop();
      if (path == null) {
        outcome = 'FAILED: extractWav returned null after '
            '${stopwatch.elapsed.inMilliseconds}ms — either the file never '
            'appeared or an exception was swallowed (see extractWav\'s '
            'try/catch).';
      } else {
        final bytes = await _fileSizeBytes(path);
        outcome = 'path: $path\n'
            'elapsed: ${stopwatch.elapsed.inMilliseconds}ms '
            '(source is a ~10s clip — anywhere near 10000ms means `untimed` '
            'did NOT speed things up)\n'
            'size: $bytes bytes '
            '(a few hundred KB+ for 10s of 16-bit mono PCM is expected; '
            'near-zero means nothing real was decoded)';
      }
    } on Object catch (e, st) {
      stopwatch.stop();
      outcome = 'THREW after ${stopwatch.elapsed.inMilliseconds}ms: $e\n$st';
    }
    debugPrint('=== AUDIO EXTRACT SPIKE RESULT ===\n$outcome\n===================================');
    if (!mounted) return;
    setState(() {
      _running = false;
      _result = outcome;
    });
  }

  Future<int> _fileSizeBytes(String path) async {
    try {
      return await File(path).length();
    } on Object {
      return -1;
    }
  }

  @override
  void dispose() {
    _extractor.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('audio extract spike')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ElevatedButton(
              key: const Key('spikeRunExtraction'),
              onPressed: _running ? null : _runExtraction,
              child: Text(_running ? 'running…' : 'extract audio'),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: SingleChildScrollView(
                child: SelectableText(_result, key: const Key('spikeResult')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
