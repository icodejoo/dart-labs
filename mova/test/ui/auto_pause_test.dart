import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mova/src/core/guard/auto_pause.dart';
import 'package:mova/src/core/model/source.dart';
import 'package:mova/src/core/keep_alive/keep_alive.dart';
import 'package:mova/src/core/state/state.dart';
import 'package:mova/src/ui/guard/auto_pause.dart';
import 'package:mova/src/ui/view.dart';

import '../support/fake_api.dart';

const _cardKey = ValueKey('card');

/// A 100px-high guarded card.
///
/// 一张 100 像素高、带守卫的卡片。
Widget _card(
  FakeMovaApi api, {
  MovaAutoPauseConfig config = const MovaAutoPauseConfig(),
  List<RouteObserver<ModalRoute<dynamic>>> observers = const [],
}) =>
    MovaAutoPause(
      api: api,
      config: config,
      routeObservers: observers,
      child: const SizedBox(key: _cardKey, height: 100),
    );

/// How many times [name] was called on [api].
///
/// [api] 上 [name] 被调用的次数。
int _n(FakeMovaApi api, String name) => api.calls.where((c) => c == name).length;

/// Walks the app through [states] in order; Flutter's lifecycle listener
/// asserts on illegal jumps such as hidden -> resumed.
///
/// 依次让应用经过 [states]；Flutter 的生命周期监听会对 hidden -> resumed 这类非法
/// 跳变断言。
void _life(WidgetTester t, List<AppLifecycleState> states) {
  for (final s in states) {
    t.binding.handleAppLifecycleStateChanged(s);
  }
}

const _toBackground = [AppLifecycleState.inactive, AppLifecycleState.hidden];
const _toForeground = [AppLifecycleState.inactive, AppLifecycleState.resumed];

/// A 300px viewport holding the card followed by a long spacer.
///
/// 一个 300 像素的视口，里面是卡片加一段很长的占位。
Widget _list(FakeMovaApi api, ScrollController c, {MovaAutoPauseConfig config = const MovaAutoPauseConfig()}) =>
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          height: 300,
          child: ListView(controller: c, children: [_card(api, config: config), const SizedBox(height: 2000)]),
        ),
      ),
    );

/// A [FakeKeepAliveApi] whose first `setKeepAlive(true)` hangs until [gate] completes.
///
/// 第一次 `setKeepAlive(true)` 会挂起直到 [gate] 完成的 [FakeKeepAliveApi]。
class _SlowKeepAliveApi extends FakeKeepAliveApi {
  _SlowKeepAliveApi(this.gate);

  final Completer<void> gate;
  bool _held = false;

  @override
  Future<MovaKeepAlivePhase> setKeepAlive(bool on) async {
    calls.add('setKeepAlive:$on');
    if (on && !_held) {
      _held = true;
      await gate.future;
    }
    return on ? answerOn : MovaKeepAlivePhase.off;
  }
}

