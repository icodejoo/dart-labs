import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luckdraw/capsule.dart';

import '../support/capsule_fixtures.dart';

/// 指定物理参数的配置。
CapsuleConfig _config(LuckyPhysics physics) =>
    capsuleConfig.copyWith(options: CapsuleOptions(physics: physics));

/// 在给定系统减少动效设置下挂载扭蛋机，返回控制器当前是否在模拟。
Future<bool> _simulating(WidgetTester tester, CapsuleConfig config,
    {required bool disableAnimations}) async {
  final controller = CapsuleController();
  addTearDown(controller.dispose);
  await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: MediaQuery(
          data: MediaQueryData(disableAnimations: disableAnimations),
          child: Align(
              alignment: Alignment.topLeft,
              child: LuckyCapsuleMachine(
                  config: config,
                  controller: controller,
                  width: capsuleSize.width,
                  height: capsuleSize.height)))));
  return controller.frame.physical;
}

/// 验证系统减少动效时物理模式回退为参数化轨迹。
void main() {
  testWidgets('system 策略跟随系统：关闭时模拟，开启时回退参数化轨迹', (tester) async {
    final config = _config(const LuckyPhysics());
    expect(await _simulating(tester, config, disableAnimations: false), isTrue);
    expect(await _simulating(tester, config, disableAnimations: true), isFalse);
  });

  testWidgets('always 恒回退、never 恒模拟，与系统设置无关', (tester) async {
    final always = _config(
        const LuckyPhysics(reduceMotion: LuckyPhysicsReduceMotion.always));
    final never = _config(
        const LuckyPhysics(reduceMotion: LuckyPhysicsReduceMotion.never));
    expect(
        await _simulating(tester, always, disableAnimations: false), isFalse);
    expect(await _simulating(tester, never, disableAnimations: true), isTrue);
  });

  testWidgets('系统设置在运行时变化后宿主重新配置', (tester) async {
    final controller = CapsuleController();
    addTearDown(controller.dispose);
    Widget view(bool reduce) => Directionality(
        textDirection: TextDirection.ltr,
        child: MediaQuery(
            data: MediaQueryData(disableAnimations: reduce),
            child: Align(
                alignment: Alignment.topLeft,
                child: LuckyCapsuleMachine(
                    config: _config(const LuckyPhysics()),
                    controller: controller,
                    width: capsuleSize.width,
                    height: capsuleSize.height))));
    await tester.pumpWidget(view(false));
    expect(controller.frame.physical, isTrue);
    await tester.pumpWidget(view(true));
    expect(controller.frame.physical, isFalse);
    await tester.pumpWidget(view(false));
    expect(controller.frame.physical, isTrue);
  });

  test('去掉物理模式的选项副本保留其余字段', () {
    const options = CapsuleOptions(
        globeRadiusFactor: 0.4,
        capsuleRadiusFactor: 0.2,
        dropTime: Duration(milliseconds: 100),
        revealTime: Duration(milliseconds: 200),
        revealOnSettle: false,
        physics: LuckyPhysics());
    final plain = options.withoutPhysics();
    expect(plain.physics, isNull);
    expect(plain, options.copyWith().withoutPhysics());
    expect(plain.globeRadiusFactor, 0.4);
    expect(plain.capsuleRadiusFactor, 0.2);
    expect(plain.dropTime, const Duration(milliseconds: 100));
    expect(plain.revealTime, const Duration(milliseconds: 200));
    expect(plain.revealOnSettle, isFalse);
    expect(plain.motion, options.motion);
  });
}
