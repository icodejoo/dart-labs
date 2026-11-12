// Regression tests for XvgAnimated's three lifecycle-control additions:
// `onAnimationStart`/`onAnimationComplete`/`onAnimationLoop`, `fps`, and
// `playbackRate`. Each hooks into an existing, already-computed piece of
// state (SvgDocument.totalDuration/hasIndefiniteLoop, the shared clock's
// frame-divisor gate) rather than introducing new timing machinery, so these
// tests exist to lock down the wiring, not to re-verify SMIL timing itself.
//
// XvgAnimated 三项生命周期控制新增的回归测试：
// `onAnimationStart`/`onAnimationComplete`/`onAnimationLoop`、`fps`、
// `playbackRate`。每一项都挂在已有的、已经算好的状态上（
// SvgDocument.totalDuration/hasIndefiniteLoop、共享时钟的跳帧除数门控），而非
// 引入新的计时机制，所以这些测试是为了锁定接线是否正确，不是重新验证 SMIL
// 计时本身。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xvg/src/animation/animated_svg_painter.dart';
import 'package:xvg/xvg.dart';

// A one-second indefinite spin has a loop period even without finite tracks.
// 一秒无限旋转即使没有有限时间线，也有明确循环周期。
const _spinner =
    '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" '
    'viewBox="0 0 24 24">'
    '<circle cx="12" cy="12" r="9" fill="none" stroke="#000" '
    'stroke-width="2" stroke-dasharray="40 20">'
    '<animateTransform attributeName="transform" type="rotate" '
    'values="0 12 12;360 12 12" dur="1s" repeatCount="indefinite"/>'
    '</circle></svg>';

// A finite flash settles at 100ms; steady-state loops finish every second after it.
// 有限闪烁在100ms稳定；之后每秒完成一个稳态循环。
const _indefiniteWithFinitePeriod =
    '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" '
    'viewBox="0 0 24 24">'
    '<circle cx="12" cy="12" r="9" fill="none" stroke="#000" '
    'stroke-width="2" stroke-dasharray="40 20">'
    '<animateTransform attributeName="transform" type="rotate" '
    'values="0 12 12;360 12 12" dur="1s" repeatCount="indefinite"/>'
    '</circle>'
    '<rect x="0" y="0" width="1" height="1" fill="#000" fill-opacity="0">'
    '<animate attributeName="fill-opacity" values="0;1" dur="100ms" '
    'begin="0s" repeatCount="1" fill="freeze"/>'
    '</rect></svg>';

// A finite, non-looping, near-instant animation — settles and stops ticking
// almost immediately.
//
// 有限、不循环、近乎瞬时的动画——几乎立刻进入定格并停止 ticking。
const _quickFlash =
    '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" '
    'viewBox="0 0 24 24">'
    '<rect width="24" height="24" fill="#000">'
    '<animate attributeName="fill-opacity" values="0;1" dur="10ms" '
    'fill="freeze"/>'
    '</rect></svg>';

Duration _clockOf(WidgetTester tester) {
  final paint = tester.widget<CustomPaint>(
    find
        .descendant(
          of: find.byType(XvgAnimated),
          matching: find.byType(CustomPaint),
        )
        .first,
  );
  return (paint.painter! as AnimatedSvgPainter).clock.value;
}

