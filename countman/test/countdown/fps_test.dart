// ignore_for_file: invalid_use_of_internal_member

import 'package:countman/countman.dart';
import 'package:countman/src/core/fps.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/manual_clock.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ManualCountmanClock clock;
  setUp(() { clock = installManualClock(); debugRefreshRateHz = 60; });
  tearDown(() { Countman.destroy(); Countman.fps = null; debugRefreshRateHz = null; });

  testWidgets('interval 0 / fps 10：约十次显示，终点精确', (t) async {
    final plugin = Countdown(interval: 0, fps: 10);
    var updates = 0;
    var last = -1;
    var completeAt = -1;
    plugin.add(CountdownOptions(duration: const Duration(seconds: 1),
      onUpdate: (p) { updates++; last = p.inMicroseconds; },
      onComplete: () => completeAt = clock.monotonicMicros()));
    await t.pump();
    for (var i = 0; i < 62; i++) {
      clock.advance(const Duration(milliseconds: 16));
      await t.pump(const Duration(milliseconds: 16));
    }
    clock.advance(const Duration(milliseconds: 8));
    await t.pump(const Duration(milliseconds: 8));
    expect(updates, inInclusiveRange(9, 12));
    expect(last, 0);
    expect(completeAt, 1000000);
  });

  test('阈值与完成比下一显示帧更早，均按真实微秒触发', () {
    final plugin = Countdown(interval: 0, fps: 1)
      ..onAttach(CountmanContext(requestFrame: () {}));
    addTearDown(plugin.dispose);
    var thresholdAt = -1;
    var completeAt = -1;
    final values = <int>[];
    plugin.add(CountdownOptions(duration: const Duration(microseconds: 750001),
      threshold: const Duration(microseconds: 375000),
      onThreshold: () => thresholdAt = clock.monotonicMicros(),
      onComplete: () => completeAt = clock.monotonicMicros(),
      onUpdate: (p) => values.add(p.inMicroseconds)));
    expect(plugin.tick(Duration.zero, Duration.zero), 375001);
    clock.advance(const Duration(microseconds: 375001));
    expect(plugin.tick(Duration.zero, Duration.zero), 375000);
    expect(thresholdAt, 375001);
    expect(values, [750001]);
    clock.advance(const Duration(microseconds: 375000));
    plugin.tick(Duration.zero, Duration.zero);
    expect(completeAt, 750001);
    expect(values, [750001, 0]);
  });

  test('高频桶取桶边界与限帧时刻的较晚者；低频桶维持原节拍', () {
    for (final interval in [10, 1000]) {
      final plugin = Countdown(interval: interval, fps: 10)
        ..onAttach(CountmanContext(requestFrame: () {}));
      addTearDown(plugin.dispose);
      plugin.add(const CountdownOptions(duration: Duration(seconds: 3)));
      expect(plugin.tick(Duration.zero, Duration.zero), 91667);
      clock.advance(const Duration(milliseconds: 100));
      final wake = plugin.tick(Duration.zero, Duration.zero);
      expect(wake, interval == 10 ? 91667 : 900001);
    }
  });

  test('半个 vsync 容差不提前显示桶、阈值或完成', () {
    final plugin = Countdown(interval: 1000, fps: 30)
      ..onAttach(CountmanContext(requestFrame: () {}));
    addTearDown(plugin.dispose);
    final values = <int>[];
    var thresholdAt = -1;
    var completeAt = -1;
    plugin.add(CountdownOptions(
      duration: const Duration(seconds: 2),
      rounding: CountdownRounding.ceil,
      threshold: const Duration(seconds: 1),
      onThreshold: () => thresholdAt = clock.monotonicMicros(),
      onComplete: () => completeAt = clock.monotonicMicros(),
      onUpdate: (p) => values.add(p.inMicroseconds),
    ));
    expect(plugin.tick(Duration.zero, Duration.zero), 1000000);
    clock.advance(const Duration(microseconds: 999999));
    expect(plugin.tick(Duration.zero, Duration.zero), 1);
    expect(values, [2000000]);
    expect(thresholdAt, -1);
    clock.advance(const Duration(microseconds: 1));
    expect(plugin.tick(Duration.zero, Duration.zero), 1000000);
    expect(values, [2000000, 1000000]);
    expect(thresholdAt, 1000000);
    clock.advance(const Duration(microseconds: 999999));
    expect(plugin.tick(Duration.zero, Duration.zero), 1);
    expect(values, [2000000, 1000000]);
    expect(completeAt, -1);
    clock.advance(const Duration(microseconds: 1));
    plugin.tick(Duration.zero, Duration.zero);
    expect(values, [2000000, 1000000, 0]);
    expect(completeAt, 2000000);
  });

  test('静音无视上限，只唤醒事件，恢复同桶立即更新', () {
    final plugin = Countdown(interval: 0, fps: 0.1)
      ..onAttach(CountmanContext(requestFrame: () {}));
    addTearDown(plugin.dispose);
    final values = <int>[];
    final h = plugin.add(CountdownOptions(duration: const Duration(seconds: 3),
      onUpdate: (p) => values.add(p.inMilliseconds)));
    plugin.tick(Duration.zero, Duration.zero);
    h.muted = true;
    expect(plugin.tick(Duration.zero, Duration.zero), 3000000);
    clock.advance(const Duration(milliseconds: 250));
    h.muted = false;
    plugin.tick(Duration.zero, Duration.zero);
    expect(values, [3000, 2750]);
  });
}
