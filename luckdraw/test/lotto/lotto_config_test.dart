import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luckdraw/lotto.dart';

import '../support/lotto_fixtures.dart';

/// 检查预设、参数契约和值语义。
void main() {
  group('LottoConfig', () {
    test('superLotto preset is 5 of 35 front and 2 of 12 back', () {
      final config = LottoConfig.superLotto();
      expect(config.pools, [kSuperLottoFront, kSuperLottoBack]);
      expect(config.pools.map((p) => [p.min, p.max, p.count]), [
        [1, 35, 5],
        [1, 12, 2]
      ]);
      expect(config.options.drawInterval, const Duration(milliseconds: 700));
      expect(config.options.ballFlightTime, const Duration(milliseconds: 500));
      expect(config.options.drawMix, 0.6);
      expect(config.options.ballRadiusFactor, 0.11);
      expect(config.options.motion.speed, 12);
      expect(config.options.motion.accelerationTime,
          const Duration(milliseconds: 800));
      config.validate();
    });
    test('pools validate min max and count', () {
      final p = lottoConfig.pools.first;
      expect(() => p.copyWith(min: 9), throwsAssertionError);
      expect(() => p.copyWith(count: 0), throwsAssertionError);
      expect(() => p.copyWith(count: 8), throwsAssertionError);
      expect(
          () => const LottoConfig(pools: []).validate(), throwsArgumentError);
      for (final options in <LottoOptions>[
        lottoOptions.copyWith(drawInterval: Duration.zero),
        lottoOptions.copyWith(ballFlightTime: Duration.zero),
        lottoOptions.copyWith(drawMix: -1),
        lottoOptions.copyWith(drawMix: 2),
        lottoOptions.copyWith(drawMix: double.nan),
        lottoOptions.copyWith(ballRadiusFactor: 0),
        lottoOptions.copyWith(ballRadiusFactor: 1),
        lottoOptions.copyWith(ballRadiusFactor: double.nan),
        lottoOptions.copyWith(motion: lottoOptions.motion.copyWith(speed: 0)),
        lottoOptions.copyWith(
            motion: lottoOptions.motion.copyWith(speed: double.infinity)),
        lottoOptions.copyWith(
            motion: lottoOptions.motion.copyWith(idleSpinSpeed: double.nan)),
        lottoOptions.copyWith(
            motion: lottoOptions.motion.copyWith(idleSpinSpeed: -1)),
        lottoOptions.copyWith(
            motion: lottoOptions.motion
                .copyWith(maxFrameDelta: const Duration(milliseconds: -1))),
        lottoOptions.copyWith(
            motion:
                lottoOptions.motion.copyWith(accelerationTime: Duration.zero)),
        lottoOptions.copyWith(
            motion:
                lottoOptions.motion.copyWith(decelerationTime: Duration.zero)),
      ]) {
        expect(() => lottoConfig.copyWith(options: options).validate(),
            throwsArgumentError);
      }
    });
    test('configuration copies retain value equality and hash codes', () {
      final p = lottoConfig.pools.first;
      final copiedPool = p.copyWith(
          min: p.min,
          max: p.max,
          count: p.count,
          ballFill: p.ballFill,
          textColor: p.textColor,
          label: '测试');
      expect(copiedPool, p.copyWith(label: '测试'));
      expect(copiedPool.hashCode, p.copyWith(label: '测试').hashCode);
      expect(p.copyWith(), p);
      final options = lottoOptions.copyWith();
      expect(options, lottoOptions);
      expect(options.hashCode, lottoOptions.hashCode);
      final style = const LottoStyle().copyWith();
      expect(style, const LottoStyle());
      expect(style.hashCode, const LottoStyle().hashCode);
      expect(style.copyWith(buttonText: '开奖'), isNot(style));
      final alternate = style.copyWith(
          drumColor: const Color(0xFF112233),
          rimColor: const Color(0xFF223344),
          slotColor: const Color(0xFF334455),
          buttonColor: const Color(0xFF445566),
          buttonTextColor: const Color(0xFF556677));
      expect(alternate.drumColor, const Color(0xFF112233));
      expect(alternate, isNot(style));
      expect(lottoConfig.copyWith(), lottoConfig);
      expect(lottoConfig.copyWith().hashCode, lottoConfig.hashCode);
      expect(lottoConfig.copyWith(pools: [copiedPool]), isNot(lottoConfig));
      expect(lottoDraw.copyWith(), lottoDraw);
      expect(
          lottoDraw.copyWith(numbers: [
            [1],
            [2]
          ]),
          isNot(lottoDraw));
      expect(lottoDraw.copyWith().hashCode, lottoDraw.hashCode);
      expect(
          lottoDraw,
          isNot(const LottoDraw([
            [7, 4, 1],
            [14, 11]
          ])));
      expect(
          lottoDraw,
          isNot(const LottoDraw([
            [7, 1, 4]
          ])));
      expect(lottoDraw, isNot('draw'));
      expect(const LottoResult.cancelled().draw, isNull);
      expect(const LottoResult(draw: lottoDraw).draw, lottoDraw);
    });
  });
}
