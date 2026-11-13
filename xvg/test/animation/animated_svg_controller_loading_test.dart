import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xvg/src/animation/animated_svg_widget.dart'
    show debugResolveAnimatedImages;
import 'package:xvg/src/animation/shared_animation_clock.dart';
import 'package:xvg/xvg.dart';

/// A source with a finite, known duration. / 有限且时长已知的源。
const _source =
    '<svg width="24" height="24">'
    '<rect width="24" height="24">'
    '<animate attributeName="opacity" values="0;1" dur="2s"/>'
    '</rect></svg>';

/// A bitmap source whose decoder is controlled by the test.
/// 由测试控制解码时机的图片源。
const _imageSource =
    '<svg width="24" height="24">'
    '<image width="24" height="24" href="data:image/png;base64,unused"/>'
    '<rect width="24" height="24">'
    '<animate attributeName="opacity" values="0;1" dur="2s"/>'
    '</rect></svg>';

/// Invalid XML used by each error route. / 各错误路径共用的非法 XML。
const _brokenSource = '<svg><rect></svg>';

/// A frame long enough to observe any unwanted ticking. / 足以观察空转的帧。
const _second = Duration(seconds: 1);

/// The finite document's natural duration. / 有限文档的自然时长。
const _twoSeconds = Duration(seconds: 2);

/// Wraps a renderer with a directionality. / 为渲染器提供文字方向。
Widget _host(Widget child) =>
    Directionality(textDirection: TextDirection.ltr, child: child);

/// Loading and parse failure contracts. / 加载与解析失败契约。
void main() {
  setUp(XvgDocumentCache.instance.clear);
  tearDown(() {
    debugResolveAnimatedImages = null;
    XvgDocumentCache.instance.clear();
  });

  testWidgets('onLoaded runs once after parse with correct info', (
    tester,
  ) async {
    final infos = <XvgAnimationInfo>[];
    final controller = XvgAnimationController(autoplay: false);
    await tester.pumpWidget(
      _host(
        AnimatedXvg.string(
          _source,
          controller: controller,
          onLoaded: infos.add,
        ),
      ),
    );
    expect(infos, hasLength(1));
    expect(infos.single.settleTime, _twoSeconds);
    expect(infos.single.loops, isFalse);
    expect(infos.single, controller.info);
    await tester.pump(_second);
    await tester.pumpWidget(
      _host(
        AnimatedXvg.string(
          _source,
          controller: controller,
          width: 48,
          onLoaded: infos.add,
        ),
      ),
    );
    expect(infos, hasLength(1));
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets(
    'first ready document stays primary when earlier image becomes ready',
    (tester) async {
      final decoded = Completer<void>();
      debugResolveAnimatedImages = (_) => decoded.future;
      final controller = XvgAnimationController(autoplay: false);
      final delayedSource = _imageSource.replaceFirst('2s', '4s');
      final readyInfo = XvgDocumentCache.instance
          .getOrParse(_source)
          .document
          .info;

      /// Keeps the delayed widget mounted while its ready sibling is removed.
      /// 移除就绪兄弟时，保持延迟控件挂载。
      Widget scene(bool includeReady) => _host(
        Column(
          children: [
            AnimatedXvg.string(
              delayedSource,
              key: const ValueKey('delayed'),
              controller: controller,
            ),
            if (includeReady)
              AnimatedXvg.string(
                _source,
                key: const ValueKey('ready'),
                controller: controller,
              ),
          ],
        ),
      );
      await tester.pumpWidget(scene(true));
      expect(controller.info, same(readyInfo));
      decoded.complete();
      await tester.pump();
      await tester.pump();
      expect(controller.info, same(readyInfo));
      await tester.pumpWidget(scene(false));
      expect(controller.info!.settleTime, _twoSeconds * 2);
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('onLoaded can setState in its parent', (tester) async {
    var loaded = false;
    await tester.pumpWidget(
      _host(
        StatefulBuilder(
          builder: (context, setState) => Column(
            children: [
              AnimatedXvg.string(
                _source,
                autoplay: false,
                onLoaded: (_) => setState(() => loaded = true),
              ),
              Text(loaded.toString()),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('true'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('image document waits for decoder before loaded and ticking', (
    tester,
  ) async {
    final decoded = Completer<void>();
    debugResolveAnimatedImages = (_) => decoded.future;
    final controller = XvgAnimationController();
    final infos = <XvgAnimationInfo>[];
    await tester.pumpWidget(
      _host(
        AnimatedXvg.string(
          _imageSource,
          controller: controller,
          onLoaded: infos.add,
        ),
      ),
    );
    expect(infos, isEmpty);
    expect(controller.info, isNull);
    expect(SharedAnimationClock.instance.subscriberCount, 0);
    await tester.pump(_second);
    expect(controller.time.value, Duration.zero);
    decoded.complete();
    await tester.pump();
    await tester.pump();
    expect(infos, hasLength(1));
    expect(infos.single.settleTime, _twoSeconds);
    expect(SharedAnimationClock.instance.subscriberCount, 1);
    await tester.pump(_second);
    expect(infos, hasLength(1));
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    expect(tester.takeException(), isNull);
  });

  testWidgets('parse failure uses onError and errorBuilder without throwing', (
    tester,
  ) async {
    final controller = XvgAnimationController();
    final errors = <Object>[];
    final events = <XvgAnimationEvent>[];
    controller.addEventListener(events.add);
    await tester.pumpWidget(
      _host(
        AnimatedXvg.string(
          _brokenSource,
          controller: controller,
          onError: (error, stack) => errors.add(error),
          errorBuilder: (context, error, stack) => const Text('parse failed'),
        ),
      ),
    );
    await tester.pump();
    expect(errors, hasLength(1));
    expect(events.whereType<XvgAnimationError>(), hasLength(1));
    expect(controller.status, XvgPlaybackStatus.error);
    expect(find.text('parse failed'), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(SharedAnimationClock.instance.subscriberCount, 0);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('onError alone renders an empty box with requested dimensions', (
    tester,
  ) async {
    var failures = 0;
    await tester.pumpWidget(
      _host(
        Center(
          child: AnimatedXvg.string(
            _brokenSource,
            width: 37,
            height: 41,
            onError: (_, _) => failures++,
          ),
        ),
      ),
    );
    await tester.pump();
    expect(failures, 1);
    expect(tester.getSize(find.byType(AnimatedXvg)), const Size(37, 41));
    expect(tester.takeException(), isNull);
  });

  testWidgets('errorBuilder alone handles failure without global reporting', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        AnimatedXvg.string(
          _brokenSource,
          errorBuilder: (context, error, stack) => const Text('handled'),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('handled'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unhandled parse failure is reported through FlutterError', (
    tester,
  ) async {
    final reported = <FlutterErrorDetails>[];
    final previousHandler = FlutterError.onError;
    FlutterError.onError = reported.add;
    try {
      await tester.pumpWidget(_host(const AnimatedXvg.string(_brokenSource)));
      await tester.pump();
    } finally {
      FlutterError.onError = previousHandler;
    }
    expect(reported, hasLength(1));
    expect(reported.single.exception, isNotNull);
    expect(find.byType(AnimatedXvg), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
