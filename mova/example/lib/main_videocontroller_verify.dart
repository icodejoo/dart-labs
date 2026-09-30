// ignore_for_file: avoid_print, implementation_imports
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mova/mova.dart';
import 'package:mova/src/core/kernel/mpv_kernel.dart';
import 'package:mova/src/platform_impl/mpv_extractor_impl.dart';

/// 摸清"VideoController 卡死 media_kit"的触发条件（见 doc/plans/2026-09-29-observe-event-ffi.md §10.7）。
///
/// 一旦卡死整个进程都受影响，所以每组必须独立进程：`--dart-define=EXP=E1..E5`。
/// E1 只创建不挂界面（连续 N 次）；E2 创建后真挂 MovaPlayer 再卸载（连续 N 次）；
/// E3 一次并发创建 N 个再依次销毁；E4 只创建销毁 1 次（新进程首个）；E5 预览抽帧器 extract+release 连续 N 次。
/// 媒体（仅 E2/E5 用）：`adb reverse tcp:8098` 的本机 HTTP 服务上的 t30.mp4。
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MovaMpvKernel.ensureInitialized();
  runApp(const MaterialApp(home: _Host()));
}

/// 实验编号。
const String kExp = String.fromEnvironment('EXP', defaultValue: 'E1');

/// 轮数。
const int kN = 5;

/// 单步超时。
const Duration kTimeout = Duration(seconds: 8);

/// 测试视频地址。
const String kUrl = 'http://127.0.0.1:8098/t30.mp4';

/// 输出一行。
void _out(String m) => print(m);

/// 带超时地跑一步，返回（耗时 ms，是否超时）。
Future<(int, bool)> _timed(Future<void> Function() f) async {
  final sw = Stopwatch()..start();
  var timedOut = false;
  await f().timeout(kTimeout, onTimeout: () => timedOut = true);
  return (sw.elapsedMilliseconds, timedOut);
}

