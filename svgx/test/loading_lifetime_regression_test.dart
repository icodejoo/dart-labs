import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:svgx/svgx.dart';
import 'package:svgx/src/cold_mount_budget.dart';
import 'package:svgx/src/svg_image_provider.dart';
import 'package:svgx/src/animation/animated_svg_widget.dart';
import 'package:svgx/src/animation/animated_svg_painter.dart';
import 'package:svgx/src/animation/svg_document_parser.dart';

const spin =
    '<svg width="24" height="24"><rect width="24" height="24"><animate attributeName="opacity" values="0;1" dur="10s" repeatCount="indefinite"/></rect></svg>';
const png =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';
const imageSvg =
    '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24"><image width="24" height="24" href="data:image/png;base64,$png"/></svg>';
ImageStreamCompleter load(StringSvgx provider) => provider.loadImage(
  provider,
  (buffer, {getTargetSize}) => throw UnimplementedError(),
);
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() {
    debugResolveAnimatedImages = null;
    debugSvgRasterize = null;
    ui.Image.onCreate = null;
    ui.Image.onDispose = null;
    ui.Picture.onCreate = null;
    ColdMountFrameBudget.instance.debugReset();
  });
  testWidgets(
    'deferred duplicate keys share one work item and live consumers win',
    (tester) async {
      final b = ColdMountFrameBudget.instance;
      var calls = 0;
      final first = b.runDeferred(
        () => ++calls,
        key: 'same',
        isActive: () => false,
      );
      final second = b.runDeferred(
        () => ++calls,
        key: 'same',
        isActive: () => true,
      );
      expect(identical(first, second), true);
      await tester.pump();
      expect(await first, 1);
      expect(calls, 1);
    },
  );
  testWidgets('deferred work skips an unmounted consumer', (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      Builder(
        builder: (context) {
          ColdMountFrameBudget.instance.runDeferred(
            () => calls++,
            key: 'gone',
            isActive: () => context.mounted,
          );
          return const SizedBox();
        },
      ),
    );
    // 首帧 post-frame 已执行；另排一项，在下一帧卸载后才轮到它。
    calls = 0;
    final context = tester.element(find.byType(Builder));
    ColdMountFrameBudget.instance.runDeferred(
      () => calls++,
      key: 'gone2',
      isActive: () => context.mounted,
    );
    var liveCalls = 0;
    final liveKey = GlobalKey();
    await tester.pumpWidget(SizedBox(key: liveKey));
    ColdMountFrameBudget.instance.runDeferred(
      () => liveCalls++,
      key: 'live',
      isActive: () => liveKey.currentContext?.mounted ?? false,
    );
    await tester.pump();
    expect(liveCalls, 1);
    expect(calls, 0);
  });
  testWidgets('provider parse exceptions reach completer listener', (
    tester,
  ) async {
    final c = load(const StringSvgx('<svg><animate>'));
    Object? error;
    final l = ImageStreamListener(
      (_, _) {},
      onError: (Object e, StackTrace? s) {
        error = e;
      },
    );
    c.addListener(l);
    await tester.pump();
    expect(error, isNotNull);
    c.removeListener(l);
  });
  testWidgets('provider ready continuation errors reach listener', (
    tester,
  ) async {
    final c = load(const StringSvgx(spin, width: double.nan));
    Object? error;
    final l = ImageStreamListener(
      (_, _) {},
      onError: (Object e, StackTrace? s) {
        error = e;
      },
    );
    c.addListener(l);
    await tester.pump();
    expect(error, isNotNull);
    c.removeListener(l);
  });
  testWidgets('provider render errors reach listener', (tester) async {
    final c = load(const StringSvgx(spin, width: 24, height: 24));
    Object? error;
    final l = ImageStreamListener(
      (_, _) {},
      onError: (Object e, StackTrace? s) {
        error = e;
      },
    );
    ui.Picture.onCreate = (_) => throw StateError('record failed');
    c.addListener(l);
    await tester.pump();
    ui.Picture.onCreate = null;
    expect(error, isA<StateError>());
    c.removeListener(l);
  });
  testWidgets(
    'provider allows only one frame in flight and disposes abandoned image',
    (tester) async {
      final c = load(
        const StringSvgx(spin, width: 24, height: 24, animationFrameRate: 60),
      );
      var pictures = 0, delivered = 0;
      final disposed = <ui.Image>[];
      final gate = Completer<ui.Image>();
      debugSvgRasterize = (_, _, _, _) {
        pictures++;
        return gate.future;
      };
      ui.Image.onDispose = disposed.add;
      final l = ImageStreamListener((image, _) {
        delivered++;
        image.dispose();
      });
      c.addListener(l);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(pictures, 1);
      c.removeListener(l);
      final recorder = ui.PictureRecorder();
      Canvas(recorder);
      final picture = recorder.endRecording();
      final image = await tester.runAsync(() => picture.toImage(1, 1));
      picture.dispose();
      gate.complete(image!);
      await tester.pump();
      expect(delivered, 0);
      expect(disposed, contains(image));
    },
  );

  testWidgets('large raster preserves aspect and logical scale', (
    tester,
  ) async {
    final c = load(const StringSvgx(spin, width: 5000, height: 100));
    ImageInfo? result;
    final l = ImageStreamListener((image, _) {
      result = image;
    });
    c.addListener(l);
    await tester.pump();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 150));
    });
    expect(result, isNotNull);
    expect(result!.image.width, 4096);
    expect(result!.image.height, 82);
    expect(result!.image.width / result!.scale, closeTo(5000, 0.01));
    c.removeListener(l);
    result!.dispose();
  });
  testWidgets('owned widget images are disposed on replacement and unmount', (
    tester,
  ) async {
    final disposed = <ui.Image>[];
    ui.Image.onDispose = disposed.add;
    Widget w(String source) => Directionality(
      textDirection: TextDirection.ltr,
      child: SvgxAnimated.string(source),
    );
    await tester.runAsync(() async {
      await tester.pumpWidget(w(imageSvg));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
    final painter =
        tester.widget<CustomPaint>(find.byType(CustomPaint)).painter
            as AnimatedSvgPainter;
    final image = painter.root.children.single.resolvedImage!;
    await tester.pumpWidget(w(spin));
    expect(disposed, contains(image));
    await tester.runAsync(() async {
      await tester.pumpWidget(w(imageSvg));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
    final second =
        (tester.widget<CustomPaint>(find.byType(CustomPaint)).painter
                as AnimatedSvgPainter)
            .root
            .children
            .single
            .resolvedImage!;
    await tester.pumpWidget(const SizedBox());
    expect(disposed, contains(second));
  });
  testWidgets(
    'failed image resolution still reveals document and starts clock',
    (tester) async {
      debugResolveAnimatedImages = (_) async =>
          throw StateError('decode failed');
      var started = 0;
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: SvgxAnimated.string(
            imageSvg,
            onAnimationStart: () => started++,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      expect(find.byType(CustomPaint), findsOneWidget);
      expect(started, 1);
    },
  );
  test('old TextPainter is disposed when text styling changes', () {
    final doc = parseAnimatedSvgDocument(
      '<svg width="100" height="100"><text y="20" fill="currentColor">A</text></svg>',
    );
    void paint(Color color) {
      final recorder = ui.PictureRecorder();
      AnimatedSvgPainter(
        root: doc.root,
        intrinsicSize: const Size(100, 100),
        clock: ValueNotifier(Duration.zero),
        theme: SvgxTheme(currentColor: color),
        fit: BoxFit.contain,
        alignment: Alignment.center,
      ).paint(Canvas(recorder), const Size(100, 100));
      recorder.endRecording().dispose();
    }

    paint(Colors.red);
    final old = doc.root.children.single.cachedTextPainter as TextPainter;
    paint(Colors.blue);
    expect(old.debugDisposed, true);
    (doc.root.children.single.cachedTextPainter as TextPainter).dispose();
  });
}
