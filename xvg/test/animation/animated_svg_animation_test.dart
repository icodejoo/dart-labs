import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xvg/src/animation/animated_svg_painter.dart';
import 'package:xvg/src/animation/animated_svg_widget.dart'
    show debugResolveAnimatedImages;
import 'package:xvg/src/animation/shared_animation_clock.dart';
import 'package:xvg/src/animation/xvg_animation_controller.dart' as debug;
import 'package:xvg/xvg.dart';

/// Common document duration. / 共用文档时长。
const _span = Duration(seconds: 2);

/// One traversal of the element fixture. / 元素样例的一次穿越。
const _second = Duration(seconds: 1);

/// A sampling interval. / 采样间隔。
const _step = Duration(milliseconds: 100);

/// Midpoint of the default span. / 默认映射时长中点。
const _half = 0.5;

/// Natural frame size. / 自然帧尺寸。
const _size = Size(24, 24);

/// Identified events within a finite two-second document.
/// 两秒有限文档内的有标识事件。
const _source =
    '<svg width="24" height="24"><rect width="24" height="24" fill="red">'
    '<animate id="pulse" attributeName="opacity" values="0;1" '
    'begin="250ms" dur="250ms" repeatCount="2"/>'
    '<animate attributeName="x" values="0;12" dur="2s" fill="freeze"/>'
    '</rect></svg>';

/// Infinite document with no model-supported period. / 模型无法确定周期的无限文档。
const _unknown =
    '<svg width="24" height="24"><rect width="24" height="24">'
    '<animate attributeName="opacity" values="0;1" dur="61s" '
    'repeatCount="indefinite"/></rect></svg>';

/// Known periodic animation. / 周期已知的动画。
const _loop =
    '<svg width="24" height="24"><rect width="24" height="24">'
    '<animate attributeName="opacity" values="0;1" dur="1s" '
    'repeatCount="indefinite"/></rect></svg>';

/// Image decoding fixture. / 图片解码样例。
const _imageSource =
    '<svg width="24" height="24">'
    '<image width="24" height="24" href="data:image/png;base64,unused"/>'
    '<rect width="24" height="24">'
    '<animate attributeName="opacity" values="0;1" dur="2s"/>'
    '</rect></svg>';

/// Forward element order. / 正向元素顺序。
const _forward = ['begin:pulse', 'repeat:pulse', 'end:pulse'];

/// Handles explicit listener accounting without a ticker.
/// 无需 ticker 即可显式统计监听者。
class _TrackedAnimation extends Animation<double> {
  /// Creates a fixed initial value. / 创建固定初值。
  _TrackedAnimation([this.current = _half]);

  /// Mutable driver value. / 可变驱动值。
  double current;

  /// Registered value listeners. / 已注册值监听者。
  final listeners = <VoidCallback>{};

  /// Total listener additions. / 累计新增监听次数。
  int additions = 0;

  /// Total listener removals. / 累计移除监听次数。
  int removals = 0;

  /// Current value. / 当前值。
  @override
  double get value => current;

  /// Unused driver status. / 不参与适配的驱动状态。
  @override
  AnimationStatus get status => AnimationStatus.forward;

  /// Records a registration. / 记录注册。
  @override
  void addListener(VoidCallback listener) {
    additions++;
    listeners.add(listener);
  }

  /// Records a removal. / 记录移除。
  @override
  void removeListener(VoidCallback listener) {
    removals++;
    listeners.remove(listener);
  }

  /// No status observation is needed. / 无需观察状态。
  @override
  void addStatusListener(AnimationStatusListener listener) {}

  /// No status observation is needed. / 无需观察状态。
  @override
  void removeStatusListener(AnimationStatusListener listener) {}

  /// Publishes a new value. / 发布新值。
  void push(double value) {
    current = value;
    for (final listener in listeners.toList()) {
      listener();
    }
  }
}

