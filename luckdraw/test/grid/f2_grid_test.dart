import 'dart:ui' as ui;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luckdraw/extend.dart';
import 'package:luckdraw/grid.dart';
import 'package:luckdraw/src/grid/motion/grid_motion.dart';
import 'package:luckdraw/src/grid/render/grid_painter.dart';
import 'grid_render_fixtures.dart';

/// 固定的短动画配置。
const _options = LuckyMotionOptions(
    accelerationTime: Duration(milliseconds: 64),
    decelerationTime: Duration(milliseconds: 96),
    timebase: LuckyTimebase.frame);

/// 创建八格测试配置。
GridConfig _config([LuckyMotionOptions options = _options]) => GridConfig(
    prizes: List.generate(8, (i) => GridPrize(x: i % 3, y: i ~/ 3)),
    options: GridOptions(motion: options));

/// 构建有界测试宿主。
Widget _root(Widget child) => MediaQuery(
    data: const MediaQueryData(),
    child: Directionality(
        textDirection: TextDirection.ltr, child: Center(child: child)));

/// 九宫格终审回归。
void main() {
  test('F2 grid deceleration options stay frozen until settlement', () {
    final m = GridMotion()
      ..configure(_config(), null)
      ..start()
      ..requestStop(2);
    final reference = GridMotion()
      ..configure(_config(), null)
      ..start()
      ..requestStop(2);
    for (var i = 0; i <= 9; i++) {
      m.tick(i * 16, 16);
      reference.tick(i * 16, 16);
    }
    m.configure(
        _config(_options.copyWith(
            decelerationTime: const Duration(milliseconds: 9600))),
        null);
    for (var i = 10; i < 30; i++) {
      m.tick(i * 16, 16);
      reference.tick(i * 16, 16);
      expect(m.frame.currIndex, reference.frame.currIndex);
    }
    expect(m.takeResult()!.index, 2);
  });
  testWidgets(
      'F2 grid early stop phase callbacks skip synthetic cruising frame',
      (tester) async {
    final controller = GridController();
    addTearDown(controller.dispose);
    final phases = <LuckyPhase>[];
    await tester.pumpWidget(_root(LuckyGrid(
        config: _config(),
        controller: controller,
        width: 300,
        height: 300,
        onPhaseChanged: phases.add)));
    controller.play();
    controller.stop(2);
    await tester.pump();
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(phases,
        [LuckyPhase.accelerating, LuckyPhase.decelerating, LuckyPhase.settled]);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('F2 grid settled callback restart preserves onEnd and playUntil',
      (tester) async {
    final controller = GridController();
    addTearDown(controller.dispose);
    var restarted = false;
    final results = <LuckyResult<GridPrize>>[];
    await tester.pumpWidget(_root(LuckyGrid(
        config: _config(),
        controller: controller,
        width: 300,
        height: 300,
        onEnd: results.add,
        onPhaseChanged: (phase) {
          if (phase == LuckyPhase.settled && !restarted) {
            restarted = true;
            controller.play();
          }
        })));
    final future = controller.playUntil(() => 2);
    await tester.pump();
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(restarted, isTrue);
    expect(results, hasLength(1));
    expect((await future).index, 2);
    expect(results.single.index, 2);
    await tester.pumpWidget(const SizedBox());
  });
  test('F2 grid aboveItems paints before buttons', () async {
    const config = GridConfig(rows: 1, cols: 1, buttons: [
      GridButton(
          x: 0,
          y: 0,
          style: LuckyCellStyle(
              background: LuckyFill.color(Color(0xFFFF0000)), borderRadius: 0))
    ]);
    final data = gridSurfaceData(config: config, layers: [
      LuckyCallbackLayer<GridLayout, GridFrame>(
          (canvas, _) =>
              canvas.drawColor(const Color(0xFF0000FF), BlendMode.src),
          position: LuckyLayerPosition.aboveItems)
    ]);
    final cache = LuckyPictureCache();
    addTearDown(cache.dispose);
    final recorder = ui.PictureRecorder();
    GridPainter(data: data, cache: cache)
        .paint(Canvas(recorder), data.layout.size);
    final picture = recorder.endRecording();
    final image = picture.toImageSync(300, 300);
    final bytes = (await image.toByteData())!;
    expect(bytes.getUint32((150 * 300 + 150) * 4), 0xFF0000FF);
    image.dispose();
    picture.dispose();
  });
  test('F2 grid direct deceleration shrink replans and empty prizes cancel',
      () {
    final m = GridMotion()
      ..configure(_config(), null)
      ..start()
      ..requestStop(7);
    for (var i = 0; i < 10; i++) {
      m.tick(i * 16, 16);
    }
    m.configure(
        _config().copyWith(prizes: _config().prizes.take(2).toList()), null);
    for (var i = 10; i < 40; i++) {
      m.tick(i * 16, 16);
    }
    expect(m.takeResult()!.index, 1);
    expect(m.frame.activeIndex, 1);
    m.start();
    m.requestStop(0);
    for (var i = 40; i < 50; i++) {
      m.tick(i * 16, 16);
    }
    m.configure(_config().copyWith(prizes: []), null);
    m.tick(800, 16);
    expect(m.phase, LuckyPhase.idle);
    expect(m.takeResult()!.cancelled, isTrue);
  });
}
