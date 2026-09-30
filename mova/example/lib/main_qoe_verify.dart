// ignore_for_file: avoid_print, implementation_imports
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mova/mova.dart';
import 'package:mova/src/core/kernel/mpv_kernel.dart';
import 'package:mova/src/platform_impl/mpv_event_backend_ffi.dart';

/// QoE 上报真机验证：TTFF、卡顿、四分终止态、错误分类、qoe:false 关闭态。
///
/// 媒体由本机 HTTP 服务提供（`adb reverse tcp:8098`=快、`tcp:8099`=限速 20KB/s）。
/// 跑法：`flutter run --release -t lib/main_qoe_verify.dart`
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MovaMpvKernel.ensureInitialized();
  runApp(const MaterialApp(home: Scaffold(body: Center(child: Text('qoe verify')))));
  Future<void>.delayed(const Duration(seconds: 1), _run);
}

/// 快速服务地址前缀。
const String kFast = 'http://127.0.0.1:8098';

/// 限速服务地址前缀。
const String kSlow = 'http://127.0.0.1:8099';

/// 输出一行。
void _out(String m) => print(m);

/// 单个场景：起 engine、收集上报事件、执行脚本、dispose，返回事件列表。
Future<List<MovaReportEvent>> _scenario(
  String tag, {
  required bool qoe,
  required Future<void> Function(MovaEngine e) script,
}) async {
  final events = <MovaReportEvent>[];
  final engine = createMovaEngine(
    audioOnly: true,
    options: MovaOpts(report: MovaReportConfig(qoe: qoe, minStall: const Duration(milliseconds: 200))),
    reporter: MovaCallbackReporter(events.add),
  );
  final t0 = DateTime.now();
  try {
    await script(engine);
  } catch (e) {
    _out('$tag SCRIPT_ERROR $e');
  }
  await engine.dispose();
  await Future<void>.delayed(const Duration(milliseconds: 500));
  _out('--- $tag qoe=$qoe events=${events.length}');
  for (final ev in events) {
    final ms = ev.at.difference(t0).inMilliseconds;
    if (ev.name == MovaReportName.play || ev.name == MovaReportName.pause) continue;
    _out('$tag +${ms}ms ${ev.name.value} ${ev.params}');
  }
  return events;
}

/// 取某名称的事件。
Iterable<MovaReportEvent> _of(List<MovaReportEvent> l, MovaReportName n) => l.where((e) => e.name == n);

