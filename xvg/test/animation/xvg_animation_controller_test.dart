import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xvg/src/animation/animated_svg_painter.dart';
import 'package:xvg/src/animation/shared_animation_clock.dart';
import 'package:xvg/src/animation/smil_animation.dart';
import 'package:xvg/src/animation/xvg_animation_controller.dart'
    as controller_debug;
import 'package:xvg/xvg.dart';

/// Time fixtures shared by playback cases. / 播放用例共用的时间常量。
const _frame = Duration(milliseconds: 16);

/// A short elapsed interval. / 短播放间隔。
const _hundredMs = Duration(milliseconds: 100);

/// A quarter-second traversal. / 四分之一秒穿越。
const _quarterSecond = Duration(milliseconds: 250);

/// A half-second traversal. / 半秒穿越。
const _halfSecond = Duration(milliseconds: 500);

/// A three-quarter-second traversal. / 四分之三秒穿越。
const _threeQuarterSecond = Duration(milliseconds: 750);

/// One second of playback. / 一秒播放时间。
const _second = Duration(seconds: 1);

/// The finite fixture's natural duration. / 有限样例的自然时长。
const _twoSeconds = Duration(seconds: 2);

/// A step past the finite document end. / 越过有限文档结束的大步长。
const _threeSeconds = Duration(seconds: 3);

/// A step across two loop periods. / 越过两个循环周期的步长。
const _fourSeconds = Duration(seconds: 4);

/// A finite two-second opacity animation. / 两秒有限透明度动画。
const _finite =
    '<svg width="24" height="24">'
    '<rect width="24" height="24">'
    '<animate attributeName="opacity" values="0;1" dur="2s" fill="freeze"/>'
    '</rect></svg>';

/// A loop with an independently known period. / 周期明确的无限动画。
const _loop =
    '<svg width="24" height="24">'
    '<rect width="24" height="24">'
    '<animate attributeName="opacity" values="0;1" dur="2s" '
    'repeatCount="indefinite"/></rect></svg>';

/// A loop whose period exceeds the model limit. / 周期超过模型上限的循环。
const _unknownPeriod =
    '<svg width="24" height="24">'
    '<rect width="24" height="24">'
    '<animate attributeName="opacity" values="0;1" dur="61s" '
    'repeatCount="indefinite"/></rect></svg>';

/// Identified begin/repeat/end events inside a longer document.
/// 较长文档内带标识的开始、重复和结束事件。
const _eventsSource =
    '<svg width="24" height="24">'
    '<rect width="24" height="24">'
    '<animate id="pulse" attributeName="opacity" values="0;1" '
    'begin="250ms" dur="250ms" repeatCount="2"/>'
    '<animate attributeName="x" values="0;1" dur="2s"/>'
    '</rect></svg>';

/// Counts actual painting samples. / 统计实际绘制采样次数。
class _CountingAnimation extends SmilAnimation {
  /// Creates a finite opacity sampler. / 创建有限透明度采样器。
  _CountingAnimation()
    : super(
        attributeName: 'opacity',
        values: [0, 1],
        duration: _twoSeconds,
        begin: Duration.zero,
        fillFreeze: true,
        repeatCount: const SmilRepeatCount.finite(1),
      );

  /// Number of calls to sample. / sample 调用次数。
  int samples = 0;

  /// Records sampling before delegating. / 记录采样并调用原实现。
  @override
  double? sample(Duration t) {
    samples++;
    return super.sample(t);
  }
}

/// Hosts one renderer with a stable identity. / 挂载身份稳定的单个渲染器。
Widget _scene(
  XvgAnimationController controller, {
  String source = _finite,
  XvgAnimationQuality? quality,
}) => Directionality(
  textDirection: TextDirection.ltr,
  child: XvgAnimated.string(source, controller: controller, quality: quality),
);

/// Returns the mounted painter without rebuilding it. / 读取挂载中的绘制器。
AnimatedSvgPainter _painter(WidgetTester tester, [int index = 0]) =>
    tester.widget<CustomPaint>(find.byType(CustomPaint).at(index)).painter!
        as AnimatedSvgPainter;

/// Anchors a newly started subscription without advancing document time.
/// 锚定新播放订阅，且不推进文档时间。
Future<void> _play(
  WidgetTester tester,
  XvgAnimationController controller,
) async {
  controller.play();
  await tester.pump();
}

