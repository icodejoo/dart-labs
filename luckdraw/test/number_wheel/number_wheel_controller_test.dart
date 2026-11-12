import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:luckdraw/src/number_wheel/control/number_wheel_controller.dart';
import 'package:luckdraw/testing.dart';

import '../support/number_wheel_fixtures.dart';

/// 验证号码命令和异步选奖。
void main() {
  group('NumberWheelController', () {
    late NumberWheelController controller;
    late ManualLuckyClock clock;
    setUp(() {
      controller = NumberWheelController();
      clock = ManualLuckyClock();
      controller.attachHeadless(
          clock: clock,
          config: numberWheelFixture,
          layout: numberWheelLayout());
    });
    tearDown(() {
      controller.dispose();
      clock.dispose();
    });
    test('stopNumber maps a number to its pocket and rejects unknown numbers',
        () {
      expect(controller.stop(), isFalse);
      expect(() => controller.stopNumber(99), throwsArgumentError);
      controller.play();
      expect(controller.stopNumber(20), isTrue);
      for (var i = 0; i < 30; i++) {
        clock.advance(const Duration(milliseconds: 20));
      }
      expect(controller.lastNumber, 20);
    });
    test('stop() without index uses the picker', () {
      controller.play();
      expect(controller.stop(), isTrue);
      for (var i = 0; i < 30; i++) {
        clock.advance(const Duration(milliseconds: 20));
      }
      expect(controller.lastResult?.index, 1);
    });
    test('playUntil waits for the server number', () async {
      final server = Completer<int?>();
      final future = controller.playUntil(() => server.future);
      clock.advance(const Duration(milliseconds: 100));
      expect(controller.lastNumber, isNull);
      server.complete(30);
      await Future<void>.delayed(Duration.zero);
      for (var i = 0; i < 30; i++) {
        clock.advance(const Duration(milliseconds: 20));
      }
      expect((await future).prize?.number, 30);
    });
  });
}
