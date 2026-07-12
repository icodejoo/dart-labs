import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:countman/countman.dart';

// Tests for the unified-direction counter animation (approach B):
//   1. Direction is fixed globally before the animation runs — every digit
//      column travels the SAME way (increase → up, decrease → down).
//   2. A wheel landing on a lower digit no longer flashes a phantom digit
//      (the old per-column cumulative interpolation bug, e.g. 1000 → 7).
//   3. The roll geometry actually reverses for a decrease (exitDirection).
//
// 统一方向计数器动画测试（方案 B）：
//   1. 方向在动画运行前全局定好——每一位都朝同一方向移动（递增→向上，递减→向下）。
//   2. 落到更小数位的轮子不再闪出幻影数位（旧的逐列累计插值 bug，如 1000 → 7）。
//   3. 递减时滚动几何确实反向（exitDirection）。

/// Builds a bare [CounterPainter] with a single mutable knob set — the roll
/// transition, one digit cell, given [increasing] and [flipDirection]. Digit
/// values are pushed via [CounterPainter.update] in each test.
///
/// 构造一个精简 [CounterPainter]：roll 过渡、单个数字单元、指定 [increasing] 与
/// [flipDirection]。各测试用 [CounterPainter.update] 推入数位值。
CounterPainter _painter({
  required bool increasing,
  AxisDirection flipDirection = AxisDirection.up,
  List<double> digitValues = const [0.0],
  List<int> fastTo = const <int>[],
  List<double> targets = const <double>[],
}) {
  return CounterPainter(
    repaint: ValueNotifier<int>(0),
    digitValues: digitValues,
    style: const TextStyle(fontSize: 20, color: Color(0xFF000000)),
    digitSize: const Size(12, 20),
    transition: CounterTransition.slide,
    flipDirection: flipDirection,
    increasing: increasing,
    fractionDigits: 0,
    groupingPattern: const [3],
    hideLeadingZeroes: false,
    numeralSystem: NumeralSystem.latin,
    fastTo: fastTo,
    targets: targets,
  );
}

