// ignore_for_file: avoid_print, implementation_imports
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:mova/src/core/kernel/mpv_event_backend.dart';
import 'package:mova/src/core/kernel/mpv_kernel.dart';
import 'package:mova/src/platform_impl/mpv_event_backend_ffi.dart';

/// 弱客户端事件订阅第二轮验证（V3/V5/V6/V7/V9），全部用 audioOnly 内核
/// （无 UI 下创建 VideoController 会卡死 media_kit，见计划文档附录）。
///
/// 跑法：`flutter run --release -t lib/main_observe_event_verify2.dart --dart-define=MODE=all`
/// `MODE=leak_qoe|leak_ctrl` 只跑 V5 循环，配合外部 `dumpsys meminfo` 采样。
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MovaMpvKernel.ensureInitialized();
  runApp(const MaterialApp(home: Scaffold(body: Center(child: Text('observe_event verify2')))));
  Future<void>.delayed(const Duration(seconds: 1), _run);
}

/// 运行模式。
const String kMode = String.fromEnvironment('MODE', defaultValue: 'all');

/// 测试媒体：默认是 Android app 私有目录（adb run-as 推入），其它平台用 `--dart-define=MEDIA=<路径>` 覆盖。
const String kMedia = String.fromEnvironment('MEDIA',
    defaultValue: '/data/user/0/com.icodejoo.mova.mova_example/files/t.mp4');

/// 泄漏循环轮数。
const int kLeakRounds = 120;

/// 创建计数。
int _created = 0;

/// 销毁计数。
int _destroyed = 0;

/// 主线程最大帧间隔（心跳）。
int _maxGap = 0;

/// 结果日志文件路径（release 桌面端 print 不回传，靠它落盘）。
final String kLog = Platform.environment['MOVA_LOG'] ?? '';

/// 输出一行（logcat 可见；设了 `MOVA_LOG` 时同时落盘）。
void _out(String m) {
  print(m);
  if (kLog.isNotEmpty) File(kLog).writeAsStringSync('$m\n', mode: FileMode.append, flush: true);
}

/// 包一层后端以统计 create/destroy。
class _CountingBackend implements MovaMpvEventBackend {
  _CountingBackend(this._inner);
  final MovaMpvEventBackend _inner;
  bool _done = false;

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
    if (!_done) {
      _done = true;
      _destroyed++;
    }
    _inner.destroy();
  }
}

/// 构造带（或不带）事件订阅的音频内核。
MovaMpvKernel _make({required bool qoe, bool counting = true}) => MovaMpvKernel(
      audioOnly: true,
      observeQoeSignals: qoe,
      backendFactory: (n, a) {
        final b = createFfiMpvEventBackend(n, a, pollInDebug: false);
        return counting ? _CountingBackend(b) : b;
      },
    );

/// 给流计数，返回取消函数与计数读取。
class _Counter<T> {
  _Counter(Stream<T> s) {
    _sub = s.listen((_) => n++);
  }
  late final StreamSubscription<T> _sub;
  int n = 0;
  Future<void> cancel() => _sub.cancel();
}

/// V3：同一内核并行读取 position/playing/buffering 流与本方案事件，对比无订阅对照组。
Future<void> _v3() async {
  Future<Map<String, int>> one(bool qoe) async {
    final k = _make(qoe: qoe);
    final pos = _Counter(k.position);
    final ply = _Counter(k.playing);
    final buf = _Counter(k.buffering);
    final rst = _Counter(k.playbackRestarts);
    await k.open(kMedia);
    await Future<void>.delayed(const Duration(seconds: 3));
    await k.pause();
    await Future<void>.delayed(const Duration(milliseconds: 500));
    await k.play();
    await Future<void>.delayed(const Duration(seconds: 1));
    await k.seek(const Duration(seconds: 10));
    await Future<void>.delayed(const Duration(seconds: 2));
    final r = {'position': pos.n, 'playing': ply.n, 'buffering': buf.n, 'restarts': rst.n};
    await pos.cancel();
    await ply.cancel();
    await buf.cancel();
    await rst.cancel();
    await k.dispose();
    return r;
  }

  final a = await one(false);
  final b = await one(true);
  _out('V3 control(no qoe)=$a');
  _out('V3 qoe=$b');
  final ok = (a['position']! - b['position']!).abs() <= 3 &&
      a['playing'] == b['playing'] &&
      (a['buffering']! - b['buffering']!).abs() <= 1 &&
      b['restarts']! >= 2;
  _out(ok ? 'V3 PASS' : 'V3 FAIL');
}

