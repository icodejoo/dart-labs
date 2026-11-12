import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:countman/countman.dart';

import '../support/manual_clock.dart';
import 'package:countman/src/widgets/card_progress.dart';

// CardCountdown now paints via a single CustomPainter (see card_countdown.dart)
// instead of a per-digit widget subtree, so its digit content isn't reachable
// via find.text(). These tests exercise the public contract (onComplete, controller,
// plugin, `to`/showHours changes, dispose) and rely on Flutter's own
// leaked-Timer/Ticker detection at test teardown to catch a missing
// CardProgress.dispose() or CountdownHandle.cancel().

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: Center(child: child)));

/// 缓存生命周期用例共用的倒计时与推进间隔。
const _cacheDuration = Duration(seconds: 65);
const _cacheTick = Duration(seconds: 1);
const _cacheFrame = Duration(milliseconds: 100);
const _cacheTextStyle = TextStyle(fontSize: 23, color: Colors.indigo);
const _cacheLabelStyle = TextStyle(fontSize: 12, color: Colors.teal);
const _cacheSeparatorStyle = TextStyle(fontSize: 18, color: Colors.orange);

/// 从卡片子树获取画笔，避免依赖私有 State 的实现。
List<FlipCardPainter> _cardPainters(WidgetTester tester) => tester
    .widgetList<CustomPaint>(find.byType(CustomPaint))
    .map((widget) => widget.painter)
    .whereType<FlipCardPainter>()
    .toList();

/// 建立可保持 State 的显式样式卡片。
Widget _cacheCard({Key? key, TextStyle textStyle = _cacheTextStyle}) => CardCountdown(
    key: key,
    to: _cacheDuration,
    style: CardCountdownStyle(
      textStyle: textStyle,
      labelStyle: _cacheLabelStyle,
      separatorStyle: _cacheSeparatorStyle,
      transitionType: CountdownType.slide,
      scaleEffect: SlideEffect.both,
      opacityEffect: SlideEffect.both,
    ));

/// 收集当前三个角色持有的段落，便于卸载后检查原生资源释放。
List<TextPainter> _paragraphs(FlipCardPainter painter) => {
  ...painter.digitCache.values,
  ...painter.sepCache.values,
  ...painter.labelCache.values,
}.toList();

/// 使用真实画布验证本地引用没有指向已释放段落。
void _paintCard(FlipCardPainter painter) {
  final recorder = ui.PictureRecorder();
  try {
    painter.paint(Canvas(recorder), painter.geom.size);
  } finally {
    recorder.endRecording().dispose();
  }
}