/// 主流程。
Future<void> _run() async {
  _out('START');

  // S0 RESTART 时序：注入 kernel 直接监听，对比首帧上报时间。
  {
    final k = MovaMpvKernel(
      audioOnly: true,
      observeQoeSignals: true,
      backendFactory: (n, a) => createFfiMpvEventBackend(n, a, pollInDebug: false),
    );
    final evs = <MovaReportEvent>[];
    final e = createMovaEngine(
      kernel: k,
      audioOnly: true,
      options: const MovaOpts(report: MovaReportConfig(qoe: true)),
      reporter: MovaCallbackReporter(evs.add),
    );
    final t0 = DateTime.now();
    final sub = k.playbackRestarts.listen((_) => _out('S0 restart +${DateTime.now().difference(t0).inMilliseconds}ms'));
    await e.open(MovaSource('$kFast/t5.mp4?t=${DateTime.now().microsecondsSinceEpoch}'));
    await Future<void>.delayed(const Duration(seconds: 3));
    for (final ev in evs.where((x) => x.name == MovaReportName.firstFrame)) {
      _out('S0 firstFrame +${ev.at.difference(t0).inMilliseconds}ms ${ev.params}');
    }
    await sub.cancel();
    await e.dispose();
  }

  // S1 正常播完：期望 firstFrame(ttff)、sessionEnd=ended。
  final s1 = await _scenario('S1_complete', qoe: true, script: (e) async {
    await e.open(MovaSource('$kFast/t5.mp4?t=${DateTime.now().microsecondsSinceEpoch}'));
    await Future<void>.delayed(const Duration(seconds: 8));
  });
  _out('S1 firstFrame=${_of(s1, MovaReportName.firstFrame).map((e) => e.params).toList()} '
      'end=${_of(s1, MovaReportName.sessionEnd).map((e) => e.params['reason']).toList()}');

  // S2 中途停止：播 3s 后换源 -> 首会话 stopped；第二个会话 dispose 时也应 stopped。
  final s2 = await _scenario('S2_stopped', qoe: true, script: (e) async {
    await e.open(MovaSource('$kFast/t30.mp4?t=${DateTime.now().microsecondsSinceEpoch}'));
    await Future<void>.delayed(const Duration(seconds: 3));
    await e.open(MovaSource('$kFast/t30.mp4?t=${DateTime.now().microsecondsSinceEpoch}b'));
    await Future<void>.delayed(const Duration(seconds: 3));
  });
  _out('S2 ends=${_of(s2, MovaReportName.sessionEnd).map((e) => e.params['reason']).toList()}');

  // S3 开播即弃：open 后立即 dispose -> abandoned（+ startupFail）。
  final s3 = await _scenario('S3_abandoned', qoe: true, script: (e) async {
    unawaited(e.open(MovaSource('$kSlow/big.mp4?t=${DateTime.now().microsecondsSinceEpoch}')));
    await Future<void>.delayed(const Duration(milliseconds: 60));
  });
  _out('S3 ends=${_of(s3, MovaReportName.sessionEnd).map((e) => e.params['reason']).toList()} '
      'startupFail=${_of(s3, MovaReportName.startupFail).length}');

  // S4 失败：打开不存在的资源 -> failed。
  final s4 = await _scenario('S4_failed', qoe: true, script: (e) async {
    await e.open(MovaSource('$kFast/not_exist.mp4?t=${DateTime.now().microsecondsSinceEpoch}'));
    await Future<void>.delayed(const Duration(seconds: 4));
  });
  _out('S4 ends=${_of(s4, MovaReportName.sessionEnd).map((e) => e.params['reason']).toList()} '
      'errors=${_of(s4, MovaReportName.error).map((e) => e.params).toList()}');

  // S5 真实卡顿：限速服务 20KB/s，码率 ~80KB/s，必然反复 rebuffer。
  final s5 = await _scenario('S5_stall', qoe: true, script: (e) async {
    await e.open(MovaSource('$kSlow/big.mp4?t=${DateTime.now().microsecondsSinceEpoch}'));
    var pos = Duration.zero;
    final sub = e.progress.listen((p) => pos = p.position);
    for (var i = 0; i < 12; i++) {
      await Future<void>.delayed(const Duration(seconds: 2));
      _out('S5 sample t=${(i + 1) * 2}s pos=${pos.inMilliseconds}ms buffering=${e.state.buffering} playing=${e.state.playing}');
    }
    await sub.cancel();
  });
  final rb = _of(s5, MovaReportName.rebuffer).toList();
  _out('S5 rebufferEvents=${rb.length} end=${_of(s5, MovaReportName.sessionEnd).map((e) => e.params).toList()}');

  // S6 关闭态：qoe:false 不应出现 QoE 专属事件。
  final s6 = await _scenario('S6_qoeOff', qoe: false, script: (e) async {
    await e.open(MovaSource('$kFast/t5.mp4?t=${DateTime.now().microsecondsSinceEpoch}'));
    await Future<void>.delayed(const Duration(seconds: 8));
  });
  const qoeNames = [
    MovaReportName.firstFrame,
    MovaReportName.startupFail,
    MovaReportName.rebuffer,
    MovaReportName.sessionStart,
    MovaReportName.sessionEnd,
  ];
  final leaked = s6.where((e) => qoeNames.contains(e.name)).length;
  _out('S6 qoeEventsWhenOff=$leaked');

  _out('ALL_DONE');
}
