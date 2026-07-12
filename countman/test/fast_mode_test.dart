import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:countman/countman.dart';

// Tests for AnimatedCounter/AnimatedCounterBuilder `fast` mode: every digit
// column does a single old→new step (no cascading roll) and settles on the
// target — on both the painter path (AnimatedCounter) and the widget path
// (AnimatedCounterBuilder).
//
// AnimatedCounter/AnimatedCounterBuilder `fast` 模式测试：每列单步 旧→新（不级联），
// 并停在目标值——painter 路径与 widget 路径都验证。
void main() {
  testWidgets('fast: AnimatedCounterBuilder (widget path) settles at target', (tester) async {
    final ctrl = AnimatedCounterController(initialValue: 1000);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: AnimatedCounterBuilder(
            controller: ctrl,
            fast: true,
            duration: const Duration(milliseconds: 200),
          ),
        ),
      ),
    ));
    await tester.pump();
    ctrl.animateTo(9999);
    await tester.pump(); // kick off (StartScheduler frame)
    await tester.pump(const Duration(milliseconds: 120)); // mid-transition
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(milliseconds: 200)); // past completion
    await tester.pump(const Duration(milliseconds: 20));
    expect(tester.takeException(), isNull);
    // 1000 → 9999: four columns, each settled on '9'.
    expect(find.text('9'), findsNWidgets(4));

    await tester.pumpWidget(const SizedBox());
    ctrl.dispose();
    Countman.destroy();
  });

  testWidgets('fast: AnimatedCounter (painter path) animates without throwing', (tester) async {
    final ctrl = AnimatedCounterController(initialValue: 1000);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: AnimatedCounter(
            controller: ctrl,
            fast: true,
            duration: const Duration(milliseconds: 200),
          ),
        ),
      ),
    ));
    await tester.pump();
    ctrl.animateTo(9999);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 20));
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox());
    ctrl.dispose();
    Countman.destroy();
  });

  testWidgets('fast: decreasing 9999 → 1000 settles without overshoot artifacts', (tester) async {
    final ctrl = AnimatedCounterController(initialValue: 9999);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: AnimatedCounterBuilder(
            controller: ctrl,
            fast: true,
            duration: const Duration(milliseconds: 200),
          ),
        ),
      ),
    ));
    await tester.pump();
    ctrl.animateTo(1000);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 260));
    await tester.pump(const Duration(milliseconds: 20));
    expect(tester.takeException(), isNull);
    // 1000 → one '1' + three '0'.
    expect(find.text('1'), findsOneWidget);
    expect(find.text('0'), findsNWidgets(3));

    await tester.pumpWidget(const SizedBox());
    ctrl.dispose();
    Countman.destroy();
  });
}
