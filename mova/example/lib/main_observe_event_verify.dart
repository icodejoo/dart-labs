// ignore_for_file: avoid_print, implementation_imports
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:mova/src/core/kernel/mpv_event_backend.dart';
import 'package:mova/src/core/kernel/mpv_kernel.dart';
import 'package:mova/src/platform_impl/mpv_event_backend_ffi.dart';

/// 弱客户端事件订阅冒烟：循环创建内核、open 真源、收 RESTART、dispose，统计事件与创建/销毁数。
///
/// 跑法：`flutter run -t lib/main_observe_event_verify.dart -d windows --no-enable-impeller`
///
/// 注意：控制组与主循环一律用 `audioOnly` 内核——无 Flutter 画面时反复创建 `VideoController`
/// 会卡死 media_kit（与本方案无关，见计划文档 §10.7）。Android 上媒体路径写死为 app 私有目录
/// `/data/user/0/com.icodejoo.mova.mova_example/files/t.mp4`（需 debug 包 `adb run-as` 推入），
/// 换设备/包名要改 `_run` 里的 `url`。
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MovaMpvKernel.ensureInitialized();
  runApp(const MaterialApp(home: Scaffold(body: Center(child: Text('observe_event verify')))));
  Future<void>.delayed(const Duration(seconds: 1), _run);
}

/// 结果日志文件路径。
final String kLog = Platform.environment['MOVA_LOG'] ?? '';

/// 打印并落盘（release 桌面端 print 不回传）。
void _out(String m) {
  print(m);
  if (kLog.isNotEmpty) File(kLog).writeAsStringSync('$m\n', mode: FileMode.append, flush: true);
}

/// 总轮数。
const int kRounds = 20;

/// 创建计数。
int _created = 0;

/// 销毁计数。
int _destroyed = 0;

/// 包一层后端以统计 create/destroy。
class _CountingBackend implements MovaMpvEventBackend {
  _CountingBackend(this._inner);
  final MovaMpvEventBackend _inner;
  bool _destroyedOnce = false;

  @override
  bool createClient(String name) {
    final ok = _inner.createClient(name);
    if (ok) _created++;
    return ok;
  }

  @override
  bool restrictEvents(Set<int> keep) => _inner.restrictEvents(keep);

  @override
  void armWakeup(void Function() onWake) => _inner.armWakeup(onWake);

  @override
  MovaRawEvent? poll() => _inner.poll();

  @override
  void destroy() {
    if (!_destroyedOnce) {
      _destroyedOnce = true;
      _destroyed++;
    }
    _inner.destroy();
  }
}

/// 探针：绕开 mova，只用 media_kit 的 Player 给各阶段计时，定位慢在哪一步。
Future<void> _probe() async {
  // 纯 media_kit（无 mova 代码）：创建 -> observeProperty -> dispose，连续多轮。
  for (var i = 0; i < 6; i++) {
    final sw = Stopwatch()..start();
    final p = Player();
    final native = p.platform as NativePlayer;
    var obs = 'ok';
    await native.observeProperty('paused-for-cache', (v) async {}).timeout(
        const Duration(seconds: 6), onTimeout: () => obs = 'TIMEOUT');
    final obsMs = sw.elapsedMilliseconds;
    var dis = 'ok';
    await p.dispose().timeout(const Duration(seconds: 6), onTimeout: () => dis = 'TIMEOUT');
    _out('PROBE round=$i observe=$obs@${obsMs}ms dispose=$dis total=${sw.elapsedMilliseconds}ms');
  }
}

