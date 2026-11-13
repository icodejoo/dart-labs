import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xvg/src/animation/animated_svg_painter.dart';
import 'package:xvg/src/animation/shared_animation_clock.dart';
import 'package:xvg/xvg.dart';

import 'animation/pixel_test_utils.dart';

/// 无动画的文字源，用 currentColor 同时验证主题透传。
const _textSource =
    '<svg width="$_side" height="$_side" viewBox="0 0 100 100">'
    '<text x="20" y="70" font-size="60" fill="currentColor">I</text></svg>';

/// 字形测试的逻辑边长。
const _side = 100;

/// Side after doubling the source dimensions. / 源尺寸翻倍后的画布边长。
const _scaledSide = _side * 2;

/// 检查静止状态的长间隔。
const _idleInterval = Duration(seconds: 5);

/// 测试使用的主题色。
const _red = Color(0xffff0000);

/// 测试使用的重着色颜色。
const _green = Color(0xff00ff00);

/// Covers text dispatch pixels, idle frames, parameters and errors.
/// 覆盖文字分发后的像素、停帧、参数及错误处理。
void main() {
  setUp(() => XvgDocumentCache.instance.clear());
  tearDown(() => XvgDocumentCache.instance.clear());

  testWidgets('静态文字源的非零 viewBox 原点和缩放保持字形位置', (tester) async {
    final key = GlobalKey();
    final reference = _textSource.replaceFirst(
      'width="$_side" height="$_side"',
      'width="$_scaledSide" height="$_scaledSide"',
    );
    final shifted = reference
        .replaceFirst('viewBox="0 0 100 100"', 'viewBox="50 50 100 100"')
        .replaceFirst('x="20" y="70"', 'x="70" y="120"');
    final images = <ByteData>[];
    for (final source in [reference, shifted]) {
      await tester.pumpWidget(
        Center(
          child: RepaintBoundary(
            key: key,
            child: Xvg.string(source, pixelSnap: XvgPixelSnap.never),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(AnimatedXvg), findsOneWidget);
      expect(find.byType(StaticXvg), findsNothing);
      images.add(await captureBoundaryPixels(tester, key));
    }
    expect(images.last.buffer.asUint8List(), images.first.buffer.asUint8List());
    var ink = 0;
    for (var y = 0; y < _scaledSide; y++) {
      for (var x = 0; x < _scaledSide; x++) {
        if (images.last.getUint8((y * _scaledSide + x) * 4 + 3) == 0) {
          continue;
        }
        expect(x, inInclusiveRange(40, 159));
        expect(y, inInclusiveRange(20, 179));
        ink++;
      }
    }
    expect(ink, greaterThan(0));
    expect(SharedAnimationClock.instance.subscriberCount, 0);
  });

  for (final entry in <String, (XvgTheme?, ColorFilter?, Color)>{
    '默认 currentColor': (null, null, const Color(0xff000000)),
    '主题 currentColor': (const XvgTheme(currentColor: _red), null, _red),
    '颜色滤镜': (
      const XvgTheme(currentColor: _red),
      const ColorFilter.mode(_green, BlendMode.srcIn),
      _green,
    ),
  }.entries) {
    testWidgets('Xvg.string 的${entry.key}能画出静态文字且不持续 tick', (tester) async {
      final key = GlobalKey();
      final loaded = <XvgAnimationInfo>[];
      final (theme, filter, expected) = entry.value;
      await tester.pumpWidget(
        Center(
          child: RepaintBoundary(
            key: key,
            child: Xvg.string(
              _textSource,
              theme: theme,
              colorFilter: filter,
              pixelSnap: XvgPixelSnap.never,
              onLoaded: loaded.add,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(AnimatedXvg), findsOneWidget);
      expect(find.byType(StaticXvg), findsNothing);
      expect(tester.getSize(find.byType(Xvg)), const Size.square(_side * 1.0));
      expect(loaded, hasLength(1));
      expect(loaded.single.settleTime, Duration.zero);
      expect(loaded.single.loops, isFalse);
      expect(SharedAnimationClock.instance.subscriberCount, 0);
      expect(tester.binding.hasScheduledFrame, isFalse);
      expect(tester.binding.transientCallbackCount, 0);

      final pixels = await captureBoundaryPixels(tester, key);
      var glyphHits = 0;
      for (var y = 40; y <= 65; y += 5) {
        for (var x = 22; x <= 35; x += 4) {
          final offset = (y * _side + x) * 4;
          if (pixels.getUint8(offset + 3) > 200) {
            expect(
              pixels.getUint32(offset, Endian.big),
              expected.toARGB32() << 8 & 0xffffffff | 255,
            );
            glyphHits++;
          }
        }
      }
      expect(glyphHits, greaterThan(0), reason: '文字的实际字形必须有不透明像素');
      expect(pixels.getUint8((2 * _side + 2) * 4 + 3), 0);
      await tester.pump(_idleInterval);
      expect(SharedAnimationClock.instance.subscriberCount, 0);
      expect(tester.binding.hasScheduledFrame, isFalse);
      expect(loaded, hasLength(1));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('同一文字源切换主题时重绘，并保留尺寸及布局参数', (tester) async {
    for (final color in [_red, const Color(0xff0000ff)]) {
      await tester.pumpWidget(
        Center(
          child: Xvg.string(
            _textSource,
            theme: XvgTheme(currentColor: color),
            width: 120,
            height: 80,
            fit: BoxFit.fill,
            alignment: Alignment.bottomRight,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final painter =
          tester.widget<CustomPaint>(find.byType(CustomPaint)).painter!
              as AnimatedSvgPainter;
      expect(painter.theme.currentColor, color);
      expect(painter.fit, BoxFit.fill);
      expect(painter.alignment, Alignment.bottomRight);
      expect(tester.getSize(find.byType(Xvg)), const Size(120, 80));
      expect(SharedAnimationClock.instance.subscriberCount, 0);
    }
  });

  testWidgets('文字解析失败的 onError 在帧后只调用一次，并显示 errorBuilder', (tester) async {
    final errors = <Object>[];
    const fallback = ValueKey('文字错误');
    await tester.pumpWidget(
      Center(
        child: Xvg.string(
          '<svg><text>',
          onError: (error, stack) => errors.add(error),
          errorBuilder: (context, error, stack) =>
              const SizedBox(key: fallback),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(errors, hasLength(1));
    expect(find.byKey(fallback), findsOneWidget);
    await tester.pump(_idleInterval);
    expect(errors, hasLength(1));
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.takeException(), isNull);
  });
}
