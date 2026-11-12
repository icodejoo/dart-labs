import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:luckdraw/extend.dart';

/// 验证显示列表与位图缓存的复用、限制和释放。
void main() {
  group('LuckyPictureCache', () {
    test('raster accepts height exactly at maxRasterSide', () {
      const maxSide = 20;
      const dpr = 2.0;
      const logicalSize = ui.Size(5, 10);
      const id = 0;
      final cache = LuckyPictureCache(
          mode: LuckyCacheMode.raster, maxRasterSide: maxSide);
      addTearDown(cache.dispose);
      final image = cache.raster(id, logicalSize, dpr, (_) {});
      expect(image, isNotNull);
      expect(image!.width, logicalSize.width * dpr);
      expect(image.height, maxSide);
      expect(
          cache.raster(id, logicalSize, dpr, (_) => fail('重复录制')), same(image));
      cache.dispose();
      expect(image.debugDisposed, isTrue);
    });
    test(
        'raster disposes its temporary picture exactly once and keeps cached resources alive',
        () {
      const id = 0;
      final cache = LuckyPictureCache(mode: LuckyCacheMode.raster);
      final original = cache.picture(id, (_) {});
      final previousCreate = ui.Picture.onCreate;
      final previousDispose = ui.Picture.onDispose;
      final created = <ui.Picture>[];
      final disposed = <ui.Picture>[];
      ui.Picture.onCreate = (picture) {
        previousCreate?.call(picture);
        created.add(picture);
      };
      ui.Picture.onDispose = (picture) {
        previousDispose?.call(picture);
        disposed.add(picture);
      };
      try {
        const size = ui.Size(4, 6);
        const dpr = 2.0;
        final image = cache.raster(id, size, dpr, (_) => fail('重复录制'));
        expect(image, isNotNull);
        expect(created, hasLength(1));
        final temporary = created.single;
        expect(temporary, isNot(same(original)));
        expect(temporary.debugDisposed, isTrue);
        expect(disposed, [same(temporary)]);
        expect(original.debugDisposed, isFalse);
        expect(image!.debugDisposed, isFalse);
        expect(cache.picture(id, (_) => fail('重复录制')), same(original));
        expect(cache.raster(id, size, dpr, (_) => fail('重复录制')), same(image));
        expect(created, hasLength(1));
        expect(disposed, [same(temporary)]);
        expect(cache.debugRecordCount, 1);
      } finally {
        ui.Picture.onCreate = previousCreate;
        ui.Picture.onDispose = previousDispose;
        for (final picture in created) {
          if (!picture.debugDisposed) picture.dispose();
        }
        cache.dispose();
      }
    });
    test('records once and reuses the picture until invalidated', () {
      final cache = LuckyPictureCache();
      final first = cache.picture(0, (_) {});
      expect(cache.picture(0, (_) => fail('重复录制')), same(first));
      expect(cache.debugRecordCount, 1);
      cache.invalidate(0);
      final second = cache.picture(0, (_) {});
      expect(second, isNot(same(first)));
      expect(cache.debugRecordCount, 2);
      cache.dispose();
      expect(() => cache.picture(1, (_) => throw StateError('record')),
          throwsStateError);
      expect(cache.debugRecordCount, 2);
    });
    test('invalidate disposes the previous picture', () {
      final cache = LuckyPictureCache();
      final picture = cache.picture(0, (_) {});
      cache.invalidate(0);
      expect(picture.debugDisposed, isTrue);
      cache.invalidate(0);
      cache.dispose();
    });
    test(
        'raster mode falls back to picture when side times dpr exceeds maxRasterSide',
        () {
      final cache = LuckyPictureCache(maxRasterSide: 20);
      expect(cache.raster(0, const ui.Size(10, 10), 1, (_) {}), isNull);
      cache.mode = LuckyCacheMode.raster;
      expect(cache.raster(0, const ui.Size(11, 1), 2, (_) {}), isNull);
      expect(cache.raster(0, const ui.Size(1, 11), 2, (_) {}), isNull);
      expect(cache.raster(0, ui.Size.zero, 1, (_) {}), isNull);
      final image = cache.raster(0, const ui.Size(10, 5), 2, (_) {})!;
      expect(image.width, 20);
      expect(image.height, 10);
      expect(cache.raster(0, const ui.Size(10, 5), 2, (_) => fail('重复录制')),
          same(image));
      final replacement = cache.raster(0, const ui.Size(5, 5), 2, (_) {})!;
      expect(image.debugDisposed, isTrue);
      expect(replacement.width, 10);
      expect(cache.debugRecordCount, 1);
      cache.invalidate(0);
      expect(replacement.debugDisposed, isTrue);
      cache.dispose();
    });
    test('dispose releases pictures and images', () {
      final cache = LuckyPictureCache(mode: LuckyCacheMode.raster);
      final picture = cache.picture(0, (_) {});
      final image = cache.raster(0, const ui.Size(4, 4), 1, (_) {})!;
      cache.dispose();
      expect(picture.debugDisposed, isTrue);
      expect(image.debugDisposed, isTrue);
      cache.dispose();
    });
  });
}
