import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luckdraw/extend.dart';
import 'package:luckdraw/src/wheel/layout/wheel_layout.dart';
import 'package:luckdraw/wheel.dart';

import '../support/fixtures.dart';

/// 固定每字符十像素、基线八像素的测量器。
final class _FixedMeasurer implements LuckyTextMeasurer {
  /// 返回固定字符宽度。
  @override
  double measure(String text, TextStyle style) => text.runes.length * 10;

  /// 返回固定字母基线。
  @override
  double baseline(TextStyle style) => 8;

  /// 无原生资源需要释放。
  @override
  void dispose() {}
}

/// 生成固定测量环境，避免字体平台差异。
WheelLayout _layout(
        [WheelConfig config = kLuckyWheelFixture,
        Size size = const Size(300, 200),
        Alignment alignment = Alignment.topLeft]) =>
    computeWheelLayout(
        config,
        LuckyLayoutInput(
            size: size,
            devicePixelRatio: 1,
            measurer: _FixedMeasurer(),
            alignment: alignment));

/// 仅替换首个奖品的文字，保留等分六扇区。
WheelConfig _textConfig(List<LuckyText> texts,
        {WheelStyle style = const WheelStyle()}) =>
    kLuckyWheelFixture.copyWith(prizes: [
      WheelPrize(texts: texts),
      ...kLuckyWheelFixture.prizes.skip(1)
    ], buttons: [], style: style);

