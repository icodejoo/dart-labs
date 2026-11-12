import 'package:flutter/animation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luckdraw/compat.dart';
import 'package:luckdraw/luckdraw.dart';

/// 验证兼容预设、诊断值类型和七个缓动名称。
void main() {
  group('compat options', () {
    test('defaults strict preset and copies retain their contracts', () {
      const defaults = LuckyCanvasCompatOptions();
      expect(defaults.remBase, 16);
      expect(defaults.viewportWidth, isNull);
      expect(defaults.handleCssUnit, isNull);
      expect(defaults.assetResolver, isNull);
      expect(defaults.timebase, LuckyTimebase.time);
      expect(defaults.stopSolver, isA<MonotonicStopSolver>());
      expect(defaults.honorDisabled, isFalse);
      expect(defaults.honorSpeedFunction, isFalse);
      final strict = LuckyCanvasCompatOptions.strictUpstream();
      expect(strict.timebase, LuckyTimebase.frame);
      expect(strict.stopSolver, isA<UpstreamStopSolver>());
      expect(strict.remBase, 16);
      final calls = <(double, String)>[];

      /// 测试单位回调，记录输入以验证预设透传。
      double unit(double value, String name) {
        calls.add((value, name));
        return value * 2;
      }

      final configured = LuckyCanvasCompatOptions.strictUpstream(
          remBase: 20, viewportWidth: 300, handleCssUnit: unit);
      expect(configured.remBase, 20);
      expect(configured.viewportWidth, 300);
      expect(configured.handleCssUnit!(3, 'em'), 6);
      expect(calls, [(3.0, 'em')]);
      final copied = defaults.copyWith(
          remBase: 20,
          viewportWidth: 300,
          handleCssUnit: unit,
          timebase: LuckyTimebase.frame,
          stopSolver: const UpstreamStopSolver(),
          honorDisabled: true,
          honorSpeedFunction: true,
          assetResolver: (src) => AssetImage(src));
      expect(copied.copyWith(), copied);
      expect(copied.copyWith().hashCode, copied.hashCode);
      expect(copied.honorDisabled, isTrue);
      expect(copied.honorSpeedFunction, isTrue);
      expect(copied.assetResolver!('a.png'), const AssetImage('a.png'));
      expect(copied.copyWith(honorDisabled: false).honorDisabled, isFalse);
      expect(defaults.copyWith(), defaults);
      expect(defaults.copyWith().hashCode, defaults.hashCode);
      expect(defaults == Object(), isFalse);
      expect(defaults == defaults.copyWith(remBase: 17), isFalse);
      expect(defaults == defaults.copyWith(viewportWidth: 1), isFalse);
      expect(defaults == defaults.copyWith(handleCssUnit: unit), isFalse);
      expect(defaults == strict, isFalse);
      expect(
          defaults == defaults.copyWith(stopSolver: const UpstreamStopSolver()),
          isFalse);
      expect(defaults == defaults.copyWith(honorSpeedFunction: true), isFalse);
      expect(defaults == defaults.copyWith(honorDisabled: true), isFalse);
      expect(
          defaults ==
              defaults.copyWith(assetResolver: (src) => AssetImage(src)),
          isFalse);
    });
    test('results warnings and seven easing names are stable values', () {
      const warning =
          LuckyCanvasCompatWarning('prizes[2].fonts[0].fontSize', '无效长度');
      expect(warning.toString(), 'prizes[2].fonts[0].fontSize: 无效长度');
      expect(warning.copyWith(), warning);
      expect(warning.copyWith().hashCode, warning.hashCode);
      expect(warning.copyWith(path: 'width').path, 'width');
      expect(warning.copyWith(message: '无效尺寸').message, '无效尺寸');
      expect(warning == Object(), isFalse);
      expect(warning == warning.copyWith(path: 'height'), isFalse);
      expect(warning == warning.copyWith(message: '其它'), isFalse);
      const result = LuckyCanvasCompatResult(config: 'config');
      expect(result.width, isNull);
      expect(result.height, isNull);
      expect(result.warnings, isEmpty);
      expect(result.copyWith(), result);
      expect(result.copyWith().hashCode, result.hashCode);
      final configured = result.copyWith(
          config: 'changed', width: 100, height: 200, warnings: [warning]);
      expect(configured.config, 'changed');
      expect(configured.width, 100);
      expect(configured.height, 200);
      expect(configured.warnings, [warning]);
      expect(configured.copyWith(), configured);
      expect(configured.copyWith().hashCode, configured.hashCode);
      expect(result == Object(), isFalse);
      expect(result == configured, isFalse);
      expect(result == result.copyWith(width: 1), isFalse);
      expect(result == result.copyWith(height: 1), isFalse);
      expect(result == result.copyWith(warnings: [warning]), isFalse);
      // 迁移结果对 core 配置保持泛型与策略对象身份，修改尺寸不重新创建配置。
      final motion = LuckyMotionOptions(
          accelerationEasing: CurveEasing(Curves.linear.flipped));
      final motionResult = LuckyCanvasCompatResult(config: motion);
      final resized = motionResult.copyWith(width: 120);
      expect(resized.config, same(motion));
      expect(resized.config.accelerationEasing.easeIn(25, 10, 80, 100), 30);
      expect(kLuckyCanvasEasingNames, {
        'quad': LuckyEasings.quad,
        'cubic': LuckyEasings.cubic,
        'quart': LuckyEasings.quart,
        'quint': LuckyEasings.quint,
        'sine': LuckyEasings.sine,
        'expo': LuckyEasings.expo,
        'circ': LuckyEasings.circ,
      });
    });
  });
}
