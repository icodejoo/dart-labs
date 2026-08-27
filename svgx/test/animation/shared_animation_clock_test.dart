// Regression test for the shared-Ticker optimization in
// animated_svg_widget.dart's `_SharedAnimationClock`: every `SvgXAnimated`
// instance used to create (and register with `SchedulerBinding`) its own
// `Ticker`; now they all subscribe to one process-wide shared ticker. This
// verifies the refactor preserves per-instance timeline semantics:
// - a later-mounted instance's timeline starts at zero regardless of how
//   long the shared clock has already been running for an earlier instance
// - instances tick independently (one settling/unsubscribing doesn't affect
//   another still-active one)
// - the shared clock actually resets once every subscriber has left, so a
//   fresh instance mounted after all others unmount starts at zero too
//
// 共享 Ticker 优化（animated_svg_widget.dart 的 `_SharedAnimationClock`）的
// 回归测试：此前每个 `SvgXAnimated` 实例都各自创建（并向 `SchedulerBinding`
// 注册）一个 `Ticker`；现在它们全部订阅同一个进程级共享 ticker。本测试验证
// 重构后仍保留逐实例的时间线语义：
// - 后挂载实例的时间线从零开始，与共享时钟已经为更早的实例跑了多久无关
// - 各实例独立计时（一个进入定格/取消订阅不影响另一个仍在活跃的实例）
// - 所有订阅者都离开后共享时钟确实会重置，因此全部卸载后新挂载的实例同样
//   从零开始

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:svgx/src/animation/animated_svg_painter.dart';
import 'package:svgx/svgx.dart';

// A one-second indefinite spin — keeps ticking for the whole test instead of
// settling.
// 一秒无限旋转——整个测试期间持续 tick，不会定格。
const _spinner =
    '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" '
    'viewBox="0 0 24 24">'
    '<circle cx="12" cy="12" r="9" fill="none" stroke="#000" '
    'stroke-width="2" stroke-dasharray="40 20">'
    '<animateTransform attributeName="transform" type="rotate" '
    'values="0 12 12;360 12 12" dur="1s" repeatCount="indefinite"/>'
    '</circle></svg>';

// A finite, non-looping, near-instant animation — settles and unsubscribes
// from the shared clock almost immediately.
// 有限、不循环、近乎瞬时的动画——几乎立刻进入定格并从共享时钟取消订阅。
const _quickFlash =
    '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" '
    'viewBox="0 0 24 24">'
    '<rect width="24" height="24" fill="#000">'
    '<animate attributeName="fill-opacity" values="0;1" dur="10ms" '
    'fill="freeze"/>'
    '</rect></svg>';

Duration _clockOf(Finder svgXAnimated, WidgetTester tester) {
  final paint = tester.widget<CustomPaint>(
    find
        .descendant(of: svgXAnimated, matching: find.byType(CustomPaint))
        .first,
  );
  return (paint.painter! as AnimatedSvgPainter).clock.value;
}

void main() {
  setUp(SvgDocumentCache.instance.clear);
  tearDown(SvgDocumentCache.instance.clear);

  testWidgets(
    "a later-mounted instance's local timeline starts at zero even though "
    'the shared clock has already run for an earlier instance',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Column(
            children: [SvgXAnimated.string(_spinner, width: 24, height: 24)],
          ),
        ),
      );
      // Let the first instance's (and the shared clock's) timeline advance.
      // 先让第一个实例（及共享时钟）的时间线跑一段。
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      final firstFinder = find.byType(SvgXAnimated).first;
      final firstClockBeforeSecondMounts = _clockOf(firstFinder, tester);
      expect(
        firstClockBeforeSecondMounts,
        greaterThan(Duration.zero),
        reason: 'sanity: the shared clock must have advanced by now',
      );

      // Mount a second instance now — its own local timeline must start at
      // (approximately) zero, not at the shared clock's already-elapsed
      // value.
      //
      // 现在挂载第二个实例——它自己的本地时间线必须（近似）从零开始，而非
      // 共享时钟已经流逝的值。
      await tester.pumpWidget(
        const MaterialApp(
          home: Column(
            children: [
              SvgXAnimated.string(_spinner, width: 24, height: 24),
              SvgXAnimated.string(_spinner, width: 24, height: 24),
            ],
          ),
        ),
      );
      final secondFinder = find.byType(SvgXAnimated).at(1);
      final secondClockAtMount = _clockOf(secondFinder, tester);
      expect(
        secondClockAtMount,
        lessThan(const Duration(milliseconds: 50)),
        reason:
            "the second instance's local timeline must start near zero, "
            "not inherit the shared clock's already-elapsed time",
      );

      // Both keep advancing independently after another round of ticks.
      // 再推进若干帧，两者应各自继续独立前进。
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(
        _clockOf(firstFinder, tester),
        greaterThan(firstClockBeforeSecondMounts),
      );
      expect(_clockOf(secondFinder, tester), greaterThan(secondClockAtMount));
    },
  );

  testWidgets(
    'a settled instance unsubscribing does not stop a still-active sibling',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Column(
            children: [
              SvgXAnimated.string(_quickFlash, width: 24, height: 24),
              SvgXAnimated.string(_spinner, width: 24, height: 24),
            ],
          ),
        ),
      );
      final spinnerFinder = find.byType(SvgXAnimated).at(1);
      final beforeSettle = _clockOf(spinnerFinder, tester);

      // Advance well past _quickFlash's 10ms duration, so it settles and
      // unsubscribes from the shared clock.
      //
      // 推进到远超过 _quickFlash 10ms 的时长，使其定格并从共享时钟取消订阅。
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }

      // The still-indefinite spinner must have kept advancing — the shared
      // clock/ticker must not have been torn down just because one
      // subscriber left.
      //
      // 仍在无限循环的 spinner 必须继续前进——共享时钟/ticker 不能因为一个
      // 订阅者离开就被拆掉。
      expect(_clockOf(spinnerFinder, tester), greaterThan(beforeSettle));
    },
  );

  testWidgets(
    'a fresh instance mounted after every prior subscriber unmounted starts '
    'at zero again',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: SvgXAnimated.string(_spinner, width: 24, height: 24),
        ),
      );
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(
        _clockOf(find.byType(SvgXAnimated), tester),
        greaterThan(Duration.zero),
      );

      // Unmount everything — the shared clock should have no subscribers
      // left and reset.
      //
      // 全部卸载——共享时钟应当没有任何订阅者，并已重置。
      await tester.pumpWidget(
        const MaterialApp(home: SizedBox.shrink()),
      );
      await tester.pump(const Duration(milliseconds: 16));

      // A brand-new instance must start at (approximately) zero, not resume
      // from wherever the now-torn-down shared clock last was.
      //
      // 全新实例必须（近似）从零开始，而非从已拆掉的共享时钟最后所处的位置
      // 继续。
      await tester.pumpWidget(
        const MaterialApp(
          home: SvgXAnimated.string(_spinner, width: 24, height: 24),
        ),
      );
      expect(
        _clockOf(find.byType(SvgXAnimated), tester),
        lessThan(const Duration(milliseconds: 50)),
      );
    },
  );
}
