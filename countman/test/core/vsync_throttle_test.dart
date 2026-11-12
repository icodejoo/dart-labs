// ignore_for_file: invalid_use_of_internal_member

import 'package:countman/countman.dart';
import 'package:countman/src/core/fps.dart';
import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_test/flutter_test.dart';

import '../support/manual_clock.dart';
import '../support/vsync_simulator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ManualCountmanClock clock;
  setUp(() => clock = installManualClock());
  tearDown(() {
    Countman.destroy();
    Countman.fps = null;
    debugRefreshRateHz = null;
  });

  /// 同一套量化与抖动模拟分别验证两种引擎，每个任务都必须达到目标节拍。
  void check(double hz, double target, int jitter, int tasks, bool countdown) {
    final engine = countdown ? 'Countdown' : 'Counter';
    final label = '$engine fps=$target hz=$hz tasks=$tasks jitter=$jitter';
    testWidgets(label, (t) async {
      debugRefreshRateHz = hz;
      final updates = List<int>.filled(tasks, 0);
      if (countdown) {
        final plugin = Countdown(name: 'vsync-cd', interval: 0, clock: clock);
        for (var i = 0; i < tasks; i++) {
          plugin.add(CountdownOptions(
            duration: const Duration(minutes: 5),
            fps: target,
            onUpdate: (_) => updates[i]++,
          ));
        }
      } else {
        for (var i = 0; i < tasks; i++) {
          counter(CounterOptions(
            to: 1e9,
            fps: target,
            curve: Curves.linear,
            duration: const Duration(minutes: 5),
            onUpdate: (_) => updates[i]++,
          ));
        }
      }
      await t.pump();
      final stats = await simulateVsync(t, clock, () => updates.first,
          hz: hz, jitterMicros: jitter);
      final margin = target == 50 ? 3.0 : 1.0;
      expect(stats.updatesPerSecond,
          inInclusiveRange(target - margin, target + margin),
          reason: '$label $stats');
      expect(stats.fps, lessThanOrEqualTo(stats.updatesPerSecond + 1.5),
          reason: '$label $stats');
      // 每个任务同相位加入，确保多任务统计没有被平均数掩盖。
      expect(updates, everyElement(updates.first), reason: label);
      if (target == hz) {
        expect(stats.fps, inInclusiveRange(hz - 1, hz + 1),
            reason: '达到屏幕刷新率应等同不限帧：$stats');
      }
      // 保留验收数字，断言同时约束更新频率和空轮询帧。
      debugPrint('VSYNC $label $stats');
      Countman.destroy();
    });
  }

  for (final hz in [60.0, 120.0]) {
    for (final target in [30.0, 20.0, if (hz == 120) 60.0]) {
      for (final jitter in [0, 1500]) {
        for (final tasks in [1, 50]) {
          for (final countdown in [false, true]) {
            check(hz, target, jitter, tasks, countdown);
          }
        }
      }
    }
  }
  for (final target in [50.0, 60.0]) {
    for (final jitter in [0, 1500]) {
      for (final countdown in [false, true]) {
        check(60, target, jitter, 1, countdown);
      }
    }
  }
}
