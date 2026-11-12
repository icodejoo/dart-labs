import 'package:flutter_test/flutter_test.dart';
import 'package:luckdraw/wheel.dart';

import '../../grid/grid_state_harness.dart';
import '../../lots/state_machine_adapter.dart';
import '../../number_wheel/state_machine_adapter.dart';
import '../../support/capsule_fixtures.dart';
import '../../support/lotto_fixtures.dart';
import '../../support/slot_fixtures.dart';
import '../../wheel/wheel_test_support.dart';

/// 尚未落地玩法的状态机测试适配器，占位由对应控制器任务卡替换。
final class _Harness {
  /// 保存目标玩法，后续填入对应控制器和手动时钟。
  _Harness(this.game);

  /// 目标玩法。
  final String game;

  /// 验证已落地转盘的真实迁移边，其余玩法保持跳过。
  Future<void> verifyEdge(String edge) async {
    if (game == 'lotto') {
      verifyLottoEdge(edge);
      return;
    }
    if (game != 'wheel') throw UnimplementedError('$game $edge 等待玩法实现');
    final host = WheelTestHost();
    final controller = wheelTestController(host,
        picker: edge == 'E15'
            ? const WheelNullPicker()
            : const WeightedPrizePicker());

    /// 开始并推进到匀速。
    void cruise() {
      expect(controller.play(), isTrue);
      wheelAdvanceTo(controller, host.clock, LuckyPhase.cruising);
    }

    /// 从空闲开始一局并完成结算。
    void settle() {
      cruise();
      expect(controller.stop(2), isTrue);
      wheelAdvanceTo(controller, host.clock, LuckyPhase.settled);
    }

    switch (edge) {
      case 'E01':
        expect(controller.phase.value, LuckyPhase.idle);
        expect(controller.play(), isTrue);
        expect(controller.phase.value, LuckyPhase.accelerating);
        expect(host.starts, 1);
      case 'E02':
        settle();
        expect(controller.play(), isTrue);
        expect(controller.phase.value, LuckyPhase.accelerating);
        expect(host.starts, 2);
      case 'E03':
        controller.idleSpin();
        host.clock.advanceFrames(2);
        final angle = controller.rotateDeg;
        expect(controller.play(), isTrue);
        host.clock.advanceFrames(1);
        expect(controller.phase.value, LuckyPhase.accelerating);
        expect(controller.rotateDeg - angle, closeTo(1.92, 1e-12));
      case 'E04':
        expect(controller.idleSpin(), isTrue);
        expect(controller.phase.value, LuckyPhase.idleSpinning);
        expect(host.clock.isTicking, isTrue);
      case 'E05':
        settle();
        expect(controller.idleSpin(), isTrue);
        expect(controller.phase.value, LuckyPhase.idleSpinning);
      case 'E06':
        controller.idleSpin();
        expect(controller.cancel(), isTrue);
        expect(controller.phase.value, LuckyPhase.idle);
        expect(host.results, isEmpty);
      case 'E07':
        cruise();
        expect(host.phases, [LuckyPhase.accelerating, LuckyPhase.cruising]);
      case 'E08':
        controller.play();
        expect(controller.stop(2), isTrue);
        expect(controller.phase.value, LuckyPhase.accelerating);
        host.clock.advanceFrames(2);
        expect(controller.phase.value, LuckyPhase.accelerating);
        expect(controller.frame.targetIndex, 2);
      case 'E09':
        controller.play();
        controller.stop(2);
        host.clock.advanceFrames(4);
        expect(controller.phase.value, LuckyPhase.accelerating);
        host.clock.advanceFrames(1);
        // FIDELITY §5.3 / 上游 step=2 直接走匀速分支并置 step=3；
        // 卡名所谓“一帧 cruising”与该路径矛盾，保留上游和卡名并登记差异。
        expect(controller.phase.value, LuckyPhase.decelerating);
        expect(host.phases, [LuckyPhase.accelerating, LuckyPhase.decelerating]);
      case 'E10':
        cruise();
        expect(controller.stop(2), isTrue);
        expect(controller.phase.value, LuckyPhase.cruising);
        host.clock.advanceFrames(1);
        expect(controller.phase.value, LuckyPhase.decelerating);
      case 'E11':
        settle();
        expect(host.results.single.index, 2);
        expect(host.results.single.cancelled, isFalse);
      case 'E12':
        controller.play();
        expect(controller.cancel(), isTrue);
        expect(controller.phase.value, LuckyPhase.idle);
        expect(host.results.single.cancelled, isTrue);
      case 'E13':
        cruise();
        expect(controller.cancel(), isTrue);
        expect(controller.phase.value, LuckyPhase.idle);
        expect(host.results.single.cancelled, isTrue);
      case 'E14':
        cruise();
        expect(controller.stop(-1), isTrue);
        expect(controller.phase.value, LuckyPhase.idle);
        expect(host.results.single.cancelled, isTrue);
      case 'E15':
        cruise();
        expect(controller.stop(), isTrue);
        expect(controller.phase.value, LuckyPhase.idle);
        expect(host.results.single.cancelled, isTrue);
      case 'E16':
        cruise();
        controller.stop(2);
        wheelAdvanceTo(controller, host.clock, LuckyPhase.decelerating);
        expect(controller.stop(3), isFalse);
        expect(controller.cancel(), isFalse);
        expect(controller.phase.value, LuckyPhase.decelerating);
        expect(host.results, isEmpty);
      case 'E17':
        expect(controller.stop(2), isFalse);
        settle();
        expect(controller.stop(2), isFalse);
        expect(controller.phase.value, LuckyPhase.settled);
      case 'E18':
        controller.play();
        expect(controller.play(), isFalse);
        wheelAdvanceTo(controller, host.clock, LuckyPhase.cruising);
        expect(controller.play(), isFalse);
        controller.stop(2);
        wheelAdvanceTo(controller, host.clock, LuckyPhase.decelerating);
        expect(controller.play(), isFalse);
        expect(host.starts, 1);
      case 'E19':
        cruise();
        final angle = controller.rotateDeg;
        expect(controller.pause(), isTrue);
        host.clock.advance(const Duration(minutes: 10));
        expect(controller.rotateDeg, angle);
        expect(controller.resume(), isTrue);
        host.clock.advanceFrames(1);
        expect(controller.rotateDeg, angle);
        host.clock.advanceFrames(1);
        expect(controller.rotateDeg, closeTo(angle + 19.2, 1e-12));
      case 'E20':
        for (final phase in LuckyPhase.values) {
          controller.reset();
          if (phase == LuckyPhase.idleSpinning) {
            controller.idleSpin();
          } else if (phase == LuckyPhase.settled) {
            settle();
          } else if (phase != LuckyPhase.idle) {
            controller.play();
            if (phase != LuckyPhase.accelerating) {
              wheelAdvanceTo(controller, host.clock, LuckyPhase.cruising);
              if (phase == LuckyPhase.decelerating) {
                controller.stop(2);
                wheelAdvanceTo(controller, host.clock, phase);
              }
            }
          }
          expect(controller.phase.value, phase);
          controller.reset();
          expect(controller.phase.value, LuckyPhase.idle);
          expect(controller.rotateDeg, 0);
          expect(controller.frame.targetIndex, -1);
        }
      case 'E21':
        final pending = controller.playUntil(() => 2);
        final count = host.phases.length;
        controller.dispose();
        host.clock.advanceFrames(100);
        expect((await pending).cancelled, isTrue);
        expect(host.phases.length, count);
        expect(host.results, isEmpty);
        expect(host.clock.isTicking, isFalse);
      case 'E22':
        controller.idleSpin();
        expect(controller.stop(2), isFalse);
        expect(controller.phase.value, LuckyPhase.idleSpinning);
      case 'E23':
        for (var i = 0; i < 100; i++) {
          settle();
        }
        expect(host.results.length, 100);
        expect(host.results.every((r) => r.index == 2), isTrue);
      case 'E24':
        cruise();
        expect(controller.stop(), isTrue);
        expect(controller.phase.value, LuckyPhase.cruising);
        wheelAdvanceTo(controller, host.clock, LuckyPhase.decelerating);
        wheelAdvanceTo(controller, host.clock, LuckyPhase.settled);
        expect(host.results.single.index, 2);
      case 'E26':
        expect(controller.pause(), isFalse);
        settle();
        expect(controller.pause(), isFalse);
        expect(controller.phase.value, LuckyPhase.settled);
    }
  }
}

