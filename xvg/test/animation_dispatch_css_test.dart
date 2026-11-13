import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xvg/src/animation/animated_svg_painter.dart';
import 'package:xvg/src/animation/animation_detector.dart';
import 'package:xvg/xvg.dart';

/// 无限线性透明度动画，覆盖检测到 ticker 的整条链路。
const _cssSource =
    '<svg xmlns="http://www.w3.org/2000/svg" '
    'width="24" height="24" viewBox="0 0 24 24">'
    '<style>@keyframes fade{from{opacity:0}to{opacity:1}}'
    'rect{animation:fade 1s linear infinite}</style>'
    '<rect width="24" height="24"/></svg>';

/// 静态样式不会触发动画分流。
const _staticSource =
    '<svg xmlns="http://www.w3.org/2000/svg" '
    'width="24" height="24"><style>rect{fill:red}</style>'
    '<rect width="24" height="24"/></svg>';

/// SMIL 动画继续进入动画路径。
const _smilSource =
    '<svg xmlns="http://www.w3.org/2000/svg" '
    'width="24" height="24"><rect width="24" height="24">'
    '<animate attributeName="opacity" values="0;1" dur="1s" '
    'repeatCount="indefinite"/></rect></svg>';

/// 读取动画控件实际使用的绘制器。
AnimatedSvgPainter _painterOf(WidgetTester tester) =>
    tester
            .widget<CustomPaint>(
              find
                  .descendant(
                    of: find.byType(AnimatedXvg),
                    matching: find.byType(CustomPaint),
                  )
                  .first,
            )
            .painter!
        as AnimatedSvgPainter;

/// 验证分流与 CSS 时间线推进；静态路径仅断言控件类型，兼容缺少原生库。
void main() {
  setUp(() {
    AnimationDetector.clearMemo();
    XvgDocumentCache.instance.clear();
  });
  tearDown(() {
    AnimationDetector.clearMemo();
    XvgDocumentCache.instance.clear();
  });

  for (final entry in <String, String>{
    'CSS': _cssSource,
    'SMIL': _smilSource,
    'CSS 与 SMIL 并存': _cssSource.replaceFirst(
      '</svg>',
      '<set attributeName="opacity" to="1" begin="2s"/></svg>',
    ),
  }.entries) {
    testWidgets('${entry.key} 自动建出 AnimatedXvg', (tester) async {
      await tester.pumpWidget(Center(child: Xvg.string(entry.value)));
      expect(find.byType(AnimatedXvg), findsOneWidget);
      expect(find.byType(StaticXvg), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('静态 SVG 自动建出 StaticXvg', (tester) async {
    await tester.pumpWidget(const Center(child: Xvg.string(_staticSource)));
    expect(find.byType(StaticXvg), findsOneWidget);
    expect(find.byType(AnimatedXvg), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('CSS 检测、编译与 ticker 在 500ms 后推进透明度轨道', (tester) async {
    await tester.pumpWidget(const Center(child: Xvg.string(_cssSource)));
    expect(find.byType(AnimatedXvg), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 16));
    final painter = _painterOf(tester);
    final track = painter.root.children.single.animations.single;
    expect(track.attributeName, 'opacity');
    final before = painter.clock.value;
    final initialOpacity = track.sample(before)!;
    await tester.pump(const Duration(milliseconds: 500));
    final after = painter.clock.value;
    expect(after - before, const Duration(milliseconds: 500));
    expect(track.sample(after)!, closeTo(initialOpacity + 0.5, 0.001));
    expect(tester.takeException(), isNull);
  });
}
