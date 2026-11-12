import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:luckdraw/extend.dart';
import 'package:luckdraw/slot.dart';
import 'package:luckdraw/src/core/foundation/constants.dart';
import 'package:luckdraw/src/slot/render/slot_atlas.dart';
import 'package:luckdraw/src/slot/render/slot_painter.dart';

import '../support/recording_canvas.dart';
import '../support/slot_fixtures.dart';

/// 使默认奖品各占一页的边长上限。
const int _side = 128;

/// 计算带一设备像素边距的单格页面字节数。
int _pageBytes(SlotLayout layout) =>
    ((layout.cellWidth).ceil() + 2) *
    ((layout.cellHeight).ceil() + 2) *
    kLuckyRgbaBytesPerPixel;

/// 验证图集按页共享预算、整次回退和资源释放。
void main() {
  final budget = LuckyRasterBudget.instance;
  setUp(budget.reset);
  tearDown(() {
    LuckyRasterBudget.debugOnFallback = null;
    expect(budget.usedBytes, 0, reason: '图集页面必须全部释放');
  });

  test('图集第二页超限释放第一页并整次回退Picture', () {
    final bytes = _pageBytes(slotLayout());
    final data = slotSurfaceData(
        performance: LuckyPerformanceOptions(
            cacheMode: LuckyCacheMode.raster,
            maxRasterSide: _side,
            maxRasterBytes: bytes));
    final cache = LuckyPictureCache();
    final atlas = SlotAtlas();
    addTearDown(cache.dispose);
    addTearDown(atlas.dispose);
    final fallbacks = <(int, int, int)>[];
    LuckyRasterBudget.debugOnFallback =
        (requested, used, limit) => fallbacks.add((requested, used, limit));
    final images = <ui.Image>[];
    final previous = ui.Image.onCreate;
    addTearDown(() => ui.Image.onCreate = previous);
    ui.Image.onCreate = images.add;
    final painter = SlotPainter(data, cache, atlas: atlas);
    expect(fallbacks, [(bytes, bytes, bytes)]);
    expect(images, hasLength(1));
    expect(images.single.debugDisposed, isTrue);
    expect(atlas.pageSizes, isEmpty);
    expect(budget.usedBytes, 0);
    final canvas = TestRecordingCanvas();
    painter.paint(canvas, data.layout.size);
    expect(canvas.countCalls(#drawRawAtlas), 0);
    expect(canvas.countCalls(#drawPicture), greaterThan(0));
    canvas.expectBalancedWithoutSaveLayer();
  });

  test('图集与普通cache共享预算且释放后可重试创建和复用', () {
    final layout = slotLayout();
    final bytes = _pageBytes(layout);
    final cache = LuckyPictureCache(mode: LuckyCacheMode.raster);
    final atlas = SlotAtlas();
    addTearDown(cache.dispose);
    addTearDown(atlas.dispose);
    final pictures = [
      for (var i = 0; i < layout.cells.length; i++) cache.picture(i, (_) {})
    ];
    final total = pictures.length * bytes;
    final image = cache.raster(-1, const ui.Size(1, 1), 1, (_) {})!;
    expect(
        atlas.prepare(pictures, layout, 1, _side, ui.FilterQuality.low,
            padding: 1, maxRasterBytes: total),
        isFalse);
    expect(budget.usedBytes, kLuckyRgbaBytesPerPixel);
    cache.invalidate(-1);
    expect(image.debugDisposed, isTrue);
    expect(
        atlas.prepare(pictures, layout, 1, _side, ui.FilterQuality.low,
            padding: 1, maxRasterBytes: total),
        isTrue);
    expect(atlas.pageSizes, hasLength(pictures.length));
    expect(budget.usedBytes, total);
    expect(
        atlas.prepare(pictures, layout, 1, _side, ui.FilterQuality.low,
            padding: 1, maxRasterBytes: total),
        isTrue);
    expect(budget.usedBytes, total);
    atlas.dispose();
    expect(budget.usedBytes, 0);
    atlas.dispose();
    expect(budget.usedBytes, 0);
  });

  test('仅改变图集字节上限为零释放旧页面并禁用raster', () {
    final layout = slotLayout();
    final cache = LuckyPictureCache();
    final atlas = SlotAtlas();
    addTearDown(cache.dispose);
    addTearDown(atlas.dispose);
    final pictures = [cache.picture(0, (_) {})];
    expect(atlas.prepare(pictures, layout, 1, _side, ui.FilterQuality.low),
        isTrue);
    expect(budget.usedBytes, greaterThan(0));
    expect(
        atlas.prepare(pictures, layout, 1, _side, ui.FilterQuality.low,
            maxRasterBytes: 0),
        isFalse);
    expect(atlas.pageSizes, isEmpty);
    expect(budget.usedBytes, 0);
  });

  test('图集原生创建异常退还本页预占并释放此前页面', () {
    final layout = slotLayout();
    final cache = LuckyPictureCache();
    final atlas = SlotAtlas();
    addTearDown(cache.dispose);
    addTearDown(atlas.dispose);
    final pictures = [
      for (var i = 0; i < layout.cells.length; i++) cache.picture(i, (_) {})
    ];
    final images = <ui.Image>[];
    final previous = ui.Image.onCreate;
    addTearDown(() => ui.Image.onCreate = previous);
    ui.Image.onCreate = (image) {
      images.add(image);
      if (images.length == 2) {
        image.dispose();
        throw StateError('第二页创建失败');
      }
    };
    expect(
        () => atlas.prepare(pictures, layout, 1, _side, ui.FilterQuality.low),
        throwsStateError);
    expect(images, hasLength(2));
    expect(images.every((image) => image.debugDisposed), isTrue);
    expect(atlas.pageSizes, isEmpty);
    expect(budget.usedBytes, 0);
  });
}
