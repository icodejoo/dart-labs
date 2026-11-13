import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luckdraw/extend.dart';
import 'package:luckdraw/src/core/render/paint_helpers.dart';

/// 真实字体的测试样式。
const TextStyle _style = TextStyle(fontFamily: 'Roboto', fontSize: 20);

/// 指定的绘制基线。
const double _baseline = 50;

/// 绘制必须使用实际段落，不能查询只按样式计算的缓存基线。
class _RejectCachedBaseline implements LuckyTextMeasurer {
  /// 本测试只验证绘制阶段，不应重新测量宽度。
  @override
  double measure(String text, TextStyle style) =>
      throw StateError('绘制不应重新测量宽度');

  /// 即使平台字体的空格与 emoji 基线相同，也能检出错误的缓存依赖。
  @override
  double baseline(TextStyle style) => throw StateError('绘制必须使用实际段落基线');

  /// 测试替身不持有原生资源。
  @override
  void dispose() {}
}

/// 记录引擎收到的段落和实际字母基线。
class _ParagraphCanvas implements Canvas {
  /// 每次绘制的实际基线。
  final List<double> baselines = [];

  /// 每次绘制的真实行数。
  final List<int> lineCounts = [];

  /// 记录字母基线与内部行数。
  @override
  void drawParagraph(ui.Paragraph paragraph, Offset offset) {
    baselines.add(offset.dy + paragraph.alphabeticBaseline);
    lineCounts.add(paragraph.computeLineMetrics().length);
  }

  /// 其它绘制操作不影响文字断言。
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// 验证 Canvas 单行空白语义及实际回退字体基线。
void main() {
  group('Canvas text fidelity', () {
    test('normalizes canvas whitespace for real font wrapping and painting',
        () {
      final measurer = TextPainterMeasurer();
      addTearDown(measurer.dispose);
      final width = measurer.measure('a ', _style) + 0.01;
      for (final whitespace in [
        '\t',
        '\n',
        '\f',
        '\r',
        '\v',
        '\u2028',
        '\u2029',
        '\u0085'
      ]) {
        final input = 'a${whitespace}b';
        expect(measurer.measure(input, _style), measurer.measure('a b', _style),
            reason: input);
        expect(
            measurer.debugPainters.single.computeLineMetrics(), hasLength(1));
        final actual = splitLuckyText(
            input, (s) => measurer.measure(s, _style), (_) => width);
        final expected = splitLuckyText(
            input,
            (s) => measurer.measure(s.replaceAll(whitespace, ' '), _style),
            (_) => width);
        expect(actual, expected, reason: input);
        expect(actual.join(), input);
        final canvas = _ParagraphCanvas();
        paintLuckyTextLines(
            canvas, [LuckyTextLine(input, 0, _baseline, _style)], measurer);
        expect(canvas.lineCounts, [1]);
      }
      final lines = layoutLuckyTextLines(
          text: const LuckyText('a\nb', wordWrap: false),
          defaults: const LuckyTextDefaults(fontFamily: 'Roboto', fontSize: 20),
          measurer: measurer,
          box: const Rect.fromLTWH(0, 0, 100, 100),
          leftBase: 100,
          topBase: 100,
          maxWidthOf: (_, __) => 100);
      expect(lines.map((line) => line.text), ['a', 'b']);
    });

    test('painted emoji fallback uses the actual paragraph alphabetic baseline',
        () async {
      final font = [
        'C:/Windows/Fonts/seguiemj.ttf',
        '/usr/share/fonts/truetype/noto/NotoColorEmoji.ttf',
        '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
        '/System/Library/Fonts/Apple Color Emoji.ttc',
      ].map(File.new).firstWhere((file) => file.existsSync());
      const family = 'LuckyF1Emoji';
      final loader = FontLoader(family)
        ..addFont(Future.value(ByteData.sublistView(await font.readAsBytes())));
      await loader.load();
      final style = _style.copyWith(fontFamilyFallback: [family]);
      final measurer = TextPainterMeasurer();
      addTearDown(measurer.dispose);
      for (final cache in [measurer, _RejectCachedBaseline(), null]) {
        final canvas = _ParagraphCanvas();
        paintLuckyTextLines(
            canvas, [LuckyTextLine('a😀', 0, _baseline, style)], cache);
        expect(canvas.baselines.single, closeTo(_baseline, 0.001));
      }
    });
  });
}
