import 'dart:math' as math;

import 'package:countman/countman.dart';
import 'package:flutter_test/flutter_test.dart';

/// 一次 vsync 模拟的统计结果。
class VsyncStats {
  VsyncStats(this.frames, this.updates, this.seconds);

  /// 引擎实际出帧数（有排帧请求且到达 vsync 边界）。
  final int frames;

  /// 用户 onUpdate 的投递次数。
  final int updates;

  /// 模拟时长（秒）。
  final int seconds;

  /// 每秒出帧数。
  double get fps => frames / seconds;

  /// 每秒显示更新数。
  double get updatesPerSecond => updates / seconds;

  @override
  String toString() =>
      'frames/s=${fps.toStringAsFixed(1)} updates/s=${updatesPerSecond.toStringAsFixed(1)}';
}

/// 模拟真实 vsync：假时钟每 1ms 前进；只有存在排帧请求，且到达 vsync 边界才出帧。
/// 与固定步长 pump 不同，休眠 Timer 到点后必须再等下一个 vsync 才能渲染。
Future<VsyncStats> simulateVsync(
  WidgetTester t,
  ManualCountmanClock clock,
  int Function() updates, {
  int seconds = 5,
  double hz = 60,
  int jitterMicros = 0,
}) async {
  final vsyncMicros = (1000000 / hz).round();
  final random = math.Random(7);
  // 抖动只扰动单次边界，不累积漂移。
  int jitter() => jitterMicros == 0
      ? 0
      : random.nextInt(jitterMicros * 2 + 1) - jitterMicros;
  var grid = vsyncMicros;
  var nextVsync = grid + jitter();
  var frames = 0;
  final start = updates();
  for (var micros = 1000; micros <= seconds * 1000000; micros += 1000) {
    clock.advance(const Duration(milliseconds: 1));
    await t.binding.delayed(const Duration(milliseconds: 1));
    if (micros >= nextVsync) {
      grid += vsyncMicros;
      nextVsync = grid + jitter();
      if (t.binding.hasScheduledFrame) {
        frames++;
        await t.pump();
      }
    }
  }
  return VsyncStats(frames, updates() - start, seconds);
}
