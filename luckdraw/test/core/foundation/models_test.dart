import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luckdraw/extend.dart' as spi;
import 'package:luckdraw/luckdraw.dart';
import 'package:luckdraw/src/core/foundation/constants.dart';

/// 基础测试颜色。
const Color _color = Color(0xFF123456);

/// 图片主资源，测试不发起实际资源加载。
const AssetImage _asset = AssetImage('gift.png');

/// 替换或后备图片资源。
const AssetImage _fallback = AssetImage('fallback.png');

/// 测试文字内容。
const String _label = '奖品';

/// 测试字体族。
const String _family = 'Roboto';

/// 测试后备字体族。
const String _fallbackFamily = 'Noto Sans';

/// 测试图片分组。
const String _group = 'prizes';

/// 测试像素长度。
const LuckyLength _px = LuckyLength.px(12);

/// 测试百分比长度。
const LuckyLength _percent = LuckyLength.percent(40);

/// 测试纯色背景。
const LuckyFill _fill = LuckyFill.color(_color);

/// 测试描边。
const LuckyBorder _border = LuckyBorder(width: 2, color: _color);

/// 测试文字覆盖。
const LuckyTextOverride _override = LuckyTextOverride(color: _color);

/// 测试阴影。
const LuckyShadow _shadow = LuckyShadow(blur: 8, color: _color);

/// 返回原图的同步 formatter，用于验证函数字段保留。
ui.Image _identity(ui.Image source) => source;

/// 断言非同一类型不会相等，且相等值可作为同一个哈希键。
void _expectValue(Object actual, Object equal) {
  expect(actual, equal);
  expect(actual.hashCode, equal.hashCode);
  expect({actual, equal}, hasLength(1));
  expect(actual == Object(), isFalse);
}