/// V6：三个引擎并存，单独 dispose 其一，其余仍能收到事件且无串扰。
Future<void> _v6() async {
  final ks = [for (var i = 0; i < 3; i++) _make(qoe: true)];
  final rc = [for (final k in ks) _Counter(k.playbackRestarts)];
  for (final k in ks) {
    await k.open(kMedia);
  }
  await Future<void>.delayed(const Duration(seconds: 2));
  final before = [for (final c in rc) c.n];
  await rc[1].cancel();
  await ks[1].dispose();
  await ks[0].seek(const Duration(seconds: 5));
  await ks[2].seek(const Duration(seconds: 6));
  await Future<void>.delayed(const Duration(seconds: 2));
  final after = [for (final c in rc) c.n];
  _out('V6 restartsBefore=$before after=$after');
  final ok = after[0] > before[0] && after[2] > before[2] && before.every((n) => n >= 1);
  for (final i in [0, 2]) {
    await rc[i].cancel();
    await ks[i].dispose();
  }
  _out(ok ? 'V6 PASS' : 'V6 FAIL');
}

/// V7：dispose 期间主线程不被拖住——统计 dispose 窗口内的最大帧间隔；
/// [qoe] 为 false 是不建弱客户端的对照组（区分 media_kit 自身开销与本方案开销）。
Future<int> _v7Once(bool qoe) async {
  var worst = 0;
  for (var i = 0; i < 10; i++) {
    final k = _make(qoe: qoe);
    await k.open(kMedia);
    await Future<void>.delayed(const Duration(milliseconds: 800));
    _maxGap = 0;
    await k.dispose();
    // 再观察 6s，覆盖 media_kit 5s 后的 mpv_terminate_destroy。
    await Future<void>.delayed(const Duration(seconds: 6));
    if (_maxGap > worst) worst = _maxGap;
  }
  return worst;
}

/// V7：对比开/关订阅两组的最大帧间隔，判据为"开组不比对照组明显更差"且小于 100ms 或与对照持平。
Future<void> _v7() async {
  final ctrl = await _v7Once(false);
  final on = await _v7Once(true);
  _out('V7 worstFrameGapMs qoeOff(control)=$ctrl qoeOn=$on');
  _out(on < 100 || on <= ctrl + 30 ? 'V7 PASS' : 'V7 FAIL');
}

/// V9：关闭态不创建任何客户端。
Future<void> _v9() async {
  final before = _created;
  final k = _make(qoe: false);
  await k.open(kMedia);
  await Future<void>.delayed(const Duration(seconds: 2));
  await k.dispose();
  final made = _created - before;
  _out('V9 clientsCreatedWhenQoeOff=$made');
  _out(made == 0 ? 'V9 PASS' : 'V9 FAIL');
}

/// V5：create/open/dispose 循环，外部采样 meminfo；qoe=false 为对照组。
Future<void> _leak(bool qoe) async {
  for (var i = 0; i < kLeakRounds; i++) {
    final k = _make(qoe: qoe);
    await k.open(kMedia);
    await Future<void>.delayed(Duration(milliseconds: [0, 10, 50, 200][i % 4] + 300));
    if (i % 3 == 0) unawaited(k.seek(const Duration(seconds: 2)));
    await k.dispose();
    if (i % 10 == 0) _out('LEAK round=$i qoe=$qoe created=$_created destroyed=$_destroyed');
  }
  _out('LEAK DONE qoe=$qoe created=$_created destroyed=$_destroyed');
  await Future<void>.delayed(const Duration(seconds: 8));
  _out('LEAK SETTLED qoe=$qoe');
}

/// 主流程。
Future<void> _run() async {
  _out('START mode=$kMode media=${File(kMedia).existsSync()}');
  var last = DateTime.now();
  Timer.periodic(const Duration(milliseconds: 20), (_) {
    final now = DateTime.now();
    final g = now.difference(last).inMilliseconds;
    if (g > _maxGap) _maxGap = g;
    last = now;
  });
  if (kMode == 'all') {
    await _v3();
    await _v6();
    await _v9();
    await _v7();
    _out('COUNTS created=$_created destroyed=$_destroyed ${_created == _destroyed ? "PASS" : "FAIL"}');
  } else {
    await _leak(kMode == 'leak_qoe');
  }
  _out('ALL_DONE');
}
