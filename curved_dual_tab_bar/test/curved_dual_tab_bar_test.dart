import 'package:curved_dual_tab_bar/curved_dual_tab_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpBar(
    WidgetTester tester, {
    required int selectedIndex,
    required ValueChanged<int> onChanged,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CurvedDualTabBar(
            titles: const ['DEPOSIT', 'WITHDRAW'],
            selectedIndex: selectedIndex,
            onChanged: onChanged,
          ),
        ),
      ),
    );
  }

  testWidgets('renders both titles', (tester) async {
    await pumpBar(tester, selectedIndex: 0, onChanged: (_) {});

    expect(find.text('DEPOSIT'), findsOneWidget);
    expect(find.text('WITHDRAW'), findsOneWidget);
  });

  testWidgets('tapping the other tab reports its index', (tester) async {
    var selected = 0;
    await pumpBar(
      tester,
      selectedIndex: selected,
      onChanged: (i) => selected = i,
    );

    await tester.tap(find.text('WITHDRAW'));
    await tester.pumpAndSettle();

    expect(selected, 1);
  });

  testWidgets('asserts exactly two titles', (tester) async {
    expect(
      () => CurvedDualTabBar(
        titles: const ['ONE', 'TWO', 'THREE'],
        selectedIndex: 0,
        onChanged: (_) {},
      ),
      throwsAssertionError,
    );
  });

  testWidgets('renders with divider gradient/cap/shadow and control offsets', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CurvedDualTabBar(
            titles: const ['DEPOSIT', 'WITHDRAW'],
            selectedIndex: 0,
            onChanged: (_) {},
            dividerGradient: const LinearGradient(
              colors: [Colors.pink, Colors.blue],
            ),
            dividerCap: StrokeCap.round,
            dividerShadow: const BoxShadow(
              color: Colors.black26,
              blurRadius: 6,
              spreadRadius: 1,
            ),
            topControlOffset: const Offset(10, 4),
            bottomControlOffset: const Offset(-10, -4),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('DEPOSIT'), findsOneWidget);
  });
}
