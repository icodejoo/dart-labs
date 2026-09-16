import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:mova/mova.dart';

/// In-process RSS probe comparing a normal video engine against an
/// `audioOnly: true` engine on the **same material**, so the delta isolates
/// the cost of the video pipeline itself.
///
/// It reads `ProcessInfo.currentRss` (`dart:io`) — the real resident set size
/// of this process, straight from the OS. No adb, no dumpsys, no estimate.
///
/// One mode per process, selected by `--dart-define`, because a single process
/// cannot give two clean baselines: once the video path has allocated decoder
/// and texture memory, the allocator does not necessarily return it to the OS,
/// so a sequential in-process A/B would flatter the second mode measured.
///
/// Run both, one after the other:
/// ```
/// flutter run -d windows --release -t lib/perf_probe_audio_only.dart --dart-define=MOVA_PERF_MODE=video
/// flutter run -d windows --release -t lib/perf_probe_audio_only.dart --dart-define=MOVA_PERF_MODE=audio
/// ```
///
/// 进程内 RSS 探针，在**同一条素材**上对比普通视频引擎与 `audioOnly: true` 引擎，
/// 使差值恰好隔离出视频管线自身的开销。
///
/// 它读取 `ProcessInfo.currentRss`（`dart:io`）——本进程真实的常驻内存，直接来自
/// 操作系统。不需要 adb、不需要 dumpsys，不是推算。
///
/// 每个进程只跑一种模式，由 `--dart-define` 选择：单进程给不出两个干净的基线——
/// 视频路径一旦分配过解码器与纹理内存，分配器未必会把它还给操作系统，顺序的
/// 进程内 A/B 会让后测的那一种模式占便宜。
///
/// **这是 Windows 桌面端的 RSS 实测，不是 Android/iOS 真机数据，两者不能直接类比。**

/// Which mode this process measures: `video` or `audio`.
///
/// 本进程测量哪种模式：`video` 或 `audio`。
const _mode = String.fromEnvironment('MOVA_PERF_MODE', defaultValue: 'video');

/// How long to let playback stabilise before sampling.
///
/// 采样前让播放稳定多久。
const _settle = Duration(seconds: 6);

/// How long to wait after `dispose()` before the release sample.
///
/// `dispose()` 后等多久再采释放后的样本。
const _afterDispose = Duration(seconds: 4);

/// The material both modes play — it carries a video track, so the audio
/// engine's job is to decode only the audio out of the very same file.
///
/// 两种模式共用的素材——它带视频轨，因此音频引擎的任务是从同一个文件里只解出
/// 音频。
const _material = MovaSource(
  'https://user-images.githubusercontent.com/28951144/229373695-22f88f13-d18f-4288-9bf1-c3e078d83722.mp4',
  title: 'perf material',
);

/// Current resident set size in MiB.
///
/// 当前常驻内存（MiB）。
double _rssMiB() => ProcessInfo.currentRss / 1024 / 1024;

/// Prints one labelled sample in a grep-friendly shape.
///
/// 以便于 grep 的格式打印一条带标签的样本。
void _sample(String label) {
  stdout.writeln('MOVA_PERF|$_mode|$label|${_rssMiB().toStringAsFixed(2)}');
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MovaEngine.ensureInitialized();
  runApp(const _ProbeApp());
}

/// The probe shell. It mounts a real [MovaPlayer] over the engine under test
/// so the video mode actually registers and composites its Flutter texture —
/// measuring a video engine that nothing renders would understate its cost.
///
/// 探针外壳。它在被测引擎之上挂载真实的 [MovaPlayer]，使视频模式真正注册纹理并
/// 参与合成——测一个无人渲染的视频引擎会低估它的开销。
class _ProbeApp extends StatefulWidget {
  /// Creates the probe shell.
  ///
  /// 创建探针外壳。
  const _ProbeApp();

  @override
  State<_ProbeApp> createState() => _ProbeAppState();
}

class _ProbeAppState extends State<_ProbeApp> {
  /// The engine under measurement; null before phase 0 and after disposal.
  ///
  /// 被测引擎；阶段 0 之前与释放之后为 null。
  MovaEngine? _engine;

  /// The latest phase label, shown on screen.
  ///
  /// 最近的阶段标签，显示在屏幕上。
  String _phase = 'baseline';

  @override
  void initState() {
    super.initState();
    unawaited(_run());
  }

  /// Drives the three-phase measurement and exits the process when done.
  ///
  /// 驱动三阶段测量，完成后退出进程。
  Future<void> _run() async {
    // Phase 0: process baseline, before any engine exists.
    // 阶段 0：进程基线，此时还没有任何引擎。
    await Future<void>.delayed(const Duration(seconds: 3));
    _sample('baseline');

    final engine = createMovaEngine(
      audioOnly: _mode == 'audio',
      options: MovaOpts(preview: MovaPrevConfig(enabled: _mode != 'audio')),
    );
    stdout.writeln('MOVA_PERF|$_mode|renderHandle|${engine.renderHandle}');
    setState(() {
      _engine = engine;
      _phase = 'playing';
    });

    await engine.open(_material);
    await Future<void>.delayed(_settle);

    // Phase 1: steady-state playback, with the surface actually mounted.
    // 阶段 1：稳定播放中，且渲染面确实已挂载。
    _sample('playing');
    stdout.writeln('MOVA_PERF|$_mode|size|${engine.state.width}x${engine.state.height}');
    stdout.writeln('MOVA_PERF|$_mode|duration|${engine.state.duration.inMilliseconds}');
    stdout.writeln('MOVA_PERF|$_mode|playing|${engine.state.playing}');

    setState(() {
      _engine = null;
      _phase = 'disposed';
    });
    await Future<void>.delayed(const Duration(milliseconds: 500));
    await engine.dispose();
    await Future<void>.delayed(_afterDispose);

    // Phase 2: after release — this is the leak check.
    // 阶段 2：释放后——这一步是泄漏检查。
    _sample('disposed');
    stdout.writeln('MOVA_PERF|$_mode|done');
    await stdout.flush();
    exit(0);
  }

  @override
  Widget build(BuildContext context) {
    final engine = _engine;
    return MaterialApp(
      home: Scaffold(
        body: engine == null
            ? Center(child: Text('mova perf probe · $_mode · $_phase'))
            : MovaPlayer(api: engine),
      ),
    );
  }
}
