// ignore_for_file: avoid_print, implementation_imports
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mova/mova.dart';
import 'package:mova/src/core/kernel/mpv_kernel.dart';

/// 带视频画面（非 audioOnly，真实 `MovaPlayer` 挂在树上）路径的 QoE 真机验证。
///
/// 媒体由本机 HTTP 服务经 `adb reverse tcp:8098` 提供（t5.mp4=5s 视频，t30.mp4=30s 视频）。
/// 跑法：`flutter run --release -t lib/main_qoe_video_verify.dart`
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MovaMpvKernel.ensureInitialized();
  runApp(const MaterialApp(home: _Host()));
}

/// 快速服务地址前缀。
const String kFast = 'http://127.0.0.1:8098';

/// 输出一行。
void _out(String m) => print(m);

/// 承载页：每个场景创建一个播放器并把 [MovaPlayer] 挂上屏幕。
class _Host extends StatefulWidget {
  const _Host();

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  /// 当前场景的播放器（页面上展示用）。
  Mova? _mova;

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(const Duration(seconds: 1), _run);
  }

  /// 单个场景：建播放器挂到屏幕，执行脚本，dispose，打印上报事件。
  Future<List<MovaReportEvent>> _scenario(String tag, Future<void> Function(Mova e) script) async {
    final events = <MovaReportEvent>[];
    final mova = createMova(
      options: const MovaOpts(report: MovaReportOpts(qoe: true)),
      reporter: MovaCallbackReporter(events.add),
    );
    setState(() => _mova = mova);
    await Future<void>.delayed(const Duration(milliseconds: 500)); // 等 Video 控件就绪
    final t0 = DateTime.now();
    try {
      await script(mova);
    } catch (e) {
      _out('$tag SCRIPT_ERROR $e');
    }
    setState(() => _mova = null);
    await mova.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 500));
    _out('--- $tag events=${events.length}');
    for (final ev in events) {
      if (ev.name == MovaReportName.play || ev.name == MovaReportName.pause) continue;
      _out('$tag +${ev.at.difference(t0).inMilliseconds}ms ${ev.name.value} ${ev.params}');
    }
    return events;
  }

  /// 主流程。
  Future<void> _run() async {
    _out('START');
    final s1 = await _scenario('V1_complete', (e) async {
      await e.open(MovaSource('$kFast/t5.mp4?t=${DateTime.now().microsecondsSinceEpoch}'));
      await Future<void>.delayed(const Duration(seconds: 8));
    });
    _out('V1 firstFrame=${s1.where((x) => x.name == MovaReportName.firstFrame).map((x) => x.params).toList()} '
        'end=${s1.where((x) => x.name == MovaReportName.sessionEnd).map((x) => '${x.params['reason']}/w${x.params['watchedMs']}').toList()}');

    final s2 = await _scenario('V2_stopped', (e) async {
      await e.open(MovaSource('$kFast/t30.mp4?t=${DateTime.now().microsecondsSinceEpoch}'));
      await Future<void>.delayed(const Duration(seconds: 3));
      await e.open(MovaSource('$kFast/t30.mp4?t=${DateTime.now().microsecondsSinceEpoch}b'));
      await Future<void>.delayed(const Duration(seconds: 3));
    });
    _out('V2 ends=${s2.where((x) => x.name == MovaReportName.sessionEnd).map((x) => x.params['reason']).toList()} '
        'firstFrames=${s2.where((x) => x.name == MovaReportName.firstFrame).length}');

    final s3 = await _scenario('V3_failed', (e) async {
      await e.open(MovaSource('$kFast/not_exist.mp4?t=${DateTime.now().microsecondsSinceEpoch}'));
      await Future<void>.delayed(const Duration(seconds: 4));
    });
    _out('V3 ends=${s3.where((x) => x.name == MovaReportName.sessionEnd).map((x) => '${x.params['reason']}/w${x.params['watchedMs']}').toList()} '
        'startupFail=${s3.where((x) => x.name == MovaReportName.startupFail).length}');

    final s4 = await _scenario('V4_abandoned', (e) async {
      unawaited(e.open(MovaSource('$kFast/t30.mp4?t=${DateTime.now().microsecondsSinceEpoch}')));
      await Future<void>.delayed(const Duration(milliseconds: 30));
    });
    _out('V4 ends=${s4.where((x) => x.name == MovaReportName.sessionEnd).map((x) => x.params['reason']).toList()}');

    _out('ALL_DONE');
  }

  @override
  Widget build(BuildContext context) {
    final e = _mova;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: e == null
            ? const Text('qoe video verify', style: TextStyle(color: Colors.white))
            : AspectRatio(aspectRatio: 16 / 9, child: MovaPlayer(api: e)),
      ),
    );
  }
}
