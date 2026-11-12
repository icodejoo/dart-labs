import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luckdraw/src/wheel/motion/wheel_motion.dart';
import 'package:luckdraw/testing.dart';
import 'package:luckdraw/wheel.dart';

/// 缩短回归所用的参考帧动画。
const _motionOptions = LuckyMotionOptions(
    accelerationTime: Duration(milliseconds: 64),
    decelerationTime: Duration(milliseconds: 96),
    timebase: LuckyTimebase.frame);

/// 创建包含指定数量奖品的配置。
WheelConfig _config(
        {int count = 6,
        LuckyMotionOptions motion = _motionOptions,
        double offset = 0,
        double range = 0}) =>
    WheelConfig(
        prizes: List.generate(count, (_) => const WheelPrize()),
        options: WheelOptions(
            motion: motion, offsetDegree: offset, stopRange: range));

/// 创建可重复的状态机。
WheelMotion _motion({double random = .5, double range = 0}) => WheelMotion(
    random: SequenceRandom([random]), picker: const WeightedPrizePicker())
  ..configure(_config(range: range), null)
  ..start()
  ..requestStop(5);

/// 推进到结算后的固定时间。
void _finish(WheelMotion motion) {
  for (var i = 1; i < 30; i++) {
    motion.tick(i * 16, 16);
  }
}

/// 构建有界测试宿主。
Widget _root(Widget child) => MediaQuery(
    data: const MediaQueryData(),
    child: Directionality(
        textDirection: TextDirection.ltr, child: Center(child: child)));

/// 转盘终审缺陷的行为回归。
void main() {
  test('F2 wheel selected target is remapped after prize shrink', () {
    final m = _motion()
      ..tick(0, 16)
      ..configure(_config(count: 2), null);
    _finish(m);
    expect(m.phase, LuckyPhase.settled);
    expect(m.takeResult()!.index, 1);
    expect(m.frame.targetIndex, 1);
  });
  test('F2 wheel empty configuration safely cancels a selected draw', () {
    final m = _motion()
      ..tick(0, 16)
      ..configure(_config(count: 0), null);
    _finish(m);
    expect(m.phase, LuckyPhase.idle);
    expect(m.takeResult()!.cancelled, isTrue);
    expect(m.frame.pointerIndex, -1);
  });
  test('F2 wheel full stop range keeps zero random endpoint inside target', () {
    final m = _motion(random: 0, range: 1)..tick(0, 16);
    _finish(m);
    expect(m.phase, LuckyPhase.settled);
    expect(m.frame.pointerIndex, 5);
  });
  test('F2 wheel deceleration options stay frozen until settlement', () {
    final m = _motion();
    final reference = _motion();
    for (var i = 0; i <= 9; i++) {
      m.tick(i * 16, 16);
      reference.tick(i * 16, 16);
    }
    m.configure(
        _config(
            motion: _motionOptions.copyWith(
                decelerationTime: const Duration(milliseconds: 9600))),
        null);
    for (var i = 10; i < 30; i++) {
      m.tick(i * 16, 16);
      reference.tick(i * 16, 16);
      expect(m.frame.rotateDeg, reference.frame.rotateDeg);
    }
    expect(m.takeResult()!.index, 5);
  });
  test('F2 wheel settled offset update refreshes pointer snapshot', () {
    final m = _motion()..tick(0, 16);
    _finish(m);
    final angle = m.frame.rotateDeg;
    final config = _config(offset: 90);
    m.configure(config, null);
    expect(m.frame.rotateDeg, angle);
    expect(m.frame.pointerIndex,
        WheelSectorAngles.fromConfig(config).sectorAtPointer(angle, 90));
  });
  test('F2 wheel finite extreme weights produce finite normalized sectors', () {
    final a = WheelSectorAngles.fromConfig(const WheelConfig(prizes: [
      WheelPrize(sectorWeight: 1e306),
      WheelPrize(sectorWeight: 2e306)
    ]));
    expect(a.sweepDeg(0), closeTo(120, 1e-10));
    expect(a.sweepDeg(1), closeTo(240, 1e-10));
    expect(a.startDeg(1), closeTo(120, 1e-10));
  });
  testWidgets('F2 wheel settled callback restart preserves onEnd and playUntil',
      (tester) async {
    final controller = WheelController(random: SequenceRandom([.5]));
    addTearDown(controller.dispose);
    var restarted = false;
    final results = <LuckyResult<WheelPrize>>[];
    await tester.pumpWidget(_root(LuckyWheel(
        config: _config(),
        controller: controller,
        width: 300,
        height: 300,
        onEnd: results.add,
        onPhaseChanged: (phase) {
          if (phase == LuckyPhase.settled && !restarted) {
            restarted = true;
            controller.play();
          }
        })));
    final future = controller.playUntil(() => 2);
    await tester.pump();
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(restarted, isTrue);
    expect(results, hasLength(1));
    expect((await future).index, 2);
    expect(results.single.index, 2);
    expect(controller.phase.value, LuckyPhase.cruising);
    await tester.pumpWidget(const SizedBox());
  });
  test('F2 wheel clearing prizes before target selection cancels safely', () {
    final m = WheelMotion(
        random: SequenceRandom([.5]), picker: const WeightedPrizePicker())
      ..configure(_config(), null)
      ..start();
    m.configure(_config(count: 0), null);
    expect(m.phase, LuckyPhase.idle);
    expect(m.takeResult()!.cancelled, isTrue);
  });
  test('F2 wheel direct deceleration shrink replans target geometry', () {
    final m = _motion()..requestStop(4);
    for (var i = 0; i < 10; i++) {
      m.tick(i * 16, 16);
    }
    expect(m.phase, LuckyPhase.decelerating);
    m.configure(_config(count: 2), null);
    for (var i = 10; i < 40; i++) {
      m.tick(i * 16, 16);
    }
    expect(m.takeResult()!.index, 0);
    expect(m.frame.pointerIndex, 0);
    m.configure(_config(count: 0), null);
    expect(m.frame.targetIndex, -1);
  });
  test(
      'F2 wheel normalization roundoff still assigns final boundary to last sector',
      () {
    final angles = WheelSectorAngles.fromConfig(const WheelConfig(prizes: [
      WheelPrize(sectorWeight: 4.149936672624096),
      WheelPrize(sectorWeight: 1),
      WheelPrize(sectorWeight: 3)
    ]));
    expect(
        angles.startDeg(2) + angles.sweepDeg(2), lessThan(359.99999999999994));
    expect(angles.sectorAtPointer(-359.99999999999994, 0), 2);
  });
}