/// 对照组：隔离"立即 dispose 卡 5 秒"到底出在 media_kit 还是 pump。
Future<void> _control() async {
  Future<void> one(String tag, MovaMpvKernel Function() make, {int waitMs = 0}) async {
    final k = make();
    if (waitMs > 0) await Future<void>.delayed(Duration(milliseconds: waitMs));
    final t0 = DateTime.now();
    var hung = false;
    await k.dispose().timeout(const Duration(seconds: 8), onTimeout: () => hung = true);
    _out('CONTROL $tag waitMs=$waitMs disposeMs=${DateTime.now().difference(t0).inMilliseconds} hung=$hung');
  }

  await one('A_noQoe_immediate', () => MovaMpvKernel(audioOnly: true, observeQoeSignals: false));
  await one('B_qoe_noFactory_immediate', () => MovaMpvKernel(audioOnly: true, observeQoeSignals: true));
  await one('C_qoe_factory_immediate', () => MovaMpvKernel(
      audioOnly: true,
      observeQoeSignals: true,
      backendFactory: (n, a) => createFfiMpvEventBackend(n, a, pollInDebug: false)));
  await one('E_audioOnly_qoe_factory_immediate', () => MovaMpvKernel(
      audioOnly: true,
      observeQoeSignals: true,
      backendFactory: (n, a) => createFfiMpvEventBackend(n, a, pollInDebug: false)));
  await one('F_audioOnly_qoe_factory_wait2s', waitMs: 2000, () => MovaMpvKernel(
      audioOnly: true,
      observeQoeSignals: true,
      backendFactory: (n, a) => createFfiMpvEventBackend(n, a, pollInDebug: false)));
  await one('D_qoe_factory_wait2s', waitMs: 2000, () => MovaMpvKernel(
      audioOnly: true,
      observeQoeSignals: true,
      backendFactory: (n, a) => createFfiMpvEventBackend(n, a, pollInDebug: false)));
}

/// 主流程。
Future<void> _run() async {
  _out('START');
  var last = DateTime.now();
  Timer.periodic(const Duration(milliseconds: 50), (_) {
    final now = DateTime.now();
    final gap = now.difference(last).inMilliseconds;
    if (gap > 200) _out('HEARTBEAT gap=${gap}ms');
    last = now;
  });
  await _probe();
  await _control();
  _out('CONTROL_DONE');
  final sw = Stopwatch()..start();
  var totalRestarts = 0;
  var totalEnds = 0;
  final firstRestartMs = <int>[];
  for (var i = 0; i < kRounds; i++) {
    final kernel = MovaMpvKernel(
      audioOnly: true,
      observeQoeSignals: true,
      backendFactory: (native, addr) => _CountingBackend(
        createFfiMpvEventBackend(native, addr, pollInDebug: false),
      ),
    );
    var restarts = 0;
    final reasons = <Object>[];
    int? firstAt;
    final openAt = sw.elapsedMilliseconds;
    final s1 = kernel.playbackRestarts.listen((_) {
      restarts++;
      firstAt ??= sw.elapsedMilliseconds - openAt;
    });
    final s2 = kernel.endFiles.listen(reasons.add);
    if (i % 3 == 0) {
      // 刚构造即 dispose
    } else {
      final url = '/data/user/0/com.icodejoo.mova.mova_example/files/t.mp4';
      unawaited(kernel.open(url));
      await Future<void>.delayed(Duration(milliseconds: i % 3 == 1 ? 3000 : 300));
      if (i % 3 == 2) {
        unawaited(kernel.seek(const Duration(seconds: 1)));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }
    final t0 = sw.elapsedMilliseconds;
    await kernel.dispose();
    final disposeMs = sw.elapsedMilliseconds - t0;
    await s1.cancel();
    await s2.cancel();
    totalRestarts += restarts;
    totalEnds += reasons.length;
    if (firstAt != null) firstRestartMs.add(firstAt!);
    _out('ROUND $i restarts=$restarts firstRestartMs=$firstAt endFiles=$reasons disposeMs=$disposeMs '
        'rssMiB=${(ProcessInfo.currentRss / 1048576).toStringAsFixed(1)}');
  }
  _out('SUMMARY rounds=$kRounds restarts=$totalRestarts endFiles=$totalEnds '
      'created=$_created destroyed=$_destroyed firstRestartMs=$firstRestartMs');
  _out(_created == _destroyed ? 'RESULT PASS created==destroyed' : 'RESULT FAIL leak');
  await Future<void>.delayed(const Duration(seconds: 6)); // 覆盖 media_kit 5s 延迟销毁窗口
  _out('ALIVE_AFTER_6S');
  exit(0);
}
