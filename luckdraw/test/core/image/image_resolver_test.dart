import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luckdraw/extend.dart';

import '../../support/fixtures.dart' as fixtures;
import '../../support/test_images.dart';

/// 首个测试槽位。
const LuckyImageSlot _slot = LuckyImageSlot('test', 0, 0);

/// 另一个测试槽位。
const LuckyImageSlot _other = LuckyImageSlot('test', 1, 0);

/// 真实图片解码的等待上限。
const Duration _decodeTimeout = Duration(seconds: 5);

/// 有限等待引擎解码，避免测试永久挂起。
Future<void> _settleImages(LuckyImageResolver resolver) async {
  final deadline = DateTime.now().add(_decodeTimeout);
  while (!resolver.isSettled) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('图片解码未完成', _decodeTimeout);
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

/// 创建本文件共用的内存图片。
Future<ui.Image> createLuckyTestImage({int width = 1, int height = 1}) =>
    fixtures.createLuckyTestImage(
        color: const ui.Color(0xff123456), width: width, height: height);

/// 用可控 provider 创建请求。
LuckyImageRequest _request(ImageProvider<Object> provider,
        {LuckyImageSlot slot = _slot,
        ImageProvider<Object>? fallback,
        LuckyImageFormatter? formatter,
        double? width,
        double? height}) =>
    LuckyImageRequest(
        slot: slot,
        image: LuckyImage(provider, fallback: fallback, formatter: formatter),
        provider: provider,
        decodeLogicalWidth: width,
        decodeLogicalHeight: height);

/// 验证图片首帧、错误隔离、目标解码和资源所有权。
void main() {
  group('LuckyImageResolver', () {
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
    testWidgets(
        'formatter output determines natural size and single dimension aspect ratio',
        (tester) async {
      final completer = LuckyTestImageCompleter();
      final source = await createLuckyTestImage(width: 80, height: 40);
      final output = await createLuckyTestImage(width: 10, height: 30);
      resolver.update([
        _request(LuckyTestImageProvider(completer), formatter: (_) => output)
      ], ImageConfiguration.empty, 3);
      completer.succeed(source, scale: 2);
      source.dispose();
      expect(resolver[_slot]!.naturalSize, const Size(5, 15));
      expect(
          computeImageBox(
              natural: resolver[_slot]!.naturalSize,
              width: const LuckyPx(20),
              maxWidth: 100,
              maxHeight: 100),
          const Size(20, 60));
    });
    for (final cancellation in ['update', 'dispose']) {
      testWidgets(
          'async formatter keeps its source valid after $cancellation until completion',
          (tester) async {
        final completer = LuckyTestImageCompleter();
        final release = Completer<void>();
        ui.Image? borrowed;
        ui.Image? output;
        Object? failure;
        resolver.update([
          _request(LuckyTestImageProvider(completer), formatter: (image) async {
            borrowed = image;
            await release.future;
            try {
              return output = image.clone();
            } on Object catch (error) {
              failure = error;
              rethrow;
            }
          })
        ], ImageConfiguration.empty, 1);
        final source = await createLuckyTestImage();
        completer.succeed(source);
        source.dispose();
        if (cancellation == 'dispose') {
          resolver.dispose();
        } else {
          resolver.update([], ImageConfiguration.empty, 1);
        }
        final disposedEarly = borrowed!.debugDisposed;
        release.complete();
        await tester.pump();
        expect(disposedEarly, isFalse);
        expect(failure, isNull);
        expect(output, isNotNull);
        expect(output!.debugDisposed, isTrue);
        expect(borrowed!.debugDisposed, isTrue);
        expect(resolver[_slot], isNull);
        expect(errors, isEmpty);
        expect(changes, 0);
      });
    }
    testWidgets('image arrivals bump the generation and notify listeners',
        (tester) async {
      final completer = LuckyTestImageCompleter();
      final provider = LuckyTestImageProvider(completer);
      resolver.update([_request(provider)], ImageConfiguration.empty, 1);
      final before = resolver.images.generation;
      expect(resolver.isSettled, isFalse);
      final image = await createLuckyTestImage();
      completer.succeed(image);
      expect(resolver.images.generation, before + 1);
      expect(changes, 1);
      expect(resolver[_slot], isNotNull);
      expect(resolver.debugDecodedBytes, image.width * image.height * 4);
      expect(ready, 1);
      final held = resolver[_slot]!.image;
      resolver.update([_request(provider)], ImageConfiguration.empty, 1);
      expect(resolver[_slot]!.image, same(held));
      expect(ready, 2);
      image.dispose();
    });
    testWidgets(
        'failure calls onImageError and does not block other images (#417)',
        (tester) async {
      final bad = LuckyTestImageCompleter();
      final good = LuckyTestImageCompleter();
      resolver.update([
        _request(LuckyTestImageProvider(bad)),
        _request(LuckyTestImageProvider(good), slot: _other)
      ], ImageConfiguration.empty, 1);
      bad.fail(StateError('primary'));
      expect(errors.single.slot, _slot);
      expect(resolver[_slot], isNull);
      expect(ready, 0);
      final image = await createLuckyTestImage();
      good.succeed(image);
      image.dispose();
      expect(resolver[_other], isNotNull);
      expect(resolver.isSettled, isTrue);
      expect(ready, 1);
    });
    testWidgets('fallback provider is used when the primary fails',
        (tester) async {
      final bad = LuckyTestImageCompleter();
      final fallback = LuckyTestImageCompleter();
      resolver.update([
        _request(LuckyTestImageProvider(bad),
            fallback: LuckyTestImageProvider(fallback))
      ], ImageConfiguration.empty, 1);
      bad.fail(StateError('primary'));
      expect(errors.single.usedFallback, isFalse);
      final image = await createLuckyTestImage();
      fallback.succeed(image);
      image.dispose();
      expect(resolver[_slot], isNotNull);
      final otherBad = LuckyTestImageCompleter();
      final otherFallback = LuckyTestImageCompleter();
      resolver.update([
        _request(LuckyTestImageProvider(otherBad),
            fallback: LuckyTestImageProvider(otherFallback))
      ], ImageConfiguration.empty, 1);
      otherBad.fail(StateError('again'));
      otherFallback.fail(StateError('fallback'));
      expect(errors.last.usedFallback, isTrue);
      expect(resolver.isSettled, isTrue);
    });
    testWidgets(
        'changing sources drops late results from stale generations (#264)',
        (tester) async {
      final completer = LuckyTestImageCompleter();
      final formatted = Completer<ui.Image>();
      ui.Image? borrowed;
      resolver.update([
        _request(LuckyTestImageProvider(completer), formatter: (image) {
          borrowed = image;
          return formatted.future;
        })
      ], ImageConfiguration.empty, 1);
      final source = await createLuckyTestImage();
      completer.succeed(source);
      expect(resolver.debugDecodedBytes, source.width * source.height * 4);
      source.dispose();
      resolver.update([], ImageConfiguration.empty, 1);
      expect(borrowed!.debugDisposed, isFalse);
      expect(resolver.debugDecodedBytes, 0);
      final output = await createLuckyTestImage();
      formatted.complete(output);
      await tester.pump();
      expect(borrowed!.debugDisposed, isTrue);
      expect(output.debugDisposed, isTrue);
      expect(resolver[_slot], isNull);
      expect(changes, 0);
      final late = LuckyTestImageCompleter();
      resolver.update([_request(LuckyTestImageProvider(late))],
          ImageConfiguration.empty, 1);
      expect(resolver.debugListenerCount, 1);
      resolver.update([], ImageConfiguration.empty, 1);
      expect(resolver.debugListenerCount, 0);
      final stale = await createLuckyTestImage();
      late.deliverLateFrame(stale);
      stale.dispose();
      expect(resolver[_slot], isNull);
      expect(changes, 0);
    });
    testWidgets(
        'decodes at draw size times device pixel ratio when a size is specified',
        (tester) async {
      final source = await createLuckyTestImage(width: 80, height: 40);
      final bytes = await tester
          .runAsync(() => source.toByteData(format: ui.ImageByteFormat.png));
      final provider = MemoryImage(bytes!.buffer.asUint8List());
      resolver.update([_request(provider, width: 10, height: 10)],
          ImageConfiguration.empty, 2);
      await tester.runAsync(() => _settleImages(resolver));
      expect(resolver[_slot]!.image.width, 20);
      expect(resolver[_slot]!.image.height, 10);
      expect(resolver[_slot]!.naturalSize, const Size(10, 5));
      final held = resolver[_slot]!.image;
      resolver.update([_request(provider, width: 12, height: 12)],
          ImageConfiguration.empty, 2);
      expect(resolver[_slot]!.image, same(held));
      resolver
          .update([_request(provider, width: 30)], ImageConfiguration.empty, 2);
      expect(held.debugDisposed, isTrue);
      await tester.runAsync(() => _settleImages(resolver));
      expect(resolver[_slot]!.naturalSize, const Size(30, 15));
      resolver
          .update([_request(provider, height: 4)], ImageConfiguration.empty, 2);
      await tester.runAsync(() => _settleImages(resolver));
      expect(resolver[_slot]!.naturalSize, const Size(8, 4));
      source.dispose();
    });
    testWidgets('natural size uses image width divided by ImageInfo.scale',
        (tester) async {
      final completer = LuckyTestImageCompleter();
      resolver.update([_request(LuckyTestImageProvider(completer))],
          ImageConfiguration.empty, 3);
      final image = await createLuckyTestImage(width: 40, height: 20);
      completer.succeed(image, scale: 2);
      expect(resolver[_slot]!.naturalSize, const Size(20, 10));
      image.dispose();
    });
    testWidgets(
        'formatter output replaces the image and is disposed on eviction',
        (tester) async {
      final completer = LuckyTestImageCompleter();
      final output = await createLuckyTestImage();
      ui.Image? input;
      resolver.update([
        _request(LuckyTestImageProvider(completer), formatter: (image) {
          input = image;
          return output;
        })
      ], ImageConfiguration.empty, 1);
      final source = await createLuckyTestImage();
      completer.succeed(source);
      source.dispose();
      expect(input!.debugDisposed, isTrue);
      expect(resolver[_slot]!.image, same(output));
      resolver.update([], ImageConfiguration.empty, 1);
      expect(output.debugDisposed, isTrue);
      final broken = LuckyTestImageCompleter();
      resolver.update([
        _request(LuckyTestImageProvider(broken),
            formatter: (_) => throw StateError('formatter'))
      ], ImageConfiguration.empty, 1);
      final image = await createLuckyTestImage();
      broken.succeed(image);
      image.dispose();
      expect(errors.single.error, isA<StateError>());
      expect(resolver.isSettled, isTrue);
    });
    testWidgets(
        'dispose removes all ImageStream listeners and disposes held images',
        (tester) async {
      final first = LuckyTestImageCompleter();
      final second = LuckyTestImageCompleter();
      resolver.update([
        _request(LuckyTestImageProvider(first)),
        _request(LuckyTestImageProvider(second), slot: _other)
      ], ImageConfiguration.empty, 1);
      final image = await createLuckyTestImage();
      first.succeed(image);
      image.dispose();
      final held = resolver[_slot]!.image;
      expect(resolver.debugListenerCount, 1);
      resolver.dispose();
      expect(resolver.debugListenerCount, 0);
      expect(held.debugDisposed, isTrue);
      final output = await createLuckyTestImage();
      second.succeed(output);
      output.dispose();
      expect(changes, 1);
    });
    testWidgets(
        'onReady fires once after every image settled including failures',
        (tester) async {
      final first = LuckyTestImageCompleter();
      final second = LuckyTestImageCompleter();
      resolver.update([
        _request(LuckyTestImageProvider(first)),
        _request(LuckyTestImageProvider(second), slot: _other)
      ], ImageConfiguration.empty, 1);
      first.fail(StateError('one'));
      expect(ready, 0);
      second.fail(StateError('two'));
      expect(ready, 1);
      expect(changes, 2);
    });
    testWidgets('only the first frame of an animated image is kept',
        (tester) async {
      final completer = LuckyTestImageCompleter();
      resolver.update([_request(LuckyTestImageProvider(completer))],
          ImageConfiguration.empty, 1);
      final image = await createLuckyTestImage();
      completer.succeed(image);
      final first = resolver[_slot]!.image;
      completer.succeed(image);
      image.dispose();
      expect(resolver[_slot]!.image, same(first));
      expect(changes, 1);
      expect(resolver.debugListenerCount, 0);
    });
  });
}
