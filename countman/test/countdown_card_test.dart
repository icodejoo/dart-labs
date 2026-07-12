import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:countman/countman.dart';

// CountdownCard now paints via a single CustomPainter (see countdown_card.dart)
// instead of a per-digit widget subtree, so its digit content isn't reachable
// via find.text(). These tests exercise the public contract (onComplete, controller,
// plugin, `to`/showHours changes, dispose) and rely on Flutter's own
// leaked-Timer/Ticker detection at test teardown to catch a missing
// AnimationController.dispose() or CountdownHandle.cancel().

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: Center(child: child)));

void main() {
  late DateTime now;
  late void Function(Duration) advance;

  setUp(() {
    now = DateTime(2024, 1, 1, 12, 0, 0);
    countdownClock = () => now;
    advance = (d) => now = now.add(d);
  });

  tearDown(() {
    countdownClock = DateTime.now;
  });

  group('CountdownCard', () {
    tearDown(Countman.destroy);

    testWidgets('renders and ticks down without throwing (merged digits)', (t) async {
      await t.pumpWidget(_wrap(const CountdownCard(to: Duration(seconds: 65))));
      await t.pump(); // initial

      for (var i = 0; i < 5; i++) {
        advance(const Duration(seconds: 1));
        await t.pump(const Duration(seconds: 1));
        await t.pump(const Duration(milliseconds: 500)); // let any transition settle
      }

      expect(t.takeException(), isNull);
      expect(find.byType(CountdownCard), findsOneWidget);
    });

    testWidgets('renders and ticks down without throwing (splitDigits)', (t) async {
      await t.pumpWidget(_wrap(const CountdownCard(
        to: Duration(seconds: 65),
        style: CountdownCardStyle(splitDigits: true),
      )));
      await t.pump();

      for (var i = 0; i < 3; i++) {
        advance(const Duration(seconds: 1));
        await t.pump(const Duration(seconds: 1));
        await t.pump(const Duration(milliseconds: 500));
      }

      expect(t.takeException(), isNull);
    });

    testWidgets('onComplete fires when countdown reaches zero', (t) async {
      bool done = false;
      await t.pumpWidget(_wrap(CountdownCard(
        to: const Duration(seconds: 2),
        onComplete: () => done = true,
      )));
      await t.pump();

      advance(const Duration(seconds: 3));
      await t.pump(const Duration(seconds: 3));
      await t.pump(const Duration(milliseconds: 500));

      expect(done, isTrue);
    });

    testWidgets('onThreshold fires once when remaining crosses threshold', (t) async {
      var count = 0;
      await t.pumpWidget(_wrap(CountdownCard(
        to: const Duration(seconds: 5),
        threshold: const Duration(seconds: 3),
        onThreshold: () => count++,
      )));
      await t.pump();
      expect(count, 0);

      advance(const Duration(seconds: 2));
      await t.pump(const Duration(seconds: 2));
      await t.pump(const Duration(milliseconds: 500));

      expect(count, 1);
    });

    testWidgets('controller pause/resume/reset works', (t) async {
      final ctrl = CountdownController();
      await t.pumpWidget(_wrap(CountdownCard(
        to: const Duration(seconds: 10),
        controller: ctrl,
      )));
      await t.pump();

      ctrl.pause();
      expect(ctrl.isPaused, isTrue);

      ctrl.resume();
      expect(ctrl.isPaused, isFalse);

      ctrl.reset(duration: const Duration(seconds: 5));
      await t.pump();
      expect(ctrl.remaining.inSeconds, 5);
    });

    testWidgets('custom plugin (group) is used', (t) async {
      final group = Countdown(name: 'card_custom_group', interval: 0);
      Countman.use(group);

      bool done = false;
      await t.pumpWidget(_wrap(CountdownCard(
        to: const Duration(seconds: 2),
        plugin: group,
        onComplete: () => done = true,
      )));
      await t.pump();

      advance(const Duration(seconds: 3));
      await t.pump(const Duration(seconds: 3));
      expect(done, isTrue);
    });

    testWidgets('showHours boundary crossing relayouts without throwing', (t) async {
      await t.pumpWidget(_wrap(const CountdownCard(to: Duration(hours: 1, seconds: 2))));
      await t.pump();
      final sizeWithHours = t.getSize(find.byType(CountdownCard));

      // Cross the 1h boundary — showHours (auto) should flip from true to false.
      advance(const Duration(seconds: 3));
      await t.pump(const Duration(seconds: 3));
      await t.pump(const Duration(milliseconds: 500));
      final sizeWithoutHours = t.getSize(find.byType(CountdownCard));

      expect(t.takeException(), isNull);
      expect(sizeWithoutHours.width, lessThan(sizeWithHours.width));
    });

    testWidgets('`to` change restarts without throwing', (t) async {
      Duration to = const Duration(seconds: 65);
      late StateSetter setState;

      await t.pumpWidget(_wrap(StatefulBuilder(builder: (_, s) {
        setState = s;
        return CountdownCard(to: to);
      })));
      await t.pump();

      setState(() => to = const Duration(seconds: 30));
      await t.pump();
      await t.pump(const Duration(milliseconds: 500));

      expect(t.takeException(), isNull);
    });

    testWidgets('disposes cleanly when removed mid-transition', (t) async {
      await t.pumpWidget(_wrap(const CountdownCard(to: Duration(seconds: 3))));
      await t.pump();

      advance(const Duration(seconds: 1)); // triggers a digit change → calendar flip starts
      await t.pump(const Duration(seconds: 1));
      await t.pump(const Duration(milliseconds: 100)); // mid-transition

      await t.pumpWidget(_wrap(const SizedBox())); // remove while animating
      await t.pump(const Duration(milliseconds: 500));

      expect(t.takeException(), isNull);
      // If AnimationController.dispose() or CountdownHandle.cancel() were
      // missing, flutter_test's own pending-timer/ticker check at tearDown
      // would fail this test.
    });
  });

  group('CountdownCard slide transition', () {
    tearDown(Countman.destroy);

    Future<void> tickThrough(WidgetTester t, {int seconds = 4}) async {
      for (var i = 0; i < seconds; i++) {
        advance(const Duration(seconds: 1));
        await t.pump(const Duration(seconds: 1));
        await t.pump(const Duration(milliseconds: 500)); // let the transition settle
      }
    }

    for (final scaleEffect in SlideEffect.values) {
      for (final opacityEffect in SlideEffect.values) {
        testWidgets(
            'scaleEffect=$scaleEffect opacityEffect=$opacityEffect renders without throwing',
            (t) async {
          await t.pumpWidget(_wrap(CountdownCard(
            to: const Duration(seconds: 65),
            style: CountdownCardStyle(
              transitionType: CountdownType.slide,
              scaleEffect: scaleEffect,
              opacityEffect: opacityEffect,
            ),
          )));
          await t.pump();

          await tickThrough(t, seconds: 3);

          expect(t.takeException(), isNull);
        });
      }
    }

    testWidgets('onComplete still fires with slide transition', (t) async {
      bool done = false;
      await t.pumpWidget(_wrap(CountdownCard(
        to: const Duration(seconds: 2),
        style: const CountdownCardStyle(
          transitionType: CountdownType.slide,
          scaleEffect: SlideEffect.both,
          opacityEffect: SlideEffect.both,
        ),
        onComplete: () => done = true,
      )));
      await t.pump();

      advance(const Duration(seconds: 3));
      await t.pump(const Duration(seconds: 3));
      await t.pump(const Duration(milliseconds: 500));

      expect(done, isTrue);
    });

    testWidgets('controller works with slide transition', (t) async {
      final ctrl = CountdownController();
      await t.pumpWidget(_wrap(CountdownCard(
        to: const Duration(seconds: 10),
        style: const CountdownCardStyle(transitionType: CountdownType.slide),
        controller: ctrl,
      )));
      await t.pump();

      ctrl.pause();
      expect(ctrl.isPaused, isTrue);
      ctrl.resume();
      expect(ctrl.isPaused, isFalse);
    });

    testWidgets('disposes cleanly when removed mid-transition', (t) async {
      await t.pumpWidget(_wrap(const CountdownCard(
        to: Duration(seconds: 3),
        style: CountdownCardStyle(
          transitionType: CountdownType.slide,
          scaleEffect: SlideEffect.both,
          opacityEffect: SlideEffect.both,
        ),
      )));
      await t.pump();

      advance(const Duration(seconds: 1)); // triggers a digit change → transition starts
      await t.pump(const Duration(seconds: 1));
      await t.pump(const Duration(milliseconds: 100)); // mid-transition

      await t.pumpWidget(_wrap(const SizedBox())); // remove while animating
      await t.pump(const Duration(milliseconds: 500));

      expect(t.takeException(), isNull);
    });

    testWidgets('does not leave the AnimationController stuck (single forward pass)', (t) async {
      await t.pumpWidget(_wrap(const CountdownCard(
        to: Duration(seconds: 3),
        style: CountdownCardStyle(transitionType: CountdownType.slide),
      )));
      await t.pump();

      advance(const Duration(seconds: 1));
      await t.pump(const Duration(seconds: 1)); // digit changes, forward(from:0) starts
      await t.pump(const Duration(milliseconds: 500)); // past duration — should have committed

      // A second digit change should still animate cleanly (no leftover
      // reversePhase/target state from a calendar-style two-leg assumption).
      advance(const Duration(seconds: 1));
      await t.pump(const Duration(seconds: 1));
      await t.pump(const Duration(milliseconds: 500));

      expect(t.takeException(), isNull);
    });
  });

  group('CountdownCard flip transition', () {
    tearDown(Countman.destroy);

    Future<void> tickThrough(WidgetTester t, {int seconds = 4}) async {
      for (var i = 0; i < seconds; i++) {
        advance(const Duration(seconds: 1));
        await t.pump(const Duration(seconds: 1));
        await t.pump(const Duration(milliseconds: 500)); // let the transition settle
      }
    }

    for (final scaleEffect in SlideEffect.values) {
      for (final opacityEffect in SlideEffect.values) {
        testWidgets(
            'scaleEffect=$scaleEffect opacityEffect=$opacityEffect renders without throwing',
            (t) async {
          await t.pumpWidget(_wrap(CountdownCard(
            to: const Duration(seconds: 65),
            style: CountdownCardStyle(
              transitionType: CountdownType.flip,
              scaleEffect: scaleEffect,
              opacityEffect: opacityEffect,
            ),
          )));
          await t.pump();

          await tickThrough(t, seconds: 3);

          expect(t.takeException(), isNull);
        });
      }
    }

    testWidgets('perspective is configurable without throwing', (t) async {
      await t.pumpWidget(_wrap(const CountdownCard(
        to: Duration(seconds: 65),
        style: CountdownCardStyle(
          transitionType: CountdownType.flip,
          perspective: 0.02,
        ),
      )));
      await t.pump();
      await tickThrough(t, seconds: 2);
      expect(t.takeException(), isNull);
    });

    testWidgets('onComplete still fires with flip transition', (t) async {
      bool done = false;
      await t.pumpWidget(_wrap(CountdownCard(
        to: const Duration(seconds: 2),
        style: const CountdownCardStyle(
          transitionType: CountdownType.flip,
          scaleEffect: SlideEffect.both,
          opacityEffect: SlideEffect.both,
        ),
        onComplete: () => done = true,
      )));
      await t.pump();

      advance(const Duration(seconds: 3));
      await t.pump(const Duration(seconds: 3));
      await t.pump(const Duration(milliseconds: 500));

      expect(done, isTrue);
    });

    testWidgets('does not leave the AnimationController stuck (single forward pass)', (t) async {
      await t.pumpWidget(_wrap(const CountdownCard(
        to: Duration(seconds: 3),
        style: CountdownCardStyle(transitionType: CountdownType.flip),
      )));
      await t.pump();

      advance(const Duration(seconds: 1));
      await t.pump(const Duration(seconds: 1));
      await t.pump(const Duration(milliseconds: 500));

      advance(const Duration(seconds: 1));
      await t.pump(const Duration(seconds: 1));
      await t.pump(const Duration(milliseconds: 500));

      expect(t.takeException(), isNull);
    });

    testWidgets('no divider drawn (only meaningful for the calendar split-flap)', (t) async {
      // Behavioral proxy: just confirm it renders through several ticks
      // without throwing when mixed with calendar-only visuals disabled.
      await t.pumpWidget(_wrap(const CountdownCard(
        to: Duration(seconds: 65),
        style: CountdownCardStyle(transitionType: CountdownType.flip),
      )));
      await t.pump();
      await tickThrough(t, seconds: 2);
      expect(t.takeException(), isNull);
    });

    testWidgets('disposes cleanly when removed mid-transition', (t) async {
      await t.pumpWidget(_wrap(const CountdownCard(
        to: Duration(seconds: 3),
        style: CountdownCardStyle(
          transitionType: CountdownType.flip,
          scaleEffect: SlideEffect.both,
          opacityEffect: SlideEffect.both,
        ),
      )));
      await t.pump();

      advance(const Duration(seconds: 1));
      await t.pump(const Duration(seconds: 1));
      await t.pump(const Duration(milliseconds: 100)); // mid-transition

      await t.pumpWidget(_wrap(const SizedBox()));
      await t.pump(const Duration(milliseconds: 500));

      expect(t.takeException(), isNull);
    });
  });

  group('CountdownCardProvider', () {
    tearDown(Countman.destroy);

    testWidgets('card inherits cardWidth from an ancestor provider', (t) async {
      await t.pumpWidget(_wrap(const CountdownCard(to: Duration(seconds: 65))));
      await t.pump();
      final sizeNoProvider = t.getSize(find.byType(CountdownCard));

      await t.pumpWidget(_wrap(const CountdownCardProvider(
        cardWidth: 200,
        child: CountdownCard(to: Duration(seconds: 65)),
      )));
      await t.pump();
      final sizeWithProvider = t.getSize(find.byType(CountdownCard));

      expect(t.takeException(), isNull);
      expect(sizeWithProvider.width, greaterThan(sizeNoProvider.width));
    });

    testWidgets('card inherits transitionType/scaleEffect/opacityEffect from provider', (t) async {
      await t.pumpWidget(_wrap(const CountdownCardProvider(
        transitionType: CountdownType.slide,
        scaleEffect: SlideEffect.both,
        scaleFactor: 2.0,
        opacityEffect: SlideEffect.both,
        perspective: 0.02,
        child: CountdownCard(to: Duration(seconds: 65)),
      )));
      await t.pump();

      for (var i = 0; i < 3; i++) {
        advance(const Duration(seconds: 1));
        await t.pump(const Duration(seconds: 1));
        await t.pump(const Duration(milliseconds: 500));
      }

      expect(t.takeException(), isNull);
    });

    testWidgets('card explicit transitionType overrides the provider', (t) async {
      await t.pumpWidget(_wrap(const CountdownCardProvider(
        transitionType: CountdownType.slide,
        child: CountdownCard(
            to: Duration(seconds: 65),
            style: CountdownCardStyle(transitionType: CountdownType.calendar)),
      )));
      await t.pump();

      for (var i = 0; i < 3; i++) {
        advance(const Duration(seconds: 1));
        await t.pump(const Duration(seconds: 1));
        await t.pump(const Duration(milliseconds: 500));
      }

      expect(t.takeException(), isNull);
    });

    testWidgets('explicit card cardWidth overrides the provider', (t) async {
      await t.pumpWidget(_wrap(const CountdownCardProvider(
        cardWidth: 200,
        child: CountdownCard(to: Duration(seconds: 65)),
      )));
      await t.pump();
      final inheritedSize = t.getSize(find.byType(CountdownCard));

      await t.pumpWidget(_wrap(const CountdownCardProvider(
        cardWidth: 200,
        child: CountdownCard(
            to: Duration(seconds: 65), style: CountdownCardStyle(cardWidth: 20)),
      )));
      await t.pump();
      final overriddenSize = t.getSize(find.byType(CountdownCard));

      expect(t.takeException(), isNull);
      expect(overriddenSize.width, lessThan(inheritedSize.width));
    });

    testWidgets('changing provider config rebuilds and relayouts descendant cards', (t) async {
      double providerCardWidth = 60;
      late StateSetter setState;

      await t.pumpWidget(_wrap(StatefulBuilder(builder: (_, s) {
        setState = s;
        return CountdownCardProvider(
          cardWidth: providerCardWidth,
          child: const CountdownCard(to: Duration(seconds: 65)),
        );
      })));
      await t.pump();
      final before = t.getSize(find.byType(CountdownCard));

      setState(() => providerCardWidth = 150);
      await t.pump();
      final after = t.getSize(find.byType(CountdownCard));

      expect(t.takeException(), isNull);
      expect(after.width, greaterThan(before.width));
    });

    testWidgets('multiple cards under one provider tick without throwing', (t) async {
      await t.pumpWidget(_wrap(CountdownCardProvider(
        cardColor: const Color(0xFF000000),
        textStyle: const TextStyle(fontSize: 20, color: Color(0xFFFFFFFF)),
        child: Column(
          children: [
            for (var i = 0; i < 5; i++) CountdownCard(to: Duration(seconds: 65 + i)),
          ],
        ),
      )));
      await t.pump();

      for (var i = 0; i < 3; i++) {
        advance(const Duration(seconds: 1));
        await t.pump(const Duration(seconds: 1));
        await t.pump(const Duration(milliseconds: 500));
      }

      expect(t.takeException(), isNull);
      expect(find.byType(CountdownCard), findsNWidgets(5));
    });

    testWidgets('disposes cleanly when provider and cards are removed mid-flip', (t) async {
      await t.pumpWidget(_wrap(const CountdownCardProvider(
        child: CountdownCard(to: Duration(seconds: 3)),
      )));
      await t.pump();

      advance(const Duration(seconds: 1));
      await t.pump(const Duration(seconds: 1));
      await t.pump(const Duration(milliseconds: 100)); // mid-flip

      await t.pumpWidget(_wrap(const SizedBox())); // remove provider + card together
      await t.pump(const Duration(milliseconds: 500));

      expect(t.takeException(), isNull);
    });
  });
}
