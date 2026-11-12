// ignore_for_file: invalid_use_of_internal_member

import 'package:countman/countman.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/manual_clock.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() { Countman.destroy(); Countman.fps = null; });

  testWidgets('Elapsed 限帧显示、阈值准时、limit 强刷终点', (t) async {
    final clock = installManualClock();
    final plugin = Elapsed(interval: 0, fps: 10);
    var updates = 0;
    var value = -1;
    var thresholdAt = -1;
    var completeAt = -1;
    plugin.add(ElapsedOptions(limit: const Duration(seconds: 1),
      threshold: const Duration(milliseconds: 350),
      onThreshold: () => thresholdAt = clock.monotonicMicros(),
      onComplete: () => completeAt = clock.monotonicMicros(),
      onUpdate: (p) { updates++; value = p.inMicroseconds; }));
    await t.pump();
    for (var i = 0; i < 10; i++) {
      if (i == 3) {
        clock.advance(const Duration(milliseconds: 50));
        await t.pump(const Duration(milliseconds: 50));
        expect(thresholdAt, 350000);
        clock.advance(const Duration(milliseconds: 50));
        await t.pump(const Duration(milliseconds: 50));
      } else {
        clock.advance(const Duration(milliseconds: 100));
        await t.pump(const Duration(milliseconds: 100));
      }
    }
    expect(updates, inInclusiveRange(9, 12));
    expect(value, 1000000);
    expect(thresholdAt, 350000);
    expect(completeAt, 1000000);
  });

  test('Elapsed nextWake 保留早于显示的精确阈值与完成', () {
    final clock = installManualClock();
    final plugin = Elapsed(interval: 0, fps: 1)
      ..onAttach(CountmanContext(requestFrame: () {}));
    addTearDown(plugin.dispose);
    var thresholdAt = -1;
    var completeAt = -1;
    plugin.add(ElapsedOptions(limit: const Duration(microseconds: 700003),
      threshold: const Duration(microseconds: 350001),
      onThreshold: () => thresholdAt = clock.monotonicMicros(),
      onComplete: () => completeAt = clock.monotonicMicros()));
    expect(plugin.tick(Duration.zero, Duration.zero), 350001);
    clock.advance(const Duration(microseconds: 350001));
    expect(plugin.tick(Duration.zero, Duration.zero), 350002);
    expect(thresholdAt, 350001);
    clock.advance(const Duration(microseconds: 350002));
    plugin.tick(Duration.zero, Duration.zero);
    expect(completeAt, 700003);
  });
}
