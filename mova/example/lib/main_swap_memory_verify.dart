import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:mova/mova.dart';

/// 0.4.0 无缝引擎切换——三阶段内存采样的独立验证入口。
///
/// 与 `main_seamless_swap_verify.dart` 的区别：那个文件四组测试共享一个进程，
/// 上一轮实测发现前面组留下的引擎/GC 残留会污染内存组自己的 baseline（出现
/// 不合理的负增量）。本文件**只做这一件事**，不跑任何其他测试组，一次进程
/// 启动只采一轮三阶段数字，避免相互污染。
///
/// 跑法：`flutter run -t lib/main_swap_memory_verify.dart -d <device-id> --release`。
/// 跑完打印 SUMMARY 后界面保持显示，不自动退出，方便截图/复制。
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MovaEngine.ensureInitialized();
  runApp(const MaterialApp(home: _MemoryVerifyPage()));
}

/// 带缓存清除参数的正片源。
MovaSource _content() => MovaSource(
      'https://user-images.githubusercontent.com/28951144/229373695-22f88f13-d18f-4288-9bf1-c3e078d83722.mp4'
      '?t=${DateTime.now().millisecondsSinceEpoch}',
      title: '正片',
    );

/// 广告素材（与 main_seamless_swap_verify.dart 保持一致，已确认可达）。
MovaSource _adSource() => MovaSource(
      'https://interactive-examples.mdn.mozilla.net/media/cc0-videos/flower.mp4'
      '?t=${DateTime.now().millisecondsSinceEpoch}',
      title: '广告',
    );

class _MemoryVerifyPage extends StatefulWidget {
  const _MemoryVerifyPage();
  @override
  State<_MemoryVerifyPage> createState() => _MemoryVerifyPageState();
}

class _MemoryVerifyPageState extends State<_MemoryVerifyPage> {
  final List<String> _log = [];
  bool _done = false;

  @override
  void initState() {
    super.initState();
    unawaited(_run());
  }

  void _mark(String s) {
    final line = '[+${DateTime.now().millisecondsSinceEpoch % 1000000}ms] $s';
    // ignore: avoid_print
    print(line);
    if (mounted) setState(() => _log.add(line));
  }

  double _mib(int bytes) => bytes / 1024 / 1024;

  Future<void> _run() async {
    // 阶段①：baseline——只打开正片，不涉及任何广告/切换逻辑，播放几秒稳定后采样。
    final opts = MovaOpts(
      ads: const MovaAdConfig(enabled: true),
      swap: const MovaSwapConfig(enabled: true, trigger: MovaEagerWarm()),
    );
    final engine = MovaSwapEngine(engineFactory: () => createMovaEngine(options: opts));
    final ctrl = MovaAdController(engine, swap: engine);

    _mark('=== 阶段① baseline：只播正片 ===');
    await ctrl.load(_content());
    await _waitPlaying(engine);
    await Future<void>.delayed(const Duration(seconds: 3));
    final baseline = ProcessInfo.currentRss;
    _mark('baseline RSS=${_mib(baseline).toStringAsFixed(2)}MiB');

    // 阶段②：插入广告，确保正片影子引擎在后台预热，双引擎并存窗口内采样。
    _mark('=== 阶段② 双引擎并存：广告播放+正片影子预热 ===');
    await ctrl.playAdNow(MovaAdBreak(
      kind: MovaAdBreakKind.mid,
      source: _adSource(),
      skippableAfter: Duration.zero,
    ));
    await _waitPlaying(engine);
    // 给影子引擎充分预热窗口，确保双引擎真正并存一段时间再采样。
    await Future<void>.delayed(const Duration(seconds: 3));
    final dualEngineRss = ProcessInfo.currentRss;
    _mark('双引擎并存 RSS=${_mib(dualEngineRss).toStringAsFixed(2)}MiB '
        '（较baseline增量=${_mib(dualEngineRss - baseline).toStringAsFixed(2)}MiB）');

    // 阶段③：skip 广告、原子切换回正片，等待旧引擎真正 dispose 完成后采样。
    _mark('=== 阶段③ 切回正片：等待旧引擎 dispose ===');
    ctrl.skip();
    await Future<void>.delayed(const Duration(seconds: 5));
    final afterSwapRss = ProcessInfo.currentRss;
    _mark('切回正片后 RSS=${_mib(afterSwapRss).toStringAsFixed(2)}MiB '
        '（较baseline增量=${_mib(afterSwapRss - baseline).toStringAsFixed(2)}MiB）');

    await ctrl.dispose();
    await engine.dispose();

    _mark('=== SUMMARY ===');
    _mark('baseline=${_mib(baseline).toStringAsFixed(2)}MiB '
        '→ 双引擎并存=${_mib(dualEngineRss).toStringAsFixed(2)}MiB'
        '(+${_mib(dualEngineRss - baseline).toStringAsFixed(2)}) '
        '→ 切回正片=${_mib(afterSwapRss).toStringAsFixed(2)}MiB'
        '(+${_mib(afterSwapRss - baseline).toStringAsFixed(2)})');

    if (mounted) setState(() => _done = true);
  }

  Future<void> _waitPlaying(MovaSwapEngine engine) {
    final completer = Completer<void>();
    late final StreamSubscription<MovaProg> sub;
    sub = engine.progress.listen((p) {
      if (p.position > Duration.zero && !engine.state.buffering) {
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