/// Supplies a minimal widget host. / 提供最小控件宿主。
Widget _host(Widget child) =>
    Directionality(textDirection: TextDirection.ltr, child: child);

/// Reads a painter and its document clock. / 读取绘制器及其文档时钟。
AnimatedSvgPainter _painter(WidgetTester tester, [int index = 0]) =>
    tester.widget<CustomPaint>(find.byType(CustomPaint).at(index)).painter!
        as AnimatedSvgPainter;

/// Rasterizes the actual mounted painter to exact RGBA bytes.
/// 将实际挂载的绘制器光栅化为精确 RGBA 字节。
Future<Uint8List> _rgba(AnimatedSvgPainter painter) async {
  final recorder = ui.PictureRecorder();
  painter.paint(ui.Canvas(recorder), _size);
  final picture = recorder.endRecording();
  final image = await picture.toImage(
    _size.width.toInt(),
    _size.height.toInt(),
  );
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  final bytes = Uint8List.fromList(data!.buffer.asUint8List());
  image.dispose();
  picture.dispose();
  return bytes;
}

/// Keeps just element events in dispatch order. / 按派发顺序提取元素事件。
List<String> _labels(List<XvgAnimationEvent> events) => [
  for (final event in events)
    if (event is XvgAnimationElementBegin)
      'begin:${event.id}'
    else if (event is XvgAnimationElementRepeat)
      'repeat:${event.id}'
    else if (event is XvgAnimationElementEnd)
      'end:${event.id}',
];