/// Verifies callback, speed and frame-cap contracts. / 验证回调、速率和帧率契约。
void main() {
  setUp(XvgDocumentCache.instance.clear);
  tearDown(XvgDocumentCache.instance.clear);

  group('onAnimationStart', () {
    testWidgets('fires exactly once, on the first tick', (tester) async {
      var startCount = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: XvgAnimated.string(
            _spinner,
            width: 24,
            height: 24,
            onAnimationStart: () => startCount++,
          ),
        ),
      );
      expect(startCount, 0, reason: 'no tick has landed yet at mount');

      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(startCount, 1, reason: 'must fire exactly once across many ticks');
    });
  });

  group('onAnimationComplete', () {
    testWidgets('fires exactly once when a finite document naturally settles', (
      tester,
    ) async {
      var completeCount = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: XvgAnimated.string(
            _quickFlash,
            width: 24,
            height: 24,
            onAnimationComplete: () => completeCount++,
          ),
        ),
      );
      expect(completeCount, 0);

      // Well past the 10ms animation's total duration.
      // 远超这个 10ms 动画的总时长。
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(completeCount, 1);

      // Further ticks must not re-fire it (the instance has unsubscribed).
      // 之后的 tick 不得再次触发（该实例已取消订阅）。
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(completeCount, 1);
    });

    testWidgets('never fires for an indefinite-loop document', (tester) async {
      var completeCount = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: XvgAnimated.string(
            _spinner,
            width: 24,
            height: 24,
            onAnimationComplete: () => completeCount++,
          ),
        ),
      );
      for (var i = 0; i < 80; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(completeCount, 0);
    });

    testWidgets(
      'does not fire when ticking stops for another reason (source swap)',
      (tester) async {
        var completeCount = 0;
        var source = _spinner;
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => XvgAnimated.string(
                source,
                width: 24,
                height: 24,
                onAnimationComplete: () => completeCount++,
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 16));
        source = _quickFlash;
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => XvgAnimated.string(
                source,
                width: 24,
                height: 24,
                onAnimationComplete: () => completeCount++,
              ),
            ),
          ),
        );
        expect(
          completeCount,
          0,
          reason:
              'stopping the old subscription for a source swap is not a settle',
        );
      },
    );
  });

  group('onAnimationLoop', () {
    testWidgets(
      'fires with an incrementing iteration count once a period elapses',
      (tester) async {
        final iterations = <int>[];
        await tester.pumpWidget(
          MaterialApp(
            home: XvgAnimated.string(
              _indefiniteWithFinitePeriod,
              width: 24,
              height: 24,
              onAnimationLoop: iterations.add,
            ),
          ),
        );
        // The first loop is at 1100ms, not at the finite track's 100ms end.
        // 首次循环为1100ms，不是有限时间线结束的100ms。
        for (var i = 0; i < 22; i++) {
          await tester.pump(const Duration(milliseconds: 16));
        }
        expect(iterations, isEmpty);
        await tester.pump(const Duration(seconds: 3));
        expect(iterations, [1, 2, 3]);
        expect(iterations, isNotEmpty);
        expect(
          iterations,
          orderedEquals(List.generate(iterations.length, (i) => i + 1)),
          reason: 'iteration numbers must be consecutive starting at 1',
        );
      },
    );

    testWidgets('fires for a pure indefinite document using its loopPeriod', (
      tester,
    ) async {
      var loopCount = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: XvgAnimated.string(
            _spinner,
            width: 24,
            height: 24,
            onAnimationLoop: (_) => loopCount++,
          ),
        ),
      );
      for (var i = 0; i < 80; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(loopCount, 1);
    });
  });

  group('fps', () {
    testWidgets('caps the sample rate below the display refresh rate', (
      tester,
    ) async {
      tester.view.display.refreshRate = 60;
      addTearDown(tester.view.display.resetRefreshRate);

      await tester.pumpWidget(
        const MaterialApp(
          home: XvgAnimated.string(_spinner, width: 24, height: 24, fps: 15),
        ),
      );

      final samples = <Duration>[];
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        samples.add(_clockOf(tester));
      }
      final distinctSamples = samples.toSet().length;

      // 60Hz capped to 15fps is a divisor of 4: about a quarter of the 40
      // pumped frames should have actually advanced the timeline. Assert a
      // generous band rather than an exact count — the shared clock's phase
      // offset can shift the divisor's rounding by one tick either way.
      //
      // 60Hz 被压到 15fps 是除数 4：40 个被推进的帧里大约四分之一真正推进了
      // 时间线。断言一个宽松的区间而非精确计数——共享时钟的相位偏移会让除数
      // 的取整方向偏移一个 tick。
      expect(distinctSamples, lessThan(20));
      expect(distinctSamples, greaterThan(4));
    });

    testWidgets('null fps samples every eligible tick (no extra throttling)', (
      tester,
    ) async {
      tester.view.display.refreshRate = 60;
      addTearDown(tester.view.display.resetRefreshRate);

      await tester.pumpWidget(
        const MaterialApp(
          home: XvgAnimated.string(_spinner, width: 24, height: 24),
        ),
      );

      final samples = <Duration>[];
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        samples.add(_clockOf(tester));
      }
      expect(samples.toSet().length, 10);
    });
  });

  group('playbackRate', () {
    testWidgets('scales elapsed timeline relative to wall-clock time', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: XvgAnimated.string(
            _spinner,
            width: 24,
            height: 24,
            playbackRate: 2.0,
          ),
        ),
      );
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      final scaled = _clockOf(tester);
      // 10 pumped frames of 16ms is 160ms of wall-clock time; at 2x this
      // instance's timeline should read close to 320ms. Allow slack for the
      // shared clock's own frame-timing rounding.
      //
      // 10 帧 16ms 是 160ms 挂钟时间；2 倍速下本实例的时间线应读到接近
      // 320ms。为共享时钟自身的帧计时取整留出余量。
      expect(scaled.inMilliseconds, greaterThan(280));
      expect(scaled.inMilliseconds, lessThan(360));
    });

    testWidgets('a finite document settles proportionally sooner', (
      tester,
    ) async {
      var completeCount = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: XvgAnimated.string(
            _quickFlash,
            width: 24,
            height: 24,
            playbackRate: 10.0,
            onAnimationComplete: () => completeCount++,
          ),
        ),
      );
      // First tick anchors at zero; the next 16ms tick settles at 10x.
      // 首tick锚定零；下一个16ms tick在10倍速下完成。
      await tester.pump(const Duration(milliseconds: 16));
      expect(completeCount, 0);
      await tester.pump(const Duration(milliseconds: 16));
      expect(completeCount, 1);
    });
  });
}
