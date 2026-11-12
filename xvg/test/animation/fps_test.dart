// Inspect protected listener state solely to verify cleanup of the final notifier.
// 全局通知器为 final，仅在本测试中读取受保护的监听状态来验证清理。
// ignore_for_file: invalid_use_of_protected_member

import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xvg/src/animation/animated_svg_painter.dart';
import 'package:xvg/src/animation/shared_animation_clock.dart';
import 'package:xvg/src/animation/xvg_fps.dart';
import 'package:xvg/xvg.dart';

/// Moving opaque rectangle with a complete first frame. / 首帧完整的不透明移动矩形。
const _source =
    '<svg width="24" height="24">'
    '<rect width="24" height="24" fill="#ff0000">'
    '<animate attributeName="x" values="0;12;0" dur="1s" '
    'repeatCount="indefinite"/></rect></svg>';

/// One observable playback step. / 一段可观测的播放时间。
const _step = Duration(milliseconds: 100);

/// Stable identity of the first widget. / 第一个控件的稳定标识。
const _first = ValueKey('first');

/// Stable identity of the second widget. / 第二个控件的稳定标识。
const _second = ValueKey('second');

/// Mounts an optional system preference and shared sibling.
/// 挂载可选的系统偏好及共享控制器的兄弟控件。
Widget _scene({
  double? fps,
  bool? system,
  bool ticker = true,
  bool autoplay = true,
  XvgAnimationController? controller,
  Animation<double>? animation,
  bool shared = false,
  double? secondFps,
}) {
  Widget child = Directionality(
    textDirection: TextDirection.ltr,
    child: Column(
      children: [
        TickerMode(
          enabled: ticker,
          child: XvgAnimated.string(
            _source,
            key: _first,
            fps: fps,
            autoplay: autoplay,
            controller: controller,
            animation: animation,
          ),
        ),
        if (shared)
          XvgAnimated.string(
            _source,
            key: _second,
            controller: controller,
            fps: secondFps,
          ),
      ],
    ),
  );
  if (system != null) {
    child = MediaQuery(
      data: MediaQueryData(disableAnimations: system),
      child: child,
    );
  }
  return child;
}

/// Reads the first widget's actual paint clock. / 读取第一个控件的实际绘制时钟。
AnimatedSvgPainter _painter(WidgetTester tester) =>
    tester
            .widget<CustomPaint>(
              find.descendant(
                of: find.byKey(_first),
                matching: find.byType(CustomPaint),
              ),
            )
            .painter!
        as AnimatedSvgPainter;

/// Advances beyond the first resume anchor. / 推进至恢复锚点之后。
Future<void> _advance(WidgetTester tester) async {
  await tester.pump(_step);
  await tester.pump(_step);
}

/// Counts actual timeline samples over display ticks. / 统计显示 tick 中实际更新的时间线采样。
Future<int> _sampleCount(WidgetTester tester) async {
  final samples = <Duration>{};
  for (var i = 0; i < 24; i++) {
    await tester.pump(const Duration(milliseconds: 16));
    samples.add(_painter(tester).time);
  }
  return samples.length;
}

