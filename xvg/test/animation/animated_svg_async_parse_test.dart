import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xvg/src/animation/animated_svg_painter.dart';
import 'package:xvg/src/animation/document_parse_worker.dart';
import 'package:xvg/src/animation/shared_animation_clock.dart';
import 'package:xvg/src/animation/svg_document_cache.dart';
import 'package:xvg/xvg.dart' hide XvgDocumentCache;

import 'async_parse_test_utils.dart';

/// Requested dimensions, also used for the pending placeholder.
/// 请求尺寸，也用于等待中的占位。
const _size = Size(37, 41);

/// One second for paused/loading time assertions. / 暂停、加载时钟断言使用的一秒。
const _second = Duration(seconds: 1);

/// Visible parse failure marker. / 可见的解析失败标记。
const _parseFailureText = 'parse failed';

/// Gives the real isolate event loop time while pumping fake widget frames.
/// 给真实 isolate 事件循环运行时间，同时推进控件测试的虚拟帧。
Future<void> _waitFor(WidgetTester tester, bool Function() ready) async {
  final timeout = Stopwatch()..start();
  while (!ready() && timeout.elapsed < const Duration(seconds: 10)) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
  }
  expect(ready(), isTrue, reason: 'worker completion timed out');
  await tester.pump();
}

/// Flushes fake microtasks while waiting for real isolate exit, before test end.
/// 测试结束前等待真实 isolate 退出，并刷新虚拟微任务。
void _asyncTestWidgets(String name, WidgetTesterCallback body) {
  testWidgets(name, (tester) async {
    try {
      await body(tester);
    } finally {
      var stopped = false;
      XvgDocumentCache.instance.debugResetAsyncParsing().then((_) {
        stopped = true;
      });
      await _waitFor(tester, () => stopped);
    }
  });
}

/// Constrains the renderer while allowing explicit TickerMode changes.
/// 约束渲染器，同时允许显式改变 TickerMode。
Widget _host(Widget child, {bool enabled = true}) => Directionality(
  textDirection: TextDirection.ltr,
  child: TickerMode(
    enabled: enabled,
    child: Center(child: child),
  ),
);

/// Reads the painter's sampled document time. / 读取画笔采样的文档时刻。
Duration _paintTime(WidgetTester tester) =>
    (tester.widget<CustomPaint>(find.byType(CustomPaint)).painter!
            as AnimatedSvgPainter)
        .clock
        .value;

