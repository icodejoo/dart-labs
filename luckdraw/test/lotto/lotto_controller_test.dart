import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:luckdraw/lotto.dart';

import '../support/lotto_fixtures.dart';

/// 验证选号、异步协议及状态命令。
void main() {
  group('LottoController', () {
    test('stopWith validates counts ranges and duplicates', () {
      final rig = LottoRig();
      addTearDown(rig.dispose);
      expect(rig.controller.stopWith(lottoDraw), isFalse);
      rig.controller.play();
      for (final draw in <LottoDraw>[
        const LottoDraw([
          [1, 2, 3]
        ]),
        const LottoDraw([
          [1],
          [11, 12]
        ]),
        const LottoDraw([
          [1, 1, 3],
          [11, 12]
        ]),
        const LottoDraw([
          [0, 2, 3],
          [11, 12]
        ]),
        const LottoDraw([
          [1, 2, 8],
          [11, 12]
        ]),
      ]) {
        expect(() => rig.controller.stopWith(draw), throwsArgumentError);
      }
      expect(rig.controller.stopWith(lottoDraw), isTrue);
      expect(rig.controller.stopWith(lottoDraw), isFalse);
      rig.until(LuckyPhase.settled);
      expect(rig.controller.lastResult!.draw, lottoDraw);
    });
    test('stop() samples without replacement using the injected Random', () {
      final rig = LottoRig();
      addTearDown(rig.dispose);
      final expected =
          const UniformLottoSampler().sample(lottoConfig, math.Random(42));
      rig.controller.play();
      expect(rig.controller.stop(), isTrue);
      rig.until(LuckyPhase.settled);
      expect(rig.controller.lastResult!.draw, expected);
      for (var seed = 0; seed < 100; seed++) {
        final draw =
            const UniformLottoSampler().sample(lottoConfig, math.Random(seed));
        draw.validate(lottoConfig);
        expect(draw.numbers.first.toSet(), hasLength(3));
        expect(draw.numbers.last.toSet(), hasLength(2));
      }
    });
    test('playUntil waits for the server draw', () async {
      final rig = LottoRig();
      addTearDown(rig.dispose);
      final server = Completer<LottoDraw?>();
      final result = rig.controller.playUntil(() => server.future,
          minSpinDuration: const Duration(milliseconds: 200));
      rig.until(LuckyPhase.cruising);
      expect(rig.controller.lastResult, isNull);
      server.complete(lottoDraw);
      await Future<void>.delayed(Duration.zero);
      expect(rig.controller.phase.value, LuckyPhase.cruising);
      rig.until(LuckyPhase.settled);
      expect((await result).draw, lottoDraw);
      final cancelled = rig.controller.playUntil(() => null);
      await Future<void>.delayed(Duration.zero);
      expect((await cancelled).cancelled, isTrue);
    });
    test('cancel during drawing is ignored like other decelerating phases', () {
      final rig = LottoRig();
      addTearDown(rig.dispose);
      rig.controller.play();
      rig.controller.stopWith(lottoDraw);
      rig.until(LuckyPhase.decelerating);
      expect(rig.controller.cancel(), isFalse);
      expect(rig.controller.stop(), isFalse);
      expect(rig.controller.phase.value, LuckyPhase.decelerating);
      rig.until(LuckyPhase.settled);
      expect(rig.controller.lastResult!.draw, lottoDraw);
    });
  });
}
