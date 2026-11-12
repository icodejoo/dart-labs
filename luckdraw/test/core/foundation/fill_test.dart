import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luckdraw/luckdraw.dart';

/// 不透明红色测试色标。
const Color _red = Color(0xFFFF0000);

/// 不透明绿色测试色标。
const Color _green = Color(0xFF00FF00);

/// 不透明蓝色测试色标。
const Color _blue = Color(0xFF0000FF);

/// 渐变像素采样范围。
const Rect _sampleRect = Rect.fromLTWH(0, 0, 100, 1);

/// 以真实 shader 绘制一行像素，返回 RGBA 数据并释放图像资源。
Future<Uint8List> _pixels(LuckyFill fill) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  final paint = Paint();
  fill.applyTo(paint, _sampleRect);
  canvas.drawRect(_sampleRect, paint);
  final picture = recorder.endRecording();
  final image = await picture.toImage(100, 1);
  try {
    return (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!
        .buffer
        .asUint8List();
  } finally {
    image.dispose();
    picture.dispose();
  }
}

/// 以固定的上游端点和真实像素验证三种填充。
void main() {
  group('LuckyFill', () {
    const rect = Rect.fromLTWH(10, 20, 120, 80);
    test('color fill creates a solid paint', () async {
      const fill = LuckyFill.color(_red);
      final paint = Paint();
      const LuckyFill.gradient(LinearGradient(colors: [_red, _blue]))
          .applyTo(paint, rect);
      expect(paint.shader, isNotNull);
      fill.applyTo(paint, rect);
      expect(paint.color, _red);
      expect(paint.shader, isNull);
      expect(fill.solidAlpha8, 255);
      expect((await _pixels(fill)).take(4), [255, 0, 0, 255]);
    });
    test('gradient fill creates a shader for the given rect', () async {
      const fill = LuckyFill.gradient(LinearGradient(colors: [_red, _blue]));
      final paint = Paint()..color = const Color(0x00FFFFFF);
      fill.applyTo(paint, rect);
      expect(paint.shader, isNotNull);
      expect(paint.color, const Color(0xFF000000));
      expect(fill.solidAlpha8, isNull);
      final bytes = await _pixels(fill);
      expect(bytes[0], greaterThan(250));
      expect(bytes[398], greaterThan(250));
      expect(bytes[3], 255);
    });
    // 从上游 utils/math.ts:104-113 记录的非正方形矩形端点。
    const expected = <int, (Offset, Offset)>{
      0: (Offset(10, 100), Offset(130, 100)),
      30: (Offset(10, 100), Offset(130, 30)),
      45: (Offset(10, 100), Offset(130, 20)),
      60: (Offset(10, 100), Offset(108, 20)),
      90: (Offset(130, 100), Offset(130, 20)),
      120: (Offset(130, 100), Offset(83, 20)),
      135: (Offset(130, 100), Offset(10, 20)),
      150: (Offset(130, 100), Offset(10, 52)),
      180: (Offset(130, 20), Offset(10, 20)),
      200: (Offset(130, 20), Offset(10, 63)),
      225: (Offset(130, 20), Offset(10, 100)),
      250: (Offset(130, 20), Offset(47, 100)),
      270: (Offset(10, 20), Offset(10, 100)),
      300: (Offset(10, 20), Offset(56, 100)),
      315: (Offset(10, 20), Offset(130, 100)),
      340: (Offset(10, 20), Offset(130, 44)),
    };
    for (final deg in [
      0,
      30,
      45,
      60,
      90,
      120,
      135,
      150,
      180,
      200,
      225,
      250,
      270,
      300,
      315,
      340
    ]) {
      test('legacy linear gradient endpoints match upstream at $deg deg', () {
        expect(
            LuckyLegacyGradientDirection.angle(deg.toDouble()).endpoints(rect),
            expected[deg]);
      });
    }
    test(
        'legacy linear gradient keywords top bottom left right map to upstream endpoints',
        () {
      expect(
          const LuckyLegacyGradientDirection.keyword(LuckyGradientKeyword.top)
              .endpoints(rect),
          (const Offset(10, 100), const Offset(10, 20)));
      expect(
          const LuckyLegacyGradientDirection.keyword(
                  LuckyGradientKeyword.bottom)
              .endpoints(rect),
          (const Offset(10, 20), const Offset(10, 100)));
      expect(
          const LuckyLegacyGradientDirection.keyword(LuckyGradientKeyword.left)
              .endpoints(rect),
          (const Offset(130, 20), const Offset(10, 20)));
      expect(
          const LuckyLegacyGradientDirection.keyword(LuckyGradientKeyword.right)
              .endpoints(rect),
          (const Offset(10, 20), const Offset(130, 20)));
      expect(
          const LuckyLegacyGradientDirection.keyword(LuckyGradientKeyword.none)
              .endpoints(rect),
          (Offset.zero, Offset.zero));
    });
    test('legacy linear gradient truncates endpoints toward zero like >> 0',
        () {
      const fractional = Rect.fromLTWH(-12.9, -7.8, 41.2, 29.6);
      expect(const LuckyLegacyGradientDirection.angle(30).endpoints(fractional),
          (const Offset(-12, 21), const Offset(28, -1)));
      expect(
          const LuckyLegacyGradientDirection.keyword(LuckyGradientKeyword.top)
              .endpoints(fractional),
          (const Offset(-12, 21), const Offset(-12, -7)));
    });
    test('negative angle is normalized into 0..360 (IMP-20)', () {
      expect(const LuckyLegacyGradientDirection.angle(-30).endpoints(rect),
          const LuckyLegacyGradientDirection.angle(330).endpoints(rect));
      expect(const LuckyLegacyGradientDirection.angle(-750).endpoints(rect),
          const LuckyLegacyGradientDirection.angle(330).endpoints(rect));
      expect(const LuckyLegacyGradientDirection.angle(720).endpoints(rect),
          expected[0]);
    });
    test('hasBackground semantics: only null means no background', () {
      const noBackground = LuckyCellStyle();
      const transparent =
          LuckyCellStyle(background: LuckyFill.color(Color(0x00000000)));
      expect(noBackground.background, isNull);
      expect(transparent.background, isNotNull);
      expect(transparent.background!.solidAlpha8, 0);
      expect(transparent, isNot(noBackground));
    });
    test(
        'legacy stops spread evenly and explicit offsets control rendered colors',
        () async {
      const direction = LuckyLegacyGradientDirection.angle(0);
      const fill = LuckyLegacyLinearFill(direction, [
        LuckyColorStop(_red),
        LuckyColorStop(_green),
        LuckyColorStop(_blue)
      ]);
      final bytes = await _pixels(fill);
      expect(bytes[0], greaterThan(250));
      expect(bytes[50 * 4 + 1], greaterThan(250));
      expect(bytes[99 * 4 + 2], greaterThan(250));
      final explicit = await _pixels(fill.copyWith(stops: const [
        LuckyColorStop(_red, 0),
        LuckyColorStop(_green, 0.25),
        LuckyColorStop(_blue, 1)
      ]));
      expect(explicit[25 * 4 + 1], greaterThan(250));
      expect(explicit[50 * 4 + 2], greaterThan(bytes[50 * 4 + 2]));
      final two = await _pixels(const LuckyFill.legacyLinear(
          direction, [LuckyColorStop(_red), LuckyColorStop(_blue)]));
      expect(two[0], greaterThan(250));
      expect(two[398], greaterThan(250));
      expect(
          () =>
              const LuckyLegacyLinearFill(direction, []).applyTo(Paint(), rect),
          throwsArgumentError);
      expect(
          () => const LuckyLegacyLinearFill(direction, [LuckyColorStop(_red)])
              .applyTo(Paint(), rect),
          throwsArgumentError);
    });
    test('fill directions and stops have value equality and copyWith', () {
      const direction = LuckyLegacyGradientDirection.angle(30);
      const keyword =
          LuckyLegacyGradientDirection.keyword(LuckyGradientKeyword.top);
      expect(direction.copyWith(), direction);
      expect(direction.copyWith(degrees: 30).hashCode, direction.hashCode);
      expect(direction.copyWith(keyword: LuckyGradientKeyword.top), keyword);
      expect(keyword.copyWith(degrees: 30), direction);
      expect(
          () => direction.copyWith(
              degrees: 10, keyword: LuckyGradientKeyword.top),
          throwsArgumentError);
      expect(direction == Object(), isFalse);
      const stop = LuckyColorStop(_red, 0.25);
      expect(stop.copyWith(), stop);
      expect(stop.copyWith().hashCode, stop.hashCode);
      expect(stop.copyWith(color: _blue, offset: 1),
          const LuckyColorStop(_blue, 1));
      expect(stop == Object(), isFalse);
      const solid = LuckyColorFill(_red);
      expect(solid.copyWith(), solid);
      expect(solid.copyWith().hashCode, solid.hashCode);
      expect(solid.copyWith(color: _blue), const LuckyColorFill(_blue));
      expect(solid == Object(), isFalse);
      const native = LuckyGradientFill(LinearGradient(colors: [_red, _blue]));
      expect(native.copyWith(), native);
      expect(native.copyWith().hashCode, native.hashCode);
      expect(
          native.copyWith(
              gradient: const RadialGradient(colors: [_red, _blue])),
          const LuckyGradientFill(RadialGradient(colors: [_red, _blue])));
      expect(native == Object(), isFalse);
      const legacy =
          LuckyLegacyLinearFill(direction, [stop, LuckyColorStop(_blue)]);
      final equal = LuckyLegacyLinearFill(
          direction, [stop.copyWith(), const LuckyColorStop(_blue)]);
      expect(legacy, equal);
      expect(legacy.hashCode, equal.hashCode);
      expect(legacy.copyWith(), legacy);
      expect(legacy.copyWith(direction: keyword).direction, keyword);
      expect(legacy.copyWith(stops: const [stop, stop]).stops, [stop, stop]);
      expect(legacy == Object(), isFalse);
    });
  });
}