/// Verifies external animation adaptation and widget event bridges.
/// 验证外部动画适配与控件事件桥接。
void main() {
  setUp(XvgDocumentCache.instance.clear);
  tearDown(() {
    debugResolveAnimatedImages = null;
    XvgDocumentCache.instance.clear();
    expect(SharedAnimationClock.instance.subscriberCount, 0);
  });

  testWidgets('forward matches implicit document time and every RGBA byte', (
    tester,
  ) async {
    final animation = AnimationController(vsync: tester, duration: _span);
    await tester.pumpWidget(
      _host(
        Column(
          children: [
            XvgAnimated.string(_source, animation: animation),
            const XvgAnimated.string(_source),
          ],
        ),
      ),
    );
    animation.forward();
    await tester.pump();
    expect(SharedAnimationClock.instance.subscriberCount, 1);
    for (var frame = 0; frame < 20; frame++) {
      await tester.pump(_step);
      final external = _painter(tester);
      final implicit = _painter(tester, 1);
      expect(external.clock.value, implicit.clock.value);
      final pixels = await tester.runAsync(
        () async => [await _rgba(external), await _rgba(implicit)],
      );
      expect(pixels!.first, orderedEquals(pixels.last), reason: 'frame $frame');
    }
    await tester.pumpWidget(const SizedBox.shrink());
    animation.dispose();
  });

  testWidgets('repeat reverse dispatches elements in both traversal orders', (
    tester,
  ) async {
    final animation = AnimationController(vsync: tester, duration: _second);
    final events = <XvgAnimationEvent>[];
    await tester.pumpWidget(
      _host(
        XvgAnimated.string(
          _source,
          animation: animation,
          animationSpan: _second,
          onEvent: events.add,
        ),
      ),
    );
    animation.repeat(reverse: true);
    await tester.pump();
    await tester.pump(_second);
    expect(_labels(events), _forward);
    events.clear();
    await tester.pump(_second);
    expect(_labels(events), _forward.reversed.toList());
    await tester.pumpWidget(const SizedBox.shrink());
    animation.dispose();
  });

  testWidgets(
    'mounting midway syncs like a seek; later changes still dispatch',
    (tester) async {
      final animation = _TrackedAnimation(1);
      final events = <XvgAnimationEvent>[];
      await tester.pumpWidget(
        _host(
          XvgAnimated.string(
            _source,
            animation: animation,
            onEvent: events.add,
          ),
        ),
      );
      expect(_painter(tester).clock.value, _span);
      expect(_labels(events), isEmpty);
      animation.push(0);
      expect(_labels(events), _forward.reversed.toList());
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'curved overshoot exceeds span and negative time clamps to zero',
    (tester) async {
      final parent = AnimationController(vsync: tester, duration: _span);
      final animation = CurvedAnimation(
        parent: parent,
        curve: Curves.elasticOut,
      );
      await tester.pumpWidget(
        _host(XvgAnimated.string(_source, animation: animation)),
      );
      parent.value = 0.2;
      expect(animation.value, greaterThan(1));
      expect(_painter(tester).clock.value, greaterThan(_span));
      animation.curve = Curves.elasticIn;
      parent.value = 0.8;
      expect(animation.value, lessThan(0));
      expect(_painter(tester).clock.value, Duration.zero);
      await tester.pumpWidget(const SizedBox.shrink());
      animation.dispose();
      parent.dispose();
    },
  );

  testWidgets('natural span, swaps and unmount maintain exactly one listener', (
    tester,
  ) async {
    final first = _TrackedAnimation();
    final second = _TrackedAnimation();

    /// Rebuilds with the same widget identity. / 使用相同控件身份重建。
    Future<void> show(
      Animation<double> animation, {
      Duration? span,
      String source = _source,
    }) => tester.pumpWidget(
      _host(
        XvgAnimated.string(source, animation: animation, animationSpan: span),
      ),
    );
    await show(first);
    expect(_painter(tester).clock.value, _second);
    expect(first.listeners, hasLength(1));
    await show(second);
    expect(first.listeners, isEmpty);
    expect(second.listeners, hasLength(1));
    first.push(1);
    expect(_painter(tester).clock.value, _second);
    await show(second, span: _second);
    expect(_painter(tester).clock.value, _second * _half);
    expect(second.additions, 1);
    await show(second, source: _source.replaceFirst('2s', '4s'));
    expect(_painter(tester).clock.value, _span);
    expect(second.listeners, hasLength(1));
    expect(second.additions, 2);
    expect(second.removals, 1);
    expect(SharedAnimationClock.instance.subscriberCount, 0);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(second.listeners, isEmpty);
    expect(second.removals, 2);
  });

  testWidgets(
    'unknown span uses error callbacks and recovers with explicit span',
    (tester) async {
      final errors = <Object>[];
      final events = <XvgAnimationEvent>[];
      final loaded = <XvgAnimationInfo>[];
      final animation = _TrackedAnimation();

      /// Builds an optionally corrected mapping. / 构建可修正的映射。
      Widget scene([Duration? span]) => _host(
        XvgAnimated.string(
          _unknown,
          animation: animation,
          animationSpan: span,
          onError: (error, stack) => errors.add(error),
          onEvent: events.add,
          onLoaded: loaded.add,
          errorBuilder: (_, _, _) => const Text('mapping failed'),
        ),
      );
      await tester.pumpWidget(scene());
      expect(errors.single, isStateError);
      expect(loaded, isEmpty);
      expect(events.whereType<XvgAnimationError>(), hasLength(1));
      expect(find.text('mapping failed'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(scene(_span));
      expect(_painter(tester).clock.value, _second);
      expect(errors, hasLength(1));
      expect(loaded, hasLength(1));
      await tester.pumpWidget(scene(_second));
      expect(loaded, hasLength(1));
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('reentrant external update cancels the old pending crossings', (
    tester,
  ) async {
    final animation = _TrackedAnimation(0);
    final events = <XvgAnimationEvent>[];
    var reversed = false;
    await tester.pumpWidget(
      _host(
        XvgAnimated.string(
          _source,
          animation: animation,
          onEvent: (event) {
            events.add(event);
            if (event is XvgAnimationElementBegin && !reversed) {
              reversed = true;
              animation.push(0);
            }
          },
        ),
      ),
    );
    animation.push(_half);
    expect(_painter(tester).clock.value, Duration.zero);
    expect(_labels(events), [_forward.first, ..._forward.reversed]);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('switching drive modes releases subscriptions and listeners', (
    tester,
  ) async {
    final animation = _TrackedAnimation();
    final controller = XvgAnimationController();
    await tester.pumpWidget(_host(const XvgAnimated.string(_source)));
    expect(SharedAnimationClock.instance.subscriberCount, 1);
    await tester.pumpWidget(
      _host(XvgAnimated.string(_source, animation: animation)),
    );
    expect(SharedAnimationClock.instance.subscriberCount, 0);
    expect(animation.listeners, hasLength(1));
    await tester.pumpWidget(
      _host(XvgAnimated.string(_source, controller: controller)),
    );
    expect(animation.listeners, isEmpty);
    expect(SharedAnimationClock.instance.subscriberCount, 1);
    await tester.pumpWidget(
      _host(XvgAnimated.string(_source, animation: animation)),
    );
    expect(SharedAnimationClock.instance.subscriberCount, 0);
    await tester.pumpWidget(_host(const XvgAnimated.string(_source)));
    expect(animation.listeners, isEmpty);
    expect(SharedAnimationClock.instance.subscriberCount, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('external updates bypass FPS and quality frame skipping', (
    tester,
  ) async {
    final animation = AnimationController(vsync: tester, duration: _span);
    await tester.pumpWidget(
      _host(
        XvgAnimated.string(
          _source,
          animation: animation,
          fps: 1,
          quality: const XvgAnimationQuality(
            frameSkipThreshold: 0,
            maxFrameDivisor: 4,
          ),
        ),
      ),
    );
    animation.forward();
    await tester.pump();
    for (var frame = 1; frame <= 8; frame++) {
      await tester.pump(_step);
      expect(_painter(tester).clock.value, _step * frame);
      expect(SharedAnimationClock.instance.subscriberCount, 0);
    }
    await tester.pumpWidget(const SizedBox.shrink());
    animation.dispose();
  });

  testWidgets('unhandled unknown span reports through FlutterError', (
    tester,
  ) async {
    final reported = <FlutterErrorDetails>[];
    final previous = FlutterError.onError;
    FlutterError.onError = reported.add;
    try {
      await tester.pumpWidget(
        _host(XvgAnimated.string(_unknown, animation: _TrackedAnimation())),
      );
    } finally {
      FlutterError.onError = previous;
    }
    expect(reported.single.exception, isStateError);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('controller and animation or nondefault automatic settings assert', () {
    final controller = XvgAnimationController();
    final animation = _TrackedAnimation();
    expect(
      () => XvgAnimated.string(
        _source,
        controller: controller,
        animation: animation,
      ),
      throwsAssertionError,
    );
    expect(
      () => XvgAnimated.string(_source, animation: animation, autoplay: false),
      throwsAssertionError,
    );
    expect(
      () => XvgAnimated.string(_source, animation: animation, playbackRate: 2),
      throwsAssertionError,
    );
    controller.dispose();
  });

  testWidgets('external status owns start and completion; loops still bridge', (
    tester,
  ) async {
    final animation = AnimationController(vsync: tester, duration: _second);
    final events = <XvgAnimationEvent>[];
    final loops = <int>[];
    final loaded = <XvgAnimationInfo>[];
    var starts = 0;
    var completions = 0;
    await tester.pumpWidget(
      _host(
        XvgAnimated.string(
          _loop,
          animation: animation,
          animationSpan: _span,
          onAnimationStart: () => starts++,
          onAnimationComplete: () => completions++,
          onAnimationLoop: loops.add,
          onLoaded: loaded.add,
          onEvent: events.add,
        ),
      ),
    );
    animation.forward();
    await tester.pump();
    await tester.pump(_second);
    expect(loops, [1, 2]);
    expect(loaded, hasLength(1));
    expect(starts, 0);
    expect(completions, 0);
    expect(events.whereType<XvgAnimationStarted>(), isEmpty);
    expect(events.whereType<XvgAnimationCompleted>(), isEmpty);
    expect(SharedAnimationClock.instance.subscriberCount, 0);
    await tester.pumpWidget(
      _host(
        XvgAnimated.string(
          _source,
          animation: animation,
          onAnimationStart: () => starts++,
          onAnimationComplete: () => completions++,
        ),
      ),
    );
    animation.reverse();
    await tester.pump();
    await tester.pump(_second);
    animation.forward();
    await tester.pump();
    await tester.pump(_second);
    expect(starts, 0);
    expect(completions, 0);
    await tester.pumpWidget(const SizedBox.shrink());
    animation.dispose();
  });

  testWidgets('external disposal preserves last frame and removal is safe', (
    tester,
  ) async {
    final parent = AnimationController(vsync: tester, duration: _span);
    final animation = CurvedAnimation(parent: parent, curve: Curves.linear);
    await tester.pumpWidget(
      _host(XvgAnimated.string(_source, animation: animation)),
    );
    parent.value = _half;
    expect(_painter(tester).clock.value, _second);
    animation.dispose();
    parent.dispose();
    await tester.pump(_second);
    expect(_painter(tester).clock.value, _second);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'image readiness samples current driver and survives driver swap',
    (tester) async {
      final ready = Completer<void>();
      debugResolveAnimatedImages = (_) => ready.future;
      final first = _TrackedAnimation();
      final second = _TrackedAnimation(0.75);
      final loaded = <XvgAnimationInfo>[];

      /// Keeps the pending source while switching its driver. / 保留加载中的源并切换驱动。
      Widget scene(Animation<double> animation) => _host(
        XvgAnimated.string(
          _imageSource,
          animation: animation,
          onLoaded: loaded.add,
        ),
      );
      await tester.pumpWidget(scene(first));
      await tester.pumpWidget(scene(second));
      expect(first.listeners, isEmpty);
      first.push(1);
      ready.complete();
      await tester.pump();
      await tester.pump();
      expect(_painter(tester).clock.value, _span * 0.75);
      expect(loaded, hasLength(1));
      await tester.pumpWidget(const SizedBox.shrink());
      expect(second.listeners, isEmpty);
    },
  );

  for (final mode in ['implicit', 'controller', 'animation']) {
    testWidgets('onEvent receives elements in $mode mode and can be removed', (
      tester,
    ) async {
      final controller = XvgAnimationController();
      final animation = _TrackedAnimation(0);
      final events = <XvgAnimationEvent>[];

      /// Changes only callback presence. / 只改变回调是否存在。
      Widget scene(bool listen) => _host(
        XvgAnimated.string(
          _source,
          controller: mode == 'controller' ? controller : null,
          animation: mode == 'animation' ? animation : null,
          onEvent: listen ? events.add : null,
        ),
      );
      await tester.pumpWidget(scene(true));
      await tester.pump();
      animation.push(_half);
      await tester.pump(_second);
      expect(_labels(events), _forward);
      await tester.pumpWidget(scene(false));
      final queries = debug.debugTimelineEventQueryCount;
      animation.push(1);
      await tester.pump(_step);
      expect(debug.debugTimelineEventQueryCount, queries);
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    });

    testWidgets('no callbacks means no timeline event queries in $mode mode', (
      tester,
    ) async {
      final controller = XvgAnimationController();
      final animation = _TrackedAnimation(0);
      final queries = debug.debugTimelineEventQueryCount;
      await tester.pumpWidget(
        _host(
          XvgAnimated.string(
            _source,
            controller: mode == 'controller' ? controller : null,
            animation: mode == 'animation' ? animation : null,
          ),
        ),
      );
      await tester.pump();
      animation.push(_half);
      await tester.pump(_second);
      expect(debug.debugTimelineEventQueryCount, queries);
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    });
  }
}