/// 每种玩法独立的夹具工厂，禁止提前导入尚未实现的玩法。
final Map<String, _Harness Function()> _factories = {
  'wheel': () => _Harness('wheel'),
  'grid': () => _Harness('grid'),
  'slot': () => _Harness('slot'),
  'capsule': () => _Harness('capsule'),
  'lots': () => _Harness('lots'),
  'lotto': () => _Harness('lotto'),
  'numberWheel': () => _Harness('numberWheel'),
};

/// 按 T0.6 建立迁移边骨架；对应玩法卡完成后解除 skip 并登记矩阵。
void main() {
  group('state machine', () {
    test('lotto E01 idle play() -> accelerating and returns true',
        () => _factories['lotto']!().verifyEdge('E01'));
    test('lotto E02 settled play() -> accelerating and returns true',
        () => _factories['lotto']!().verifyEdge('E02'));
    test('lotto E03 idleSpinning play() -> accelerating from idle speed',
        () => _factories['lotto']!().verifyEdge('E03'));
    test('lotto E04 idle idleSpin() -> idleSpinning',
        () => _factories['lotto']!().verifyEdge('E04'));
    test('lotto E05 settled idleSpin() -> idleSpinning',
        () => _factories['lotto']!().verifyEdge('E05'));
    test('lotto E06 idleSpinning cancel() -> idle without end callback',
        () => _factories['lotto']!().verifyEdge('E06'));
    test('lotto E07 accelerating past accelerationTime -> cruising',
        () => _factories['lotto']!().verifyEdge('E07'));
    test('lotto E08 accelerating stop(i) stays accelerating with stop pending',
        () => _factories['lotto']!().verifyEdge('E08'));
    test(
        'lotto E09 pending stop at end of acceleration -> cruising one tick -> decelerating',
        () => _factories['lotto']!().verifyEdge('E09'));
    test('lotto E10 cruising stop(i) -> decelerating on the next tick',
        () => _factories['lotto']!().verifyEdge('E10'));
    test('lotto E11 decelerating past decelerationTime -> settled with result',
        () => _factories['lotto']!().verifyEdge('E11'));
    test('lotto E12 accelerating cancel() -> idle cancelled',
        () => _factories['lotto']!().verifyEdge('E12'));
    test('lotto E13 cruising cancel() -> idle cancelled',
        () => _factories['lotto']!().verifyEdge('E13'));
    test('lotto E14 cruising stop(negative) -> idle cancelled',
        () => _factories['lotto']!().verifyEdge('E14'));
    test('lotto E15 stop() with picker returning null -> idle cancelled',
        () => _factories['lotto']!().verifyEdge('E15'));
    test('lotto E16 decelerating ignores stop() and cancel()',
        () => _factories['lotto']!().verifyEdge('E16'));
    test('lotto E17 idle and settled ignore stop()',
        () => _factories['lotto']!().verifyEdge('E17'));
    test('lotto E18 moving ignores play() (#370)',
        () => _factories['lotto']!().verifyEdge('E18'));
    test('lotto E19 pause() freezes and resume() continues without a jump',
        () => _factories['lotto']!().verifyEdge('E19'));
    test('lotto E20 reset() from any phase -> idle at origin',
        () => _factories['lotto']!().verifyEdge('E20'));
    test('lotto E21 dispose while moving emits no further callbacks',
        () => _factories['lotto']!().verifyEdge('E21'));
    test('lotto E22 idleSpinning ignores stop()',
        () => _factories['lotto']!().verifyEdge('E22'));
    test('lotto E23 100 consecutive draws return to settled (#175)',
        () => _factories['lotto']!().verifyEdge('E23'));
    test(
        'lotto E24 stop() without index uses the picker and still decelerates (#355)',
        () => _factories['lotto']!().verifyEdge('E24'));
    test('lotto E26 pause() is ignored when idle or settled',
        () => _factories['lotto']!().verifyEdge('E26'));

    test('slot E01 idle play() -> accelerating and returns true',
        () => verifySlotEdge('E01'));
    test('slot E02 settled play() -> accelerating and returns true',
        () => verifySlotEdge('E02'));
    test('slot E03 idleSpinning play() -> accelerating from idle speed',
        () => verifySlotEdge('E03'));
    test('slot E04 idle idleSpin() -> idleSpinning',
        () => verifySlotEdge('E04'));
    test('slot E05 settled idleSpin() -> idleSpinning',
        () => verifySlotEdge('E05'));
    test('slot E06 idleSpinning cancel() -> idle without end callback',
        () => verifySlotEdge('E06'));
    test('slot E07 accelerating past accelerationTime -> cruising',
        () => verifySlotEdge('E07'));
    test('slot E08 accelerating stop(i) stays accelerating with stop pending',
        () => verifySlotEdge('E08'));
    test(
        'slot E09 pending stop at end of acceleration -> cruising one tick -> decelerating',
        () => verifySlotEdge('E09'));
    test('slot E10 cruising stop(i) -> decelerating on the next tick',
        () => verifySlotEdge('E10'));
    test('slot E11 decelerating past decelerationTime -> settled with result',
        () => verifySlotEdge('E11'));
    test('slot E12 accelerating cancel() -> idle cancelled',
        () => verifySlotEdge('E12'));
    test('slot E13 cruising cancel() -> idle cancelled',
        () => verifySlotEdge('E13'));
    test('slot E14 cruising stop(negative) -> idle cancelled',
        () => verifySlotEdge('E14'));
    test('slot E15 stop() with picker returning null -> idle cancelled',
        () => verifySlotEdge('E15'));
    test('slot E16 decelerating ignores stop() and cancel()',
        () => verifySlotEdge('E16'));
    test(
        'slot E17 idle and settled ignore stop()', () => verifySlotEdge('E17'));
    test('slot E18 moving ignores play() (#370)', () => verifySlotEdge('E18'));
    test('slot E19 pause() freezes and resume() continues without a jump',
        () => verifySlotEdge('E19'));
    test('slot E20 reset() from any phase -> idle at origin',
        () => verifySlotEdge('E20'));
    test('slot E21 dispose while moving emits no further callbacks',
        () => verifySlotEdge('E21'));
    test('slot E22 idleSpinning ignores stop()', () => verifySlotEdge('E22'));
    test('slot E23 100 consecutive draws return to settled (#175)',
        () => verifySlotEdge('E23'));
    test(
        'slot E24 stop() without index uses the picker and still decelerates (#355)',
        () => verifySlotEdge('E24'));
    test('slot E26 pause() is ignored when idle or settled',
        () => verifySlotEdge('E26'));
  });
  group('state machine', () {
    test('wheel E01 idle play() -> accelerating and returns true',
        () => _factories['wheel']!().verifyEdge('E01'));
    test('wheel E02 settled play() -> accelerating and returns true',
        () => _factories['wheel']!().verifyEdge('E02'));
    test('wheel E03 idleSpinning play() -> accelerating from idle speed',
        () => _factories['wheel']!().verifyEdge('E03'));
    test('wheel E04 idle idleSpin() -> idleSpinning',
        () => _factories['wheel']!().verifyEdge('E04'));
    test('wheel E05 settled idleSpin() -> idleSpinning',
        () => _factories['wheel']!().verifyEdge('E05'));
    test('wheel E06 idleSpinning cancel() -> idle without end callback',
        () => _factories['wheel']!().verifyEdge('E06'));
    test('wheel E07 accelerating past accelerationTime -> cruising',
        () => _factories['wheel']!().verifyEdge('E07'));
    test('wheel E08 accelerating stop(i) stays accelerating with stop pending',
        () => _factories['wheel']!().verifyEdge('E08'));
    test(
        'wheel E09 pending stop at end of acceleration -> cruising one tick -> decelerating',
        () => _factories['wheel']!().verifyEdge('E09'));
    test('wheel E10 cruising stop(i) -> decelerating on the next tick',
        () => _factories['wheel']!().verifyEdge('E10'));
    test('wheel E11 decelerating past decelerationTime -> settled with result',
        () => _factories['wheel']!().verifyEdge('E11'));
    test('wheel E12 accelerating cancel() -> idle cancelled',
        () => _factories['wheel']!().verifyEdge('E12'));
    test('wheel E13 cruising cancel() -> idle cancelled',
        () => _factories['wheel']!().verifyEdge('E13'));
    test('wheel E14 cruising stop(negative) -> idle cancelled',
        () => _factories['wheel']!().verifyEdge('E14'));
    test('wheel E15 stop() with picker returning null -> idle cancelled',
        () => _factories['wheel']!().verifyEdge('E15'));
    test('wheel E16 decelerating ignores stop() and cancel()',
        () => _factories['wheel']!().verifyEdge('E16'));
    test('wheel E17 idle and settled ignore stop()',
        () => _factories['wheel']!().verifyEdge('E17'));
    test('wheel E18 moving ignores play() (#370)',
        () => _factories['wheel']!().verifyEdge('E18'));
    test('wheel E19 pause() freezes and resume() continues without a jump',
        () => _factories['wheel']!().verifyEdge('E19'));
    test('wheel E20 reset() from any phase -> idle at origin',
        () => _factories['wheel']!().verifyEdge('E20'));
    test('wheel E21 dispose while moving emits no further callbacks',
        () => _factories['wheel']!().verifyEdge('E21'));
    test('wheel E22 idleSpinning ignores stop()',
        () => _factories['wheel']!().verifyEdge('E22'));
    test('wheel E23 100 consecutive draws return to settled (#175)',
        () => _factories['wheel']!().verifyEdge('E23'));
    test(
        'wheel E24 stop() without index uses the picker and still decelerates (#355)',
        () => _factories['wheel']!().verifyEdge('E24'));
    test('wheel E26 pause() is ignored when idle or settled',
        () => _factories['wheel']!().verifyEdge('E26'));
    for (final game in []) {
      test('$game E01 idle play() -> accelerating and returns true',
          () => _factories[game]!().verifyEdge('E01'),
          skip: '等待对应玩法控制器任务卡');
      test('$game E02 settled play() -> accelerating and returns true',
          () => _factories[game]!().verifyEdge('E02'),
          skip: '等待对应玩法控制器任务卡');
      test('$game E03 idleSpinning play() -> accelerating from idle speed',
          () => _factories[game]!().verifyEdge('E03'),
          skip: '等待对应玩法控制器任务卡');
      test('$game E04 idle idleSpin() -> idleSpinning',
          () => _factories[game]!().verifyEdge('E04'),
          skip: '等待对应玩法控制器任务卡');
      test('$game E05 settled idleSpin() -> idleSpinning',
          () => _factories[game]!().verifyEdge('E05'),
          skip: '等待对应玩法控制器任务卡');
      test('$game E06 idleSpinning cancel() -> idle without end callback',
          () => _factories[game]!().verifyEdge('E06'),
          skip: '等待对应玩法控制器任务卡');
      test('$game E07 accelerating past accelerationTime -> cruising',
          () => _factories[game]!().verifyEdge('E07'),
          skip: '等待对应玩法控制器任务卡');
      test(
          '$game E08 accelerating stop(i) stays accelerating with stop pending',
          () => _factories[game]!().verifyEdge('E08'),
          skip: '等待对应玩法控制器任务卡');
      test(
          '$game E09 pending stop at end of acceleration -> cruising one tick -> decelerating',
          () => _factories[game]!().verifyEdge('E09'),
          skip: '等待对应玩法控制器任务卡');
      test('$game E10 cruising stop(i) -> decelerating on the next tick',
          () => _factories[game]!().verifyEdge('E10'),
          skip: '等待对应玩法控制器任务卡');
      test(
          '$game E11 decelerating past decelerationTime -> settled with result',
          () => _factories[game]!().verifyEdge('E11'),
          skip: '等待对应玩法控制器任务卡');
      test('$game E12 accelerating cancel() -> idle cancelled',
          () => _factories[game]!().verifyEdge('E12'),
          skip: '等待对应玩法控制器任务卡');
      test('$game E13 cruising cancel() -> idle cancelled',
          () => _factories[game]!().verifyEdge('E13'),
          skip: '等待对应玩法控制器任务卡');
      test('$game E14 cruising stop(negative) -> idle cancelled',
          () => _factories[game]!().verifyEdge('E14'),
          skip: '等待对应玩法控制器任务卡');
      test('$game E15 stop() with picker returning null -> idle cancelled',
          () => _factories[game]!().verifyEdge('E15'),
          skip: '等待对应玩法控制器任务卡');
      test('$game E16 decelerating ignores stop() and cancel()',
          () => _factories[game]!().verifyEdge('E16'),
          skip: '等待对应玩法控制器任务卡');
      test('$game E17 idle and settled ignore stop()',
          () => _factories[game]!().verifyEdge('E17'),
          skip: '等待对应玩法控制器任务卡');
      test('$game E18 moving ignores play() (#370)',
          () => _factories[game]!().verifyEdge('E18'),
          skip: '等待对应玩法控制器任务卡');
      test('$game E19 pause() freezes and resume() continues without a jump',
          () => _factories[game]!().verifyEdge('E19'),
          skip: '等待对应玩法控制器任务卡');
      test('$game E20 reset() from any phase -> idle at origin',
          () => _factories[game]!().verifyEdge('E20'),
          skip: '等待对应玩法控制器任务卡');
      test('$game E21 dispose while moving emits no further callbacks',
          () => _factories[game]!().verifyEdge('E21'),
          skip: '等待对应玩法控制器任务卡');
      test('$game E22 idleSpinning ignores stop()',
          () => _factories[game]!().verifyEdge('E22'),
          skip: '等待对应玩法控制器任务卡');
      test('$game E23 100 consecutive draws return to settled (#175)',
          () => _factories[game]!().verifyEdge('E23'),
          skip: '等待对应玩法控制器任务卡');
      test(
          '$game E24 stop() without index uses the picker and still decelerates (#355)',
          () => _factories[game]!().verifyEdge('E24'),
          skip: '等待对应玩法控制器任务卡');
      test('$game E26 pause() is ignored when idle or settled',
          () => _factories[game]!().verifyEdge('E26'),
          skip: '等待对应玩法控制器任务卡');
    }
    test('grid E01 idle play() -> accelerating and returns true',
        () => GridStateHarness.verifyEdge('E01'));
    test('grid E02 settled play() -> accelerating and returns true',
        () => GridStateHarness.verifyEdge('E02'));
    test('grid E03 idleSpinning play() -> accelerating from idle speed',
        () => GridStateHarness.verifyEdge('E03'));
    test('grid E04 idle idleSpin() -> idleSpinning',
        () => GridStateHarness.verifyEdge('E04'));
    test('grid E05 settled idleSpin() -> idleSpinning',
        () => GridStateHarness.verifyEdge('E05'));
    test('grid E06 idleSpinning cancel() -> idle without end callback',
        () => GridStateHarness.verifyEdge('E06'));
    test('grid E07 accelerating past accelerationTime -> cruising',
        () => GridStateHarness.verifyEdge('E07'));
    test('grid E08 accelerating stop(i) stays accelerating with stop pending',
        () => GridStateHarness.verifyEdge('E08'));
    test(
        'grid E09 pending stop at end of acceleration -> cruising one tick -> decelerating',
        () => GridStateHarness.verifyEdge('E09'));
    test('grid E10 cruising stop(i) -> decelerating on the next tick',
        () => GridStateHarness.verifyEdge('E10'));
    test('grid E11 decelerating past decelerationTime -> settled with result',
        () => GridStateHarness.verifyEdge('E11'));
    test('grid E12 accelerating cancel() -> idle cancelled',
        () => GridStateHarness.verifyEdge('E12'));
    test('grid E13 cruising cancel() -> idle cancelled',
        () => GridStateHarness.verifyEdge('E13'));
    test('grid E14 cruising stop(negative) -> idle cancelled',
        () => GridStateHarness.verifyEdge('E14'));
    test('grid E15 stop() with picker returning null -> idle cancelled',
        () => GridStateHarness.verifyEdge('E15'));
    test('grid E16 decelerating ignores stop() and cancel()',
        () => GridStateHarness.verifyEdge('E16'));
    test('grid E17 idle and settled ignore stop()',
        () => GridStateHarness.verifyEdge('E17'));
    test('grid E18 moving ignores play() (#370)',
        () => GridStateHarness.verifyEdge('E18'));
    test('grid E19 pause() freezes and resume() continues without a jump',
        () => GridStateHarness.verifyEdge('E19'));
    test('grid E20 reset() from any phase -> idle at origin',
        () => GridStateHarness.verifyEdge('E20'));
    test('grid E21 dispose while moving emits no further callbacks',
        () => GridStateHarness.verifyEdge('E21'));
    test('grid E22 idleSpinning ignores stop()',
        () => GridStateHarness.verifyEdge('E22'));
    test('grid E23 100 consecutive draws return to settled (#175)',
        () => GridStateHarness.verifyEdge('E23'));
    test(
        'grid E24 stop() without index uses the picker and still decelerates (#355)',
        () => GridStateHarness.verifyEdge('E24'));
    test('grid E26 pause() is ignored when idle or settled',
        () => GridStateHarness.verifyEdge('E26'));
  });
  group('state machine', () {
    test('capsule E01 idle play() -> accelerating and returns true',
        () => verifyCapsuleEdge('E01'));
    test('capsule E02 settled play() -> accelerating and returns true',
        () => verifyCapsuleEdge('E02'));
    test('capsule E03 idleSpinning play() -> accelerating from idle speed',
        () => verifyCapsuleEdge('E03'));
    test('capsule E04 idle idleSpin() -> idleSpinning',
        () => verifyCapsuleEdge('E04'));
    test('capsule E05 settled idleSpin() -> idleSpinning',
        () => verifyCapsuleEdge('E05'));
    test('capsule E06 idleSpinning cancel() -> idle without end callback',
        () => verifyCapsuleEdge('E06'));
    test('capsule E07 accelerating past accelerationTime -> cruising',
        () => verifyCapsuleEdge('E07'));
    test(
        'capsule E08 accelerating stop(i) stays accelerating with stop pending',
        () => verifyCapsuleEdge('E08'));
    test(
        'capsule E09 pending stop at end of acceleration -> cruising one tick -> decelerating',
        () => verifyCapsuleEdge('E09'));
    test('capsule E10 cruising stop(i) -> decelerating on the next tick',
        () => verifyCapsuleEdge('E10'));
    test(
        'capsule E11 decelerating past decelerationTime -> settled with result',
        () => verifyCapsuleEdge('E11'));
    test('capsule E12 accelerating cancel() -> idle cancelled',
        () => verifyCapsuleEdge('E12'));
    test('capsule E13 cruising cancel() -> idle cancelled',
        () => verifyCapsuleEdge('E13'));
    test('capsule E14 cruising stop(negative) -> idle cancelled',
        () => verifyCapsuleEdge('E14'));
    test('capsule E15 stop() with picker returning null -> idle cancelled',
        () => verifyCapsuleEdge('E15'));
    test('capsule E16 decelerating ignores stop() and cancel()',
        () => verifyCapsuleEdge('E16'));
    test('capsule E17 idle and settled ignore stop()',
        () => verifyCapsuleEdge('E17'));
    test('capsule E18 moving ignores play() (#370)',
        () => verifyCapsuleEdge('E18'));
    test('capsule E19 pause() freezes and resume() continues without a jump',
        () => verifyCapsuleEdge('E19'));
    test('capsule E20 reset() from any phase -> idle at origin',
        () => verifyCapsuleEdge('E20'));
    test('capsule E21 dispose while moving emits no further callbacks',
        () => verifyCapsuleEdge('E21'));
    test('capsule E22 idleSpinning ignores stop()',
        () => verifyCapsuleEdge('E22'));
    test('capsule E23 100 consecutive draws return to settled (#175)',
        () => verifyCapsuleEdge('E23'));
    test(
        'capsule E24 stop() without index uses the picker and still decelerates (#355)',
        () => verifyCapsuleEdge('E24'));
    test('capsule E26 pause() is ignored when idle or settled',
        () => verifyCapsuleEdge('E26'));
    test('lots E01 idle play() -> accelerating and returns true',
        () => verifyLotsEdge('E01'));
    test('lots E02 settled play() -> accelerating and returns true',
        () => verifyLotsEdge('E02'));
    test('lots E03 idleSpinning play() -> accelerating from idle speed',
        () => verifyLotsEdge('E03'));
    test('lots E04 idle idleSpin() -> idleSpinning',
        () => verifyLotsEdge('E04'));
    test('lots E05 settled idleSpin() -> idleSpinning',
        () => verifyLotsEdge('E05'));
    test('lots E06 idleSpinning cancel() -> idle without end callback',
        () => verifyLotsEdge('E06'));
    test('lots E07 accelerating past accelerationTime -> cruising',
        () => verifyLotsEdge('E07'));
    test('lots E08 accelerating stop(i) stays accelerating with stop pending',
        () => verifyLotsEdge('E08'));
    test(
        'lots E09 pending stop at end of acceleration -> cruising one tick -> decelerating',
        () => verifyLotsEdge('E09'));
    test('lots E10 cruising stop(i) -> decelerating on the next tick',
        () => verifyLotsEdge('E10'));
    test('lots E11 decelerating past decelerationTime -> settled with result',
        () => verifyLotsEdge('E11'));
    test('lots E12 accelerating cancel() -> idle cancelled',
        () => verifyLotsEdge('E12'));
    test('lots E13 cruising cancel() -> idle cancelled',
        () => verifyLotsEdge('E13'));
    test('lots E14 cruising stop(negative) -> idle cancelled',
        () => verifyLotsEdge('E14'));
    test('lots E15 stop() with picker returning null -> idle cancelled',
        () => verifyLotsEdge('E15'));
    test('lots E16 decelerating ignores stop() and cancel()',
        () => verifyLotsEdge('E16'));
    test(
        'lots E17 idle and settled ignore stop()', () => verifyLotsEdge('E17'));
    test('lots E18 moving ignores play() (#370)', () => verifyLotsEdge('E18'));
    test('lots E19 pause() freezes and resume() continues without a jump',
        () => verifyLotsEdge('E19'));
    test('lots E20 reset() from any phase -> idle at origin',
        () => verifyLotsEdge('E20'));
    test('lots E21 dispose while moving emits no further callbacks',
        () => verifyLotsEdge('E21'));
    test('lots E22 idleSpinning ignores stop()', () => verifyLotsEdge('E22'));
    test('lots E23 100 consecutive draws return to settled (#175)',
        () => verifyLotsEdge('E23'));
    test(
        'lots E24 stop() without index uses the picker and still decelerates (#355)',
        () => verifyLotsEdge('E24'));
    test('lots E26 pause() is ignored when idle or settled',
        () => verifyLotsEdge('E26'));
    test('numberWheel E01 idle play() -> accelerating and returns true',
        () => verifyNumberWheelEdge('E01'));
    test('numberWheel E02 settled play() -> accelerating and returns true',
        () => verifyNumberWheelEdge('E02'));
    test('numberWheel E03 idleSpinning play() -> accelerating from idle speed',
        () => verifyNumberWheelEdge('E03'));
    test('numberWheel E04 idle idleSpin() -> idleSpinning',
        () => verifyNumberWheelEdge('E04'));
    test('numberWheel E05 settled idleSpin() -> idleSpinning',
        () => verifyNumberWheelEdge('E05'));
    test('numberWheel E06 idleSpinning cancel() -> idle without end callback',
        () => verifyNumberWheelEdge('E06'));
    test('numberWheel E07 accelerating past accelerationTime -> cruising',
        () => verifyNumberWheelEdge('E07'));
    test(
        'numberWheel E08 accelerating stop(i) stays accelerating with stop pending',
        () => verifyNumberWheelEdge('E08'));
    test(
        'numberWheel E09 pending stop at end of acceleration -> cruising one tick -> decelerating',
        () => verifyNumberWheelEdge('E09'));
    test('numberWheel E10 cruising stop(i) -> decelerating on the next tick',
        () => verifyNumberWheelEdge('E10'));
    test(
        'numberWheel E11 decelerating past decelerationTime -> settled with result',
        () => verifyNumberWheelEdge('E11'));
    test('numberWheel E12 accelerating cancel() -> idle cancelled',
        () => verifyNumberWheelEdge('E12'));
    test('numberWheel E13 cruising cancel() -> idle cancelled',
        () => verifyNumberWheelEdge('E13'));
    test('numberWheel E14 cruising stop(negative) -> idle cancelled',
        () => verifyNumberWheelEdge('E14'));
    test('numberWheel E15 stop() with picker returning null -> idle cancelled',
        () => verifyNumberWheelEdge('E15'));
    test('numberWheel E16 decelerating ignores stop() and cancel()',
        () => verifyNumberWheelEdge('E16'));
    test('numberWheel E17 idle and settled ignore stop()',
        () => verifyNumberWheelEdge('E17'));
    test('numberWheel E18 moving ignores play() (#370)',
        () => verifyNumberWheelEdge('E18'));
    test(
        'numberWheel E19 pause() freezes and resume() continues without a jump',
        () => verifyNumberWheelEdge('E19'));
    test('numberWheel E20 reset() from any phase -> idle at origin',
        () => verifyNumberWheelEdge('E20'));
    test('numberWheel E21 dispose while moving emits no further callbacks',
        () => verifyNumberWheelEdge('E21'));
    test('numberWheel E22 idleSpinning ignores stop()',
        () => verifyNumberWheelEdge('E22'));
    test('numberWheel E23 100 consecutive draws return to settled (#175)',
        () => verifyNumberWheelEdge('E23'));
    test(
        'numberWheel E24 stop() without index uses the picker and still decelerates (#355)',
        () => verifyNumberWheelEdge('E24'));
    test('numberWheel E26 pause() is ignored when idle or settled',
        () => verifyNumberWheelEdge('E26'));
  });
}