/// 验证 const 模型、字段复制、默认值及 SPI 的基础导出。
void main() {
  group('core models', () {
    test(
        'LuckyText LuckyImage LuckyCellStyle and LuckyBoxBlock are const and value-equal',
        () {
      const text = LuckyText(_label, fontFamilyFallback: [_fallbackFamily]);
      _expectValue(text.copyWith(fontFamilyFallback: [_fallbackFamily]), text);
      const image = LuckyImage(_asset, width: _percent);
      _expectValue(image.copyWith(), image);
      const style =
          LuckyCellStyle(background: _fill, border: _border, text: _override);
      _expectValue(style.copyWith(), style);
      const block = LuckyBoxBlock(images: [image], background: _fill);
      _expectValue(block.copyWith(images: [image.copyWith()]), block);
      _expectValue(_border.copyWith(), _border);
      const defaults = LuckyTextDefaults(fontFamilyFallback: [_fallbackFamily]);
      _expectValue(
          defaults.copyWith(fontFamilyFallback: [_fallbackFamily]), defaults);
      _expectValue(
          _override.copyWith(fontFamilyFallback: [_fallbackFamily]),
          const LuckyTextOverride(
              color: _color, fontFamilyFallback: [_fallbackFamily]));
      expect(block, isNot(block.copyWith(images: [])));
      expect(text, isNot(text.copyWith(fontFamilyFallback: [])));
      expect(defaults, isNot(defaults.copyWith(fontFamilyFallback: [])));
      expect(_override, isNot(_override.copyWith(color: kLuckyTransparent)));
    });
    test('copyWith replaces only the given fields', () {
      const text =
          LuckyText(_label, top: _px, fontFamilyFallback: [_fallbackFamily]);
      expect(
          text.copyWith(color: _color),
          const LuckyText(_label,
              top: _px, fontFamilyFallback: [_fallbackFamily], color: _color));
      expect(
          text.copyWith(
              text: '',
              top: LuckyLength.zero,
              left: _percent,
              color: _color,
              fontSize: 24,
              fontFamily: _family,
              fontFamilyFallback: [],
              fontWeight: FontWeight.w700,
              lineHeight: 30,
              wordWrap: false,
              lengthLimit: _px,
              lineClamp: 0),
          const LuckyText('',
              top: LuckyLength.zero,
              left: _percent,
              color: _color,
              fontSize: 24,
              fontFamily: _family,
              fontFamilyFallback: [],
              fontWeight: FontWeight.w700,
              lineHeight: 30,
              wordWrap: false,
              lengthLimit: _px,
              lineClamp: 0));
      const defaults = LuckyTextDefaults();
      expect(defaults.copyWith(), defaults);
      expect(
          defaults.copyWith(
              color: _color,
              fontSize: 24,
              fontFamily: _family,
              fontFamilyFallback: [_fallbackFamily],
              fontWeight: FontWeight.w700,
              lineHeight: 30,
              wordWrap: false,
              lengthLimit: _px,
              lineClamp: 2),
          const LuckyTextDefaults(
              color: _color,
              fontSize: 24,
              fontFamily: _family,
              fontFamilyFallback: [_fallbackFamily],
              fontWeight: FontWeight.w700,
              lineHeight: 30,
              wordWrap: false,
              lengthLimit: _px,
              lineClamp: 2));
      const override = LuckyTextOverride();
      expect(override.copyWith(), override);
      expect(
          override.copyWith(
              color: _color,
              fontSize: 24,
              fontFamily: _family,
              fontFamilyFallback: [_fallbackFamily],
              fontWeight: FontWeight.w700,
              lineHeight: 30),
          const LuckyTextOverride(
              color: _color,
              fontSize: 24,
              fontFamily: _family,
              fontFamilyFallback: [_fallbackFamily],
              fontWeight: FontWeight.w700,
              lineHeight: 30));
      const image = LuckyImage(_asset, semanticLabel: _label);
      expect(image.copyWith(opacity: 0),
          const LuckyImage(_asset, semanticLabel: _label, opacity: 0));
      final changedImage = image.copyWith(
          image: _fallback,
          top: _px,
          left: _percent,
          width: _percent,
          height: _px,
          formatter: _identity,
          borderRadius: 8,
          opacity: 0.5,
          fallback: _asset,
          semanticLabel: '');
      expect(
          changedImage,
          const LuckyImage(_fallback,
              top: _px,
              left: _percent,
              width: _percent,
              height: _px,
              formatter: _identity,
              borderRadius: 8,
              opacity: 0.5,
              fallback: _asset,
              semanticLabel: ''));
      expect(identical(changedImage.formatter, _identity), isTrue);
      expect(image.semanticLabel, _label);
      expect(_border.copyWith(width: 0, color: kLuckyTransparent),
          const LuckyBorder(width: 0, color: kLuckyTransparent));
      const style = LuckyCellStyle(background: _fill);
      expect(style.copyWith(border: _border),
          const LuckyCellStyle(background: _fill, border: _border));
      expect(
          style.copyWith(
              background: const LuckyFill.color(kLuckyTransparent),
              shadow: _shadow,
              borderRadius: 8,
              border: _border,
              foreground: _fill,
              text: _override),
          const LuckyCellStyle(
              background: LuckyFill.color(kLuckyTransparent),
              shadow: _shadow,
              borderRadius: 8,
              border: _border,
              foreground: _fill,
              text: _override));
      const block = LuckyBoxBlock(images: [image]);
      expect(block.copyWith(borderRadius: 8),
          const LuckyBoxBlock(images: [image], borderRadius: 8));
      expect(
          block.copyWith(
              padding: const LuckyEdgeInsets.all(4),
              borderRadius: 8,
              background: _fill,
              border: _border,
              images: []),
          const LuckyBoxBlock(
              padding: LuckyEdgeInsets.all(4),
              borderRadius: 8,
              background: _fill,
              border: _border));
      expect(text.copyWith(top: null), text);
      expect(style.copyWith(background: null), style);
    });
    test('LuckyTextDefaults match upstream defaultStyle', () {
      const defaults = LuckyTextDefaults();
      expect(defaults.color, const Color(0xFF000000));
      expect(defaults.fontSize, 18);
      expect(defaults.fontFamily, isNull);
      expect(defaults.fontFamilyFallback, isNull);
      expect(defaults.fontWeight, FontWeight.w400);
      expect(defaults.lineHeight, isNull);
      expect(defaults.wordWrap, isTrue);
      expect(defaults.lengthLimit, const LuckyLength.percent(90));
      expect(defaults.lineClamp, isNull);
      expect(const LuckyText(_label).wordWrap, isNull);
      expect(const LuckyText(_label, wordWrap: false).wordWrap, isFalse);
    });
    test('image slots requests and errors retain providers and diagnostics',
        () {
      const slot = spi.LuckyImageSlot(_group, 1, 0);
      expect(slot.toString(), 'prizes[1].imgs[0]');
      expect(slot.copyWith(active: true).toString(), 'prizes[1].activeImgs[0]');
      _expectValue(slot.copyWith(), slot);
      expect(
          slot.copyWith(
              group: 'blocks', itemIndex: 2, imageIndex: 3, active: true),
          const spi.LuckyImageSlot('blocks', 2, 3, active: true));
      const image = LuckyImage(_asset);
      const request =
          spi.LuckyImageRequest(slot: slot, image: image, provider: _asset);
      _expectValue(request.copyWith(), request);
      expect(request.decodeLogicalWidth, isNull);
      expect(request.decodeLogicalHeight, isNull);
      final activeSlot = slot.copyWith(active: true);
      final replacement = image.copyWith(image: _fallback);
      final changed = request.copyWith(
          slot: activeSlot,
          image: replacement,
          provider: _fallback,
          decodeLogicalWidth: 40,
          decodeLogicalHeight: 50);
      expect(
          changed,
          spi.LuckyImageRequest(
              slot: activeSlot,
              image: replacement,
              provider: _fallback,
              decodeLogicalWidth: 40,
              decodeLogicalHeight: 50));
      expect(identical(changed.provider, _fallback), isTrue);
      final error = StateError('无法解码');
      final stack = StackTrace.current;
      final diagnostic = LuckyImageError(slot: slot, error: error);
      _expectValue(diagnostic.copyWith(), diagnostic);
      expect(diagnostic.usedFallback, isFalse);
      expect(diagnostic.stackTrace, isNull);
      final secondError = ArgumentError('后备图失败');
      expect(
          diagnostic.copyWith(
              slot: activeSlot,
              error: secondError,
              stackTrace: stack,
              usedFallback: true),
          LuckyImageError(
              slot: activeSlot,
              error: secondError,
              stackTrace: stack,
              usedFallback: true));
      expect(diagnostic.copyWith(stackTrace: stack).stackTrace, same(stack));
    });
    test('performance options keep vector defaults and accept raster overrides',
        () {
      const options = LuckyPerformanceOptions();
      _expectValue(options.copyWith(), options);
      expect(options.cacheMode, LuckyCacheMode.auto);
      expect(options.maxRasterSide, 4096);
      expect(options.pauseWhenHidden, isTrue);
      expect(options.filterQuality, FilterQuality.low);
      expect(
          options.copyWith(
              cacheMode: LuckyCacheMode.raster,
              maxRasterSide: 2048,
              pauseWhenHidden: false,
              filterQuality: FilterQuality.high),
          const LuckyPerformanceOptions(
              cacheMode: LuckyCacheMode.raster,
              maxRasterSide: 2048,
              pauseWhenHidden: false,
              filterQuality: FilterQuality.high));
      expect(LuckyTextScaling.values,
          [LuckyTextScaling.none, LuckyTextScaling.system]);
    });
    test('angle conversion and shared constants retain upstream units', () {
      expect(spi.luckyDegToRad(180), math.pi);
      expect(spi.luckyDegToRad(-90), -math.pi / 2);
      expect(spi.luckyDegToRad(73.31), math.pi / 180 * 73.31);
      expect(spi.kLuckyReferenceFrameMs, 1000 / 60);
      expect(kLuckyInitialFps, 16.6);
      expect(kLuckyDefaultMaxFrameDelta, const Duration(milliseconds: 100));
      expect(kLuckyMaxSolverIterations, 100000);
      expect(kLuckyDefaultMaxRasterSide, 4096);
      expect(kLuckyEllipsis, '...');
      expect(kLuckyPointerDeg, -90);
      expect(kLuckyGridSpeedDivisor, 40);
      expect(kLuckyGridAccelerationBase, 0.1);
      expect(kLuckyDefaultSpeed, 20);
      expect(kLuckyDefaultAccelerationTime, const Duration(milliseconds: 2500));
      expect(kLuckyDefaultDecelerationTime, const Duration(milliseconds: 2500));
      expect(kLuckyDefaultIdleSpinSpeed, 2);
      expect(kLuckyTransparent, const Color(0x00000000));
      expect(kLuckyGridActiveBackground, const Color(0xFFFFCE98));
      expect(kLuckyGridDefaultGutter, 5);
      expect(kLuckyGridDefaultBorderRadius, 20);
      expect(kLuckySlotDefaultColSpacing, 5);
    });
  });
}
