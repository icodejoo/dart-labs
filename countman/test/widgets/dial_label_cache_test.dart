import 'dart:ui' as ui;

import 'package:countman/countman.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/manual_clock.dart';

// 保存实际绘制的段落及位置，验证缓存身份和原有对齐。
class _LabelCanvas implements Canvas {
  final paragraphs = <ui.Paragraph>[];
  final offsets = <Offset>[];

  @override
  void drawParagraph(ui.Paragraph paragraph, Offset offset) {
    paragraphs.add(paragraph);
    offsets.add(offset);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

const _style = DialCountdownStyle(ticks: DialTicksConfig(showLabels: true));
const _size = Size.square(200);

// 使用真实组件拥有的画笔，覆盖 builder 刷新与资源释放路径。
CustomPainter _painter(WidgetTester tester) => tester
    .widgetList<CustomPaint>(find.byType(CustomPaint))
    .firstWhere((w) => w.painter != null)
    .painter!;

Widget _host({
  DialCountdownStyle style = _style,
  Countdown? plugin,
  CustomPainter Function(BuildContext, TimeParts)? painterBuilder,
}) => Directionality(
  textDirection: TextDirection.ltr,
  child: Center(
    child: DialCountdown(
      to: const Duration(seconds: 45),
      style: style,
      plugin: plugin,
      painterBuilder: painterBuilder,
    ),
  ),
);

_LabelCanvas _paint(CustomPainter painter, [Size size = _size]) {
  final canvas = _LabelCanvas();
  // 假画布无法观察位图，改走矢量路径验证段落缓存。
  (painter as dynamic).debugUseTickImages = false;
  painter.paint(canvas, size);
  return canvas;
}

// 私有画笔的测试入口不增加公共组件 API。
int _count(CustomPainter painter) =>
    (painter as dynamic).debugLabelCount as int;

void main() {
  tearDown(Countman.destroy);
  tearDown(DialCountdown.clearTickImageCache);

  testWidgets('Dial 多次 paint 和逐帧 builder 更新复用同一画笔及段落', (tester) async {
    final clock = installManualClock();
    final plugin = Countdown(name: 'dial-label-cache', interval: 0);
    await tester.pumpWidget(_host(plugin: plugin));
    final painter = _painter(tester);
    final first = _paint(painter);
    expect(first.paragraphs, hasLength(12));
    for (var frame = 0; frame < 5; frame++) {
      clock.advance(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 16));
      expect(_painter(tester), same(painter));
      final next = _paint(painter);
      expect(next.paragraphs, orderedEquals(first.paragraphs));
      expect(next.offsets, first.offsets);
      expect(_count(painter), 12);
    }
    await tester.pumpWidget(const SizedBox.shrink());
    expect(_count(painter), 0);
    expect(first.paragraphs.map((p) => p.debugDisposed), everyElement(isTrue));
  });

  testWidgets('Dial 修改标签集合后释放旧段落并显示新文字', (tester) async {
    await tester.pumpWidget(_host());
    final painter = _painter(tester);
    final old = _paint(painter).paragraphs;
    await tester.pumpWidget(
      _host(
        style: const DialCountdownStyle(
          ticks: DialTicksConfig(showLabels: true, majorEvery: 7),
        ),
      ),
    );
    expect(old.map((p) => p.debugDisposed), everyElement(isTrue));
    final next = _paint(painter).paragraphs;
    expect(next, hasLength(9));
    expect(_count(painter), 9);
    expect(next.map((p) => p.debugDisposed), everyElement(isFalse));
    // 用字宽与原始排版比对，覆盖 0、7、14… 的文字内容。
    for (var i = 0; i < next.length; i++) {
      final reference = TextPainter(
        text: TextSpan(
          text: '${i * 7}',
          style: const TextStyle(
            color: Color(0xFF3A2730),
            fontSize: 14,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      expect(next[i].maxIntrinsicWidth, reference.maxIntrinsicWidth);
      reference.dispose();
    }
  });

  testWidgets('Dial 样式按值复用且实际样式变化释放旧段落', (tester) async {
    DialCountdownStyle style(Color color) => DialCountdownStyle(
      ticks: DialTicksConfig(
        showLabels: true,
        labelStyle: TextStyle(fontSize: 18, color: color),
      ),
    );
    await tester.pumpWidget(_host(style: style(Colors.red)));
    final painter = _painter(tester);
    final old = _paint(painter).paragraphs;
    await tester.pumpWidget(_host(style: style(Colors.red)));
    expect(_paint(painter).paragraphs, orderedEquals(old));
    await tester.pumpWidget(_host(style: style(Colors.blue)));
    expect(old.map((p) => p.debugDisposed), everyElement(isTrue));
    final next = _paint(painter).paragraphs;
    expect(next.map((p) => p.debugDisposed), everyElement(isFalse));
    expect(next.first, isNot(same(old.first)));
  });

  testWidgets('Dial 等价显式样式及刻度几何变化保留标签缓存', (tester) async {
    await tester.pumpWidget(_host());
    final painter = _painter(tester);
    final old = _paint(painter).paragraphs;
    await tester.pumpWidget(
      _host(
        style: const DialCountdownStyle(
          ticks: DialTicksConfig(
            showLabels: true,
            radius: 48,
            labelStyle: TextStyle(
              color: Color(0xFF3A2730),
              fontSize: 14,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ),
    );
    expect(_paint(painter).paragraphs, orderedEquals(old));
    await tester.pumpWidget(_host());
    expect(_paint(painter).paragraphs, orderedEquals(old));
    await tester.pumpWidget(
      _host(
        style: const DialCountdownStyle(
          ticks: DialTicksConfig(showLabels: true),
          colors: DialColors(off: Colors.blue),
        ),
      ),
    );
    expect(old.map((p) => p.debugDisposed), everyElement(isTrue));
    expect(_paint(painter).paragraphs.first, isNot(same(old.first)));
  });

  testWidgets('Dial 尺寸改变只在影响实际字号时重新排版', (tester) async {
    await tester.pumpWidget(_host());
    final painter = _painter(tester);
    final old = _paint(painter).paragraphs;
    final oldHeight = old.first.height;
    final large = _paint(painter, const Size.square(300)).paragraphs;
    expect(old.map((p) => p.debugDisposed), everyElement(isTrue));
    expect(large.first.height, greaterThan(oldHeight));
    expect(
      _paint(painter, const Size.square(300)).paragraphs,
      orderedEquals(large),
    );
    await tester.pumpWidget(
      _host(
        style: const DialCountdownStyle(
          ticks: DialTicksConfig(
            showLabels: true,
            labelStyle: TextStyle(fontSize: 12),
          ),
        ),
      ),
    );
    final fixed = _paint(painter).paragraphs;
    expect(
      _paint(painter, const Size.square(300)).paragraphs,
      orderedEquals(fixed),
    );
  });

  testWidgets('Dial 关闭标签及切换自定义 painter 时清空缓存', (tester) async {
    await tester.pumpWidget(_host());
    final painter = _painter(tester);
    final old = _paint(painter).paragraphs;
    await tester.pumpWidget(
      _host(
        style: const DialCountdownStyle(
          ticks: DialTicksConfig(showLabels: false),
        ),
      ),
    );
    expect(_count(painter), 0);
    expect(_paint(painter).paragraphs, isEmpty);
    expect(old.map((p) => p.debugDisposed), everyElement(isTrue));
    await tester.pumpWidget(_host());
    final next = _paint(painter).paragraphs;
    expect(next, hasLength(12));
    await tester.pumpWidget(_host(painterBuilder: (_, _) => _EmptyPainter()));
    expect(_count(painter), 0);
    expect(next.map((p) => p.debugDisposed), everyElement(isTrue));
    await tester.pumpWidget(_host());
    expect(_paint(_painter(tester)).paragraphs, hasLength(12));
  });
}

class _EmptyPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {}

  @override
  bool shouldRepaint(_EmptyPainter oldDelegate) => false;
}
