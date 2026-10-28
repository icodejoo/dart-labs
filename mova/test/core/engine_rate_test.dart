import 'package:flutter_test/flutter_test.dart';
import 'package:mova/src/core/engine.dart';
import 'package:mova/src/core/events/events.dart';

import '../support/fake_kernel.dart';

/// `setRate` contract: clamped to 0.25–4.0 (NaN becomes 1.0), and kernel, state
/// and event all see the same value.
///
/// `setRate` 契约：钳到 0.25–4.0（NaN 当 1.0），内核、state、事件看到同一个值。
void main() {
  late FakeKernel k;
  late MovaEngine e;
  late List<MovaEvent> events;

  setUp(() {
    k = FakeKernel();
    e = MovaEngine(kernel: k);
    events = <MovaEvent>[];
    e.events.listen(events.add);
  });

  tearDown(() => e.dispose());

  /// The rate values carried by every `MovaRateChange` seen so far.
  ///
  /// 目前收到的所有 `MovaRateChange` 载荷。
  Future<List<double>> rateEvents() async {
    await Future<void>.delayed(Duration.zero);
    return events.whereType<MovaRateChange>().map((x) => x.value).toList();
  }

  group('MovaEngine.setRate', () {
    test('forwards an in-range rate to the kernel, state and one event', () async {
      await e.setRate(1.5);
      expect(k.calls, contains('setRate'));
      expect(k.lastRate, 1.5);
      expect(e.state.rate, 1.5);
      expect(await rateEvents(), [1.5]);
    });

    test('clamps above the upper bound to 4.0 in state and event', () async {
      await e.setRate(10);
      expect(k.lastRate, 4.0);
      expect(e.state.rate, 4.0);
      expect(await rateEvents(), [4.0]);
    });

    test('clamps below the lower bound (0, negative) to 0.25', () async {
      await e.setRate(0);
      expect(k.lastRate, 0.25);
      expect(e.state.rate, 0.25);
      await e.setRate(-3);
      expect(e.state.rate, 0.25);
      expect(await rateEvents(), [0.25, 0.25]);
    });

    test('treats NaN as 1.0', () async {
      await e.setRate(2);
      await e.setRate(double.nan);
      expect(k.lastRate, 1.0);
      expect(e.state.rate, 1.0);
      expect((await rateEvents()).last, 1.0);
    });

    test('keeps the exact bounds', () async {
      await e.setRate(0.25);
      expect(e.state.rate, 0.25);
      await e.setRate(4.0);
      expect(e.state.rate, 4.0);
    });
  });
}