void main() {
  late ManualCountmanClock clock;
  late void Function(Duration) advance;

  setUp(() {
    clock = installManualClock();
    advance = clock.advance;
  });


  group('CardCountdown', () {
    tearDown(Countman.destroy);

    testWidgets('相等显式样式跨卡共享，热重载与最后卸载成对释放', (t) async {
      final equalStyle = TextStyle(
          fontSize: _cacheTextStyle.fontSize, color: _cacheTextStyle.color);
      expect(equalStyle, _cacheTextStyle);
      expect(identical(equalStyle, _cacheTextStyle), isFalse);
      const firstKey = ValueKey('cache-first');
      const secondKey = ValueKey('cache-second');
      await t.pumpWidget(_wrap(Column(children: [
        _cacheCard(key: firstKey),
        _cacheCard(key: secondKey, textStyle: equalStyle),
      ])));
      final painters = _cardPainters(t);
      final cache = painters.first.digitCache;
      final initialParagraphs = _paragraphs(painters.first);
      expect(cache, same(painters.last.digitCache));
      expect(painters.first.sepCache, same(painters.last.sepCache));
      expect(painters.first.labelCache, same(painters.last.labelCache));

      final reassemble = t.binding.reassembleApplication();
      await t.pump();
      await reassemble;
      expect(_cardPainters(t).first.digitCache, same(cache));
      expect(initialParagraphs.map((p) => p.debugDisposed), everyElement(isFalse));

      await t.pumpWidget(_wrap(Column(children: [_cacheCard(key: secondKey)])));
      expect(_cardPainters(t).single.digitCache, same(cache));
      advance(_cacheTick);
      await t.pump(_cacheTick);
      await t.pump(_cacheFrame);
      _paintCard(_cardPainters(t).single);
      expect(t.takeException(), isNull);
      expect(initialParagraphs.map((p) => p.debugDisposed), everyElement(isFalse));

      final allParagraphs = _paragraphs(_cardPainters(t).single);
      await t.pumpWidget(_wrap(const SizedBox()));
      expect(allParagraphs, isNotEmpty);
      expect(allParagraphs.map((p) => p.debugDisposed), everyElement(isTrue));
      expect(cache, isEmpty);
      await t.pumpWidget(_wrap(_cacheCard()));
      expect(_cardPainters(t).single.digitCache, isNot(same(cache)));
    });

    testWidgets('样式切换先释放旧缓存，再获取新缓存', (t) async {
      await t.pumpWidget(_wrap(_cacheCard()));
      final cache = _cardPainters(t).single.digitCache;
      final oldParagraphs = cache.values.toList();
      await t.pumpWidget(_wrap(_cacheCard(textStyle: const TextStyle(color: Colors.red))));
      final painter = _cardPainters(t).single;
      expect(painter.digitCache, isNot(same(cache)));
      expect(cache, isEmpty);
      expect(oldParagraphs.map((p) => p.debugDisposed), everyElement(isTrue));
      _paintCard(painter);
      expect(t.takeException(), isNull);
    });

    testWidgets('样式切换保留另一张卡仍在使用的旧缓存', (t) async {
      const firstKey = ValueKey('switch-first');
      const secondKey = ValueKey('switch-second');
      await t.pumpWidget(_wrap(Column(children: [
        _cacheCard(key: firstKey), _cacheCard(key: secondKey),
      ])));
      final oldCache = _cardPainters(t).first.digitCache;
      final oldParagraphs = oldCache.values.toList();
      await t.pumpWidget(_wrap(Column(children: [
        _cacheCard(key: firstKey, textStyle: const TextStyle(color: Colors.red)),
        _cacheCard(key: secondKey),
      ])));
      expect(_cardPainters(t).last.digitCache, same(oldCache));
      expect(oldParagraphs.map((p) => p.debugDisposed), everyElement(isFalse));
      advance(_cacheTick);
      await t.pump(_cacheTick);
      await t.pump(_cacheFrame);
      expect(t.takeException(), isNull);
      await t.pumpWidget(_wrap(const SizedBox()));
      expect(oldParagraphs.map((p) => p.debugDisposed), everyElement(isTrue));
    });

    testWidgets('Provider 继承与显式样式切换不混淆缓存所有权', (t) async {
      /// 保持 Provider 与卡片的 State，只切换样式来源。
      Widget host(bool explicit) => _wrap(CardCountdownProvider(
        textStyle: _cacheTextStyle,
        labelStyle: _cacheLabelStyle,
        separatorStyle: _cacheSeparatorStyle,
        child: explicit ? _cacheCard() : const CardCountdown(to: _cacheDuration),
      ));
      await t.pumpWidget(host(true));
      final pooled = _cardPainters(t).single.digitCache;
      final pooledParagraphs = pooled.values.toList();
      await t.pumpWidget(host(false));
      final inherited = _cardPainters(t).single.digitCache;
      expect(inherited, isNot(same(pooled)));
      expect(pooledParagraphs.map((p) => p.debugDisposed), everyElement(isTrue));
      final inheritedParagraphs = inherited.values.toList();
      await t.pumpWidget(host(true));
      expect(_cardPainters(t).single.digitCache, isNot(same(inherited)));
      expect(inheritedParagraphs.map((p) => p.debugDisposed), everyElement(isFalse));
      await t.pumpWidget(_wrap(const SizedBox()));
      expect(inheritedParagraphs.map((p) => p.debugDisposed), everyElement(isTrue));
    });

    for (final mutation in ['clear', 'remove', 'replace', 'fifo']) {
      testWidgets('generation 在 $mutation 后使数字和标签引用失效', (t) async {
        await t.pumpWidget(_wrap(_cacheCard()));
        final painter = _cardPainters(t).single;
        painter.model
          ..target = painter.model.committed.map((digit) => (digit + 1) % 10).toList()
          ..changedMask = List.filled(painter.geom.cells.length, true);
        // ignore: invalid_use_of_internal_member
        (painter.controller as CardProgress).forward(from: .375);
        _paintCard(painter);
        final caches = {painter.digitCache, painter.sepCache, painter.labelCache};
        for (final map in caches) {
          final cache = map as CardGlyphCache;
          final generation = cache.generation;
          final key = cache.keys.first;
          switch (mutation) {
            case 'clear':
              cache.clear();
            case 'remove':
              cache.remove(key);
            case 'replace':
              cache[key] = TextPainter(
                text: TextSpan(text: key.$1, style: key.$2),
                textDirection: TextDirection.ltr,
              )..layout();
            case 'fifo':
              for (var i = 0; i < CardGlyphCache.capacity; i++) {
                final text = 'eviction-$i';
                cache[(text, key.$2)] = TextPainter(
                  text: TextSpan(text: text, style: key.$2),
                  textDirection: TextDirection.ltr,
                )..layout();
              }
          }
          expect(cache.generation, greaterThan(generation));
        }
        expect(() => _paintCard(painter), returnsNormally);
        await t.pump(_cacheFrame);
        expect(t.takeException(), isNull);
      });
    }

    testWidgets('renders and ticks down without throwing (merged digits)', (t) async {
      await t.pumpWidget(_wrap(const CardCountdown(to: Duration(seconds: 65))));
      await t.pump(); // initial

      for (var i = 0; i < 5; i++) {
        advance(const Duration(seconds: 1));
        await t.pump(const Duration(seconds: 1));
        await t.pump(const Duration(milliseconds: 500)); // let any transition settle
      }

      expect(t.takeException(), isNull);
      expect(find.byType(CardCountdown), findsOneWidget);
    });

    testWidgets('renders and ticks down without throwing (splitDigits)', (t) async {
      await t.pumpWidget(_wrap(const CardCountdown(
        to: Duration(seconds: 65),
        style: CardCountdownStyle(splitDigits: true),
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
      await t.pumpWidget(_wrap(CardCountdown(
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
      await t.pumpWidget(_wrap(CardCountdown(
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
      await t.pumpWidget(_wrap(CardCountdown(
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
      await t.pumpWidget(_wrap(CardCountdown(
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
      await t.pumpWidget(_wrap(const CardCountdown(to: Duration(hours: 1, seconds: 2))));
      await t.pump();
      final sizeWithHours = t.getSize(find.byType(CardCountdown));

      // Cross the 1h boundary — showHours (auto) should flip from true to false.
      advance(const Duration(seconds: 3));
      await t.pump(const Duration(seconds: 3));
      await t.pump(const Duration(milliseconds: 500));
      final sizeWithoutHours = t.getSize(find.byType(CardCountdown));

      expect(t.takeException(), isNull);
      expect(sizeWithoutHours.width, lessThan(sizeWithHours.width));
    });

    testWidgets('`to` change restarts without throwing', (t) async {
      Duration to = const Duration(seconds: 65);
      late StateSetter setState;

      await t.pumpWidget(_wrap(StatefulBuilder(builder: (_, s) {
        setState = s;
        return CardCountdown(to: to);
      })));
      await t.pump();

      setState(() => to = const Duration(seconds: 30));
      await t.pump();
      await t.pump(const Duration(milliseconds: 500));

      expect(t.takeException(), isNull);
    });

    testWidgets('disposes cleanly when removed mid-transition', (t) async {
      await t.pumpWidget(_wrap(const CardCountdown(to: Duration(seconds: 3))));
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

  group('CardCountdown slide transition', () {
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
          await t.pumpWidget(_wrap(CardCountdown(
            to: const Duration(seconds: 65),
            style: CardCountdownStyle(
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
      await t.pumpWidget(_wrap(CardCountdown(
        to: const Duration(seconds: 2),
        style: const CardCountdownStyle(
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
      await t.pumpWidget(_wrap(CardCountdown(
        to: const Duration(seconds: 10),
        style: const CardCountdownStyle(transitionType: CountdownType.slide),
        controller: ctrl,
      )));
      await t.pump();

      ctrl.pause();
      expect(ctrl.isPaused, isTrue);
      ctrl.resume();
      expect(ctrl.isPaused, isFalse);
    });

    testWidgets('disposes cleanly when removed mid-transition', (t) async {
      await t.pumpWidget(_wrap(const CardCountdown(
        to: Duration(seconds: 3),
        style: CardCountdownStyle(
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
      await t.pumpWidget(_wrap(const CardCountdown(
        to: Duration(seconds: 3),
        style: CardCountdownStyle(transitionType: CountdownType.slide),
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

  group('CardCountdown flip transition', () {
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
          await t.pumpWidget(_wrap(CardCountdown(
            to: const Duration(seconds: 65),
            style: CardCountdownStyle(
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
      await t.pumpWidget(_wrap(const CardCountdown(
        to: Duration(seconds: 65),
        style: CardCountdownStyle(
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
      await t.pumpWidget(_wrap(CardCountdown(
        to: const Duration(seconds: 2),
        style: const CardCountdownStyle(
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
      await t.pumpWidget(_wrap(const CardCountdown(
        to: Duration(seconds: 3),
        style: CardCountdownStyle(transitionType: CountdownType.flip),
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
      await t.pumpWidget(_wrap(const CardCountdown(
        to: Duration(seconds: 65),
        style: CardCountdownStyle(transitionType: CountdownType.flip),
      )));
      await t.pump();
      await tickThrough(t, seconds: 2);
      expect(t.takeException(), isNull);
    });

    testWidgets('disposes cleanly when removed mid-transition', (t) async {
      await t.pumpWidget(_wrap(const CardCountdown(
        to: Duration(seconds: 3),
        style: CardCountdownStyle(
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

  group('CardCountdownProvider', () {
    tearDown(Countman.destroy);

    testWidgets('card inherits cardWidth from an ancestor provider', (t) async {
      await t.pumpWidget(_wrap(const CardCountdown(to: Duration(seconds: 65))));
      await t.pump();
      final sizeNoProvider = t.getSize(find.byType(CardCountdown));

      await t.pumpWidget(_wrap(const CardCountdownProvider(
        cardWidth: 200,
        child: CardCountdown(to: Duration(seconds: 65)),
      )));
      await t.pump();
      final sizeWithProvider = t.getSize(find.byType(CardCountdown));

      expect(t.takeException(), isNull);
      expect(sizeWithProvider.width, greaterThan(sizeNoProvider.width));
    });

    testWidgets('card inherits transitionType/scaleEffect/opacityEffect from provider', (t) async {
      await t.pumpWidget(_wrap(const CardCountdownProvider(
        transitionType: CountdownType.slide,
        scaleEffect: SlideEffect.both,
        scaleFactor: 2.0,
        opacityEffect: SlideEffect.both,
        perspective: 0.02,
        child: CardCountdown(to: Duration(seconds: 65)),
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
      await t.pumpWidget(_wrap(const CardCountdownProvider(
        transitionType: CountdownType.slide,
        child: CardCountdown(
            to: Duration(seconds: 65),
            style: CardCountdownStyle(transitionType: CountdownType.calendar)),
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
      await t.pumpWidget(_wrap(const CardCountdownProvider(
        cardWidth: 200,
        child: CardCountdown(to: Duration(seconds: 65)),
      )));
      await t.pump();
      final inheritedSize = t.getSize(find.byType(CardCountdown));

      await t.pumpWidget(_wrap(const CardCountdownProvider(
        cardWidth: 200,
        child: CardCountdown(
            to: Duration(seconds: 65), style: CardCountdownStyle(cardWidth: 20)),
      )));
      await t.pump();
      final overriddenSize = t.getSize(find.byType(CardCountdown));

      expect(t.takeException(), isNull);
      expect(overriddenSize.width, lessThan(inheritedSize.width));
    });

    testWidgets('changing provider config rebuilds and relayouts descendant cards', (t) async {
      double providerCardWidth = 60;
      late StateSetter setState;

      await t.pumpWidget(_wrap(StatefulBuilder(builder: (_, s) {
        setState = s;
        return CardCountdownProvider(
          cardWidth: providerCardWidth,
          child: const CardCountdown(to: Duration(seconds: 65)),
        );
      })));
      await t.pump();
      final before = t.getSize(find.byType(CardCountdown));

      setState(() => providerCardWidth = 150);
      await t.pump();
      final after = t.getSize(find.byType(CardCountdown));

      expect(t.takeException(), isNull);
      expect(after.width, greaterThan(before.width));
    });

    testWidgets('multiple cards under one provider tick without throwing', (t) async {
      await t.pumpWidget(_wrap(CardCountdownProvider(
        cardColor: const Color(0xFF000000),
        textStyle: const TextStyle(fontSize: 20, color: Color(0xFFFFFFFF)),
        child: Column(
          children: [
            for (var i = 0; i < 5; i++) CardCountdown(to: Duration(seconds: 65 + i)),
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
      expect(find.byType(CardCountdown), findsNWidgets(5));
    });

    testWidgets('disposes cleanly when provider and cards are removed mid-flip', (t) async {
      await t.pumpWidget(_wrap(const CardCountdownProvider(
        child: CardCountdown(to: Duration(seconds: 3)),
      )));
      await t.pump();

      advance(const Duration(seconds: 1));
      await t.pump(const Duration(seconds: 1));
      await t.pump(const Duration(milliseconds: 100)); // mid-flip

      await t.pumpWidget(_wrap(const SizedBox())); // remove provider + card together
      await t.pump(const Duration(milliseconds: 500));

      expect(t.takeException(), isNull);
    });

    testWidgets('语义标签默认为 Countdown，可用 semanticsLabel 本地化', (t) async {
      final handle = t.ensureSemantics();
      await t.pumpWidget(_wrap(const CardCountdown(to: Duration(seconds: 65))));
      await t.pump();
      expect(find.bySemanticsLabel('Countdown'), findsOneWidget);

      await t.pumpWidget(_wrap(const CardCountdown(
        to: Duration(seconds: 65),
        semanticsLabel: '倒计时',
      )));
      await t.pump();
      expect(find.bySemanticsLabel('倒计时'), findsOneWidget);
      expect(find.bySemanticsLabel('Countdown'), findsNothing);

      Countman.destroy();
      handle.dispose();
    });
  });
}
