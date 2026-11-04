// 0.3.0：CountmanTheme（ThemeExtension）——生效、优先级、字段级合并与 lerp。
// Provider 上的 *Style 已弃用，这里仍要验证它的优先级。
// ignore_for_file: deprecated_member_use

import 'package:countman/countman.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/manual_clock.dart';

/// 用给定主题扩展包一层 MaterialApp。
Widget _app(Widget child, {CountmanTheme? theme}) => MaterialApp(
      themeAnimationDuration: Duration.zero,
      theme: ThemeData(extensions: [if (theme != null) theme]),
      home: Scaffold(body: Center(child: child)),
    );

void main() {
  setUp(installManualClock);
  tearDown(Countman.destroy);

  group('主题对各组件生效', () {
    testWidgets('RingCounter 读取 ringCounterStyle', (tester) async {
      await tester.pumpWidget(_app(
        const RingCounter(to: 10),
        theme: const CountmanTheme(ringCounterStyle: RingCounterStyle(size: 120)),
      ));
      expect(tester.getSize(find.byType(RingCounter)), const Size.square(120));
    });

    testWidgets('RingCountdown / BarCounter / BarCountdown / DialCountdown', (tester) async {
      await tester.pumpWidget(_app(
        const Column(children: [
          RingCountdown(to: Duration(seconds: 30)),
          BarCounter(to: 10),
          BarCountdown(to: Duration(seconds: 30)),
          DialCountdown(to: Duration(seconds: 30)),
        ]),
        theme: const CountmanTheme(
          ringCountdownStyle: RingCounterStyle(size: 50),
          barCounterStyle: BarCounterStyle(width: 111, height: 7),
          barCountdownStyle: BarCounterStyle(width: 222, height: 9),
          dialCountdownStyle: DialCountdownStyle(size: 66),
        ),
      ));
      expect(tester.getSize(find.byType(RingCountdown)), const Size.square(50));
      expect(tester.getSize(find.byType(BarCounter)), const Size(111, 7));
      expect(tester.getSize(find.byType(BarCountdown)), const Size(222, 9));
      expect(tester.getSize(find.byType(DialCountdown)), const Size.square(66));
    });

    testWidgets('文本三件套与 OdometerCounter / CardCountdown', (tester) async {
      await tester.pumpWidget(_app(
        const Column(children: [
          TextCounter(to: 5),
          TextCountdown(to: Duration(seconds: 30)),
          TextElapsed(),
          CardCountdown(to: Duration(seconds: 30), labels: null),
        ]),
        theme: const CountmanTheme(
          textCounterStyle:
              CountmanTextStyle(textStyle: TextStyle(fontSize: 31)),
          textCountdownStyle:
              CountmanTextStyle(textStyle: TextStyle(fontSize: 32)),
          textElapsedStyle:
              CountmanTextStyle(textStyle: TextStyle(fontSize: 33)),
          cardCountdownStyle: CardCountdownStyle(cardHeight: 44),
        ),
      ));
      double sizeOf(Finder f) => tester.widget<Text>(f).style!.fontSize!;
      expect(sizeOf(find.descendant(of: find.byType(TextCounter), matching: find.byType(Text))), 31);
      expect(sizeOf(find.descendant(of: find.byType(TextCountdown), matching: find.byType(Text))), 32);
      expect(sizeOf(find.descendant(of: find.byType(TextElapsed), matching: find.byType(Text))), 33);
      expect(tester.getSize(find.byType(CardCountdown)).height, 44);
    });

    testWidgets('OdometerCounter 与 AnimatedCounter 读取主题', (tester) async {
      Future<Size> measure(CountmanTheme? theme, Widget w) async {
        await tester.pumpWidget(_app(w, theme: theme));
        return tester.getSize(find.byType(AnimatedCounter));
      }

      final bare = await measure(null, const AnimatedCounter(value: 12));
      final themed = await measure(
        const CountmanTheme(
            animatedCounterStyle:
                AnimatedCounterStyle(padding: EdgeInsets.all(10))),
        const AnimatedCounter(value: 12),
      );
      expect(themed.width, greaterThan(bare.width));
      expect(themed.height, closeTo(bare.height + 20, 0.01));
      // widget.style 优先于主题：padding 4 比主题的 10 小，增量与 padding 成正比。
      final styled = await measure(
        const CountmanTheme(
            animatedCounterStyle:
                AnimatedCounterStyle(padding: EdgeInsets.all(10))),
        const AnimatedCounter(
            value: 12,
            style: AnimatedCounterStyle(padding: EdgeInsets.all(4))),
      );
      expect(styled.height, closeTo(bare.height + 8, 0.01));
      expect(styled.width, greaterThan(bare.width));
      expect(themed.width, greaterThan(styled.width));

      // OdometerCounter 的容器 padding 来自主题。
      await tester.pumpWidget(_app(
        const OdometerCounter(to: 12),
        theme: const CountmanTheme(
            odometerCounterStyle:
                OdometerCounterStyle(padding: EdgeInsets.all(13))),
      ));
      final padding = tester.widget<Padding>(find
          .descendant(
              of: find.byType(OdometerCounter),
              matching: find.byWidgetPredicate(
                  (w) => w is Padding && w.padding == const EdgeInsets.all(13)))
          .first);
      expect(padding.padding, const EdgeInsets.all(13));
    });
  });

  group('优先级：widget > provider(弃用) > theme > 默认', () {
    const theme = CountmanTheme(ringCounterStyle: RingCounterStyle(size: 100));
    const provider = RingCounterStyle(size: 90);
    const own = RingCounterStyle(size: 80);

    testWidgets('默认值 80；仅主题 100', (tester) async {
      await tester.pumpWidget(_app(const RingCounter(to: 1)));
      expect(tester.getSize(find.byType(RingCounter)), const Size.square(80));
      await tester.pumpWidget(_app(const RingCounter(to: 1), theme: theme));
      expect(tester.getSize(find.byType(RingCounter)), const Size.square(100));
    });

    testWidgets('Provider 盖过主题', (tester) async {
      await tester.pumpWidget(_app(
        const CounterProvider(
          ringCounterStyle: provider,
          child: RingCounter(to: 1),
        ),
        theme: theme,
      ));
      expect(tester.getSize(find.byType(RingCounter)), const Size.square(90));
    });

    testWidgets('widget style 盖过 Provider 与主题', (tester) async {
      await tester.pumpWidget(_app(
        const CounterProvider(
          ringCounterStyle: provider,
          child: RingCounter(to: 1, style: own),
        ),
        theme: theme,
      ));
      expect(tester.getSize(find.byType(RingCounter)), const Size.square(80));
    });

    testWidgets('字段级合并：各层只覆盖自己设置的字段', (tester) async {
      await tester.pumpWidget(_app(
        const CounterProvider(
          ringCounterStyle: RingCounterStyle(strokeWidth: 5),
          child: RingCounter(to: 1, style: RingCounterStyle(showTrack: false)),
        ),
        theme: const CountmanTheme(
          ringCounterStyle: RingCounterStyle(size: 100, strokeWidth: 12, clockwise: false),
        ),
      ));
      expect(tester.getSize(find.byType(RingCounter)), const Size.square(100));
      final painter = tester
          .widget<CustomPaint>(find
              .descendant(
                  of: find.byType(RingCounter),
                  matching: find.byType(CustomPaint))
              .first)
          .painter! as RingPainter;
      expect(painter.strokeWidth, 5, reason: 'Provider 盖过主题的 strokeWidth');
      expect(painter.showTrack, isFalse, reason: 'widget 自身字段');
      expect(painter.clockwise, isFalse, reason: '主题字段向下回退');
    });
  });

  group('第三方读取', () {
    testWidgets('CountmanTheme.of / maybeOf', (tester) async {
      CountmanTheme? seen;
      CountmanTheme? bare;
      const t = CountmanTheme(textCounterStyle: CountmanTextStyle(maxLines: 3));
      await tester.pumpWidget(_app(
        Builder(builder: (context) {
          seen = CountmanTheme.of(context);
          return const SizedBox();
        }),
        theme: t,
      ));
      expect(seen, t);
      await tester.pumpWidget(_app(Builder(builder: (context) {
        bare = CountmanTheme.maybeOf(context);
        return const SizedBox();
      })));
      expect(bare, isNull);
    });

    testWidgets('主题变化后组件随之更新', (tester) async {
      await tester.pumpWidget(_app(const RingCounter(to: 1),
          theme: const CountmanTheme(ringCounterStyle: RingCounterStyle(size: 60))));
      expect(tester.getSize(find.byType(RingCounter)), const Size.square(60));
      await tester.pumpWidget(_app(const RingCounter(to: 1),
          theme: const CountmanTheme(ringCounterStyle: RingCounterStyle(size: 70))));
      await tester.pump();
      expect(tester.getSize(find.byType(RingCounter)), const Size.square(70));
    });
  });

  group('copyWith / lerp', () {
    test('copyWith 只替换给定字段，== 按值', () {
      const a = CountmanTheme(ringCounterStyle: RingCounterStyle(size: 1));
      final b = a.copyWith(barCounterStyle: const BarCounterStyle(width: 2));
      expect(b.ringCounterStyle, const RingCounterStyle(size: 1));
      expect(b.barCounterStyle, const BarCounterStyle(width: 2));
      expect(a == const CountmanTheme(ringCounterStyle: RingCounterStyle(size: 1)), isTrue);
      expect(a == b, isFalse);
      expect(a.hashCode, const CountmanTheme(ringCounterStyle: RingCounterStyle(size: 1)).hashCode);
    });

    test('lerp：数值字段按 t 插值，其他类型返回自身', () {
      const a = CountmanTheme(
        ringCounterStyle: RingCounterStyle(size: 80, strokeWidth: 4, clockwise: true, color: Color(0xFF000000)),
        barCounterStyle: BarCounterStyle(width: 100, vertical: false),
        textCounterStyle: CountmanTextStyle(
            textStyle: TextStyle(fontSize: 10), padding: EdgeInsets.all(0), maxLines: 1),
        cardCountdownStyle: CardCountdownStyle(cardWidth: 40, splitDigits: false),
        dialCountdownStyle: DialCountdownStyle(size: 100, glow: false),
        odometerCounterStyle: OdometerCounterStyle(padding: EdgeInsets.all(2)),
        animatedCounterStyle: AnimatedCounterStyle(
            numberAlignment: -1, colorFadeDuration: Duration(milliseconds: 200)),
      );
      const b = CountmanTheme(
        ringCounterStyle: RingCounterStyle(size: 120, strokeWidth: 8, clockwise: false, color: Color(0xFFFFFFFF)),
        barCounterStyle: BarCounterStyle(width: 200, vertical: true),
        textCounterStyle: CountmanTextStyle(
            textStyle: TextStyle(fontSize: 30), padding: EdgeInsets.all(8), maxLines: 2),
        cardCountdownStyle: CardCountdownStyle(cardWidth: 80, splitDigits: true),
        dialCountdownStyle: DialCountdownStyle(size: 200, glow: true),
        odometerCounterStyle: OdometerCounterStyle(padding: EdgeInsets.all(6)),
        animatedCounterStyle: AnimatedCounterStyle(
            numberAlignment: 1, colorFadeDuration: Duration(milliseconds: 600)),
      );
      final quarter = a.lerp(b, 0.25);
      expect(quarter.ringCounterStyle!.size, 90);
      expect(quarter.ringCounterStyle!.strokeWidth, 5);
      expect(quarter.ringCounterStyle!.clockwise, isTrue, reason: 't<0.5 取前者');
      expect(quarter.ringCounterStyle!.color, Color.lerp(a.ringCounterStyle!.color, b.ringCounterStyle!.color, 0.25));
      expect(quarter.barCounterStyle!.width, 125);
      expect(quarter.barCounterStyle!.vertical, isFalse);
      expect(quarter.textCounterStyle!.textStyle!.fontSize, 15);
      expect(quarter.textCounterStyle!.padding, const EdgeInsets.all(2));
      expect(quarter.textCounterStyle!.maxLines, 1);
      expect(quarter.cardCountdownStyle!.cardWidth, 50);
      expect(quarter.cardCountdownStyle!.splitDigits, isFalse);
      expect(quarter.dialCountdownStyle!.size, 125);
      expect(quarter.dialCountdownStyle!.glow, isFalse);
      expect(quarter.odometerCounterStyle!.padding, const EdgeInsets.all(3));
      expect(quarter.animatedCounterStyle!.numberAlignment, -0.5);
      expect(quarter.animatedCounterStyle!.colorFadeDuration, const Duration(milliseconds: 300));

      final threeQuarter = a.lerp(b, 0.75);
      expect(threeQuarter.ringCounterStyle!.size, 110);
      expect(threeQuarter.ringCounterStyle!.clockwise, isFalse, reason: 't>=0.5 取后者');
      expect(threeQuarter.barCounterStyle!.vertical, isTrue);

      expect(a.lerp(null, 0.5), a);
      expect(a.lerp(a, 0.5), a);
    });

    test('lerp：任一端缺失（未设置）时按 t 取一端，不当成 0', () {
      const a = CountmanTheme(ringCounterStyle: RingCounterStyle(size: 80));
      const b = CountmanTheme();
      expect(a.lerp(b, 0.25).ringCounterStyle, const RingCounterStyle(size: 80));
      expect(a.lerp(b, 0.75).ringCounterStyle, isNull);
      // 样式内部字段一端缺失同理。
      final mixed = RingCounterStyle.lerp(const RingCounterStyle(size: 80), const RingCounterStyle(strokeWidth: 10), 0.25)!;
      expect(mixed.size, 80);
      expect(mixed.strokeWidth, isNull);
      expect(RingCounterStyle.lerp(null, null, 0.5), isNull);
    });

    testWidgets('AnimatedTheme 过渡中的中间值被应用', (tester) async {
      Widget build(double size) => MaterialApp(
            theme: ThemeData(extensions: [
              CountmanTheme(ringCounterStyle: RingCounterStyle(size: size)),
            ]),
            home: const Scaffold(body: Center(child: RingCounter(to: 1))),
          );
      await tester.pumpWidget(build(100));
      await tester.pumpWidget(build(200));
      await tester.pump(kThemeAnimationDuration ~/ 2);
      final mid = tester.getSize(find.byType(RingCounter)).width;
      expect(mid, greaterThan(100));
      expect(mid, lessThan(200));
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(RingCounter)), const Size.square(200));
    });
  });
}
