// ignore_for_file: avoid_print, implementation_imports
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:mova/src/core/kernel/mpv_kernel.dart';

/// 验证"无 Flutter 画面时反复创建 VideoController 会卡死 media_kit"在 Windows 上是否同样成立。
///
/// 两组各连续创建/销毁 [kRounds] 次 `MovaMpvKernel`（不开 QoE、不带 pump，排除本方案）：
/// A 组 audioOnly（无 VideoController），B 组默认（带 VideoController，但页面只有一个 Text）。
/// 跑法：`MOVA_LOG=<文件> mova_example.exe`（release 桌面端 print 不回传，靠落盘）。
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MovaMpvKernel.ensureInitialized();
  runApp(const MaterialApp(home: Scaffold(body: Center(child: Text('dispose hang verify')))));
  Future<void>.delayed(const Duration(seconds: 1), _run);
}

/// 每组轮数。
const int kRounds = 6;

/// 单次 dispose 超时。
const Duration kTimeout = Duration(seconds: 8);

/// 结果日志文件路径。
final String kLog = Platform.environment['MOVA_LOG'] ?? '';

/// 打印并落盘。
void _out(String m) {
  print(m);
  if (kLog.isNotEmpty) {
    File(kLog).writeAsStringSync('$m\n', mode: FileMode.append, flush: true);
  }
}

/// 跑一组：返回超时次数。
Future<int> _group(String tag, {required bool audioOnly}) async {
  var hung = 0;
  for (var i = 0; i < kRounds; i++) {
    final k = MovaMpvKernel(audioOnly: audioOnly, observeQoeSignals: false);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final sw = Stopwatch()..start();
    var timedOut = false;
    await k.dispose().timeout(kTimeout, onTimeout: () => timedOut = true);
    if (timedOut) hung++;
    _out('$tag round=$i disposeMs=${sw.elapsedMilliseconds} hung=$timedOut');
  }
  return hung;
}

/// 主流程。
Future<void> _run() async {
  _out('START');
  final a = await _group('A_audioOnly', audioOnly: true);
  final b = await _group('B_withVideoController', audioOnly: false);
  _out('RESULT audioOnlyHung=$a withVideoControllerHung=$b');
  _out('ALL_DONE');
}