/// 承载页：E2 时把 MovaPlayer 挂上来。
class _Host extends StatefulWidget {
  const _Host();

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  MovaApi? _engine;

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(const Duration(seconds: 1), _run);
  }

  /// E1：只创建不挂界面，连续 N 次。
  Future<void> _e1() async {
    for (var i = 0; i < kN; i++) {
      final k = MovaMpvKernel(observeQoeSignals: false);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      final (ms, to) = await _timed(k.dispose);
      _out('E1 round=$i disposeMs=$ms hung=$to');
    }
  }

  /// E2：创建后真挂 MovaPlayer 再卸载，连续 N 次。
  Future<void> _e2() async {
    for (var i = 0; i < kN; i++) {
      final e = createMovaEngine();
      setState(() => _engine = e);
      await Future<void>.delayed(const Duration(milliseconds: 500));
      unawaited(e.open(MovaSource('$kUrl?t=${DateTime.now().microsecondsSinceEpoch}')));
      await Future<void>.delayed(const Duration(seconds: 1));
      setState(() => _engine = null);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      final (ms, to) = await _timed(e.dispose);
      _out('E2 round=$i disposeMs=$ms hung=$to');
    }
  }

  /// E3：一次并发创建 N 个，再依次销毁。
  Future<void> _e3() async {
    final ks = [for (var i = 0; i < kN; i++) MovaMpvKernel(observeQoeSignals: false)];
    await Future<void>.delayed(const Duration(milliseconds: 800));
    for (var i = 0; i < ks.length; i++) {
      final (ms, to) = await _timed(ks[i].dispose);
      _out('E3 idx=$i disposeMs=$ms hung=$to');
    }
  }

  /// E4：新进程里只创建销毁 1 次。
  Future<void> _e4() async {
    final k = MovaMpvKernel(observeQoeSignals: false);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final (ms, to) = await _timed(k.dispose);
    _out('E4 disposeMs=$ms hung=$to');
  }

  /// E5：预览抽帧器 extract + release 连续 N 次（内部无界面创建 VideoController）。
  Future<void> _e5() async {
    for (var i = 0; i < kN; i++) {
      final x = MovaFrameExtractor();
      final sw = Stopwatch()..start();
      Object? bytes;
      var extractTimedOut = false;
      try {
        bytes = await x
            .extract('$kUrl?t=${DateTime.now().microsecondsSinceEpoch}', Duration(seconds: 2 + i), width: 160, hwdec: false)
            .timeout(kTimeout, onTimeout: () {
          extractTimedOut = true;
          return null;
        });
      } catch (e) {
        bytes = 'ERR $e';
      }
      final extractMs = sw.elapsedMilliseconds;
      final (relMs, relTo) = await _timed(x.dispose);
      _out('E5 round=$i extractMs=$extractMs extractTimedOut=$extractTimedOut gotBytes=${bytes is List ? bytes.length : bytes} releaseMs=$relMs releaseHung=$relTo');
    }
  }

  /// E6：createMovaEngine() 默认（懒创建），从不挂界面，连续创建销毁 N 次。
  Future<void> _e6() async {
    for (var i = 0; i < kN; i++) {
      final e = createMovaEngine();
      await Future<void>.delayed(const Duration(milliseconds: 300));
      unawaited(e.open(MovaSource('$kUrl?t=${DateTime.now().microsecondsSinceEpoch}')));
      await Future<void>.delayed(const Duration(milliseconds: 800));
      final (ms, to) = await _timed(e.dispose);
      _out('E6 round=$i disposeMs=$ms hung=$to');
    }
  }

  /// E7：先 open 播放、1s 后才挂上 MovaPlayer，确认画面尺寸事件正常、销毁正常。
  Future<void> _e7() async {
    for (var i = 0; i < 3; i++) {
      final e = createMovaEngine();
      var w = 0, h = 0;
      final sub = e.events.listen((ev) {
        if (ev is MovaSizeChange) {
          w = ev.width;
          h = ev.height;
        }
      });
      unawaited(e.open(MovaSource('$kUrl?t=${DateTime.now().microsecondsSinceEpoch}')));
      await Future<void>.delayed(const Duration(seconds: 1));
      final sizeBefore = '${w}x$h';
      setState(() => _engine = e); // 此刻才读取 renderHandle，创建 VideoController
      await Future<void>.delayed(const Duration(seconds: 2));
      final sizeAfter = '${w}x$h';
      final playing = e.state.playing;
      setState(() => _engine = null);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await sub.cancel();
      final (ms, to) = await _timed(e.dispose);
      _out('E7 round=$i sizeBeforeMount=$sizeBefore sizeAfterMount=$sizeAfter playing=$playing disposeMs=$ms hung=$to');
    }
  }

  /// E8：无缝切换回归——影子引擎预热期间就要有画面管线，切换后新 active 能出画面。
  Future<void> _e8() async {
    final swap = MovaSwapEngine(
      engineFactory: () => createMovaEngine(options: const MovaOpts(swap: MovaSwapConfig(enabled: true))),
    );
    setState(() => _engine = swap);
    await Future<void>.delayed(const Duration(milliseconds: 500));
    unawaited(swap.open(MovaSource('http://127.0.0.1:8098/t5.mp4?t=${DateTime.now().microsecondsSinceEpoch}')));
    await Future<void>.delayed(const Duration(seconds: 2));
    final epochBefore = swap.state.renderEpoch;
    final t0 = DateTime.now();
    final ok = await swap.swapTo(MovaSource('$kUrl?t=${DateTime.now().microsecondsSinceEpoch}c'), at: const Duration(seconds: 3));
    final ms = DateTime.now().difference(t0).inMilliseconds;
    await Future<void>.delayed(const Duration(seconds: 2));
    _out('E8 swapOk=$ok swapMs=$ms epoch $epochBefore->${swap.state.renderEpoch} playing=${swap.state.playing} '
        'size=${swap.state.width}x${swap.state.height}');
    setState(() => _engine = null);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final (dms, to) = await _timed(swap.dispose);
    _out('E8 disposeMs=$dms hung=$to');
  }

  Future<void> _run() async {
    _out('START $kExp');
    switch (kExp) {
      case 'E1':
        await _e1();
      case 'E2':
        await _e2();
      case 'E3':
        await _e3();
      case 'E4':
        await _e4();
      case 'E5':
        await _e5();
      case 'E6':
        await _e6();
      case 'E7':
        await _e7();
      case 'E8':
        await _e8();
    }
    _out('ALL_DONE $kExp');
  }

  @override
  Widget build(BuildContext context) {
    final e = _engine;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: e == null
            ? Text('VideoController verify $kExp', style: const TextStyle(color: Colors.white))
            : AspectRatio(aspectRatio: 16 / 9, child: MovaPlayer(api: e)),
      ),
    );
  }
}
