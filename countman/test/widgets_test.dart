import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:countman/countman.dart';

void main() {

// ── helpers ───────────────────────────────────────────────────────────────────

/// Wraps a widget in a minimal Material app so Text / Icon can render.
Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

/// Pumps frame 1 (anchor, dt=0) then frame 2 (advance time).
Future<void> _pumpTwo(WidgetTester t, [Duration advance = const Duration(milliseconds: 200)]) async {
  await t.pump();
  await t.pump(advance);
}

// ── CounterBuilder ─────────────────────────────────────────────────────────────

group('CounterBuilder', () {
  tearDown(Countman.destroy);

  testWidgets('renders from value on first frame', (t) async {
    await t.pumpWidget(_wrap(
      CounterBuilder(
        from: 50,
        to: 100,
        builder: (_, v) => Text(v.toInt().toString()),
      ),
    ));
    await t.pump(); // frame 1: value = from = 50
    Countman.destroy();

    expect(find.text('50'), findsOneWidget);
  });

  testWidgets('defaults from to 0 when not provided', (t) async {
    await t.pumpWidget(_wrap(
      CounterBuilder(to: 100, builder: (_, v) => Text(v.toInt().toString())),
    ));
    await t.pump();
    Countman.destroy();

    expect(find.text('0'), findsOneWidget);
  });

  testWidgets('animates toward to', (t) async {
    await t.pumpWidget(_wrap(
      CounterBuilder(
        to: 100,
        duration: const Duration(milliseconds: 200),
        builder: (_, v) => Text(v.toInt().toString()),
      ),
    ));

    await t.pump();                                   // frame 1: value=0
    expect(find.text('0'), findsOneWidget);

    await t.pump(const Duration(milliseconds: 100));  // frame 2: mid-progress
    // value should be somewhere between 0 and 100
    final midText = t.widget<Text>(find.byType(Text)).data!;
    expect(int.parse(midText), greaterThan(0));
    expect(int.parse(midText), lessThan(100));

    await t.pump(const Duration(milliseconds: 400));  // frame 3: done
    Countman.destroy();
    expect(find.text('100'), findsOneWidget);
  });

  testWidgets('calls onComplete when animation reaches to', (t) async {
    double? doneValue;
    await t.pumpWidget(_wrap(
      CounterBuilder(
        to: 42,
        duration: const Duration(milliseconds: 100),
        onComplete: (v) => doneValue = v,
        builder: (_, v) => Text(v.toInt().toString()),
      ),
    ));

    await _pumpTwo(t);
    Countman.destroy();

    expect(doneValue, 42.0);
  });

  testWidgets('custom curve affects animation progress', (t) async {
    final linear = <double>[];
    final bounce = <double>[];

    await t.pumpWidget(_wrap(Row(children: [
      CounterBuilder(
        to: 100,
        duration: const Duration(milliseconds: 200),
        curve: Curves.linear,
        builder: (_, v) { linear.add(v); return const SizedBox(); },
      ),
      CounterBuilder(
        to: 100,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeIn,
        builder: (_, v) { bounce.add(v); return const SizedBox(); },
      ),
    ])));

    await t.pump();
    await t.pump(const Duration(milliseconds: 100)); // mid-point
    Countman.destroy();

    // At t=0.5, easeIn is slower than linear, so easeIn value < linear value
    expect(linear.last, greaterThan(bounce.last));
  });

  testWidgets('retargets mid-animation when to changes', (t) async {
    double currentTo = 100;
    late StateSetter set;

    await t.pumpWidget(_wrap(StatefulBuilder(builder: (_, s) {
      set = s;
      return CounterBuilder(
        to: currentTo,
        duration: const Duration(milliseconds: 400),
        builder: (_, v) => Text(v.toInt().toString()),
      );
    })));

    await t.pump();
    await t.pump(const Duration(milliseconds: 200)); // ~50% progress

    final mid = int.parse(t.widget<Text>(find.byType(Text)).data!);
    expect(mid, greaterThan(0));

    // Retarget to 200 from current mid position
    set(() => currentTo = 200);
    await t.pump();                                   // frame 1 of retarget: value = mid
    final afterRetarget = int.parse(t.widget<Text>(find.byType(Text)).data!);
    expect(afterRetarget, greaterThanOrEqualTo(mid)); // did not jump to 0
    Countman.destroy();
  });

  testWidgets('retargets after animation completes (bug: task removed from queue)', (t) async {
    double currentTo = 100;
    late StateSetter set;

    await t.pumpWidget(_wrap(StatefulBuilder(builder: (_, s) {
      set = s;
      return CounterBuilder(
        to: currentTo,
        duration: const Duration(milliseconds: 100),
        builder: (_, v) => Text(v.toInt().toString()),
      );
    })));

    await _pumpTwo(t); // let first animation complete
    expect(find.text('100'), findsOneWidget);

    // Retarget after completion — task was removed from queue.
    // Needs 3 pumps: rebuild → anchor (dt=0) → advance past duration.
    set(() => currentTo = 200);
    await t.pump();                                   // setState rebuild + new task scheduled
    await t.pump();                                   // frame 1: dt=0, started, value=100
    await t.pump(const Duration(milliseconds: 300)); // frame 2: accum=300 > 100ms → done
    Countman.destroy();

    expect(find.text('200'), findsOneWidget);
  });

  testWidgets('disposes task when widget is removed', (t) async {
    final values = <double>[];
    await t.pumpWidget(_wrap(
      CounterBuilder(
        to: 100,
        duration: const Duration(milliseconds: 400),
        onUpdate: (v) => values.add(v),
        builder: (_, v) => Text(v.toInt().toString()),
      ),
    ));

    await t.pump();
    await t.pump(const Duration(milliseconds: 100));

    // Remove the widget
    await t.pumpWidget(_wrap(const SizedBox()));
    final countAfterRemove = values.length;

    await t.pump(const Duration(milliseconds: 400));
    Countman.destroy();

    expect(values.length, countAfterRemove); // no more updates
  });
});

// ── CounterText ────────────────────────────────────────────────────────────────

group('CounterText', () {
  tearDown(Countman.destroy);

  testWidgets('default formatter shows toInt', (t) async {
    await t.pumpWidget(_wrap(CounterText(to: 99)));
    await t.pump();
    Countman.destroy();

    expect(find.text('0'), findsOneWidget);
  });

  testWidgets('custom formatter applied', (t) async {
    await t.pumpWidget(_wrap(
      CounterText(
        to: 100,
        formatter: (v) => '${v.toInt()}px',
      ),
    ));
    await t.pump();
    Countman.destroy();

    expect(find.text('0px'), findsOneWidget);
  });

  testWidgets('reaches to value', (t) async {
    await t.pumpWidget(_wrap(
      CounterText(to: 50, duration: const Duration(milliseconds: 100)),
    ));
    await _pumpTwo(t);
    Countman.destroy();

    expect(find.text('50'), findsOneWidget);
  });

  testWidgets('no Row when no prefix/suffix', (t) async {
    await t.pumpWidget(_wrap(CounterText(to: 10)));
    await t.pump();
    Countman.destroy();

    expect(find.byType(Row), findsNothing);
  });

  testWidgets('prefix String shown', (t) async {
    await t.pumpWidget(_wrap(CounterText(to: 10, prefix: '¥')));
    await t.pump();
    Countman.destroy();

    expect(find.text('¥'), findsOneWidget);
    expect(find.byType(Row), findsOneWidget);
  });

  testWidgets('suffix String shown', (t) async {
    await t.pumpWidget(_wrap(CounterText(to: 10, suffix: ' pts')));
    await t.pump();
    Countman.destroy();

    expect(find.text(' pts'), findsOneWidget);
    expect(find.byType(Row), findsOneWidget);
  });

  testWidgets('both prefix and suffix shown', (t) async {
    await t.pumpWidget(_wrap(CounterText(to: 10, prefix: '¥', suffix: ' 元')));
    await t.pump();
    Countman.destroy();

    expect(find.text('¥'), findsOneWidget);
    expect(find.text(' 元'), findsOneWidget);
  });

  testWidgets('prefixWidget shown instead of prefix String', (t) async {
    await t.pumpWidget(_wrap(
      CounterText(
        to: 10,
        prefixWidget: const Icon(Icons.star, key: Key('icon')),
        prefix: 'IGNORED',
      ),
    ));
    await t.pump();
    Countman.destroy();

    expect(find.byKey(const Key('icon')), findsOneWidget);
    expect(find.text('IGNORED'), findsNothing);
  });

  testWidgets('suffixWidget shown instead of suffix String', (t) async {
    await t.pumpWidget(_wrap(
      CounterText(
        to: 10,
        suffixWidget: const Icon(Icons.check, key: Key('icon')),
        suffix: 'IGNORED',
      ),
    ));
    await t.pump();
    Countman.destroy();

    expect(find.byKey(const Key('icon')), findsOneWidget);
    expect(find.text('IGNORED'), findsNothing);
  });

  testWidgets('prefixWidget triggers Row even without prefix String', (t) async {
    await t.pumpWidget(_wrap(
      CounterText(to: 10, prefixWidget: const Icon(Icons.star)),
    ));
    await t.pump();
    Countman.destroy();

    expect(find.byType(Row), findsOneWidget);
  });

  testWidgets('suffixWidget triggers Row even without suffix String', (t) async {
    await t.pumpWidget(_wrap(
      CounterText(to: 10, suffixWidget: const Icon(Icons.check)),
    ));
    await t.pump();
    Countman.destroy();

    expect(find.byType(Row), findsOneWidget);
  });

  testWidgets('onComplete called when animation completes', (t) async {
    double? done;
    await t.pumpWidget(_wrap(
      CounterText(
        to: 77,
        duration: const Duration(milliseconds: 100),
        onComplete: (v) => done = v,
      ),
    ));
    await _pumpTwo(t);
    Countman.destroy();

    expect(done, 77.0);
  });

  testWidgets('from value respected', (t) async {
    await t.pumpWidget(_wrap(CounterText(from: 50, to: 100)));
    await t.pump();
    Countman.destroy();

    expect(find.text('50'), findsOneWidget);
  });
});

} // main