/// 验证转盘几何与上游内容坐标。
void main() {
  group('computeWheelLayout', () {
    test(
        'radius is half the shorter side and center is (R, R) for topLeft alignment',
        () {
      final layout = _layout();
      expect(layout.radius, 100);
      expect(layout.center, const Offset(100, 100));
      expect(layout.isEmpty, isFalse);
      expect(_layout(const WheelConfig(), Size.zero).isEmpty, isTrue);
    });
    test('alignment center moves the wheel into the box middle', () {
      expect(
          _layout(kLuckyWheelFixture, const Size(300, 200), Alignment.center)
              .center,
          const Offset(150, 100));
    });
    test('blocks shrink prize radius by the first padding token', () {
      final layout = _layout(kLuckyWheelFixture.copyWith(blocks: [
        const WheelBlock(padding: 10),
        const WheelBlock(padding: 5)
      ]));
      expect(layout.blocks.map((b) => b.radius), [100, 90]);
      expect(layout.prizeRadius, 85);
    });
    test('uniform sector middles start at -90 + prizeDeg / 2 + offsetDegree',
        () {
      final layout = _layout(kLuckyWheelFixture.copyWith(
          options: const WheelOptions(offsetDegree: 17)));
      for (var i = 0; i < layout.sectors.length; i++) {
        expect(layout.sectors[i].middleRad,
            luckyDegToRad(-90 + 30 + 17) + i * luckyDegToRad(60));
        expect(layout.sectors[i].localRotation,
            layout.sectors[i].middleRad + math.pi / 2);
      }
      expect(layout.sectors.first.anchor.distance, closeTo(100, 1e-12));
      expect(layout.sectors.first.fan.getBounds().isEmpty, isFalse);
    });
    test('sector weights produce proportional sweeps (#151)', () {
      final layout = _layout(const WheelConfig(
          prizes: [WheelPrize(sectorWeight: 1), WheelPrize(sectorWeight: 3)]));
      expect(layout.angles.uniform, isFalse);
      expect(layout.angles.startDeg(1), 90);
      expect(layout.angles.sweepDeg(0), 90);
      expect(layout.angles.sweepDeg(1), 270);
      expect(layout.sectors[1].middleRad, luckyDegToRad(-90 + 90 + 135));
    });
    test(
        'button radius resolves percent against prize radius and maxBtnRadius is computed upfront',
        () {
      final layout = _layout(kLuckyWheelFixture.copyWith(blocks: [
        const WheelBlock(padding: 20)
      ], buttons: [
        const WheelButton(radius: LuckyLength.percent(50)),
        const WheelButton(
            radius: LuckyLength.px(10),
            pointer: true,
            background: LuckyFill.color(Color(0xff123456)))
      ]));
      expect(layout.maxBtnRadius, 40);
      expect(layout.sectors.first.prizeHeight, 40);
      expect(layout.buttons.last.pointerPath!.getBounds(),
          const Rect.fromLTRB(-10, -20, 10, 0));
      expect(layout.buttons.first.pointerPath, isNull);
      expect(_layout().buttons.single.pointerPath, isNull);
    });
    test('prize text wraps with the per-line upstream width formula', () {
      final layout = _layout(_textConfig([
        const LuckyText('abcdefghijklmnopqrstuvwx',
            top: LuckyLength.px(5),
            lineHeight: 10,
            lengthLimit: LuckyLength.percent(100))
      ]));
      final lines = layout.sectors.first.texts;
      expect(lines.map((l) => l.text), ['abcdefghi', 'jklmnopq', 'rstuvwx']);
      for (var i = 0; i < lines.length; i++) {
        expect(
            lines[i].text.length * 10,
            lessThanOrEqualTo(
                (100 - (5 + (i + 1) * 10)) * math.tan(math.pi / 6) * 2));
      }
    });
    test('prize text without wordWrap splits on newlines and drops empty lines',
        () {
      final texts =
          _layout(_textConfig([const LuckyText('甲\n\n乙\n', wordWrap: false)]))
              .sectors
              .first
              .texts;
      expect(texts.map((l) => l.text), ['甲', '乙']);
      expect(texts.map((l) => l.baselineY), [18, 36]);
    });
    test(
        'button text splits on newlines without wrapping and keeps empty lines',
        () {
      final layout = _layout(kLuckyWheelFixture.copyWith(buttons: [
        const WheelButton(
            texts: [LuckyText('甲\n\n乙\n', lengthLimit: LuckyLength.px(1))])
      ]));
      expect(
          layout.buttons.single.texts.map((l) => l.text), ['甲', '', '乙', '']);
    });
    test('text baseline y is top + (lineIndex + 1) * lineHeight', () {
      final lines = _layout(_textConfig([
        const LuckyText('甲\n乙',
            top: LuckyLength.percent(10), lineHeight: 12, wordWrap: false)
      ])).sectors.first.texts;
      expect(lines.map((l) => l.baselineY), [22, 34]);
      expect(lines.first.x, -5);
    });
    test(
        'line height falls back lineHeight -> default lineHeight -> fontSize -> default fontSize',
        () {
      final cases = [
        _textConfig([const LuckyText('甲', lineHeight: 11, fontSize: 13)],
            style: const WheelStyle(text: LuckyTextDefaults(lineHeight: 12))),
        _textConfig([const LuckyText('甲', fontSize: 13)],
            style: const WheelStyle(text: LuckyTextDefaults(lineHeight: 12))),
        _textConfig([const LuckyText('甲', fontSize: 13)]),
        _textConfig([const LuckyText('甲')]),
      ];
      expect(cases.map((c) => _layout(c).sectors.first.texts.single.baselineY),
          [11, 12, 13, 18]);
    });
    test(
        'button text left offset resolves against the prize chord like upstream',
        () {
      final layout = _layout(kLuckyWheelFixture.copyWith(buttons: [
        const WheelButton(
            radius: LuckyLength.px(20),
            texts: [LuckyText('甲', left: LuckyLength.percent(50))])
      ]));
      expect(layout.buttons.single.texts.single.x,
          closeTo(-5 + 100 * math.sin(math.pi / 6), 1e-12));
    });
    test('prize image box uses arc length and prize height as max box', () {
      const image = LuckyImage(AssetImage('gift.png'),
          width: LuckyLength.percent(50),
          height: LuckyLength.percent(50),
          left: LuckyLength.percent(10),
          top: LuckyLength.percent(10));
      final layout = _layout(kLuckyWheelFixture.copyWith(prizes: [
        const WheelPrize(images: [image]),
        ...kLuckyWheelFixture.prizes.skip(1)
      ]));
      final placement = layout.sectors.first.images.single;
      expect(placement.maxWidth, luckyDegToRad(60) * 100);
      expect(placement.maxHeight, 70);
      expect(placement.leftBase, closeTo(100, 1e-12));
      expect(placement.topBase, 70);
      expect(placement.place(const Size(10, 10)).top, 7);
      expect(placement.slot, const LuckyImageSlot('prizes', 0, 0));
    });
    test('block image is centered and offset by top - radius', () {
      const image = WheelBlockImage(AssetImage('block.png'),
          top: LuckyLength.percent(25), rotate: true);
      final layout = _layout(const WheelConfig(blocks: [
        WheelBlock(images: [image])
      ], buttons: [
        WheelButton(radius: LuckyLength.px(20), images: [image])
      ]));
      final placement = layout.blocks.single.images.single;
      expect(placement.place(const Size(40, 20)),
          const Rect.fromLTWH(-20, -50, 40, 20));
      expect(layout.blocks.single.rotate, [true]);
      expect(layout.buttons.single.images.single.maxWidth, 40);
      expect(layout.buttons.single.images.single.leftBase, 20);
      expect(layout.buttons.single.images.single.topBase, 20);
    });
    test('empty prizes produce no sectors and no NaN', () {
      final layout = _layout(const WheelConfig(buttons: [
        WheelButton(texts: [LuckyText('开始')])
      ]));
      expect(layout.sectors, isEmpty);
      expect(layout.angles.prizeDeg, 0);
      expect(layout.buttons.single.texts.single.x.isFinite, isTrue);
      expect(layout.angles.sectorAtPointer(0, 0), -1);
    });
    test(
        'padding larger than the radius clamps to zero without throwing (#336)',
        () {
      final layout = _layout(kLuckyWheelFixture
          .copyWith(blocks: [const WheelBlock(padding: 500)]));
      expect(layout.prizeRadius, 0);
      expect(layout.sectors.first.fan.getBounds(), Rect.zero);
    });
    test('sectorAtPointer inverts the final angle to the target sector', () {
      final configs = [
        kLuckyWheelFixture,
        const WheelConfig(prizes: [WheelPrize(), WheelPrize(sectorWeight: 3)])
      ];
      for (final config in configs) {
        final angles = WheelSectorAngles.fromConfig(config);
        for (var i = 0; i < angles.count; i++) {
          expect(
              angles.sectorAtPointer(
                  720 - angles.startDeg(i) - angles.sweepDeg(i) / 2 - 17, 17),
              i);
        }
        expect(angles.sectorAtPointer(double.nan, 0), -1);
      }
      const roundingConfig = WheelConfig(prizes: [
        WheelPrize(sectorWeight: 2),
        WheelPrize(sectorWeight: 10),
        WheelPrize()
      ]);
      final roundingAngles = WheelSectorAngles.fromConfig(roundingConfig);
      // 最后一段的浮点终点略小于 360，端点应归入末段。
      expect(roundingAngles.sectorAtPointer(-359.99999999999994, 0), 2);
    });
    test('invalid sector weights are rejected and nonfinite sizes stay empty',
        () {
      expect(
          () =>
              _layout(const WheelConfig(prizes: [WheelPrize(sectorWeight: 0)])),
          throwsArgumentError);
      expect(
          () => _layout(const WheelConfig(
              prizes: [WheelPrize(sectorWeight: double.infinity)])),
          throwsArgumentError);
      expect(
          () => _layout(const WheelConfig(prizes: [
                WheelPrize(sectorWeight: 1e308),
                WheelPrize(sectorWeight: 9e307)
              ])),
          throwsArgumentError);
      expect(
          _layout(const WheelConfig(),
                  const Size(double.infinity, double.infinity))
              .isEmpty,
          isTrue);
    });
  });
}
