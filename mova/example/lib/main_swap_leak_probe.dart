import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:mova/mova.dart';

/// 0.4.0 无缝引擎切换——内存泄漏定性探针（N 轮重复 + 长观察窗）。
///
/// 三阶段采样只能看到"切回后没回落"，无法区分**真泄漏**与**一次性开销/分配器
/// 不还 OS**。本探针改用两条判据：
/// 1. 重复 N 轮「插播广告 → 跳过 → 切回正片」，每轮同一时点采一次 RSS。
///    线性单调爬升 = 真泄漏；前一两轮涨完后趋平 = 非泄漏。
/// 2. 最后一轮结束后静置 60s，每 5s 采一次，看是否缓慢回落（GC/分配器延迟）。
///
/// 模式经 `--dart-define=MODE=swap|hard` 选择（用 `String.fromEnvironment`，
/// 编译期注入，不受 Android 进程环境变量限制）：
/// - `swap`：`MovaSwapConfig.enabled = true`，走影子引擎预热 + 原子切换，
///   每轮真实创建/销毁 2 个引擎。
/// - `hard`：`enabled = false`，`MovaSwapEngine` 退化为纯直通，全程只有 1 个
///   引擎，每轮只是 `open()` 换源。作为「额外 open/dispose 循环」的对照组。
///
/// 跑法：
/// `flutter run -t lib/main_swap_leak_probe.dart -d <id> --release --dart-define=MODE=swap`
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MovaEngine.ensureInitialized();
  runApp(const MaterialApp(home: _LeakProbePage()));
}

/// 编译期注入的模式：`swap`（默认）或 `hard`。
const String kMode = String.fromEnvironment('MODE', defaultValue: 'swap');

/// 重复轮数。
const int kRounds = 8;

/// 带缓存清除参数的正片源。
MovaSource _content() => MovaSource(
      'https://user-images.githubusercontent.com/28951144/229373695-22f88f13-d18f-4288-9bf1-c3e078d83722.mp4'
      '?t=${DateTime.now().microsecondsSinceEpoch}',
      title: '正片',
    );

/// 带缓存清除参数的广告源。
MovaSource _adSource() => MovaSource(
      'https://interactive-examples.mdn.mozilla.net/media/cc0-videos/flower.mp4'
      '?t=${DateTime.now().microsecondsSinceEpoch}',
      title: '广告',
    );

class _LeakProbePage extends StatefulWidget {
  const _LeakProbePage();
  @override
  State<_LeakProbePage> createState() => _LeakProbePageState();
}

class _LeakProbePageState extends State<_LeakProbePage> {
  final List<String> _log = [];
  bool _done = false;

  @override
  void initState() {
    super.initState();
    unawaited(_run());
  }

  /// 打屏 + logcat 双路输出一行日志。
  void _mark(String s) {
    final line = '[${DateTime.now().toIso8601String().substring(11, 23)}] $s';
    // ignore: avoid_print
    print('LEAKPROBE $line');
    if (mounted) setState(() => _log.add(line));
  }

  double _mib(int bytes) => bytes / 1024 / 1024;

  /// 采一次 RSS 并打印，返回字节数。
  int _sample(String tag) {
    final rss = ProcessInfo.currentRss;
    _mark('$tag RSS=${_mib(rss).toStringAsFixed(2)}MiB');
    return rss;
  }

  Future<void> _run() async {
    _mark('=== MODE=$kMode rounds=$kRounds ===');
    final opts = MovaOpts(
      ads: const MovaAdConfig(enabled: true),
      swap: MovaSwapConfig(enabled: kMode == 'swap', trigger: const MovaEagerWarm()),
    );
    final engine = MovaSwapEngine(engineFactory: () => createMovaEngine(options: opts));
    final ctrl = MovaAdController(engine, swap: engine);

    await ctrl.load(_content());
    await _waitPlaying(engine);
    await Future<void>.delayed(const Duration(seconds: 4));
    final baseline = _sample('baseline');

    final samples = <int>[];
    for (var i = 1; i <= kRounds; i++) {
      _mark('--- round $i: 插播广告 ---');
      await ctrl.playAdNow(MovaAdBreak(
        kind: MovaAdBreakKind.mid,
        source: _adSource(),
        skippableAfter: Duration.zero,
      ));
      final gotAd = await _waitAd(ctrl, true);
      if (!gotAd) _mark('round $i: 广告未起播（超时），继续');
      await Future<void>.delayed(const Duration(seconds: 3));
      _sample('round $i 广告中');

      _mark('--- round $i: skip 回切正片 ---');
      ctrl.skip();
      await _waitAd(ctrl, false);
      await Future<void>.delayed(const Duration(seconds: 4));
      samples.add(_sample('round $i 切回正片后'));
    }

    _mark('=== 静置观察 60s（不再操作，只采样）===');
    for (var t = 5; t <= 60; t += 5) {
      await Future<void>.delayed(const Duration(seconds: 5));
      _sample('settle +${t}s');
    }

    _mark('=== 全部 dispose 后再观察 20s ===');
    await ctrl.dispose();
    await engine.dispose();
    for (var t = 5; t <= 20; t += 5) {
      await Future<void>.delayed(const Duration(seconds: 5));
      _sample('disposed +${t}s');
    }

    _mark('=== SUMMARY MODE=$kMode ===');
    _mark('baseline=${_mib(baseline).toStringAsFixed(2)}');
    for (var i = 0; i < samples.length; i++) {
      _mark('round ${i + 1}=${_mib(samples[i]).toStringAsFixed(2)}MiB '
          '(较baseline +${_mib(samples[i] - baseline).toStringAsFixed(2)}, '
          '较上轮 ${i == 0 ? "-" : (_mib(samples[i] - samples[i - 1])).toStringAsFixed(2)})');
    }
    if (mounted) setState(() => _done = true);
  }

  /// 等待广告阶段变为 [wanted]；超时 30s 返回 false。
  Future<bool> _waitAd(MovaAdController ctrl, bool wanted) async {
    if (ctrl.isShowingAd == wanted) return true;
    final completer = Completer<bool>();
    late final StreamSubscription<void> sub;
    sub = ctrl.changes.listen((_) {
      if (ctrl.isShowingAd == wanted && !completer.isCompleted) {
        unawaited(sub.cancel());
        completer.complete(true);
      }
    });
    return completer.future.timeout(const Duration(seconds: 30), onTimeout: () {
      unawaited(sub.cancel());
      return false;
    });
  }

  /// 等待真正出画（position 前进且非缓冲）。
  Future<void> _waitPlaying(MovaSwapEngine engine) {
    final completer = Completer<void>();
    late final StreamSubscription<MovaProg> sub;
    sub = engine.progress.listen((p) {
      if (p.position > Duration.zero && !engine.state.buffering) {
        unawaited(sub.cancel());
        if (!completer.isCompleted) completer.complete();
      }
    });
    return completer.future.timeout(const Duration(seconds: 25), onTimeout: () {
      unawaited(sub.cancel());
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: SingleChildScrollView(
            reverse: true,
            child: Text(
              (_done ? '=== DONE ===\n' : '') + _log.join('\n'),
              style: const TextStyle(
                  color: Colors.greenAccent, fontFamily: 'monospace', fontSize: 11),
            ),
          ),
        ),
      ),
    );
  }
}
