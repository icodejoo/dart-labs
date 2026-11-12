import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luckdraw/lotto.dart';

import '../support/lotto_fixtures.dart';

/// 指定物理参数的配置。
LottoConfig _config(LuckyPhysics physics) =>
    lottoConfig.copyWith(options: lottoOptions.copyWith(physics: physics));

/// 构建挂载大乐透的视图。
Widget _view(LottoController controller, LottoConfig config,
        {required bool reduce}) =>
    Directionality(
        textDirection: TextDirection.ltr,
        child: MediaQuery(
            data: MediaQueryData(disableAnimations: reduce),
            child: Center(
                child: LuckyLotto(
                    config: config,
                    controller: controller,
                    width: lottoSize.width,
                    height: lottoSize.height))));

/// 验证系统减少动效时物理模式回退为参数化轨迹。
void main() {
  testWidgets('system 策略跟随系统，运行时变化后宿主重新配置', (tester) async {
    final controller = LottoController();
    addTearDown(controller.dispose);
    final config = _config(const LuckyPhysics());
    await tester.pumpWidget(_view(controller, config, reduce: false));
    expect(controller.frame.physical, everyElement(1));
    await tester.pumpWidget(_view(controller, config, reduce: true));
    expect(controller.frame.physical, everyElement(0));
    await tester.pumpWidget(_view(controller, config, reduce: false));
    expect(controller.frame.physical, everyElement(1));
  });

  testWidgets('always 恒回退、never 恒模拟，与系统设置无关', (tester) async {
    final controller = LottoController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_view(
        controller,
        _config(
            const LuckyPhysics(reduceMotion: LuckyPhysicsReduceMotion.always)),
        reduce: false));
    expect(controller.frame.physical, everyElement(0));
    await tester.pumpWidget(_view(
        controller,
        _config(
            const LuckyPhysics(reduceMotion: LuckyPhysicsReduceMotion.never)),
        reduce: true));
    expect(controller.frame.physical, everyElement(1));
  });

  test('去掉物理模式的选项副本保留其余字段', () {
    const options = LottoOptions(
        drawInterval: Duration(milliseconds: 11),
        ballFlightTime: Duration(milliseconds: 22),
        sortResults: false,
        drawMix: 0.4,
        ballRadiusFactor: 0.2,
        physics: LuckyPhysics());
    final plain = options.withoutPhysics();
    expect(plain.physics, isNull);
    expect(plain.drawInterval, const Duration(milliseconds: 11));
    expect(plain.ballFlightTime, const Duration(milliseconds: 22));
    expect(plain.sortResults, isFalse);
    expect(plain.drawMix, 0.4);
    expect(plain.ballRadiusFactor, 0.2);
    expect(plain.motion, options.motion);
  });
}