void main() {
  testWidgets('1. a card scrolled out of the viewport pauses; scrolled back it plays', (t) async {
    final api = FakeMovaApi()..push(const MovaState(playing: true));
    final c = ScrollController();
    addTearDown(c.dispose);
    await t.pumpWidget(_list(api, c));
    expect(api.calls, isEmpty);
    c.jumpTo(150);
    await t.pump();
    expect(_n(api, 'pause'), 1);
    c.jumpTo(0);
    await t.pump();
    expect(_n(api, 'play'), 1);
  });

  testWidgets('2. minVisibleFraction 0.5 pauses once less than half is visible', (t) async {
    final api = FakeMovaApi()..push(const MovaState(playing: true));
    final c = ScrollController();
    addTearDown(c.dispose);
    await t.pumpWidget(_list(api, c, config: const MovaAutoPauseConfig(minVisibleFraction: 0.5)));
    c.jumpTo(30);
    await t.pump();
    expect(_n(api, 'pause'), 0, reason: '70% still visible');
    c.jumpTo(70);
    await t.pump();
    expect(_n(api, 'pause'), 1, reason: '30% visible');
  });

  testWidgets('3. TickerMode disabled (an inactive shell branch) pauses; re-enabled plays', (t) async {
    final api = FakeMovaApi()..push(const MovaState(playing: true));
    Widget app(bool on) => MaterialApp(home: TickerMode(enabled: on, child: _card(api)));
    await t.pumpWidget(app(true));
    expect(api.calls, isEmpty);
    await t.pumpWidget(app(false));
    expect(_n(api, 'pause'), 1);
    await t.pumpWidget(app(true));
    expect(_n(api, 'play'), 1);
  });

  testWidgets('4. a route pushed on the same navigator pauses; popping it plays', (t) async {
    final api = FakeMovaApi()..push(const MovaState(playing: true));
    final nav = GlobalKey<NavigatorState>();
    await t.pumpWidget(MaterialApp(navigatorKey: nav, home: Scaffold(body: _card(api))));
    expect(api.calls, isEmpty);
    nav.currentState!.push(MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('top'))));
    await t.pumpAndSettle();
    expect(_n(api, 'pause'), 1);
    nav.currentState!.pop();
    await t.pumpAndSettle();
    expect(_n(api, 'play'), 1);
  });

  testWidgets('5. a non-opaque route on an outer navigator is only seen with a routeObserver', (t) async {
    // An opaque outer route is already caught by TickerMode (the overlay
    // disables tickers of what it covers); a translucent one — a dialog, a
    // transparent page — is not, and `ModalRoute.isCurrentOf` cannot see it.
    //
    // 不透明的外层路由已被 TickerMode 兜住（overlay 会禁用被盖住子树的 ticker）；
    // 半透明的——对话框、透明页——则不会，`ModalRoute.isCurrentOf` 也看不到。
    Route<void> translucent() => PageRouteBuilder<void>(
          opaque: false,
          pageBuilder: (_, _, _) => const SizedBox.expand(),
        );

    Future<(FakeMovaApi, GlobalKey<NavigatorState>)> mount(bool observed) async {
      // One observer per navigator: Flutter forbids sharing one between two.
      final outerObs = RouteObserver<ModalRoute<dynamic>>();
      final innerObs = RouteObserver<ModalRoute<dynamic>>();
      final api = FakeMovaApi()..push(const MovaState(playing: true));
      final outer = GlobalKey<NavigatorState>();
      await t.pumpWidget(
        MaterialApp(
          navigatorKey: outer,
          navigatorObservers: [if (observed) outerObs],
          home: Navigator(
            observers: [if (observed) innerObs],
            onGenerateRoute: (_) => MaterialPageRoute<void>(builder: (_) => Scaffold(body: _card(api, observers: [if (observed) outerObs, if (observed) innerObs]))),
          ),
        ),
      );
      return (api, outer);
    }

    final (blind, blindNav) = await mount(false);
    blindNav.currentState!.push(translucent());
    await t.pumpAndSettle();
    expect(_n(blind, 'pause'), 0, reason: 'documented limit: the inner route is still current');

    await t.pumpWidget(const SizedBox());
    final (api, nav) = await mount(true);
    nav.currentState!.push(translucent());
    await t.pumpAndSettle();
    expect(_n(api, 'pause'), 1);
    nav.currentState!.pop();
    await t.pumpAndSettle();
    expect(_n(api, 'play'), 1);
  });

  testWidgets('5b. an opaque route on an outer navigator is caught by TickerMode alone', (t) async {
    final api = FakeMovaApi()..push(const MovaState(playing: true));
    final outer = GlobalKey<NavigatorState>();
    await t.pumpWidget(
      MaterialApp(
        navigatorKey: outer,
        home: Navigator(
          onGenerateRoute: (_) => MaterialPageRoute<void>(builder: (_) => Scaffold(body: _card(api))),
        ),
      ),
    );
    outer.currentState!.push(MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('top'))));
    await t.pumpAndSettle();
    expect(_n(api, 'pause'), 1);
  });

  testWidgets('6. app lifecycle: hidden pauses, resumed plays', (t) async {
    final api = FakeMovaApi()..push(const MovaState(playing: true));
    await t.pumpWidget(MaterialApp(home: _card(api)));
    _life(t, _toBackground);
    await t.pump();
    expect(_n(api, 'pause'), 1);
    _life(t, _toForeground);
    await t.pump();
    expect(_n(api, 'play'), 1);
  });

  testWidgets('7. the system pausing during inactive does not lose the intent to resume', (t) async {
    final api = FakeMovaApi()..push(const MovaState(playing: true));
    await t.pumpWidget(MaterialApp(home: _card(api)));
    _life(t, [AppLifecycleState.inactive]);
    api.push(const MovaState(playing: false)); // Android reclaimed the surface and libmpv paused itself
    _life(t, [AppLifecycleState.hidden]);
    await t.pump();
    _life(t, _toForeground);
    await t.pump();
    expect(_n(api, 'play'), 1);
  });

  testWidgets('8. while in the mini window, going to the background does not pause', (t) async {
    final api = FakeMovaApi()..push(const MovaState(playing: true, mini: true));
    await t.pumpWidget(MaterialApp(home: _card(api)));
    _life(t, _toBackground);
    await t.pump();
    expect(_n(api, 'pause'), 0);
    _life(t, _toForeground);
    await t.pump();
    expect(_n(api, 'play'), 0);
  });

  testWidgets('9. a live source returning after the grace period jumps to the edge, then plays', (t) async {
    final api = FakeMovaApi()..push(const MovaState(playing: true, type: MovaStreamType.live));
    const cfg = MovaAutoPauseConfig(liveResumeGrace: Duration.zero);
    Widget app(bool on) => MaterialApp(home: TickerMode(enabled: on, child: _card(api, config: cfg)));
    await t.pumpWidget(app(true));
    await t.pumpWidget(app(false));
    expect(_n(api, 'pause'), 1);
    api.push(const MovaState(playing: false, type: MovaStreamType.live)); // what pause() really leaves behind
    await t.pumpWidget(app(true));
    await t.pump();
    await t.pump();
    expect(api.calls, ['pause', 'backToLiveEdge', 'play']);
  });

  testWidgets('10. after unmounting, lifecycle changes touch nothing', (t) async {
    final api = FakeMovaApi()..push(const MovaState(playing: true));
    await t.pumpWidget(MaterialApp(home: _card(api)));
    _life(t, _toBackground);
    await t.pump();
    _life(t, _toForeground); // frames are off while hidden, so unmount from the foreground
    await t.pump();
    await t.pumpWidget(const SizedBox());
    final before = List<String>.of(api.calls);
    _life(t, _toBackground);
    _life(t, _toForeground);
    await t.pump();
    expect(api.calls, before);
    expect(t.takeException(), isNull);
  });

  testWidgets('11. MovaView mounts the guard only when autoPause is given', (t) async {
    final made = <FakeMovaApi>[];
    Widget view({MovaAutoPauseConfig? autoPause}) => MaterialApp(
          home: MovaView(
            source: const MovaSource('https://a/1.mp4'),
            autoPause: autoPause,
            engineFactory: (o) {
              final api = FakeMovaApi(options: o);
              made.add(api);
              return api;
            },
          ),
        );
    await t.pumpWidget(view(autoPause: const MovaAutoPauseConfig()));
    await t.pump();
    expect(find.byType(MovaAutoPause), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    await t.pumpWidget(view());
    await t.pump();
    expect(find.byType(MovaAutoPause), findsNothing);
  });

  // ---- keepAlive (hiddenMode) ----

  const keepAliveCfg = MovaAutoPauseConfig(hiddenMode: MovaHiddenMode.keepAlive);
  const livePlaying = MovaState(playing: true, playbackIntent: true, type: MovaStreamType.live);

  testWidgets('13. keepAlive mode asks a capable engine to hold, then wake; it never pauses or plays', (t) async {
    final api = FakeKeepAliveApi()..push(livePlaying);
    Widget app(bool on) => MaterialApp(home: TickerMode(enabled: on, child: _card(api, config: keepAliveCfg)));
    await t.pumpWidget(app(true));
    await t.pumpWidget(app(false));
    await t.pump();
    expect(_n(api, 'setKeepAlive:true'), 1);
    await t.pumpWidget(app(true));
    await t.pump();
    expect(_n(api, 'setKeepAlive:false'), 1);
    expect(_n(api, 'pause'), 0);
    expect(_n(api, 'play'), 0);
  });

  testWidgets('14. an engine without the capability degrades to pause and play', (t) async {
    final api = FakeMovaApi()..push(livePlaying);
    Widget app(bool on) => MaterialApp(home: TickerMode(enabled: on, child: _card(api, config: keepAliveCfg)));
    await t.pumpWidget(app(true));
    await t.pumpWidget(app(false));
    await t.pump();
    expect(_n(api, 'pause'), 1);
    await t.pumpWidget(app(true));
    await t.pump();
    expect(_n(api, 'play'), 1);
  });

  testWidgets('15. backgrounding while held pauses (resumed -> inactive -> hidden)', (t) async {
    final api = FakeKeepAliveApi()..push(livePlaying);
    Widget app(bool on) => MaterialApp(home: TickerMode(enabled: on, child: _card(api, config: keepAliveCfg)));
    await t.pumpWidget(app(true));
    await t.pumpWidget(app(false));
    await t.pump();
    expect(_n(api, 'setKeepAlive:true'), 1);
    _life(t, _toBackground);
    await t.pump();
    expect(_n(api, 'pause'), 1);
    _life(t, _toForeground);
    await t.pump();
  });

  testWidgets('16. a play intent arriving while hidden holds it in keepAlive mode and pauses it in pause mode', (t) async {
    const idle = MovaState(type: MovaStreamType.live);
    final held = FakeKeepAliveApi()..push(idle);
    Widget app(FakeMovaApi api, MovaAutoPauseConfig cfg, bool on) =>
        MaterialApp(home: TickerMode(enabled: on, child: _card(api, config: cfg)));
    await t.pumpWidget(app(held, keepAliveCfg, true));
    await t.pumpWidget(app(held, keepAliveCfg, false));
    await t.pump();
    expect(held.calls, isEmpty);
    held.push(livePlaying);
    await t.pump();
    expect(_n(held, 'setKeepAlive:true'), 1);

    await t.pumpWidget(const SizedBox());
    final paused = FakeKeepAliveApi()..push(idle);
    await t.pumpWidget(app(paused, const MovaAutoPauseConfig(), true));
    await t.pumpWidget(app(paused, const MovaAutoPauseConfig(), false));
    await t.pump();
    paused.push(livePlaying);
    await t.pump();
    expect(_n(paused, 'pause'), 1);
    expect(_n(paused, 'setKeepAlive:true'), 0);
  });

  testWidgets('17. becoming visible while setKeepAlive(true) is still pending ends with a wake and no second hold', (t) async {
    final gate = Completer<void>();
    final api = _SlowKeepAliveApi(gate)..push(livePlaying);
    Widget app(bool on) => MaterialApp(home: TickerMode(enabled: on, child: _card(api, config: keepAliveCfg)));
    await t.pumpWidget(app(true));
    await t.pumpWidget(app(false));
    await t.pump();
    await t.pumpWidget(app(true));
    await t.pump();
    gate.complete();
    await t.pump();
    await t.pump();
    expect(api.calls.last, 'setKeepAlive:false');
    expect(_n(api, 'setKeepAlive:true'), 1);
  });

  testWidgets('18. MovaView with a keepAlive autoPause hands the hold to its engine', (t) async {
    final made = <FakeKeepAliveApi>[];
    await t.pumpWidget(
      MaterialApp(
        home: TickerMode(
          enabled: false,
          child: MovaView(
            source: const MovaSource('https://a/live.flv', type: MovaStreamType.live),
            autoPause: keepAliveCfg,
            engineFactory: (o) {
              final api = FakeKeepAliveApi(options: o)..push(livePlaying);
              made.add(api);
              return api;
            },
          ),
        ),
      ),
    );
    await t.pump();
    expect(made, hasLength(1));
    expect(_n(made.single, 'setKeepAlive:true'), 1);
  });
}