/// Unmounts before disposing an externally owned controller.
/// 先卸载控件，再释放外部控制器。
Future<void> _close(
  WidgetTester tester,
  XvgAnimationController controller,
) async {
  await tester.pumpWidget(const SizedBox.shrink());
  controller.dispose();
  expect(SharedAnimationClock.instance.subscriberCount, 0);
  expect(tester.takeException(), isNull);
}

/// Controller playback and event contracts. / 控制器播放及事件契约。
void main() {
  setUp(XvgDocumentCache.instance.clear);
  tearDown(() {
    XvgDocumentCache.instance.clear();
    XvgAnimationQuality.defaultQuality = XvgAnimationQuality.balanced;
  });

  testWidgets('play pause and paused seek repaint without rebuilding', (
    tester,
  ) async {
    final sampling = _CountingAnimation();
    XvgDocumentCache.instance
            .getOrParse(_finite)
            .document
            .root
            .children
            .single
            .animations[0] =
        sampling;
    final controller = XvgAnimationController(autoplay: false);
    await tester.pumpWidget(_scene(controller));
    expect(controller.status, XvgPlaybackStatus.paused);
    expect(SharedAnimationClock.instance.subscriberCount, 0);
    final painter = _painter(tester);
    final initialSamples = sampling.samples;
    controller.seek(_halfSecond);
    expect(controller.time.value, _halfSecond);
    await tester.pump();
    expect(sampling.samples, greaterThan(initialSamples));
    expect(_painter(tester), same(painter));
    expect(painter.time, _halfSecond);
    await _play(tester, controller);
    await tester.pump(_quarterSecond);
    expect(controller.time.value, _threeQuarterSecond);
    controller.pause();
    await tester.pump(_second);
    expect(controller.time.value, _threeQuarterSecond);
    expect(controller.status, XvgPlaybackStatus.paused);
    await _close(tester, controller);
  });

  testWidgets('rate changes preserve time and zero pauses', (tester) async {
    final controller = XvgAnimationController();
    await tester.pumpWidget(_scene(controller));
    await tester.pump();
    await tester.pump(_quarterSecond);
    expect(controller.time.value, _quarterSecond);
    controller.playbackRate = 2;
    expect(controller.time.value, _quarterSecond);
    await tester.pump(_quarterSecond);
    expect(controller.time.value, _threeQuarterSecond);
    controller.playbackRate = 0;
    expect(controller.status, XvgPlaybackStatus.paused);
    await tester.pump(_second);
    expect(controller.time.value, _threeQuarterSecond);
    expect(SharedAnimationClock.instance.subscriberCount, 0);
    await _close(tester, controller);
  });

  testWidgets('tiny playback rates accumulate fractional microseconds', (
    tester,
  ) async {
    final controller = XvgAnimationController(playbackRate: 0.00001);
    await tester.pumpWidget(_scene(controller));
    await tester.pump();
    for (var index = 0; index < 10; index++) {
      await tester.pump(_frame);
    }
    expect(controller.time.value, const Duration(microseconds: 2));
    await _close(tester, controller);
  });

  testWidgets('negative playback completes at zero and reverse resumes', (
    tester,
  ) async {
    final controller = XvgAnimationController(
      autoplay: false,
      playbackRate: -1,
    );
    final events = <XvgAnimationEvent>[];
    controller.addEventListener(events.add);
    await tester.pumpWidget(_scene(controller));
    controller.seek(_halfSecond);
    await _play(tester, controller);
    await tester.pump(_second);
    expect(controller.time.value, Duration.zero);
    expect(controller.status, XvgPlaybackStatus.completed);
    expect(events.whereType<XvgAnimationCompleted>(), hasLength(1));
    expect(SharedAnimationClock.instance.subscriberCount, 0);
    controller.reverse();
    expect(controller.playbackRate, 1);
    await tester.pump();
    await tester.pump(_quarterSecond);
    expect(controller.time.value, _quarterSecond);
    await _close(tester, controller);
  });

  testWidgets('completion is reversible through replay and seek', (
    tester,
  ) async {
    final controller = XvgAnimationController();
    await tester.pumpWidget(_scene(controller));
    await tester.pump();
    await tester.pump(_threeSeconds);
    expect(controller.time.value, _twoSeconds);
    expect(controller.status, XvgPlaybackStatus.completed);
    await _play(tester, controller);
    expect(controller.time.value, Duration.zero);
    await tester.pump(_quarterSecond);
    expect(controller.time.value, _quarterSecond);
    await tester.pump(_threeSeconds);
    controller.seek(_halfSecond);
    expect(controller.status, XvgPlaybackStatus.paused);
    await _play(tester, controller);
    await tester.pump(_quarterSecond);
    expect(controller.time.value, _threeQuarterSecond);
    controller.stop();
    expect(controller.time.value, Duration.zero);
    expect(controller.status, XvgPlaybackStatus.paused);
    await _close(tester, controller);
  });

  testWidgets('seek clamps at finite bounds without emitting crossed cues', (
    tester,
  ) async {
    final controller = XvgAnimationController(autoplay: false);
    var cues = 0;
    controller.addCue(_second, () => cues++);
    await tester.pumpWidget(_scene(controller));
    controller.seek(_fourSeconds);
    expect(controller.time.value, _twoSeconds);
    controller.seek(-_second);
    expect(controller.time.value, Duration.zero);
    expect(cues, 0);
    await _close(tester, controller);
  });

  testWidgets('once range completes and negative replay starts at its end', (
    tester,
  ) async {
    final controller = XvgAnimationController(autoplay: false);
    await tester.pumpWidget(_scene(controller));
    controller.setRange(_halfSecond, _second);
    expect(controller.time.value, _halfSecond);
    await _play(tester, controller);
    await tester.pump(_second);
    expect(controller.time.value, _second);
    expect(controller.status, XvgPlaybackStatus.completed);
    controller.playbackRate = -1;
    controller.seek(_halfSecond);
    await _play(tester, controller);
    expect(controller.time.value, _second);
    await tester.pump(_quarterSecond);
    expect(controller.time.value, _threeQuarterSecond);
    controller.clearRange();
    controller.pause();
    controller.seek(_fourSeconds);
    expect(controller.time.value, _twoSeconds);
    await _close(tester, controller);
  });

  testWidgets('range loop splits crossings and keeps cues in both segments', (
    tester,
  ) async {
    final controller = XvgAnimationController(autoplay: false);
    final sequence = <String>[];
    controller.addEventListener((event) {
      if (event is XvgAnimationRangeLooped) {
        sequence.add('loop:${event.iteration}');
      }
    });
    controller.addCue(_quarterSecond, () => sequence.add('early'));
    controller.addCue(_threeQuarterSecond, () => sequence.add('late'));
    await tester.pumpWidget(_scene(controller));
    controller.setRange(Duration.zero, _second, mode: XvgRangeMode.loop);
    controller.seek(_halfSecond);
    await _play(tester, controller);
    await tester.pump(_second);
    expect(controller.time.value, _halfSecond);
    expect(sequence, ['late', 'loop:1', 'early']);
    sequence.clear();
    await tester.pump(_twoSeconds);
    expect(controller.time.value, _halfSecond);
    expect(sequence, ['late', 'loop:2', 'early', 'late', 'loop:3', 'early']);
    await _close(tester, controller);
  });

  testWidgets('reverse range loop crosses cues in reverse order', (
    tester,
  ) async {
    final controller = XvgAnimationController(
      autoplay: false,
      playbackRate: -1,
    );
    final sequence = <String>[];
    controller.addCue(_quarterSecond, () => sequence.add('early'));
    controller.addCue(_threeQuarterSecond, () => sequence.add('late'));
    await tester.pumpWidget(_scene(controller));
    controller.setRange(Duration.zero, _second, mode: XvgRangeMode.loop);
    controller.seek(_halfSecond);
    await _play(tester, controller);
    await tester.pump(_second);
    expect(controller.time.value, _halfSecond);
    expect(sequence, ['early', 'late']);
    await _close(tester, controller);
  });

  testWidgets('ping pong reflects at each endpoint including a large tick', (
    tester,
  ) async {
    final controller = XvgAnimationController(autoplay: false);
    await tester.pumpWidget(_scene(controller));
    controller.setRange(Duration.zero, _second, mode: XvgRangeMode.pingPong);
    await _play(tester, controller);
    await tester.pump(_threeQuarterSecond);
    expect(controller.time.value, _threeQuarterSecond);
    await tester.pump(_halfSecond);
    expect(controller.time.value, _threeQuarterSecond);
    expect(controller.playbackRate, 1);
    await tester.pump(_threeSeconds);
    expect(controller.time.value, _quarterSecond);
    expect(controller.playbackRate, 1);
    expect(controller.status, XvgPlaybackStatus.playing);
    await _close(tester, controller);
  });

  testWidgets(
    'ping pong keeps rate across reflections and reverses actual travel',
    (tester) async {
      final controller = XvgAnimationController(autoplay: false);
      await tester.pumpWidget(_scene(controller));
      controller.setRange(Duration.zero, _second, mode: XvgRangeMode.pingPong);
      await _play(tester, controller);
      for (var round = 0; round < 3; round++) {
        await tester.pump(_threeQuarterSecond);
        expect(controller.time.value, _threeQuarterSecond);
        await tester.pump(_halfSecond);
        expect(controller.time.value, _threeQuarterSecond);
        expect(controller.playbackRate, 1);
        controller.pause();
        await _play(tester, controller);
        await tester.pump(_quarterSecond);
        expect(controller.time.value, _halfSecond);
        await tester.pump(_halfSecond);
        expect(controller.time.value, Duration.zero);
        expect(controller.playbackRate, 1);
      }
      await tester.pump(_second + _quarterSecond);
      expect(controller.time.value, _threeQuarterSecond);
      controller.reverse();
      expect(controller.playbackRate, -1);
      await tester.pump(_hundredMs);
      expect(controller.time.value, _threeQuarterSecond + _hundredMs);
      controller.setRange(Duration.zero, _second, mode: XvgRangeMode.pingPong);
      await tester.pump(_hundredMs);
      expect(controller.time.value, _threeQuarterSecond);
      controller.clearRange();
      await tester.pump(_quarterSecond);
      expect(controller.time.value, _halfSecond);
      expect(controller.playbackRate, -1);
      await _close(tester, controller);
    },
  );

  testWidgets('fitDuration uses natural duration and rejects unknown cycles', (
    tester,
  ) async {
    final controller = XvgAnimationController(autoplay: false);
    await tester.pumpWidget(_scene(controller));
    controller.fitDuration(_halfSecond);
    expect(controller.playbackRate, 4);
    await tester.pumpWidget(_scene(controller, source: _unknownPeriod));
    expect(controller.info!.naturalDuration, isNull);
    expect(() => controller.fitDuration(_second), throwsStateError);
    await _close(tester, controller);
  });

  testWidgets('divisor two does not lose crossed cues and removeCue works', (
    tester,
  ) async {
    const quality = XvgAnimationQuality(
      frameSkipThreshold: 0,
      maxFrameDivisor: 2,
      offscreenLayerFrameDivisor: 2,
    );
    final controller = XvgAnimationController(autoplay: false);
    final crossed = <int>[];

    /// Marks an incorrectly retained cue. / 标记被错误保留的 cue。
    void removed() => crossed.add(-1);
    for (var index = 1; index <= 8; index++) {
      final cue = index;
      controller.addCue(
        Duration(milliseconds: index * 10),
        () => crossed.add(cue),
      );
    }
    controller.addCue(_frame, removed);
    controller.removeCue(_frame, removed);
    await tester.pumpWidget(_scene(controller, quality: quality));
    await _play(tester, controller);
    for (var index = 0; index < 8; index++) {
      await tester.pump(_frame);
    }
    expect(crossed, orderedEquals(List.generate(8, (index) => index + 1)));
    await _close(tester, controller);
  });

  testWidgets('element begin repeat end preserve forward and reverse order', (
    tester,
  ) async {
    final controller = XvgAnimationController(autoplay: false);
    final events = <XvgAnimationEvent>[];
    controller.addEventListener(events.add);
    await tester.pumpWidget(_scene(controller, source: _eventsSource));
    await _play(tester, controller);
    await tester.pump(_second);
    expect(_elementLabels(events), [
      'begin:pulse',
      'repeat:pulse:1',
      'end:pulse',
    ]);
    events.clear();
    controller.reverse();
    await tester.pump(_second);
    expect(_elementLabels(events), [
      'end:pulse',
      'repeat:pulse:1',
      'begin:pulse',
    ]);
    await _close(tester, controller);
  });

  testWidgets('reverse crossing includes destination and excludes origin', (
    tester,
  ) async {
    final controller = XvgAnimationController(
      autoplay: false,
      playbackRate: -1,
    );
    final events = <XvgAnimationEvent>[];
    controller.addEventListener(events.add);
    await tester.pumpWidget(_scene(controller, source: _eventsSource));
    controller.seek(_threeQuarterSecond);
    await _play(tester, controller);
    await tester.pump(_halfSecond);
    expect(_elementLabels(events), ['repeat:pulse:1', 'begin:pulse']);
    await _close(tester, controller);
  });

  testWidgets('no listeners means no timeline event queries', (tester) async {
    final controller = XvgAnimationController();
    await tester.pumpWidget(_scene(controller, source: _eventsSource));
    final initialQueries = controller_debug.debugTimelineEventQueryCount;
    await tester.pump();
    await tester.pump(_second);
    expect(controller_debug.debugTimelineEventQueryCount, initialQueries);

    /// Enables timeline dispatch without changing state. / 开启时间线派发，不改状态。
    void listener(XvgAnimationEvent _) {}
    controller.addEventListener(listener);
    controller.seek(Duration.zero);
    await tester.pump();
    await tester.pump(_second);
    expect(
      controller_debug.debugTimelineEventQueryCount,
      greaterThan(initialQueries),
    );
    controller.removeEventListener(listener);
    final afterRemoval = controller_debug.debugTimelineEventQueryCount;
    controller.seek(Duration.zero);
    await tester.pump();
    await tester.pump(_second);
    expect(controller_debug.debugTimelineEventQueryCount, afterRemoval);
    await _close(tester, controller);
  });

  testWidgets('a late subscriber anchors the first tick at exactly zero', (
    tester,
  ) async {
    final running = XvgAnimationController();
    final late = XvgAnimationController();
    await tester.pumpWidget(_scene(running, source: _loop));
    await tester.pump();
    await tester.pump(_second);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Column(
          children: [
            XvgAnimated.string(_loop, controller: running),
            XvgAnimated.string(_loop, controller: late),
          ],
        ),
      ),
    );
    expect(late.time.value, Duration.zero);
    await tester.pump(_hundredMs);
    expect(late.time.value, Duration.zero);
    await tester.pump(_hundredMs);
    expect(late.time.value, _hundredMs);
    await tester.pumpWidget(const SizedBox.shrink());
    running.dispose();
    late.dispose();
  });

  testWidgets('pre-first-tick seek rate and play retain a pending anchor', (
    tester,
  ) async {
    final running = XvgAnimationController();
    final late = XvgAnimationController();
    final events = <XvgAnimationEvent>[];
    late.addEventListener(events.add);
    await tester.pumpWidget(_scene(running, source: _loop));
    await tester.pump();
    await tester.pump(_second);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Column(
          children: [
            XvgAnimated.string(_loop, controller: running),
            XvgAnimated.string(_loop, controller: late),
          ],
        ),
      ),
    );
    late.seek(_halfSecond);
    late.playbackRate = 2;
    late.play();
    await tester.pump(_hundredMs);
    expect(late.time.value, _halfSecond);
    expect(events.whereType<XvgAnimationStarted>(), hasLength(1));
    await tester.pump(_hundredMs);
    expect(late.time.value, _halfSecond + _hundredMs * 2);
    await tester.pumpWidget(const SizedBox.shrink());
    running.dispose();
    late.dispose();
  });

  testWidgets('one controller subscribes once until every TickerMode is off', (
    tester,
  ) async {
    final controller = XvgAnimationController();

    /// Applies independent visibility to shared widgets. / 分别控制共享控件可见性。
    Widget scene(bool first, bool second) => Directionality(
      textDirection: TextDirection.ltr,
      child: Column(
        children: [
          TickerMode(
            enabled: first,
            child: XvgAnimated.string(_loop, controller: controller),
          ),
          TickerMode(
            enabled: second,
            child: XvgAnimated.string(_loop, controller: controller),
          ),
        ],
      ),
    );
    await tester.pumpWidget(scene(true, true));
    expect(SharedAnimationClock.instance.subscriberCount, 1);
    await tester.pump();
    await tester.pump(_hundredMs);
    expect(_painter(tester, 0).time, _painter(tester, 1).time);
    await tester.pumpWidget(scene(false, true));
    expect(SharedAnimationClock.instance.subscriberCount, 1);
    await tester.pumpWidget(scene(false, false));
    expect(SharedAnimationClock.instance.subscriberCount, 0);
    final pausedTime = controller.time.value;
    await tester.pump(_second);
    expect(controller.time.value, pausedTime);
    await tester.pumpWidget(scene(true, false));
    expect(SharedAnimationClock.instance.subscriberCount, 1);
    await tester.pump();
    await tester.pump(_hundredMs);
    expect(controller.time.value, pausedTime + _hundredMs);
    await _close(tester, controller);
  });

  testWidgets('shared controller honors the least degraded attached widget', (
    tester,
  ) async {
    final controller = XvgAnimationController();
    const degraded = XvgAnimationQuality(
      frameSkipThreshold: 0,
      maxFrameDivisor: 4,
    );
    tester.view.display.refreshRate = 60;
    addTearDown(tester.view.display.resetRefreshRate);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Column(
          children: [
            XvgAnimated.string(
              _loop,
              controller: controller,
              quality: degraded,
              maxFps: 15,
            ),
            XvgAnimated.string(
              _loop,
              controller: controller,
              quality: XvgAnimationQuality.exact,
            ),
          ],
        ),
      ),
    );
    await tester.pump();
    final positions = <Duration>[];
    for (var index = 0; index < 8; index++) {
      await tester.pump(_frame);
      positions.add(controller.time.value);
    }
    expect(positions.toSet(), hasLength(8));
    expect(SharedAnimationClock.instance.subscriberCount, 1);
    await _close(tester, controller);
  });

  testWidgets('pure indefinite two-second loop emits all loop iterations', (
    tester,
  ) async {
    final controller = XvgAnimationController();
    final iterations = <int>[];
    controller.addEventListener((event) {
      if (event is XvgAnimationLooped) iterations.add(event.iteration);
    });
    await tester.pumpWidget(_scene(controller, source: _loop));
    await tester.pump();
    await tester.pump(_fourSeconds + _halfSecond);
    expect(controller.info!.loopPeriod, _twoSeconds);
    expect(iterations, [1, 2]);
    await _close(tester, controller);
  });

  testWidgets('unbounded reverse replay does not jump to the safety ceiling', (
    tester,
  ) async {
    final controller = XvgAnimationController(
      autoplay: false,
      playbackRate: -1,
    );
    await tester.pumpWidget(_scene(controller, source: _loop));
    controller.seek(_halfSecond);
    await _play(tester, controller);
    await tester.pump(_second);
    expect(controller.status, XvgPlaybackStatus.completed);
    await _play(tester, controller);
    expect(controller.time.value, Duration.zero);
    await tester.pump(_frame);
    expect(controller.status, XvgPlaybackStatus.completed);
    expect(controller.time.value, Duration.zero);
    await _close(tester, controller);
  });

  testWidgets('external source replacement preserves current time', (
    tester,
  ) async {
    final controller = XvgAnimationController(autoplay: false);
    await tester.pumpWidget(_scene(controller));
    controller.seek(_second);
    await tester.pumpWidget(_scene(controller, source: _loop));
    expect(controller.time.value, _second);
    expect(controller.info!.loops, isTrue);
    await _close(tester, controller);
  });

  testWidgets(
    'cue seek cancels the old crossing and preserves the sought time',
    (tester) async {
      final controller = XvgAnimationController(autoplay: false);
      var staleCues = 0;
      controller.addCue(_quarterSecond, () => controller.seek(_hundredMs));
      controller.addCue(_halfSecond, () => staleCues++);
      await tester.pumpWidget(_scene(controller));
      await _play(tester, controller);
      await tester.pump(_second);
      expect(controller.time.value, _hundredMs);
      expect(staleCues, 0);
      await _close(tester, controller);
    },
  );

  testWidgets('cue pause cancels the remaining old crossing callbacks', (
    tester,
  ) async {
    final controller = XvgAnimationController(autoplay: false);
    var staleCues = 0;
    controller.addCue(_quarterSecond, controller.pause);
    controller.addCue(_halfSecond, () => staleCues++);
    await tester.pumpWidget(_scene(controller));
    await _play(tester, controller);
    await tester.pump(_second);
    expect(controller.status, XvgPlaybackStatus.paused);
    expect(staleCues, 0);
    final pausedTime = controller.time.value;
    await tester.pump(_second);
    expect(controller.time.value, pausedTime);
    await _close(tester, controller);
  });

  testWidgets(
    'attaching the same document after completion retains completion',
    (tester) async {
      final controller = XvgAnimationController();
      final document = XvgDocumentCache.instance.getOrParse(_finite).document;
      controller.attach(
        Object(),
        document: document,
        visible: true,
        quality: () => XvgAnimationQuality.exact,
        fpsDivisor: () => 1,
      );
      await tester.pump();
      await tester.pump(_threeSeconds);
      expect(controller.status, XvgPlaybackStatus.completed);
      controller.attach(
        Object(),
        document: document,
        visible: true,
        quality: () => XvgAnimationQuality.exact,
        fpsDivisor: () => 1,
      );
      expect(controller.status, XvgPlaybackStatus.completed);
      expect(controller.time.value, _twoSeconds);
      expect(SharedAnimationClock.instance.subscriberCount, 0);
      controller.dispose();
    },
  );

  testWidgets(
    'a recovered secondary source clears error with primary unchanged',
    (tester) async {
      final controller = XvgAnimationController();
      final primary = XvgDocumentCache.instance.getOrParse(_finite).document;
      final secondary = Object();
      controller.attach(
        Object(),
        document: primary,
        visible: true,
        quality: () => XvgAnimationQuality.exact,
        fpsDivisor: () => 1,
      );
      controller.documentError(
        secondary,
        StateError('bad source'),
        StackTrace.current,
      );
      expect(controller.status, XvgPlaybackStatus.error);
      expect(controller.info, same(primary.info));
      controller.attach(
        secondary,
        document: XvgDocumentCache.instance.getOrParse(_loop).document,
        visible: true,
        quality: () => XvgAnimationQuality.exact,
        fpsDivisor: () => 1,
      );
      expect(controller.info, same(primary.info));
      expect(controller.status, XvgPlaybackStatus.playing);
      expect(SharedAnimationClock.instance.subscriberCount, 1);
      controller.dispose();
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );

  test('loaded listener can dispose during initial attachment', () {
    final controller = XvgAnimationController();
    controller.addEventListener((event) {
      if (event is XvgAnimationLoaded) controller.dispose();
    });
    expect(
      () => controller.attach(
        Object(),
        document: XvgDocumentCache.instance.getOrParse(_finite).document,
        visible: true,
        quality: () => XvgAnimationQuality.exact,
        fpsDivisor: () => 1,
      ),
      returnsNormally,
    );
    expect(SharedAnimationClock.instance.subscriberCount, 0);
  });

  test('all public operations assert after dispose', () {
    final controller = XvgAnimationController();

    /// A callback used to exercise registration contracts. / 用于验证注册契约的回调。
    void cue() {}

    /// An event callback used to exercise registration. / 用于验证注册的事件回调。
    void listener(XvgAnimationEvent _) {}
    controller.dispose();
    final operations = <VoidCallback>[
      controller.play,
      controller.pause,
      controller.stop,
      () => controller.seek(_second),
      () => controller.playbackRate = 2,
      controller.reverse,
      () => controller.setRange(Duration.zero, _second),
      controller.clearRange,
      () => controller.fitDuration(_second),
      () => controller.addCue(_second, cue),
      () => controller.removeCue(_second, cue),
      () => controller.addEventListener(listener),
      () => controller.removeEventListener(listener),
      () => controller.addListener(cue),
      () => controller.removeListener(cue),
      controller.dispose,
    ];
    for (final operation in operations) {
      expect(operation, throwsAssertionError);
    }
    expect(() => controller.time, throwsAssertionError);
    expect(() => controller.status, throwsAssertionError);
    expect(() => controller.info, throwsAssertionError);
    expect(() => controller.playbackRate, throwsAssertionError);
  });

  testWidgets(
    'cue disposal cancels remaining callbacks and releases the ticker',
    (tester) async {
      final controller = XvgAnimationController();
      var staleCues = 0;
      controller.addCue(_quarterSecond, controller.dispose);
      controller.addCue(_halfSecond, () => staleCues++);
      controller.attach(
        Object(),
        document: XvgDocumentCache.instance.getOrParse(_finite).document,
        visible: true,
        quality: () => XvgAnimationQuality.exact,
        fpsDivisor: () => 1,
      );
      await tester.pump();
      await tester.pump(_second);
      expect(staleCues, 0);
      expect(SharedAnimationClock.instance.subscriberCount, 0);
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.takeException(), isNull);
    },
  );
}

/// Converts element events to stable readable labels. / 将元素事件转为稳定标签。
List<String> _elementLabels(List<XvgAnimationEvent> events) => [
  for (final event in events)
    if (event is XvgAnimationElementBegin)
      'begin:${event.id}'
    else if (event is XvgAnimationElementEnd)
      'end:${event.id}'
    else if (event is XvgAnimationElementRepeat)
      'repeat:${event.id}:${event.iteration}',
];