/// Async parsing through the real native worker. / 通过真实原生 worker 的异步解析。
void main() {
  final cache = XvgDocumentCache.instance;
  final clock = SharedAnimationClock.instance;
  setUpAll(RustLib.init);
  setUp(cache.debugResetAsyncParsing);
  tearDown(cache.debugResetAsyncParsing);

  _asyncTestWidgets(
    'unavailable worker loads through fallback without a widget error',
    (tester) async {
      DocumentParseWorker.instance.debugNativeLibraryPath =
          missingAsyncWorkerLibrary;
      var loaded = 0;
      var errors = 0;
      await tester.pumpWidget(
        _host(
          XvgAnimated.string(
            largeAsyncSvg(),
            autoplay: false,
            onLoaded: (_) => loaded++,
            onError: (_, _) => errors++,
            errorBuilder: (_, _, _) => const Text(_parseFailureText),
          ),
        ),
      );
      await _waitFor(tester, () => loaded == 1);
      expect(errors, 0);
      expect(find.text(_parseFailureText), findsNothing);
      expect(find.byType(CustomPaint), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(DocumentParseWorker.instance.debugStartCount, 1);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  _asyncTestWidgets(
    'large source shows sized placeholder then loads once safely',
    (tester) async {
      var loaded = 0;
      var parentUpdated = false;
      await tester.pumpWidget(
        _host(
          StatefulBuilder(
            builder: (context, setState) {
              return XvgAnimated.string(
                largeAsyncSvg(),
                width: _size.width,
                height: _size.height,
                autoplay: false,
                onLoaded: (_) {
                  loaded++;
                  setState(() => parentUpdated = true);
                },
              );
            },
          ),
        ),
      );
      expect(find.byType(CustomPaint), findsNothing);
      expect(tester.getSize(find.byType(XvgAnimated)), _size);
      expect(loaded, 0);
      expect(clock.subscriberCount, 0);
      await _waitFor(tester, () => loaded == 1);
      expect(parentUpdated, isTrue);
      expect(find.byType(CustomPaint), findsOneWidget);
      await tester.pump(_second);
      expect(loaded, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  _asyncTestWidgets('unmount while pending neither attaches nor calls loaded', (
    tester,
  ) async {
    final source = largeAsyncSvg();
    var loaded = 0;
    var finished = false;
    await tester.pumpWidget(
      _host(XvgAnimated.string(source, onLoaded: (_) => loaded++)),
    );
    cache.getOrParseAsync(source).then((_) => finished = true);
    expect(clock.subscriberCount, 0);
    await tester.pumpWidget(const SizedBox.shrink());
    await _waitFor(tester, () => finished);
    expect(loaded, 0);
    expect(clock.subscriberCount, 0);
    expect(tester.takeException(), isNull);
  });

  _asyncTestWidgets(
    'source swap rejects old completion and keeps only latest info',
    (tester) async {
      final source = largeAsyncSvg();
      final infos = <XvgAnimationInfo>[];
      var oldFinished = false;
      await tester.pumpWidget(
        _host(
          XvgAnimated.string(source, autoplay: false, onLoaded: infos.add),
        ),
      );
      cache.getOrParseAsync(source).then((_) => oldFinished = true);
      await tester.pumpWidget(
        _host(
          XvgAnimated.string(
            largeAsyncSvg(duration: '3s'),
            autoplay: false,
            onLoaded: infos.add,
          ),
        ),
      );
      await _waitFor(tester, () => oldFinished && infos.isNotEmpty);
      expect(infos, hasLength(1));
      expect(infos.single.naturalDuration, const Duration(seconds: 7));
      expect(_paintTime(tester), Duration.zero);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  _asyncTestWidgets('stale parse error after source swap is ignored', (
    tester,
  ) async {
    var errors = 0;
    var oldFinished = false;
    final invalid = invalidLargeAsyncSvg();
    await tester.pumpWidget(
      _host(XvgAnimated.string(invalid, onError: (_, _) => errors++)),
    );
    cache
        .getOrParseAsync(invalid)
        .then(
          (_) {},
          onError: (Object _, StackTrace _) {
            oldFinished = true;
          },
        );
    await tester.pumpWidget(
      _host(const XvgAnimated.string(smallAsyncSvg, autoplay: false)),
    );
    await _waitFor(tester, () => oldFinished);
    expect(errors, 0);
    expect(find.byType(CustomPaint), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  _asyncTestWidgets('async failure reports once and recovers on source swap', (
    tester,
  ) async {
    var errors = 0;
    await tester.pumpWidget(
      _host(
        XvgAnimated.string(
          invalidLargeAsyncSvg(),
          onError: (_, _) => errors++,
          errorBuilder: (_, _, _) => const Text(_parseFailureText),
        ),
      ),
    );
    await _waitFor(tester, () => errors == 1);
    expect(find.text(_parseFailureText), findsOneWidget);
    expect(clock.subscriberCount, 0);
    await tester.pumpWidget(
      _host(const XvgAnimated.string(smallAsyncSvg, autoplay: false)),
    );
    expect(find.byType(CustomPaint), findsOneWidget);
    expect(errors, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  _asyncTestWidgets(
    'external controller preserves seek and driver swap during loading',
    (tester) async {
      final a = XvgAnimationController();
      final b = XvgAnimationController(autoplay: false)..seek(_second);
      final source = largeAsyncSvg();
      await tester.pumpWidget(
        _host(XvgAnimated.string(source, controller: a)),
      );
      expect(a.status, XvgPlaybackStatus.loading);
      expect(clock.subscriberCount, 0);
      await tester.pumpWidget(
        _host(XvgAnimated.string(source, controller: b)),
      );
      await _waitFor(tester, () => b.info != null);
      expect(a.info, isNull);
      expect(_paintTime(tester), _second);
      expect(clock.subscriberCount, 0);
      b.play();
      expect(clock.subscriberCount, 1);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(clock.subscriberCount, 0);
      a.dispose();
      b.dispose();
    },
  );

  _asyncTestWidgets(
    'TickerMode disabled while pending stays unsubscribed when ready',
    (tester) async {
      final source = largeAsyncSvg();
      var loaded = false;
      final widget = XvgAnimated.string(
        source,
        onLoaded: (_) => loaded = true,
      );
      await tester.pumpWidget(_host(widget));
      expect(clock.subscriberCount, 0);
      await tester.pumpWidget(_host(widget, enabled: false));
      await _waitFor(tester, () => loaded);
      expect(clock.subscriberCount, 0);
      await tester.pump(_second);
      expect(_paintTime(tester), Duration.zero);
      await tester.pumpWidget(_host(widget));
      expect(clock.subscriberCount, 1);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  _asyncTestWidgets(
    'implicit pause/rate changes during loading apply when ready',
    (tester) async {
      final source = largeAsyncSvg();
      var loaded = false;
      await tester.pumpWidget(_host(XvgAnimated.string(source)));
      await tester.pumpWidget(
        _host(
          XvgAnimated.string(
            source,
            autoplay: false,
            playbackRate: 2,
            onLoaded: (_) => loaded = true,
          ),
        ),
      );
      await _waitFor(tester, () => loaded);
      expect(clock.subscriberCount, 0);
      await tester.pump(_second);
      expect(_paintTime(tester), Duration.zero);
      await tester.pumpWidget(
        _host(XvgAnimated.string(source, playbackRate: 2)),
      );
      expect(clock.subscriberCount, 1);
      await tester.pump();
      await tester.pump(_second);
      expect(_paintTime(tester), _second * 2);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  _asyncTestWidgets(
    'Flutter animation uses latest value/span and never shared clock',
    (tester) async {
      final animation = AnimationController(vsync: tester, value: 0.2);
      final source = largeAsyncSvg();
      var loaded = false;
      await tester.pumpWidget(
        _host(
          XvgAnimated.string(
            source,
            animation: animation,
            onLoaded: (_) => loaded = true,
          ),
        ),
      );
      animation.value = 0.75;
      await tester.pumpWidget(
        _host(
          XvgAnimated.string(
            source,
            animation: animation,
            animationSpan: const Duration(seconds: 8),
            onLoaded: (_) => loaded = true,
          ),
        ),
      );
      expect(clock.subscriberCount, 0);
      await _waitFor(tester, () => loaded);
      expect(_paintTime(tester), const Duration(seconds: 6));
      expect(clock.subscriberCount, 0);
      animation.value = 0.5;
      await tester.pump();
      expect(_paintTime(tester), const Duration(seconds: 4));
      await tester.pumpWidget(const SizedBox.shrink());
      animation.dispose();
    },
  );

  _asyncTestWidgets('small source paints and loads on its first frame', (
    tester,
  ) async {
    var loaded = 0;
    await tester.pumpWidget(
      _host(
        XvgAnimated.string(
          smallAsyncSvg,
          autoplay: false,
          onLoaded: (_) => loaded++,
        ),
      ),
    );
    expect(find.byType(CustomPaint), findsOneWidget);
    expect(loaded, 1);
    expect(DocumentParseWorker.instance.debugStartCount, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