void main() {
  group('resolveColumnPhase — increasing (wraps up through 0)', () {
    test('mid-cell 9.4 → leaving 9, arriving 0', () {
      final p = _painter(increasing: true, digitValues: [9.4]);
      final (cur, nxt, phase) = p.resolveColumnPhase(0);
      expect(cur, 9);
      expect(nxt, 0);
      expect(phase, closeTo(0.4, 1e-9));
    });

    test('past one wrap 10.6 → leaving 0, arriving 1', () {
      final p = _painter(increasing: true, digitValues: [10.6]);
      final (cur, nxt, phase) = p.resolveColumnPhase(0);
      expect(cur, 0);
      expect(nxt, 1);
      expect(phase, closeTo(0.6, 1e-9));
    });

    test('exact integer 5.0 → resting on 5, phase 0', () {
      final p = _painter(increasing: true, digitValues: [5.0]);
      final (cur, nxt, phase) = p.resolveColumnPhase(0);
      expect(cur, 5);
      expect(nxt, 6);
      expect(phase, 0.0);
    });
  });

  group('resolveColumnPhase — decreasing (wraps down through 9, no phantom)', () {
    test('mid-cell 0.4 → leaving 1, arriving 0 (rolls 1→0, never 9)', () {
      final p = _painter(increasing: false, digitValues: [0.4]);
      final (cur, nxt, phase) = p.resolveColumnPhase(0);
      expect(cur, 1);
      expect(nxt, 0);
      expect(phase, closeTo(0.6, 1e-9));
    });

    test('negative position -0.4 → leaving 0, arriving 9 (the real wrap)', () {
      final p = _painter(increasing: false, digitValues: [-0.4]);
      final (cur, nxt, phase) = p.resolveColumnPhase(0);
      expect(cur, 0);
      expect(nxt, 9);
      expect(phase, closeTo(0.4, 1e-9));
    });

    test('deep negative -1.0 → resting on 9 (never a negative digit)', () {
      final p = _painter(increasing: false, digitValues: [-1.0]);
      final (cur, nxt, phase) = p.resolveColumnPhase(0);
      expect(cur, 9);
      expect(nxt, 8);
      expect(phase, 0.0);
    });
  });

  group('ghost-prevention rests at target but allows bounce overshoot', () {
    // Ghost snaps p=0 only while APPROACHING the target. A bounce overshoot
    // past the target (increase: v > tgt; decrease: v < tgt) must keep rolling,
    // otherwise the bounce is invisible.
    //
    // ghost 只在“接近”目标时把 p 压 0。越过目标的 bounce（递增 v > tgt；递减 v < tgt）
    // 必须继续滚动，否则回弹不可见。
    test('increase: rests exactly at target', () {
      final p = _painter(increasing: true, digitValues: [5.0], fastTo: [5], targets: [5.0]);
      expect(p.resolveColumnPhase(0).$3, 0.0);
    });

    test('increase: overshoot past target still rolls (bounce)', () {
      final p = _painter(increasing: true, digitValues: [5.3], fastTo: [5], targets: [5.0]);
      final (cur, _, phase) = p.resolveColumnPhase(0);
      expect(cur, 5);
      expect(phase, closeTo(0.3, 1e-9));
    });

    test('decrease: overshoot below target still rolls (bounce)', () {
      final p = _painter(increasing: false, digitValues: [4.7], fastTo: [5], targets: [5.0]);
      final (cur, _, phase) = p.resolveColumnPhase(0);
      expect(cur, 5);
      expect(phase, closeTo(0.3, 1e-9));
    });
  });

  group('exitDirection — decrease must roll DOWN, not up', () {
    test('flip up: increase = up (-1), decrease = down (+1)', () {
      expect(_painter(increasing: true).exitDirection(), -1.0);
      expect(_painter(increasing: false).exitDirection(), 1.0);
    });

    test('flip down: increase = down (+1), decrease = up (-1)', () {
      expect(
        _painter(increasing: true, flipDirection: AxisDirection.down).exitDirection(),
        1.0,
      );
      expect(
        _painter(increasing: false, flipDirection: AxisDirection.down).exitDirection(),
        -1.0,
      );
    });
  });

  group('end-to-end settle (painter path, exact via resolveColumnPhase)', () {
    // AnimatedCounter drives the live CounterPainter. After settling, each
    // column rests at phase ≈ 0 with `cur` = its target digit; reassembling
    // them must equal the target. Covers the tricky cases (carry up, borrow
    // down, big jumps, the phantom-prone borrow) end to end.
    //
    // AnimatedCounter 驱动实时 CounterPainter。稳定后每列停在相位 ≈ 0，其 `cur`
    // = 目标数位；拼回来必须等于目标。端到端覆盖棘手场景（进位、借位、大跳变、
    // 易出幻影的借位）。
    Future<void> expectSettles(WidgetTester tester, int from, int to) async {
      final ctrl = AnimatedCounterController(initialValue: from);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(
            child: AnimatedCounter(
              controller: ctrl,
              duration: const Duration(milliseconds: 200),
            ),
          ),
        ),
      ));
      await tester.pump();
      ctrl.animateTo(to);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      final painter = tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((w) => w.painter)
          .whereType<CounterPainter>()
          .first;

      final sb = StringBuffer();
      for (int i = 0; i < painter.digitValues.length; i++) {
        final (cur, _, phase) = painter.resolveColumnPhase(i);
        expect(phase, lessThan(0.02),
            reason: '$from → $to column $i should be at rest, phase=$phase');
        sb.write(cur);
      }
      final settled = sb.toString().replaceFirst(RegExp(r'^0+(?=\d)'), '');
      expect(settled, to.toString(),
          reason: '$from → $to should settle on "$to", got "$settled"');
    }

    testWidgets('19 → 21 (carry up)', (t) => expectSettles(t, 19, 21));
    testWidgets('21 → 19 (borrow down)', (t) => expectSettles(t, 21, 19));
    testWidgets('1000 → 7 (phantom-prone borrow)', (t) => expectSettles(t, 1000, 7));
    testWidgets('0 → 9999 (big jump up)', (t) => expectSettles(t, 0, 9999));
    testWidgets('9999 → 0 (big jump down)', (t) => expectSettles(t, 9999, 0));
  });

  group('leading zeros hidden at rest (via buildColumns visible count)', () {
    // buildColumns() returns only the VISIBLE digit columns. After settling,
    // leading zeros must be dropped: 1000 → 7 shows one column ("7"), not four
    // ("0007"); a grow to 1000 shows four.
    //
    // buildColumns() 只返回可见数位列。稳定后前导零必须去掉：1000 → 7 只剩一列（"7"），
    // 而非四列（"0007"）；增长到 1000 则四列。
    Future<CounterPainter> settleAndGetPainter(
        WidgetTester tester, int from, int to) async {
      final ctrl = AnimatedCounterController(initialValue: from);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(
            child: AnimatedCounter(
              controller: ctrl,
              duration: const Duration(milliseconds: 200),
            ),
          ),
        ),
      ));
      await tester.pump();
      ctrl.animateTo(to);
      await tester.pump();
      await tester.pumpAndSettle();
      return tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((w) => w.painter)
          .whereType<CounterPainter>()
          .first;
    }

    testWidgets('1000 → 7 shows 1 column, not 0007', (tester) async {
      final p = await settleAndGetPainter(tester, 1000, 7);
      expect(p.buildColumns().length, 1);
    });

    testWidgets('42 → 1000 shows 4 columns', (tester) async {
      final p = await settleAndGetPainter(tester, 42, 1000);
      expect(p.buildColumns().length, 4);
    });

    testWidgets('value 0 keeps the units column (not blank)', (tester) async {
      // Regression: reveal-fade must exempt the units place, else a value of 0
      // renders at opacity 0 (blank) instead of "0".
      //
      // 回归：淡入必须豁免个位，否则值为 0 会以 0 不透明度渲染（空白）而非 "0"。
      final p = await settleAndGetPainter(tester, 99, 0);
      final cols = p.buildColumns();
      expect(cols.length, 1);
      expect(p.resolveColumnPhase(cols.first.index).$1, 0);
    });
  });

  testWidgets('all-nines target cascades, not lockstep (0 → 99)', (tester) async {
    // With the cumulative cascade, the units place spins ~10× faster than the
    // tens place, so mid-animation the two columns show DIFFERENT digits at
    // some frame (e.g. "49"). The old minimal-wrapped-delta made both columns
    // step 0→9 identically → lockstep 00,11,…,99. Assert they desync.
    //
    // 采用累计级联时，个位比十位快约 10×，故动画中途两列在某帧显示不同数位（如 "49"）。
    // 旧的最小环绕增量让两列 0→9 完全一致 → 锁步 00,11,…,99。断言它们不同步。
    final ctrl = AnimatedCounterController(initialValue: 0);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: AnimatedCounter(
            controller: ctrl,
            duration: const Duration(milliseconds: 300),
          ),
        ),
      ),
    ));
    await tester.pump();
    ctrl.animateTo(99);
    await tester.pump();

    final painter = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((w) => w.painter)
        .whereType<CounterPainter>()
        .first;

    var sawDesync = false;
    for (var ms = 0; ms < 300; ms += 15) {
      await tester.pump(const Duration(milliseconds: 15));
      // index 0 = tens, index 1 = units (2-digit target).
      final tens = painter.resolveColumnPhase(0).$1;
      final units = painter.resolveColumnPhase(1).$1;
      if (tens != units) sawDesync = true;
    }
    expect(sawDesync, isTrue,
        reason: 'units and tens should differ mid-roll (cascade), not move in lockstep');

    await tester.pumpAndSettle();
  });
}
