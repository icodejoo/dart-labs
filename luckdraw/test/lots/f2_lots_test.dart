import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:luckdraw/lots.dart';
import '../support/f2_lifecycle_fixtures.dart';
import '../support/lots_fixtures.dart';

/// 抽签布局失效与恢复回归。
void main() {
  test('F2 lots empty layout preserves pending stop until geometry returns',
      () {
    final motion = lotsMotion();
    cruiseLots(motion);
    motion.stop(1);
    final position = motion.frame.shakePhaseDeg;
    motion.configure(lotsFixture, lotsLayout(lotsFixture, Size.zero));
    expect(motion.tick(120, 20), 0);
    expect(motion.frame.shakePhaseDeg, position);
    motion.configure(lotsFixture, lotsLayout());
    settleLots(motion);
    expect(motion.takeResult()!.index, 1);
  });
  test('F2 lots settled visible slot shrink remaps raised stick and hit target',
      () {
    final motion = lotsMotion();
    cruiseLots(motion);
    motion.stop(2);
    settleLots(motion);
    final config = lotsFixture.copyWith(
        options: lotsFixture.options.copyWith(visibleSticks: 1));
    final layout = lotsLayout(config);
    motion.configure(config, layout);
    expect(motion.frame.targetSlot, 0);
    expect(motion.frame.targetIndex, 2);
    final hits = const LotsGame()
        .hitTestAll(config, layout, motion.frame, layout.card.center);
    expect(hits.single.index, 2);
  });
  test('F2 lots dispose freezes phase result and item callbacks', () {
    final host = F2LifecycleHost<LuckyResult<LotsStick>>();
    final controller = LotsController()
      ..attach(host)
      ..configure(lotsFixture, lotsLayout());
    controller.play();
    host.clock.advanceFrames(10);
    expect(host.callbacks, greaterThan(0));
    final before = host.callbacks;
    controller.dispose();
    host.clock.advanceFrames(100);
    expect(host.callbacks, before);
    expect(host.clock.isTicking, isFalse);
    host.clock.dispose();
  });
  test(
      'F2 lots direct count shrink cancels movement and removes stale settled targets',
      () {
    final m = lotsMotion();
    cruiseLots(m);
    m.stop(2);
    m.tick(120, 20);
    final next = lotsFixture.copyWith(sticks: [lotsFixture.sticks.first]);
    m.configure(next, lotsLayout(next));
    expect(m.phase, LuckyPhase.idle);
    expect(m.takeResult()!.cancelled, isTrue);
    final settled = lotsMotion();
    cruiseLots(settled);
    settled.stop(2);
    settleLots(settled);
    settled.configure(next, lotsLayout(next));
    expect(settled.frame.targetSlot, -1);
    expect(settled.frame.targetIndex, -1);
    expect(settled.phase, LuckyPhase.idle);
  });
  test(
      'F2 lots idle start preserves shake phase and follows documented amplitude easing',
      () {
    final m = lotsMotion()
      ..idleSpin()
      ..tick(20, 20);
    final phase = m.frame.shakePhaseDeg;
    m.start();
    expect(m.frame.shakePhaseDeg, phase);
    m.tick(40, 20);
    expect(m.frame.shakePhaseDeg - phase,
        closeTo(lotsFixture.options.motion.speed * 20 / (1000 / 60), 1e-10));
    expect(m.frame.shakeDeg.abs(), lessThan(lotsFixture.options.maxShakeDeg));
  });
}
