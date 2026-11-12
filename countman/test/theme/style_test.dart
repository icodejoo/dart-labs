import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:countman/countman.dart';

// Tests for the per-widget `*Style` API: value semantics (copyWith / merge /
// == / hashCode) and that a widget actually applies the style (text style +
// container decoration).
//
// 各组件 `*Style` API 的测试：值语义（copyWith / merge / == / hashCode），以及
// 组件确实应用了样式（文本样式 + 容器装饰）。

void main() {
  tearDown(Countman.destroy);

  group('TextCounterStyle value semantics', () {
    test('merge: this non-null fields win, other fills the gaps', () {
      const a = TextCounterStyle(textStyle: TextStyle(fontSize: 10));
      const b = TextCounterStyle(textStyle: TextStyle(fontSize: 20), maxLines: 2);
      final m = a.merge(b);
      expect(m.textStyle!.fontSize, 10, reason: 'a (higher priority) wins');
      expect(m.maxLines, 2, reason: 'b fills the gap a left null');
    });

    test('merge(null) returns this', () {
      const a = TextCounterStyle(maxLines: 3);
      expect(identical(a.merge(null), a), isTrue);
    });

    test('copyWith replaces only the given fields', () {
      const a = TextCounterStyle(textStyle: TextStyle(fontSize: 10), maxLines: 1);
      final c = a.copyWith(maxLines: 5);
      expect(c.maxLines, 5);
      expect(c.textStyle!.fontSize, 10, reason: 'untouched field preserved');
    });

    test('== and hashCode by value', () {
      const a = TextCounterStyle(maxLines: 2, textStyle: TextStyle(fontSize: 10));
      const b = TextCounterStyle(maxLines: 2, textStyle: TextStyle(fontSize: 10));
      const c = TextCounterStyle(maxLines: 3);
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(equals(c)));
    });
  });

  group('RingCounterStyle value semantics + new fields', () {
    test('merge keeps this.strokeWidth, takes other.sweepAngle', () {
      const a = RingCounterStyle(strokeWidth: 4);
      const b = RingCounterStyle(strokeWidth: 8, sweepAngle: 3.14, showTrack: false);
      final m = a.merge(b);
      expect(m.strokeWidth, 4);
      expect(m.sweepAngle, 3.14);
      expect(m.showTrack, false);
    });
  });

  group('BarStyle / DialStyle / CardStyle / AnimatedCounterStyle exist & merge', () {
    test('BarCountdownStyle vertical + merge', () {
      const a = BarCountdownStyle(vertical: true);
      const b = BarCountdownStyle(vertical: false, height: 12);
      final m = a.merge(b);
      expect(m.vertical, true);
      expect(m.height, 12);
    });

    test('DialCountdownStyle show flags + merge', () {
      const a = DialCountdownStyle(showTicks: false);
      const b = DialCountdownStyle(showTicks: true, glow: true);
      final m = a.merge(b);
      expect(m.showTicks, false);
      expect(m.glow, true);
    });

    test('CardCountdownStyle merge', () {
      const a = CardCountdownStyle(splitDigits: true);
      const b = CardCountdownStyle(splitDigits: false, cardWidth: 40);
      final m = a.merge(b);
      expect(m.splitDigits, true);
      expect(m.cardWidth, 40);
    });

    test('AnimatedCounterStyle merge', () {
      const a = AnimatedCounterStyle(numberAlignment: -1);
      const b = AnimatedCounterStyle(numberAlignment: 1, useTabularFigures: false);
      final m = a.merge(b);
      expect(m.numberAlignment, -1);
      expect(m.useTabularFigures, false);
    });
  });

  group('style is actually applied by widgets', () {
    testWidgets('TextCounter applies decoration + textStyle', (t) async {
      await t.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: Center(
            child: TextCounter(
              to: 100,
              style: TextCounterStyle(
                textStyle: TextStyle(fontSize: 20, color: Color(0xFF112233)),
                decoration: BoxDecoration(color: Color(0xFFAABBCC)),
              ),
            ),
          ),
        ),
      ));
      await t.pump();

      // Container decoration from the style is present.
      expect(
        find.byWidgetPredicate((w) =>
            w is DecoratedBox &&
            w.decoration is BoxDecoration &&
            (w.decoration as BoxDecoration).color == const Color(0xFFAABBCC)),
        findsOneWidget,
      );
      // Number text style from the style is applied.
      final txt = t.widget<Text>(find.byType(Text).first);
      expect(txt.style?.fontSize, 20);
      expect(txt.style?.color, const Color(0xFF112233));
    });

    testWidgets('CounterProvider.textCounterStyle inherited; widget style wins', (t) async {
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: CounterProvider(
            textCounterStyle: const TextCounterStyle(textStyle: TextStyle(fontSize: 30)),
            child: Column(children: const [
              TextCounter(to: 5, key: Key('inherit')),
              TextCounter(
                to: 5,
                key: Key('override'),
                style: TextCounterStyle(textStyle: TextStyle(fontSize: 12)),
              ),
            ]),
          ),
        ),
      ));
      await t.pump();
      Text txt(Key k) => t.widget<Text>(
          find.descendant(of: find.byKey(k), matching: find.byType(Text)));
      expect(txt(const Key('inherit')).style?.fontSize, 30,
          reason: 'provider default inherited');
      expect(txt(const Key('override')).style?.fontSize, 12,
          reason: 'widget style overrides provider');
    });

    testWidgets('CardCountdown forwards curve to its transition painter', (t) async {
      await t.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: Center(
            child: CardCountdown(to: Duration(seconds: 5), curve: Curves.easeInOut),
          ),
        ),
      ));
      await t.pump();
      final fcp = t
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((c) => c.painter)
          .whereType<FlipCardPainter>()
          .first;
      expect(fcp.curve, Curves.easeInOut);
    });

    testWidgets('TextCountdown gains prefix/suffix with per-affix style', (t) async {
      await t.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: Center(
            child: TextCountdown(
              to: Duration(minutes: 1),
              prefix: '⏱ ',
              suffix: ' left',
              style: TextCountdownStyle(
                prefixStyle: TextStyle(fontSize: 8),
                suffixStyle: TextStyle(fontSize: 9),
              ),
            ),
          ),
        ),
      ));
      await t.pump();
      // Prefix and suffix render as their own Text nodes.
      expect(find.text('⏱ '), findsOneWidget);
      expect(find.text(' left'), findsOneWidget);
    });
  });
}
