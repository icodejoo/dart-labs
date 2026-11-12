import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luckdraw/capsule.dart';
import 'package:luckdraw/grid.dart';
import 'package:luckdraw/lotto.dart';
import 'package:luckdraw/number_wheel.dart';
import 'package:luckdraw/wheel.dart';

import '../support/fixtures.dart';
import '../support/test_images.dart';

/// 生命周期测试的统一胶囊填充。
const LuckyFill _fill = LuckyFill.color(Color(0xFFFFAA00));

/// 每次挂载均创建独立的真实页面、开始命令和控制器释放函数。
typedef _Session = (Widget, bool Function(), VoidCallback);

/// 统计真实图像流的添加和移除次数，包含框架缓存监听。
final class _CountingImageStream extends LuckyTestImageCompleter {
  /// 创建尚无监听的流。
  _CountingImageStream();

  /// 累计添加次数。
  int additions = 0;

  /// 累计移除次数。
  int removals = 0;

  /// 记录每次订阅。
  @override
  void addListener(ImageStreamListener listener) {
    additions++;
    super.addListener(listener);
  }

  /// 记录每次解除订阅。
  @override
  void removeListener(ImageStreamListener listener) {
    removals++;
    super.removeListener(listener);
  }
}

/// 同时核对原生资源、图像监听和真实宿主 Ticker 的释放。
Future<void> _cycles(
    WidgetTester tester, _Session Function(LuckyImage image) create) async {
  final source = await tester
      .runAsync(() => createLuckyTestImage(color: const Color(0xFFFFAA00)));
  final pictures = <ui.Picture>{};
  final images = <ui.Image>{};
  final pictureCreate = ui.Picture.onCreate;
  final pictureDispose = ui.Picture.onDispose;
  final imageCreate = ui.Image.onCreate;
  final imageDispose = ui.Image.onDispose;
  var createdPictures = 0;
  var disposedPictures = 0;
  var createdImages = 0;
  var disposedImages = 0;
  ui.Picture.onCreate = (value) {
    pictureCreate?.call(value);
    pictures.add(value);
    createdPictures++;
  };
  ui.Picture.onDispose = (value) {
    pictureDispose?.call(value);
    if (pictures.remove(value)) disposedPictures++;
  };
  ui.Image.onCreate = (value) {
    imageCreate?.call(value);
    images.add(value);
    createdImages++;
  };
  ui.Image.onDispose = (value) {
    imageDispose?.call(value);
    if (images.remove(value)) disposedImages++;
  };
  try {
    for (var i = 0; i < 10; i++) {
      final stream = _CountingImageStream();
      final provider = LuckyTestImageProvider(stream);
      final session = create(LuckyImage(provider,
          width: const LuckyLength.px(12), height: const LuckyLength.px(12)));
      await tester.pumpWidget(MediaQuery(
          data: const MediaQueryData(devicePixelRatio: 2),
          child: Directionality(
              textDirection: TextDirection.ltr,
              child: Center(
                  child: SizedBox.square(dimension: 320, child: session.$1)))));
      if (stream.listenerCount > 0) {
        stream.succeed(source!);
        await tester.pump();
      }
      expect(session.$2(), isTrue);
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.binding.transientCallbackCount, greaterThan(0));
      await tester.pumpWidget(const SizedBox());
      session.$3();
      await provider.evict();
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
      await tester.pump();
      expect(stream.listenerCount, 0);
      expect(stream.removals, stream.additions);
      expect(tester.binding.transientCallbackCount, 0);
      expect(pictures, isEmpty);
      expect(images, isEmpty);
      expect(tester.takeException(), isNull);
    }
    expect(createdPictures, greaterThan(0));
    expect(createdImages, greaterThan(0));
    expect(disposedPictures, createdPictures);
    expect(disposedImages, createdImages);
  } finally {
    ui.Picture.onCreate = pictureCreate;
    ui.Picture.onDispose = pictureDispose;
    ui.Image.onCreate = imageCreate;
    ui.Image.onDispose = imageDispose;
    source!.dispose();
  }
}

/// 各玩法分别复现十次页面生命周期，所有新增缓存都必须释放。
void main() {
  group('PERF resources', () {
    testWidgets(
        'wheel releases native caches streams and tickers in ten cycles',
        (tester) => _cycles(tester, (image) {
              final controller = WheelController();
              return (
                LuckyWheel(
                    config: WheelConfig(prizes: [
                      WheelPrize(images: [image]),
                      const WheelPrize(),
                    ]),
                    controller: controller),
                controller.play,
                controller.dispose
              );
            }));
    testWidgets(
        'grid releases native caches streams and tickers in ten cycles',
        (tester) => _cycles(tester, (image) {
              final controller = GridController();
              return (
                LuckyGrid(
                    config: GridConfig(
                        prizes: [
                          GridPrize(
                              x: 0, y: 0, images: [GridImage(image.image)]),
                          const GridPrize(x: 1, y: 0),
                        ],
                        style: const GridStyle(
                            cell: LuckyCellStyle(
                          background: LuckyFill.color(Color(0xFFFFAA00)),
                          shadow:
                              LuckyShadow(blur: 6, color: Color(0x66000000)),
                        ))),
                    controller: controller),
                controller.play,
                controller.dispose
              );
            }));
    testWidgets(
        'number wheel releases native caches streams and tickers in ten cycles',
        (tester) => _cycles(tester, (image) {
              final controller = NumberWheelController();
              return (
                LuckyNumberWheel(
                    config: NumberWheelConfig.range(0, 36),
                    controller: controller),
                controller.play,
                controller.dispose
              );
            }));
    testWidgets(
        'capsule releases native caches streams and tickers in ten cycles',
        (tester) => _cycles(tester, (image) {
              final controller = CapsuleController();
              return (
                LuckyCapsuleMachine(
                    config: CapsuleConfig(prizes: [
                      CapsulePrize(
                          topFill: _fill, bottomFill: _fill, images: [image]),
                      const CapsulePrize(topFill: _fill, bottomFill: _fill),
                    ]),
                    controller: controller),
                controller.play,
                controller.dispose
              );
            }));
    testWidgets(
        'lotto releases native caches streams and tickers in ten cycles',
        (tester) => _cycles(tester, (image) {
              final controller = LottoController();
              return (
                LuckyLotto(
                    config: LottoConfig.superLotto(), controller: controller),
                controller.play,
                controller.dispose
              );
            }));
  });
}
