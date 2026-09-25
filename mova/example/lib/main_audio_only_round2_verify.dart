import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:mova/mova.dart';

/// 0.4.x 仅音频模式——第二轮真机验证，补齐 CLAUDE.md 记录的两项仍未测缺口：
///
/// 1. 带视频轨源在 `audioOnly: true` 下是否真的只出声不出画（用
///    `MovaState.size`/`renderHandle` 的真实值判定，而非肉眼）。
/// 2. 连播多轮（本文件跑 6 轮）观察内存是否随轮次累积爬升——每轮独立开引擎、
///    稳定播放、采样、dispose、再采样，全部用 `print()`（而非
///    `perf_probe_audio_only.dart` 里已知在 Android release 下不出现在 logcat
///    的 `stdout.writeln`），这样才能被 `adb logcat` 抓到。
///
/// 跑法：`flutter run -t lib/main_audio_only_round2_verify.dart -d <device-id> --release`。
/// 全部打印以 `MOVA_R2|` 开头，便于 grep。跑完不自动退出，方便截图。
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MovaEngine.ensureInitialized();
  runApp(const MaterialApp(home: _Round2Page()));
}

/// 带视频轨的素材——本轮验证"audioOnly 下是否只出声不出画"必须用这条，纯音频
/// 素材测不出这件事。
const _videoSource = MovaSource(
  'https://user-images.githubusercontent.com/28951144/229373695-22f88f13-d18f-4288-9bf1-c3e078d83722.mp4',
  title: '带视频轨素材',
);

/// 连播轮数——用户要求 5-10 轮，取 6 轮。
const _rounds = 6;

double _mib(int bytes) => bytes / 1024 / 1024;

class _Round2Page extends StatefulWidget {
  const _Round2Page();
  @override
  State<_Round2Page> createState() => _Round2PageState();
}

class _Round2PageState extends State<_Round2Page> {
  final List<String> _log = [];
  bool _done = false;

  @override
  void initState() {
    super.initState();
    unawaited(_run());
  }

  void _mark(String s) {
    final line = 'MOVA_R2|$s';
    // 用 print() 而非 stdout.writeln——已知后者在 Android release 包下不出现在 logcat。
    // ignore: avoid_print
    print(line);
    if (mounted) setState(() => _log.add(line));
  }

  Future<void> _run() async {
    // ===== 第一部分：带视频轨源在 audioOnly 下的行为断言 =====
    _mark('=== PART1 带视频轨源 + audioOnly=true ===');
    final engine1 = createMovaEngine(audioOnly: true);
    _mark('renderHandle(open前)=${engine1.renderHandle}');
    await engine1.open(_videoSource);
    await _waitReady(engine1);
    await Future<void>.delayed(const Duration(seconds: 3));
    _mark('renderHandle(播放中)=${engine1.renderHandle}');
    _mark('size(播放中)=${engine1.state.width}x${engine1.state.height}');
    _mark('duration=${engine1.state.duration.inMilliseconds}ms');
    _mark('playing=${engine1.state.playing}');
    _mark('PART1 结论：renderHandle应为null、size应为0x0——若播放正常进行(duration>0且playing=true)'
        '但两者仍是null/0x0，即证明只出声不出画');
    await engine1.dispose();
    await Future<void>.delayed(const Duration(seconds: 2));

    // ===== 第二部分：连播 N 轮，观察 RSS 是否随轮次累积爬升 =====
    _mark('=== PART2 连播$_rounds轮，每轮开关一次引擎 ===');
    final beforeRss = <double>[];
    final afterRss = <double>[];
    for (var i = 1; i <= _rounds; i++) {
      final engine = createMovaEngine(audioOnly: true);
      await engine.open(_videoSource);
      await _waitReady(engine);
      // 稳定后再采样，避免过渡期噪声。
      await Future<void>.delayed(const Duration(seconds: 4));
      final rssPlaying = _mib(ProcessInfo.currentRss);
      beforeRss.add(rssPlaying);
      _mark('round$i playing RSS=${rssPlaying.toStringAsFixed(2)}MiB '
          'size=${engine.state.width}x${engine.state.height} renderHandle=${engine.renderHandle}');
      await engine.dispose();
      await Future<void>.delayed(const Duration(seconds: 2));
      final rssDisposed = _mib(ProcessInfo.currentRss);
      afterRss.add(rssDisposed);
      _mark('round$i disposed RSS=${rssDisposed.toStringAsFixed(2)}MiB');
    }

    _mark('=== SUMMARY ===');
    _mark('playing序列(MiB)=${beforeRss.map((e) => e.toStringAsFixed(2)).join(",")}');
    _mark('disposed序列(MiB)=${afterRss.map((e) => e.toStringAsFixed(2)).join(",")}');
    final firstPlaying = beforeRss.first;
    final lastPlaying = beforeRss.last;
    _mark('playing态首轮→末轮增量=${(lastPlaying - firstPlaying).toStringAsFixed(2)}MiB');
    final firstDisposed = afterRss.first;
    final lastDisposed = afterRss.last;
    _mark('disposed态首轮→末轮增量=${(lastDisposed - firstDisposed).toStringAsFixed(2)}MiB');

    // ===== 第三部分：关闭态（audioOnly:false）全流程回归——确认与不开启该特性时
    // 行为完全一致：renderHandle 非空、size 非 0x0。 =====
    _mark('=== PART3 关闭态回归 audioOnly=false ===');
    final engine3 = createMovaEngine();
    await engine3.open(_videoSource);
    await _waitReady(engine3);
    await Future<void>.delayed(const Duration(seconds: 3));
    _mark('audioOnly=false renderHandle=${engine3.renderHandle} '
        'size=${engine3.state.width}x${engine3.state.height} playing=${engine3.state.playing}');
    _mark('PART3 结论：renderHandle应非null、size应非0x0——与开启audioOnly前(0.3.x)行为一致即回归通过');
    await engine3.dispose();

    if (mounted) setState(() => _done = true);
  }

  Future<void> _waitReady(MovaEngine engine) {
    final completer = Completer<void>();
    late final StreamSubscription<MovaProg> sub;
    sub = engine.progress.listen((p) {
      if (p.position > Duration.zero) {
        unawaited(sub.cancel());
        if (!completer.isCompleted) completer.complete();
      }
    });
    return completer.future.timeout(const Duration(seconds: 20), onTimeout: () {
      unawaited(sub.cancel());
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Container(
          color: Colors.black87,
          padding: const EdgeInsets.all(12),
          width: double.infinity,
          height: double.infinity,
          child: SingleChildScrollView(
            child: Text(
              (_done ? '=== DONE ===\n' : '') + _log.join('\n'),
              style: const TextStyle(color: Colors.greenAccent, fontFamily: 'monospace', fontSize: 12),
            ),
          ),
        ),
      ),
    );
  }
}
