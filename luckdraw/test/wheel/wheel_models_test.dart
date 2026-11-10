import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luckdraw/wheel.dart';

import '../support/fixtures.dart';

/// 各配置模型共用的非默认填充。
const LuckyFill _fill = LuckyFill.color(Color(0xff123456));

/// 模型测试共用的图片。
const AssetImage _provider = AssetImage('wheel.png');

/// 验证模型的值语义与 copyWith 契约。
void main() {
  group('wheel models', () {
    test(
        'config options and style preserve defaults and replace only given values',
        () {
      const config = WheelConfig();
      expect(config.options.motion.timebase, LuckyTimebase.time);
      expect(config.options.motion.stopSolver, isA<MonotonicStopSolver>());
      expect(config.style.background, const LuckyFill.color(Color(0x00000000)));
      expect(config.style.text, const LuckyTextDefaults());
      expect(config, config.copyWith());
      expect(config.hashCode, config.copyWith().hashCode);
      final full = config.copyWith(
          blocks: [const WheelBlock(padding: 5)],
          prizes: kLuckyWheelFixture.prizes,
          buttons: kLuckyWheelFixture.buttons,
          options:
              const WheelOptions(gutter: 3, offsetDegree: 10, stopRange: 0.5),
          style: const WheelStyle(background: _fill));
      expect(full.blocks.single.padding, 5);
      expect(full.prizes, kLuckyWheelFixture.prizes);
      expect(full.buttons, kLuckyWheelFixture.buttons);
      expect(full.options.gutter, 3);
      expect(full.options.offsetDegree, 10);
      expect(full.options.stopRange, 0.5);
      expect(full.style.background, _fill);
      expect(full, full.copyWith());
      expect(full.hashCode, full.copyWith().hashCode);
      expect(full, isNot(config));
      expect(config == Object(), isFalse);
      final options = full.options.copyWith(
          gutter: 7,
          offsetDegree: 20,
          stopRange: 0.7,
          motion: const LuckyMotionOptions(speed: 5));
      expect(options.gutter, 7);
      expect(options.offsetDegree, 20);
      expect(options.stopRange, 0.7);
      expect(options.motion.speed, 5);
      expect(options, options.copyWith());
      expect(options.hashCode, options.copyWith().hashCode);
      expect(options, isNot(full.options));
      final style = full.style.copyWith(
          background: const LuckyFill.color(Color(0xff654321)),
          text: const LuckyTextDefaults(fontSize: 12));
      expect(style.background, const LuckyFill.color(Color(0xff654321)));
      expect(style.text.fontSize, 12);
      expect(style, style.copyWith());
      expect(style.hashCode, style.copyWith().hashCode);
      expect(style.copyWith(clearBackground: true).background, isNull);
      expect(style, isNot(full.style));
    });
    test(
        'block prize and button copies compare all content and callback fields',
        () {
      const block = WheelBlock();
      final changedBlock = block.copyWith(
          padding: 12,
          background: _fill,
          images: [const WheelBlockImage(_provider)]);
      expect(changedBlock.padding, 12);
      expect(changedBlock.background, _fill);
      expect(changedBlock.images.single.image, _provider);
      expect(changedBlock, changedBlock.copyWith());
      expect(changedBlock.hashCode, changedBlock.copyWith().hashCode);
      expect(block, block.copyWith());
      expect(block, isNot(changedBlock));

      /// 自定义内容应能读取全部几何字段。
      void painter(Canvas canvas, WheelPrizePaintContext context) {
        expect(context.index, 1);
        expect(context.sweepRad, 2);
        expect(context.prizeRadius, 3);
        expect(context.prizeHeight, 4);
        expect(context.shortSide, 5);
      }

      const prize = WheelPrize();
      final changedPrize = prize.copyWith(
          background: _fill,
          texts: [const LuckyText('奖品')],
          images: [const LuckyImage(_provider)],
          weight: 2,
          sectorWeight: 3,
          disabled: true,
          painter: painter,
          semanticsLabel: '奖品描述');
      expect(changedPrize.background, _fill);
      expect(changedPrize.texts.single.text, '奖品');
      expect(changedPrize.images.single.image, _provider);
      expect(changedPrize.weight, 2);
      expect(changedPrize.sectorWeight, 3);
      expect(changedPrize.disabled, isTrue);
      expect(changedPrize.semanticsLabel, '奖品描述');
      expect(changedPrize, changedPrize.copyWith());
      expect(changedPrize.hashCode, changedPrize.copyWith().hashCode);
      expect(prize, prize.copyWith());
      expect(prize, isNot(changedPrize));
      final recorder = ui.PictureRecorder();
      changedPrize.painter!(
          Canvas(recorder),
          WheelPrizePaintContext(
              index: changedPrize.weight!.toInt() - 1,
              sweepRad: 2,
              prizeRadius: 3,
              prizeHeight: 4,
              shortSide: 5));
      recorder.endRecording().dispose();

      const button = WheelButton();
      final changedButton = button.copyWith(
          radius: const LuckyLength.percent(30),
          pointer: true,
          background: _fill,
          texts: [const LuckyText('开始')],
          images: [const LuckyImage(_provider)]);
      expect(changedButton.radius.resolve(100), 30);
      expect(changedButton.pointer, isTrue);
      expect(changedButton.background, _fill);
      expect(changedButton.texts.single.text, '开始');
      expect(changedButton.images.single.image, _provider);
      expect(changedButton, changedButton.copyWith());
      expect(changedButton.hashCode, changedButton.copyWith().hashCode);
      expect(button, button.copyWith());
      expect(button, isNot(changedButton));
    });
    test(
        'block image copies retain inherited fields and include rotation in equality',
        () {
      const image = WheelBlockImage(_provider);
      expect(image, image.copyWith());
      expect(image.hashCode, image.copyWith().hashCode);

      /// formatter 保留图像所有权约定。
      ui.Image formatter(ui.Image source) => source;
      final changed = image.copyWith(
          image: const AssetImage('other.png'),
          top: const LuckyLength.px(1),
          left: const LuckyLength.px(2),
          width: const LuckyLength.px(3),
          height: const LuckyLength.px(4),
          formatter: formatter,
          borderRadius: 5,
          opacity: 0.5,
          fallback: _provider,
          semanticLabel: '图像',
          rotate: true);
      expect(changed.image, const AssetImage('other.png'));
      expect(changed.top, const LuckyLength.px(1));
      expect(changed.left, const LuckyLength.px(2));
      expect(changed.width, const LuckyLength.px(3));
      expect(changed.height, const LuckyLength.px(4));
      expect(changed.formatter, formatter);
      expect(changed.borderRadius, 5);
      expect(changed.opacity, 0.5);
      expect(changed.fallback, _provider);
      expect(changed.semanticLabel, '图像');
      expect(changed.rotate, isTrue);
      expect(changed, changed.copyWith());
      expect(changed.hashCode, changed.copyWith().hashCode);
      expect(image, isNot(changed));
      expect(image.copyWith(rotate: true), isNot(image));
    });
  });
}
