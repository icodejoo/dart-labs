import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luckdraw/extend.dart';
import 'package:luckdraw/src/wheel/render/wheel_painter.dart';
import 'package:luckdraw/wheel.dart';

import '../support/fixtures.dart';

/// 本批固定绘制尺寸。
const Size kWheelRenderSize = Size(400, 400);

/// 本批动画测试的帧步长。
const Duration kWheelRenderStep = Duration(milliseconds: 16);

/// 扇区交替配色。
const List<Color> kWheelRenderColors = [Color(0xffffe3a1), Color(0xffffbd69)];

/// 中心按钮和外环强调色。
const Color kWheelRenderAccent = Color(0xffb33644);

/// 测试字体名称；Roboto 无中文字形，视觉夹具使用英文标签。
const String kWheelRenderFont = 'Roboto';

/// 基于已验收标准夹具添加配色及确定性字体，不修改共享夹具。
WheelConfig wheelRenderFixture() => kLuckyWheelFixture.copyWith(prizes: [
      for (var i = 0; i < kLuckyWheelFixture.prizes.length; i++)
        kLuckyWheelFixture.prizes[i].copyWith(
            texts: [LuckyText('PRIZE ${i + 1}', fontFamily: kWheelRenderFont)],
            background: LuckyFill.color(
                kWheelRenderColors[i % kWheelRenderColors.length])),
    ], buttons: [
      kLuckyWheelFixture.buttons.single.copyWith(
          background: const LuckyFill.color(kWheelRenderAccent),
          texts: const [
            LuckyText('START',
                fontFamily: kWheelRenderFont,
                color: Color(0xffffffff),
                top: LuckyLength.px(-12))
          ]),
    ]);

/// 提供有界约束、文字方向和像素环境的 Widget 测试根。
Widget wheelRenderRoot(Widget child) => MediaQuery(
    data: const MediaQueryData(),
    child: Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
            child: SizedBox.fromSize(size: kWheelRenderSize, child: child))));

/// 查找生产渲染器持有的真实画笔。
WheelPainter wheelSurfacePainter(WidgetTester tester) => tester
    .widgetList<CustomPaint>(find.byType(CustomPaint))
    .map((widget) => widget.painter)
    .whereType<WheelPainter>()
    .single;

/// 可注入原生图像的只读图片视图。
final class WheelRenderImages implements LuckyImageSet {
  /// 当前槽位数据，图片所有权由测试管理。
  final Map<LuckyImageSlot, LuckyResolvedImage> values = {};

  /// 可手动增加的图片代际。
  @override
  int generation = 0;

  /// 本夹具没有未决请求。
  @override
  bool get isSettled => true;

  /// 获取指定槽位的图像。
  @override
  LuckyResolvedImage? operator [](LuckyImageSlot slot) => values[slot];
}

/// 真实布局和真实画笔的离屏测试环境。
final class WheelPainterHarness {
  /// 根据配置准备静态显示列表。
  WheelPainterHarness(
      {WheelConfig? config,
      LuckyPerformanceOptions performance = const LuckyPerformanceOptions(),
      List<LuckyLayer<WheelLayout, WheelFrame>> layers = const [],
      LuckyHooks hooks = const LuckyHooks(),
      WheelRenderImages? images}) {
    final actual = config ?? wheelRenderFixture();
    final input = LuckyLayoutInput.headless(kWheelRenderSize);
    final layout = const WheelGame().computeLayout(actual, input);
    input.measurer.dispose();
    data = LuckySurfaceData(
        config: actual,
        layout: layout,
        layoutGeneration: 1,
        frame: frame,
        frameListenable: frames,
        images: images ?? WheelRenderImages(),
        imagesListenable: imageChanges,
        layers: layers,
        hooks: hooks,
        devicePixelRatio: 2,
        textDirection: TextDirection.ltr,
        performance: performance,
        isAnimating: true);
    painter = WheelPainter(data, cache);
    addTearDown(dispose);
  }

  /// 复用帧。
  final WheelFrame frame = WheelFrame();

  /// 帧重绘信号。
  final LuckyFrameNotifier frames = LuckyFrameNotifier();

  /// 图片信号。
  final LuckyFrameNotifier imageChanges = LuckyFrameNotifier();

  /// 原生资源缓存。
  final LuckyPictureCache cache = LuckyPictureCache();

  /// 已准备的渲染输入。
  late final LuckySurfaceData<WheelConfig, WheelLayout, WheelFrame> data;

  /// 生产画笔。
  late final WheelPainter painter;

  /// 释放测试拥有的所有资源。
  void dispose() {
    cache.dispose();
    frames.dispose();
    imageChanges.dispose();
  }
}

/// 以真实 Ticker 逐帧推进到目标阶段，超时明确失败。
Future<void> wheelPumpTo(
    WidgetTester tester, WheelController controller, LuckyPhase phase) async {
  for (var i = 0; i < 100 && controller.phase.value != phase; i++) {
    await tester.pump(kWheelRenderStep);
  }
  expect(controller.phase.value, phase);
}