/// Verifies resolution, live updates, shared ownership and cleanup.
/// 验证解析、实时切换、共享驱动与清理。
void main() {
  setUp(() {
    Xvg.fps.value = null;
    XvgDocumentCache.instance.clear();
  });
  tearDown(() {
    Xvg.fps.value = null;
    XvgDocumentCache.instance.clear();
    expect(Xvg.fps.hasListeners, isFalse);
    expect(SharedAnimationClock.instance.subscriberCount, 0);
  });

  testWidgets('global and instance caps change live without reattaching', (
    tester,
  ) async {
    tester.view.display.refreshRate = 60;
    addTearDown(tester.view.display.resetRefreshRate);
    await tester.pumpWidget(_scene());
    await _advance(tester);
    expect(await _sampleCount(tester), 24);
    Xvg.fps.value = 15;
    await tester.pump();
    expect(await _sampleCount(tester), inInclusiveRange(6, 7));
    Xvg.fps.value = 30;
    await tester.pump();
    expect(await _sampleCount(tester), inInclusiveRange(12, 13));
    await tester.pumpWidget(_scene(fps: 15));
    expect(await _sampleCount(tester), inInclusiveRange(6, 7));
    Xvg.fps.value = 0;
    await tester.pump();
    expect(await _sampleCount(tester), inInclusiveRange(6, 7));
    await tester.pumpWidget(_scene(fps: double.infinity));
    expect(await _sampleCount(tester), 24);
    await tester.pumpWidget(_scene());
    expect(_painter(tester).time, Duration.zero);
    Xvg.fps.value = 30;
    await tester.pump();
    expect(SharedAnimationClock.instance.subscriberCount, 1);
    await _advance(tester);
    expect(_painter(tester).time, greaterThan(Duration.zero));
    expect(await _sampleCount(tester), inInclusiveRange(12, 13));
    Xvg.fps.value = null;
    await tester.pump();
    expect(await _sampleCount(tester), 24);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('global unfreeze preserves autoplay false', (tester) async {
    Xvg.fps.value = 0;
    await tester.pumpWidget(_scene(autoplay: false));
    for (final fps in [null, 10.0]) {
      Xvg.fps.value = fps;
      await _advance(tester);
      expect(_painter(tester).time, Duration.zero);
      expect(SharedAnimationClock.instance.subscriberCount, 0);
      Xvg.fps.value = 0;
    }
    await tester.pumpWidget(const SizedBox());
  });

  for (final instance in [null, 0.0, 10.0, double.infinity]) {
    for (final global in [null, 0.0, 20.0, double.infinity]) {
      test('priority: instance=$instance global=$global', () {
        final effective = instance ?? global;
        expect(
          resolveFps(instance: instance, global: global),
          effective == double.infinity ? null : effective,
        );
      });
    }
  }

  for (final invalid in [-1.0, double.negativeInfinity, double.nan]) {
    test('rejects invalid fps $invalid', () {
      expect(
        () => resolveFps(instance: invalid, global: null),
        throwsAssertionError,
      );
      expect(
        () => resolveFps(instance: null, global: invalid),
        throwsAssertionError,
      );
      expect(
        () => XvgAnimated.string(_source, fps: invalid),
        throwsAssertionError,
      );
      expect(() => Xvg.string(_source, fps: invalid), throwsAssertionError);
    });
  }

  testWidgets('defaults preserve playback without a MediaQuery ancestor', (
    tester,
  ) async {
    await tester.pumpWidget(_scene());
    await _advance(tester);
    expect(_painter(tester).time, greaterThan(Duration.zero));
    expect(SharedAnimationClock.instance.subscriberCount, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'instance changes reset immediately and resume from first frame',
    (tester) async {
      final controller = XvgAnimationController();
      await tester.pumpWidget(_scene(controller: controller));
      await _advance(tester);
      expect(controller.time.value, greaterThan(Duration.zero));
      await tester.pumpWidget(_scene(controller: controller, fps: 0));
      expect(controller.time.value, Duration.zero);
      expect(_painter(tester).time, Duration.zero);
      expect(SharedAnimationClock.instance.subscriberCount, 0);
      await _advance(tester);
      expect(controller.time.value, Duration.zero);
      await tester.pumpWidget(
        _scene(controller: controller, fps: double.infinity),
      );
      expect(controller.time.value, Duration.zero);
      expect(SharedAnimationClock.instance.subscriberCount, 1);
      await _advance(tester);
      expect(controller.time.value, greaterThan(Duration.zero));
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );

  testWidgets('global listener pauses and resumes after one pump', (
    tester,
  ) async {
    await tester.pumpWidget(_scene());
    await _advance(tester);
    Xvg.fps.value = 0;
    await tester.pump();
    expect(_painter(tester).time, Duration.zero);
    expect(SharedAnimationClock.instance.subscriberCount, 0);
    await _advance(tester);
    expect(_painter(tester).time, Duration.zero);
    Xvg.fps.value = null;
    await tester.pump();
    expect(SharedAnimationClock.instance.subscriberCount, 1);
    await _advance(tester);
    expect(_painter(tester).time, greaterThan(Duration.zero));
    await tester.pumpWidget(const SizedBox());
  });

  for (final useGlobal in [false, true]) {
    testWidgets('initial freezing holds first frame; global=$useGlobal', (
      tester,
    ) async {
      if (useGlobal) Xvg.fps.value = 0;
      await tester.pumpWidget(_scene(fps: useGlobal ? null : 0));
      expect(_painter(tester).time, Duration.zero);
      expect(SharedAnimationClock.instance.subscriberCount, 0);
      await _advance(tester);
      expect(_painter(tester).time, Duration.zero);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('system reduced motion has no effect', (tester) async {
    await tester.pumpWidget(_scene(system: true));
    await _advance(tester);
    final before = _painter(tester).time;
    expect(before, greaterThan(Duration.zero));
    await tester.pumpWidget(_scene(system: false));
    await _advance(tester);
    expect(_painter(tester).time, greaterThan(before));
    await tester.pumpWidget(const SizedBox());
  });

  for (final global in [0.0, 10.0]) {
    testWidgets('instance infinity ignores global $global and live changes', (
      tester,
    ) async {
      Xvg.fps.value = global;
      await tester.pumpWidget(_scene(fps: double.infinity));
      await _advance(tester);
      final before = _painter(tester).time;
      expect(before, greaterThan(Duration.zero));
      Xvg.fps.value = global == 0 ? 10 : 0;
      await _advance(tester);
      expect(_painter(tester).time, greaterThan(before));
      await tester.pumpWidget(_scene(fps: 0));
      expect(_painter(tester).time, Duration.zero);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('instance zero overrides unlimited global', (tester) async {
    Xvg.fps.value = double.infinity;
    await tester.pumpWidget(_scene(fps: 0));
    await _advance(tester);
    expect(_painter(tester).time, Duration.zero);
    expect(SharedAnimationClock.instance.subscriberCount, 0);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('implicit autoplay false never starts after freezing', (
    tester,
  ) async {
    await tester.pumpWidget(_scene(autoplay: false));
    await tester.pumpWidget(_scene(autoplay: false, fps: 0));
    await tester.pumpWidget(_scene(autoplay: false, fps: double.infinity));
    await _advance(tester);
    expect(_painter(tester).time, Duration.zero);
    expect(SharedAnimationClock.instance.subscriberCount, 0);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('paused external controller retains its playback intent', (
    tester,
  ) async {
    final controller = XvgAnimationController(autoplay: false);
    await tester.pumpWidget(_scene(controller: controller));
    controller.seek(_step);
    await tester.pumpWidget(_scene(controller: controller, fps: 0));
    expect(controller.time.value, Duration.zero);
    await tester.pumpWidget(
      _scene(controller: controller, fps: double.infinity),
    );
    await _advance(tester);
    expect(controller.status, XvgPlaybackStatus.paused);
    expect(controller.time.value, Duration.zero);
    expect(SharedAnimationClock.instance.subscriberCount, 0);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets('freezing resets document time outside a selected range', (
    tester,
  ) async {
    final controller = XvgAnimationController();
    const rangeStart = Duration(milliseconds: 300);
    const rangeEnd = Duration(milliseconds: 900);
    controller.setRange(rangeStart, rangeEnd, mode: XvgRangeMode.loop);
    await tester.pumpWidget(_scene(controller: controller));
    await _advance(tester);
    expect(controller.time.value, greaterThan(rangeStart));
    Xvg.fps.value = 0;
    await tester.pump();
    expect(controller.time.value, Duration.zero);
    expect(_painter(tester).time, Duration.zero);
    expect(SharedAnimationClock.instance.subscriberCount, 0);
    Xvg.fps.value = null;
    await tester.pump();
    expect(controller.time.value, rangeStart);
    expect(SharedAnimationClock.instance.subscriberCount, 1);
    await _advance(tester);
    expect(controller.time.value, greaterThan(rangeStart));
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets('shared controller resets only when all widgets freeze', (
    tester,
  ) async {
    final controller = XvgAnimationController();

    /// Updates both attached preferences. / 更新两个挂载偏好。
    Widget scene(bool first, bool second) => _scene(
      controller: controller,
      shared: true,
      fps: first ? 0 : double.infinity,
      secondFps: second ? 0 : double.infinity,
    );

    await tester.pumpWidget(scene(false, false));
    await _advance(tester);
    final before = controller.time.value;
    await tester.pumpWidget(scene(true, false));
    expect(controller.time.value, before);
    expect(SharedAnimationClock.instance.subscriberCount, 1);
    await _advance(tester);
    expect(controller.time.value, greaterThan(before));
    await tester.pumpWidget(scene(true, true));
    expect(controller.time.value, Duration.zero);
    expect(SharedAnimationClock.instance.subscriberCount, 0);
    await _advance(tester);
    expect(controller.time.value, Duration.zero);
    await tester.pumpWidget(scene(true, false));
    expect(controller.time.value, Duration.zero);
    expect(SharedAnimationClock.instance.subscriberCount, 1);
    await _advance(tester);
    expect(controller.time.value, greaterThan(Duration.zero));
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets('removing the last non-frozen attachment resets shared time', (
    tester,
  ) async {
    final controller = XvgAnimationController();
    await tester.pumpWidget(
      _scene(
        controller: controller,
        shared: true,
        fps: 0,
        secondFps: double.infinity,
      ),
    );
    await _advance(tester);
    expect(controller.time.value, greaterThan(Duration.zero));
    await tester.pumpWidget(_scene(controller: controller, fps: 0));
    expect(controller.time.value, Duration.zero);
    expect(SharedAnimationClock.instance.subscriberCount, 0);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets('TickerMode pause differs from all widgets freezing', (
    tester,
  ) async {
    final controller = XvgAnimationController();
    await tester.pumpWidget(_scene(controller: controller));
    await _advance(tester);
    final before = controller.time.value;
    await tester.pumpWidget(_scene(controller: controller, ticker: false));
    expect(controller.time.value, before);
    Xvg.fps.value = 0;
    await tester.pump();
    expect(controller.time.value, Duration.zero);
    Xvg.fps.value = null;
    await tester.pump();
    expect(SharedAnimationClock.instance.subscriberCount, 0);
    await tester.pumpWidget(_scene(controller: controller));
    await _advance(tester);
    expect(controller.time.value, greaterThan(Duration.zero));
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets('hidden non-frozen sibling prevents shared first-frame reset', (
    tester,
  ) async {
    final controller = XvgAnimationController();
    await tester.pumpWidget(_scene(controller: controller));
    await _advance(tester);
    final before = controller.time.value;
    await tester.pumpWidget(
      _scene(
        controller: controller,
        ticker: false,
        fps: double.infinity,
        shared: true,
        secondFps: 0,
      ),
    );
    expect(controller.time.value, before);
    expect(SharedAnimationClock.instance.subscriberCount, 0);
    await _advance(tester);
    expect(controller.time.value, before);
    await tester.pumpWidget(
      _scene(
        controller: controller,
        fps: double.infinity,
        shared: true,
        secondFps: 0,
      ),
    );
    await _advance(tester);
    expect(controller.time.value, greaterThan(before));
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets('external animation ignores every fps input', (tester) async {
    final driver = AnimationController(vsync: tester, duration: _step);
    await tester.pumpWidget(_scene(animation: driver));
    driver.value = 0.5;
    await tester.pump();
    const midpoint = Duration(milliseconds: 500);
    const laterTime = Duration(milliseconds: 750);
    expect(_painter(tester).time, midpoint);
    Xvg.fps.value = 0;
    await tester.pumpWidget(_scene(animation: driver, fps: 0, system: true));
    expect(_painter(tester).time, midpoint);
    driver.value = 0.75;
    await tester.pump();
    expect(_painter(tester).time, laterTime);
    Xvg.fps.value = null;
    await tester.pumpWidget(_scene(animation: driver, fps: double.infinity));
    expect(_painter(tester).time, laterTime);
    expect(SharedAnimationClock.instance.subscriberCount, 0);
    await tester.pumpWidget(const SizedBox());
    driver.dispose();
  });

  testWidgets('dispose removes the global notifier listener', (tester) async {
    expect(Xvg.fps.hasListeners, isFalse);
    await tester.pumpWidget(_scene());
    expect(Xvg.fps.hasListeners, isTrue);
    await tester.pumpWidget(const SizedBox());
    expect(Xvg.fps.hasListeners, isFalse);
    Xvg.fps.value = 0;
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('freezing renders an opaque complete first frame', (
    tester,
  ) async {
    await tester.pumpWidget(_scene());
    await _advance(tester);
    Xvg.fps.value = 0;
    await tester.pump();
    final painter = _painter(tester);
    expect(painter.time, Duration.zero);
    final recorder = ui.PictureRecorder();
    const size = 24;
    painter.paint(Canvas(recorder), Size.square(size.toDouble()));
    final picture = recorder.endRecording();
    await tester.runAsync(() async {
      final image = await picture.toImage(size, size);
      final pixels = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      const channels = 4;
      const opaque = 255;
      for (var offset = 0; offset < pixels.lengthInBytes; offset += channels) {
        expect(pixels.getUint8(offset), opaque);
        expect(pixels.getUint8(offset + channels - 1), opaque);
      }
      image.dispose();
    });
    picture.dispose();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Xvg.string forwards live fps to the animated renderer', (
    tester,
  ) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Xvg.string(_source, fps: 0),
      ),
    );
    await tester.pump();
    expect(tester.widget<XvgAnimated>(find.byType(XvgAnimated)).fps, 0);
    expect(SharedAnimationClock.instance.subscriberCount, 0);
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Xvg.string(_source, fps: double.infinity),
      ),
    );
    expect(
      tester.widget<XvgAnimated>(find.byType(XvgAnimated)).fps,
      double.infinity,
    );
    expect(SharedAnimationClock.instance.subscriberCount, 1);
    await tester.pumpWidget(const SizedBox());
  });
}
