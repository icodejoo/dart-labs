import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:luckdraw/extend.dart';
import 'package:luckdraw/src/core/foundation/constants.dart';
import 'package:luckdraw/src/core/render/cached_picture.dart';

import '../../support/recording_canvas.dart';

/// 测试纹理的逻辑尺寸。
const ui.Size _size = ui.Size(3, 5);

/// 测试纹理在 DPR 为 1 时的名义字节数。
const int _bytes = 3 * 5 * kLuckyRgbaBytesPerPixel;

/// 验证共享预算、失败回退和纹理生命周期。
void main() {
  final budget = LuckyRasterBudget.instance;
  setUp(budget.reset);
  tearDown(() {
    LuckyRasterBudget.debugOnFallback = null;
    expect(budget.usedBytes, 0, reason: '每次预占必须配对释放');
  });

  test('共享账本允许恰好到达上限且释放不会减到负数', () {
    expect(LuckyRasterBudget.instance, same(budget));
    expect(budget.usedBytes, 0);
    expect(budget.tryReserve(_bytes, _bytes), isTrue);
    expect(budget.usedBytes, _bytes);
    expect(budget.tryReserve(1, _bytes), isFalse);
    expect(budget.usedBytes, _bytes);
    budget.release(_bytes - 1);
    expect(budget.usedBytes, 1);
    budget.release(_bytes);
    expect(budget.usedBytes, 0);
    budget.release(_bytes);
    expect(budget.usedBytes, 0);
    expect(() => budget.tryReserve(-1, _bytes), throwsAssertionError);
    expect(() => budget.release(-1), throwsAssertionError);
  });

  test('预占失败仅在debug通知请求量当前占用和本次上限', () {
    final calls = <(int, int, int)>[];
    LuckyRasterBudget.debugOnFallback =
        (requested, used, limit) => calls.add((requested, used, limit));
    expect(budget.tryReserve(_bytes, _bytes), isTrue);
    expect(calls, isEmpty);
    expect(budget.tryReserve(_bytes, _bytes), isFalse);
    expect(calls, [(_bytes, _bytes, _bytes)]);
    expect(budget.usedBytes, _bytes);
    budget.release(_bytes);
  });

  test('测试reset清零已预占字节', () {
    expect(budget.tryReserve(_bytes, _bytes), isTrue);
    budget.reset();
    expect(budget.usedBytes, 0);
  });

  test('位图按向上取整的物理尺寸计费且超限返回null', () {
    const dpr = 1.1;
    const roundedBytes = 4 * 6 * kLuckyRgbaBytesPerPixel;
    final cache = LuckyPictureCache(
        mode: LuckyCacheMode.raster, maxRasterBytes: roundedBytes - 1);
    addTearDown(cache.dispose);
    expect(cache.raster(0, _size, dpr, (_) => fail('超限不应录制')), isNull);
    expect(budget.usedBytes, 0);
    cache.maxRasterBytes = roundedBytes;
    final image = cache.raster(0, _size, dpr, (_) {})!;
    expect((image.width, image.height), (4, 6));
    expect(budget.usedBytes, roundedBytes);
    expect(cache.debugRasterBytes, roundedBytes);
    expect(cache.raster(0, _size, dpr, (_) => fail('不应重复录制')), same(image));
    expect(budget.usedBytes, roundedBytes);
  });

  test('多个cache共享预算并按各自上限决定能否新增纹理', () {
    final first =
        LuckyPictureCache(mode: LuckyCacheMode.raster, maxRasterBytes: _bytes);
    final second =
        LuckyPictureCache(mode: LuckyCacheMode.raster, maxRasterBytes: _bytes);
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    expect(first.raster(0, _size, 1, (_) {}), isNotNull);
    expect(second.raster(0, _size, 1, (_) => fail('超限不应录制')), isNull);
    second.maxRasterBytes = _bytes * 2;
    expect(second.raster(0, _size, 1, (_) {}), isNotNull);
    expect(budget.usedBytes, _bytes * 2);
    first.dispose();
    expect(budget.usedBytes, _bytes);
    second.invalidateAll();
    expect(budget.usedBytes, 0);
  });

  test('替换失败保留旧图而成功替换失效和销毁均配对释放', () {
    final cache =
        LuckyPictureCache(mode: LuckyCacheMode.raster, maxRasterBytes: _bytes);
    addTearDown(cache.dispose);
    final first = cache.raster(0, _size, 1, (_) {})!;
    const origin = ui.Offset(-1, -1);
    expect(cache.raster(0, _size, 1, (_) {}, origin: origin), isNull);
    expect(first.debugDisposed, isFalse);
    expect(budget.usedBytes, _bytes);
    cache.maxRasterBytes = _bytes * 3;
    final replacement = cache.raster(0, _size, 1, (_) {}, origin: origin)!;
    expect(first.debugDisposed, isTrue);
    expect(budget.usedBytes, _bytes);
    final other = cache.raster(1, _size, 1, (_) {})!;
    expect(budget.usedBytes, _bytes * 2);
    cache.invalidate(0);
    expect(replacement.debugDisposed, isTrue);
    expect(budget.usedBytes, _bytes);
    cache.invalidate(0);
    expect(budget.usedBytes, _bytes);
    cache.dispose();
    expect(other.debugDisposed, isTrue);
    expect(budget.usedBytes, 0);
    cache.dispose();
    expect(budget.usedBytes, 0);
  });

  test('零字节上限禁用新增及已有位图的回放入口', () {
    final cache = LuckyPictureCache(mode: LuckyCacheMode.raster);
    addTearDown(cache.dispose);
    final image = cache.raster(0, _size, 1, (_) {})!;
    cache.maxRasterBytes = 0;
    expect(cache.raster(0, _size, 1, (_) {}), isNull);
    expect(cache.raster(1, _size, 1, (_) => fail('禁用时不应录制')), isNull);
    expect(image.debugDisposed, isFalse);
    expect(budget.usedBytes, _bytes);
    cache.invalidateAll();
    expect(budget.usedBytes, 0);
  });

  test('录制异常退还预占且保留其它cache的账目', () {
    final cache = LuckyPictureCache(mode: LuckyCacheMode.raster);
    addTearDown(cache.dispose);
    expect(budget.tryReserve(_bytes, _bytes), isTrue);
    expect(() => cache.raster(0, _size, 1, (_) => throw StateError('录制失败')),
        throwsStateError);
    expect(cache.debugRasterBytes, 0);
    expect(cache.debugRecordCount, 0);
    expect(budget.usedBytes, _bytes);
    budget.release(_bytes);
  });

  test('原生纹理创建异常退还预占且保留旧纹理', () {
    final cache = LuckyPictureCache(mode: LuckyCacheMode.raster);
    addTearDown(cache.dispose);
    final image = cache.raster(0, _size, 1, (_) {})!;
    final previous = ui.Image.onCreate;
    addTearDown(() => ui.Image.onCreate = previous);
    ui.Image.onCreate = (image) {
      image.dispose();
      throw StateError('纹理创建失败');
    };
    expect(() => cache.raster(0, _size, 2, (_) => fail('不应重复录制')),
        throwsStateError);
    expect(image.debugDisposed, isFalse);
    expect(cache.debugRasterBytes, _bytes);
    expect(budget.usedBytes, _bytes);
  });

  test('CachedPicture从performance传入预算并回退Picture绘制', () {
    final cache = LuckyPictureCache();
    addTearDown(cache.dispose);
    final playback = LuckyCachedPicture(
        cache,
        0,
        ui.Offset.zero & _size,
        1,
        (_) {},
        const LuckyPerformanceOptions(
            cacheMode: LuckyCacheMode.raster, maxRasterBytes: 0));
    final canvas = TestRecordingCanvas();
    playback.paint(canvas, isMoving: true);
    expect(cache.maxRasterBytes, 0);
    expect(cache.debugRasterBytes, 0);
    expect(canvas.countCalls(#drawPicture), 1);
    expect(canvas.countCalls(#drawImageRect), 0);
  });

  test('预算选项默认32MiB且纳入copyWith相等性和哈希', () {
    const defaults = LuckyPerformanceOptions();
    expect(defaults.maxRasterBytes, 32 * 1024 * 1024);
    expect(defaults.maxRasterBytes, kLuckyDefaultMaxRasterBytes);
    expect(defaults.copyWith().maxRasterBytes, defaults.maxRasterBytes);
    const disabled = LuckyPerformanceOptions(maxRasterBytes: 0);
    final copied = defaults.copyWith(maxRasterBytes: 0);
    expect(copied, disabled);
    expect(copied.hashCode, disabled.hashCode);
    expect(copied, isNot(defaults));
    expect(copied.hashCode, isNot(defaults.hashCode));
  });
}
