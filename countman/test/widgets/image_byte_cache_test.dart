import 'dart:ui' as ui;

import 'package:countman/src/widgets/painter/image_byte_cache.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('位图命中更新 LRU，按字节淘汰并释放最旧图片', (tester) async {
    final cache = ImageByteCache<int>(48);
    addTearDown(cache.clear);
    var draws = 0;
    ui.Image? obtain(int key, ui.Size size) => cache.obtain(
      key,
      size: size,
      ratio: 1,
      draw: (c) {
        draws++;
        c.drawColor(const ui.Color(0xFFFF0000), ui.BlendMode.src);
      },
    );
    final first = obtain(1, const ui.Size(2, 2))!;
    final second = obtain(2, const ui.Size(2, 2))!;
    expect(obtain(1, const ui.Size(2, 2)), same(first));
    expect(draws, 2);
    // 新图占 32 字节，应淘汰较旧的第二张，而非第一张。
    final third = obtain(3, const ui.Size(4, 2))!;
    expect(cache.bytes, 48);
    expect(cache.length, 2);
    expect(second.debugDisposed, isTrue);
    expect(first.debugDisposed, isFalse);
    expect(obtain(1, const ui.Size(2, 2)), same(first));
    final fourth = obtain(4, const ui.Size(6, 2))!;
    expect(first.debugDisposed, isTrue);
    expect(third.debugDisposed, isTrue);
    expect(cache.length, 1);
    cache.clear();
    cache.clear();
    expect(fourth.debugDisposed, isTrue);
    expect(cache.bytes, 0);
    expect(cache.length, 0);
    expect(obtain(4, const ui.Size(6, 2)), isNot(same(fourth)));
  });

  testWidgets('单张超预算和无效尺寸直接返回 null，失败后可重试', (tester) async {
    final cache = ImageByteCache<int>(64);
    addTearDown(cache.clear);
    var draws = 0;
    ui.Image? obtain(
      int key,
      ui.Size size, {
      double ratio = 1,
      double padding = 0,
    }) => cache.obtain(
      key,
      size: size,
      ratio: ratio,
      padding: padding,
      draw: (_) => draws++,
    );
    final kept = obtain(0, const ui.Size(2, 2))!;
    expect(obtain(1, const ui.Size(5, 5)), isNull);
    expect(obtain(1, const ui.Size(2, 2), padding: 2), isNull);
    expect(obtain(1, ui.Size.zero), isNull);
    expect(obtain(1, const ui.Size(-1, 1)), isNull);
    expect(obtain(1, const ui.Size(1, 1), ratio: 0), isNull);
    expect(obtain(1, const ui.Size(1, 1), ratio: -1), isNull);
    expect(obtain(1, const ui.Size(double.infinity, 1)), isNull);
    expect(obtain(1, const ui.Size(double.nan, 1)), isNull);
    expect(draws, 1);
    expect(cache.bytes, 16);
    expect(kept.debugDisposed, isFalse);
    ui.Canvas? failedCanvas;
    expect(
      cache.obtain(
        1,
        size: const ui.Size(2, 2),
        ratio: 1,
        draw: (canvas) {
          failedCanvas = canvas;
          throw StateError('模拟绘制失败');
        },
      ),
      isNull,
    );
    expect(failedCanvas, isNotNull);
    expect(cache.length, 1);
    expect(obtain(1, const ui.Size(2, 2)), isNotNull);
    expect(cache.bytes, 32);
  });

  testWidgets('真实位图包含 DPR 和边距，原点平移后像素正确', (tester) async {
    final cache = ImageByteCache<int>(256);
    addTearDown(cache.clear);
    final image = cache.obtain(
      0,
      size: const ui.Size(2, 2),
      ratio: 2,
      padding: 1,
      draw: (c) => c.drawRect(
        const ui.Rect.fromLTWH(0, 0, 2, 2),
        ui.Paint()..color = const ui.Color(0xFFFF0000),
      ),
    )!;
    expect(image.width, 8);
    expect(image.height, 8);
    expect(cache.bytes, 256);
    final data = (await tester.runAsync(() => image.toByteData()))!;
    int alpha(int x, int y) => data.getUint8((y * 8 + x) * 4 + 3);
    expect(alpha(0, 0), 0);
    expect(alpha(2, 2), 255);
    expect(alpha(5, 5), 255);
    expect(alpha(6, 6), 0);
  });
}
