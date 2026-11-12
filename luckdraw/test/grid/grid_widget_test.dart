import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luckdraw/extend.dart';
import 'package:luckdraw/grid.dart';

import '../support/grid_fixtures.dart';
import '../support/test_images.dart';
import 'grid_controller_test.dart' show gridHost;

/// 采集宿主输入并转交默认后端。
final class _CaptureRenderer extends LuckyRenderer<GridConfig, GridLayout,
    GridFrame, LuckyResult<GridPrize>> {
  /// 最近渲染数据。
  late LuckySurfaceData<GridConfig, GridLayout, GridFrame> data;

  /// 记录布局后正常绘制。
  @override
  Widget buildSurface(BuildContext context,
      LuckySurfaceData<GridConfig, GridLayout, GridFrame> data) {
    this.data = data;
    return const GridCanvasRenderer().buildSurface(context, data);
  }
}

/// 宿主、样式热更新和渐进图片的集成断言。
void main() {
  group('LuckyGrid', () {
    testWidgets('renders blocks cells and the active highlight',
        (tester) async {
      final controller = GridController();
      final renderer = _CaptureRenderer();
      final changes = <int>[];
      LuckyResult<GridPrize>? result;
      await tester.pumpWidget(gridHost(LuckyGrid(
          config: gridFixture.copyWith(
              options: const GridOptions(
                  motion: LuckyMotionOptions(
                      accelerationTime: Duration(milliseconds: 64),
                      decelerationTime: Duration(milliseconds: 96)))),
          controller: controller,
          renderer: renderer,
          width: 300,
          height: 300,
          onActiveChanged: changes.add,
          onEnd: (value) => result = value,
          semanticsValueBuilder: (phase, _) => phase.name)));
      expect(renderer.data.layout.blocks, hasLength(1));
      expect(renderer.data.layout.cells, hasLength(9));
      expect(controller.frame.activeIndex, -1);
      expect(controller.play(), isTrue);
      expect(controller.stop(4), isTrue);
      await tester.pump();
      for (var i = 0; i < 24; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(controller.phase.value, LuckyPhase.settled);
      expect(controller.frame.activeIndex, 4);
      expect(result!.prize, gridFixture.prizes[4]);
      expect(changes, contains(4));
      expect(find.byType(CustomPaint), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    });
    testWidgets('activeStyle change repaints without restarting motion',
        (tester) async {
      final controller = GridController();
      final renderer = _CaptureRenderer();
      var paints = 0;
      var config = gridFixture;
      late StateSetter rebuild;
      await tester.pumpWidget(gridHost(StatefulBuilder(builder: (_, setter) {
        rebuild = setter;
        return LuckyGrid(
            config: config,
            controller: controller,
            renderer: renderer,
            width: 300,
            height: 300,
            hooks: LuckyHooks(afterDraw: (_, __) => paints++));
      })));
      controller.play();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      final position = controller.frame.currIndex;
      final before = paints;
      rebuild(() => config = config.copyWith(
          activeStyle: const LuckyCellStyle(
              background: LuckyFill.color(Color(0xFF33AA99)))));
      await tester.pump();
      expect(controller.phase.value, LuckyPhase.accelerating);
      expect(controller.frame.currIndex, position);
      expect(renderer.data.layout.cells.first.active.background,
          config.activeStyle.background);
      expect(paints, greaterThan(before));
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    });
    testWidgets('images load progressively and failures use the fallback',
        (tester) async {
      final first = LuckyTestImageCompleter();
      final failed = LuckyTestImageCompleter();
      final fallback = LuckyTestImageCompleter();
      final active = LuckyTestImageCompleter();
      final firstProvider = LuckyTestImageProvider(first);
      final failedProvider = LuckyTestImageProvider(failed);
      final fallbackProvider = LuckyTestImageProvider(fallback);
      final activeProvider = LuckyTestImageProvider(active);
      final config = gridFixture.copyWith(prizes: [
        GridPrize(
            x: 0,
            y: 0,
            images: [GridImage(firstProvider, activeImage: activeProvider)]),
        GridPrize(
            x: 1,
            y: 0,
            images: [GridImage(failedProvider, fallback: fallbackProvider)]),
      ]);
      final renderer = _CaptureRenderer();
      var ready = 0;
      final errors = <LuckyImageError>[];
      await tester.pumpWidget(gridHost(LuckyGrid(
          config: config,
          renderer: renderer,
          width: 300,
          height: 300,
          onReady: () => ready++,
          onImageError: errors.add)));
      final image = (await tester.runAsync(
          () => createGridTestImage(color: const Color(0xFFFF0000))))!;
      first.succeed(image);
      await tester.pump();
      expect(renderer.data.images[const LuckyImageSlot('prizes', 0, 0)],
          isNotNull);
      expect(renderer.data.images.isSettled, isFalse);
      expect(ready, 0);
      failed.fail(StateError('图片失败'));
      await tester.pump();
      fallback.succeed(image);
      active.succeed(image);
      await tester.pump();
      expect(errors.single.usedFallback, isFalse);
      expect(renderer.data.images[const LuckyImageSlot('prizes', 1, 0)],
          isNotNull);
      expect(
          renderer
              .data.images[const LuckyImageSlot('prizes', 0, 0, active: true)],
          isNotNull);
      expect(renderer.data.images.isSettled, isTrue);
      expect(ready, 1);
      await tester.pumpWidget(const SizedBox());
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
      expect(
          first.listenerCount +
              failed.listenerCount +
              fallback.listenerCount +
              active.listenerCount,
          0);
      image.dispose();
    });
  });
  test(
      'GridGame images > requests retain groups sizes and only explicit active providers',
      () {
    const provider = AssetImage('base');
    const image = GridImage(provider,
        activeImage: provider,
        width: LuckyLength.percent(50),
        height: LuckyLength.px(30));
    final config = gridFixture.copyWith(blocks: const [
      LuckyBoxBlock(images: [
        LuckyImage(provider,
            width: LuckyLength.px(20), height: LuckyLength.px(10))
      ])
    ], prizes: const [
      GridPrize(x: 0, y: 0, images: [image, GridImage(provider)])
    ], buttons: const [
      GridButton(x: 1, y: 1, images: [GridImage(provider)])
    ]);
    final layout = gridLayout(config);
    final requests = const GridGame().collectImages(config, layout);
    expect(requests, hasLength(5));
    expect(requests.first.slot, const LuckyImageSlot('blocks', 0, 0));
    expect(requests.first.decodeLogicalWidth, 20);
    expect(requests.first.decodeLogicalHeight, 10);
    expect(requests[1].decodeLogicalWidth, layout.cellWidth * 0.5);
    expect(requests[1].decodeLogicalHeight, 30);
    expect(requests[3].slot.active, isTrue);
    expect(requests.last.slot.group, 'buttons');
  });
}
