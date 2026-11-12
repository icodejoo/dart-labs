import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luckdraw/extend.dart';

import '../../support/fixtures.dart' as fixtures;

/// 测试的固定槽位。
const LuckyImageSlot _slot = LuckyImageSlot('hardening', 0, 0);

/// 初始目标设备像素数。
const int _initialPixels = 20;

/// 测试解码像素比。
const double _dpr = 2;

/// 真实解码的等待上限。
const Duration _timeout = Duration(seconds: 5);

/// 捕获已经撤销的监听器，模拟平台排队中的错误。
final class _LateErrorCompleter extends ImageStreamCompleter {
  /// 最近被移除的解析器监听。
  ImageStreamListener? removed;

  /// 保存监听后照常移除。
  @override
  void removeListener(ImageStreamListener listener) {
    removed = listener;
    super.removeListener(listener);
  }
}

/// 绕过全局缓存，精确观测解析器和后备图的订阅。
final class _UncachedProvider extends ImageProvider<_UncachedProvider> {
  /// 创建尚未结算的流。
  final _LateErrorCompleter completer = _LateErrorCompleter();

  /// 实际解析次数。
  int resolutions = 0;

  /// 返回当前实例作为键。
  @override
  Future<_UncachedProvider> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  /// 不经过缓存直接连接流。
  @override
  void resolveStreamForKey(ImageConfiguration configuration, ImageStream stream,
      _UncachedProvider key, ImageErrorListener handleError) {
    resolutions++;
    stream.setCompleter(completer);
  }
}

/// 为宽或高单独指定目标尺寸，避免另一轴掩盖边界。
LuckyImageRequest _request(ImageProvider<Object> provider,
        {double? width, double? height, ImageProvider<Object>? fallback}) =>
    LuckyImageRequest(
        slot: _slot,
        image: LuckyImage(provider, fallback: fallback),
        provider: provider,
        decodeLogicalWidth: width,
        decodeLogicalHeight: height);

/// 等待真实引擎解码，超时明确失败。
Future<void> _settle(LuckyImageResolver resolver) async {
  final deadline = DateTime.now().add(_timeout);
  while (!resolver.isSettled) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('真实图片解码超时', _timeout);
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

/// 创建大于所有测试目标尺寸的正方形 PNG。
Future<MemoryImage> _png(WidgetTester tester) async {
  const sourceSide = 80;
  final image = await fixtures.createLuckyTestImage(
      color: const ui.Color(0xff123456), width: sourceSide, height: sourceSide);
  try {
    final data = await tester
        .runAsync(() => image.toByteData(format: ui.ImageByteFormat.png));
    return MemoryImage(data!.buffer.asUint8List());
  } finally {
    image.dispose();
  }
}

/// 验证两轴边界是否复用，再越过边界验证旧图释放和新尺寸。
Future<void> _checkBoundary(WidgetTester tester, LuckyImageResolver resolver,
    int boundary, int outside) async {
  final provider = await _png(tester);
  for (final vertical in [false, true]) {
    /// 只改变被测轴的设备像素数。
    LuckyImageRequest request(int pixels) => _request(provider,
        width: vertical ? null : pixels / _dpr,
        height: vertical ? pixels / _dpr : null);
    resolver.update([request(_initialPixels)], ImageConfiguration.empty, _dpr);
    await tester.runAsync(() => _settle(resolver));
    final held = resolver[_slot]!;
    expect(held.image.width, _initialPixels);
    expect(held.image.height, _initialPixels);
    resolver.update([request(boundary)], ImageConfiguration.empty, _dpr);
    expect(resolver[_slot], same(held));
    expect(held.image.debugDisposed, isFalse);
    expect(resolver.debugListenerCount, 0);
    resolver.update([request(outside)], ImageConfiguration.empty, _dpr);
    expect(held.image.debugDisposed, isTrue);
    await tester.runAsync(() => _settle(resolver));
    expect(resolver[_slot], isNot(same(held)));
    expect(resolver[_slot]!.image.width, outside);
    expect(resolver[_slot]!.image.height, outside);
    resolver.update([], ImageConfiguration.empty, _dpr);
  }
}

/// 验证解码滞回闭区间、像素下限及撤销错误隔离。
void main() {
  late LuckyImageResolver resolver;
  late List<LuckyImageError> errors;
  var changes = 0;
  var ready = 0;
  setUp(() {
    errors = [];
    changes = 0;
    ready = 0;
    resolver = LuckyImageResolver(
        onChanged: () => changes++,
        onError: errors.add,
        onReady: () => ready++);
  });
  tearDown(() {
    resolver.dispose();
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  });

  testWidgets('decode growth above 125 percent immediately replaces the image',
      (tester) async {
    final provider = await _png(tester);
    const grownPixels = 26;
    resolver.update([_request(provider, width: _initialPixels / _dpr)],
        ImageConfiguration.empty, _dpr);
    await tester.runAsync(() => _settle(resolver));
    final held = resolver[_slot]!.image;
    resolver.update([_request(provider, width: grownPixels / _dpr)],
        ImageConfiguration.empty, _dpr);
    expect(held.debugDisposed, isTrue);
    await tester.runAsync(() => _settle(resolver));
    expect(resolver[_slot]!.image, isNot(same(held)));
    expect(resolver[_slot]!.image.width, grownPixels);
    expect(resolver[_slot]!.image.height, grownPixels);
    expect(errors, isEmpty);
  });

  testWidgets('decode shrink at exactly 50 percent reuses each dimension',
      (tester) async {
    await _checkBoundary(tester, resolver, 10, 9);
    expect(errors, isEmpty);
  });

  testWidgets('decode growth at exactly 125 percent reuses each dimension',
      (tester) async {
    await _checkBoundary(tester, resolver, 25, 26);
    expect(errors, isEmpty);
  });

  testWidgets('positive subpixel decode dimensions clamp to one pixel',
      (tester) async {
    final provider = await _png(tester);
    const subpixel = 0.1;
    const minimumPixel = 1;
    resolver.update([_request(provider, width: subpixel, height: subpixel)],
        ImageConfiguration.empty, _dpr);
    await tester.runAsync(() => _settle(resolver));
    expect(errors, isEmpty);
    expect(resolver.isSettled, isTrue);
    expect(resolver[_slot]!.image.width, minimumPixel);
    expect(resolver[_slot]!.image.height, minimumPixel);
    expect(ready, minimumPixel);
  });

  testWidgets('late errors from revoked requests never notify the host',
      (tester) async {
    final primary = _UncachedProvider();
    final fallback = _UncachedProvider();
    resolver.update([_request(primary, fallback: fallback)],
        ImageConfiguration.empty, _dpr);
    expect(primary.resolutions, 1);
    expect(resolver.debugListenerCount, 1);
    resolver.update([], ImageConfiguration.empty, _dpr);
    final generation = resolver.generation;
    final previousChanges = changes;
    final previousReady = ready;
    final removed = primary.completer.removed;
    expect(removed, isNotNull);
    expect(removed!.onError, isNotNull);
    removed.onError!(StateError('late'), StackTrace.current);
    await tester.pump();
    expect(errors, isEmpty);
    expect(changes, previousChanges);
    expect(ready, previousReady);
    expect(resolver.generation, generation);
    expect(resolver[_slot], isNull);
    expect(resolver.debugListenerCount, 0);
    expect(fallback.resolutions, 0);
  });
}
