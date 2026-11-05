import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mova/mova.dart';
import 'package:mova/src/ui/guard/guard_scope.dart';
import 'package:mova/src/ui/snapshot_guard.dart';

import '../../support/fake_bridge_api.dart';

// 保留旧替身契约；仅本文件模拟真实引擎的全屏状态回写。
class _Api extends FakeBridgeApi {
  @override
  Future<void> setFullscreen(bool value) async {
    await super.setFullscreen(value);
    push(state.copyWith(fullscreen: value));
  }
}

final _routePlayer = find.byWidgetPredicate(
  (w) => w is MovaPlayer && !w.fullscreenRoute,
);

Future<void> _settle(WidgetTester t) async {
  await t.pump();
  await t.pumpAndSettle(const Duration(milliseconds: 100));
}

Widget _app(
  _Api api, {
  bool enabled = true,
  MovaChrome? chrome,
  MovaPlayerStyle? style,
  Widget? surface,
  Widget Function(Widget)? wrap,
}) {
  Widget child = SizedBox(
    height: 260,
    child: MovaPlayer(
      api: api,
      chrome: chrome,
      fullscreenRoute: enabled,
      style: style,
      surface: surface,
    ),
  );
  if (wrap != null) child = wrap(child);
  return MaterialApp(home: Scaffold(body: child));
}

Future<void> _cleanup(WidgetTester t, _Api api) async {
  await api.setFullscreen(false);
  await _settle(t);
  await t.pumpWidget(const SizedBox.shrink());
  await t.pump();
  await api.dispose();
}

/// Verifies route ownership and fullscreen transitions.
///
/// 验证路由所有权与全屏转换。
void main() {
  testWidgets('E4 reentry during exit waits for the old GlobalKey route', (
    t,
  ) async {
    final api = _Api();
    final surfaceKey = GlobalKey();
    await t.pumpWidget(_app(api, surface: SizedBox(key: surfaceKey)));
    await api.setFullscreen(true);
    await _settle(t);
    await api.setFullscreen(false);
    await t.pump();
    await t.pump(const Duration(milliseconds: 30));
    await api.setFullscreen(true);
    await t.pump();
    expect(t.takeException(), isNull);
    expect(_routePlayer, findsOneWidget);
    await _settle(t);
    expect(api.state.fullscreen, isTrue);
    expect(_routePlayer, findsOneWidget);
    expect(find.byKey(surfaceKey), findsOneWidget);
    expect(t.takeException(), isNull);
    await _cleanup(t, api);
  });
  // surface 和 poster 的全局键都只能有一个挂载点，反复进入退出也不冲突。
  testWidgets('P2 全屏路由让出带 GlobalKey 的 surface 与 poster', (t) async {
    final api = _Api();
    final surfaceKey = GlobalKey();
    final posterKey = GlobalKey();
    await t.pumpWidget(
      MaterialApp(
        home: MovaPlayer(
          api: api,
          fullscreenRoute: true,
          surface: ColoredBox(key: surfaceKey, color: Colors.red),
          poster: ColoredBox(key: posterKey, color: Colors.blue),
        ),
      ),
    );
    for (var i = 0; i < 2; i++) {
      await api.setFullscreen(true);
      await _settle(t);
      expect(t.takeException(), isNull);
      expect(find.byKey(surfaceKey), findsOneWidget);
      expect(find.byKey(posterKey), findsOneWidget);
      expect(
        find.ancestor(of: find.byKey(surfaceKey), matching: _routePlayer),
        findsOneWidget,
      );
      await api.setFullscreen(false);
      await _settle(t);
      expect(t.takeException(), isNull);
      expect(find.byKey(surfaceKey), findsOneWidget);
      expect(find.byKey(posterKey), findsOneWidget);
    }
    await _cleanup(t, api);
  });
  testWidgets('默认关闭保持旧树与旧全屏调用，运行时开启接管已全屏状态', (t) async {
    final api = _Api();
    // 使用构造器默认值，关闭路径不增加 PopScope 或第二个视图。
    await t.pumpWidget(MaterialApp(home: MovaPlayer(api: api)));
    await api.setFullscreen(true);
    await _settle(t);
    expect(find.byType(MovaPlayer), findsOneWidget);
    expect(find.byType(PopScope<void>), findsNothing);
    expect(api.calls.where((c) => c == 'setFullscreen'), hasLength(1));
    await t.pumpWidget(_app(api));
    await _settle(t);
    expect(find.byType(MovaPlayer), findsNWidgets(2));
    expect(api.state.fullscreen, isTrue);
    await t.pumpWidget(_app(api, enabled: false));
    await _settle(t);
    expect(api.state.fullscreen, isFalse);
    expect(find.byType(MovaPlayer), findsOneWidget);
    await _cleanup(t, api);
  });

  testWidgets('返回只退出全屏、显示内联控制条且路由不重复探测清晰度', (t) async {
    final api = _Api();
    final chrome = MovaChrome();
    await t.pumpWidget(_app(api, chrome: chrome));
    chrome.hide();
    final probes = api.calls.where((c) => c == 'loadQualities').length;
    await api.setFullscreen(true);
    await _settle(t);
    expect(_routePlayer, findsOneWidget);
    expect(t.widget<MovaPlayer>(_routePlayer).autoLoadQualities, isFalse);
    expect(api.calls.where((c) => c == 'loadQualities'), hasLength(probes));
    expect(await t.binding.handlePopRoute(), isTrue);
    await _settle(t);
    expect(api.state.fullscreen, isFalse);
    expect(find.byType(MovaPlayer), findsOneWidget);
    expect(chrome.value.controlsVisible, isTrue);
    expect(find.byType(Scaffold), findsOneWidget);
    await _cleanup(t, api);
    chrome.dispose();
  });

  testWidgets('锁定返回保持全屏并使用视图文案提示解锁，样式直接继承', (t) async {
    final api = _Api();
    const style = MovaPlayerStyle(
      strings: MovaStrs(unlock: 'Unlock this view'),
      theme: MovaTheme(progressColor: 0xFF9C27B0),
    );
    await t.pumpWidget(_app(api, style: style));
    await api.setFullscreen(true);
    api.push(api.state.copyWith(locked: true));
    await _settle(t);
    expect(
      t.widget<MovaPlayer>(_routePlayer).style,
      style.copyWith(
        gesture: const MovaGestureConfig(),
        controls: const MovaCtrlsConfig(),
        danmaku: const MovaDanmakuStyle(),
        icons: const MovaIcons(),
      ),
    );
    await t.pumpWidget(
      _app(
        api,
        style: const MovaPlayerStyle(
          strings: MovaStrs(unlock: 'Unlock updated view'),
        ),
      ),
    );
    await _settle(t);
    await t.binding.handlePopRoute();
    await _settle(t);
    expect(api.state.fullscreen, isTrue);
    expect(find.text('Unlock updated view'), findsWidgets);
    expect(find.byType(MovaPlayer), findsNWidgets(2));
    api.push(api.state.copyWith(locked: false));
    await t.binding.handlePopRoute();
    await _settle(t);
    expect(api.state.fullscreen, isFalse);
    await _cleanup(t, api);
  });

  testWidgets('路由自建 chrome 独立播种与计时，退出唤出内联视图', (t) async {
    final api = _Api()..ready = true;
    final inline = MovaChrome();
    await t.pumpWidget(_app(api, chrome: inline));
    inline.show(sticky: true);
    await api.setFullscreen(true);
    await _settle(t);
    expect(api.sinks, hasLength(2));
    final context = t.element(
      find
          .descendant(of: _routePlayer, matching: find.byType(MouseRegion))
          .first,
    );
    final fullscreen = MovaChrome.of(context);
    expect(identical(fullscreen, inline), isFalse);
    expect(fullscreen.value.controlsVisible, isTrue);
    fullscreen.showHud(MovaHud.volume, text: 'route only');
    expect(inline.value.hud, MovaHud.none);
    await t.pump(const Duration(seconds: 4));
    expect(fullscreen.value.controlsVisible, isFalse);
    expect(inline.value.controlsVisible, isTrue);
    await api.setFullscreen(false);
    await _settle(t);
    expect(api.sinks, hasLength(1));
    expect(inline.value.controlsVisible, isTrue);
    await _cleanup(t, api);
    inline.dispose();
  });

  testWidgets('Windows 内联与全屏自定义 surface 都经过转场快照守卫', (t) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final api = _Api();
    const surface = ColoredBox(
      key: ValueKey('custom-surface'),
      color: Colors.red,
    );
    await t.pumpWidget(_app(api, surface: surface));
    await api.setFullscreen(true);
    await _settle(t);
    final surfaces = find.byKey(const ValueKey('custom-surface'));
    // 全屏期间内联侧让出，宿主 surface 仅由路由挂载一次。
    expect(surfaces, findsOneWidget);
    for (final element in surfaces.evaluate()) {
      final guard = element.findAncestorWidgetOfExactType<MovaSnapshotGuard>();
      expect(guard, isNotNull);
      expect(guard!.enabled, isTrue);
      final render = element
          .findAncestorRenderObjectOfType<RenderMovaSnapshotGuard>();
      expect(render!.alwaysNeedsCompositing, isTrue);
    }
    await t.binding.handlePopRoute();
    await _settle(t);
    expect(surfaces, findsOneWidget);
    expect(t.takeException(), isNull);
    await _cleanup(t, api);
    debugDefaultTargetPlatformOverride = null;
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('B13 自有全屏遮挡进出不暂停，路由继承后台守卫归属', (t) async {
    final api = _Api()..renderHandle = Object();
    api.push(const MovaState(playing: true, playbackIntent: true));
    final observer = RouteObserver<ModalRoute<dynamic>>();
    final innerObserver = RouteObserver<ModalRoute<dynamic>>();
    final root = GlobalKey<NavigatorState>();
    await t.pumpWidget(
      MaterialApp(
        navigatorKey: root,
        navigatorObservers: [observer],
        home: Navigator(
          observers: [innerObserver],
          onGenerateRoute: (_) => MaterialPageRoute<void>(
            builder: (_) => Scaffold(
              body: MovaAutoPause(
                api: api,
                config: const MovaAutoPauseConfig(background: false),
                routeObservers: [innerObserver, observer],
                child: SizedBox(
                  height: 260,
                  child: MovaPlayer(api: api, fullscreenRoute: true),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await api.setFullscreen(true);
    await _settle(t);
    final routeContext = t.element(
      find
          .descendant(of: _routePlayer, matching: find.byType(MouseRegion))
          .first,
    );
    expect(movaGuardedBy(routeContext, api), isTrue);
    expect(ModalRoute.of(routeContext)!.navigator, same(root.currentState));
    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ]) {
      t.binding.handleAppLifecycleStateChanged(state);
    }
    await _settle(t);
    expect(api.calls.where((c) => c == 'pause'), isEmpty);
    for (final state in [
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      t.binding.handleAppLifecycleStateChanged(state);
    }
    await api.setFullscreen(false);
    await _settle(t);
    expect(api.calls.where((c) => c == 'pause'), isEmpty);
    expect(api.state.playing, isTrue);
    final covered = root.currentState!.push<void>(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('ordinary page')),
      ),
    );
    await _settle(t);
    expect(api.calls.where((c) => c == 'pause'), hasLength(1));
    root.currentState!.pop();
    await _settle(t);
    await covered;
    await _cleanup(t, api);
  });

  testWidgets('换 API 与卸载只释放自有路由，方向退出仍走原 API', (t) async {
    final a = _Api(), b = _Api();
    await t.pumpWidget(_app(a));
    await a.setFullscreen(true);
    await _settle(t);
    expect(_routePlayer, findsOneWidget);
    await t.pumpWidget(_app(b));
    await _settle(t);
    expect(a.lastFullscreen, isFalse);
    expect(find.byType(MovaPlayer), findsOneWidget);
    expect(a.disposed, isFalse);
    await b.setFullscreen(true);
    await _settle(t);
    expect(_routePlayer, findsOneWidget);
    await t.pumpWidget(const SizedBox.shrink());
    await _settle(t);
    expect(b.lastFullscreen, isFalse);
    expect(b.disposed, isFalse);
    expect(t.takeException(), isNull);
    await a.dispose();
    await b.dispose();
  });

  testWidgets('同 API 多视图只推一次，PiP 与 mini 回流不抢路由或污染其他引擎', (t) async {
    final api = _Api(), other = _Api();
    await t.pumpWidget(
      MaterialApp(
        home: Column(
          children: [
            for (var i = 0; i < 2; i++)
              SizedBox(
                height: 250,
                child: MovaPlayer(api: api, fullscreenRoute: true),
              ),
          ],
        ),
      ),
    );
    await api.setFullscreen(true);
    await _settle(t);
    expect(_routePlayer, findsOneWidget);
    api.push(api.state.copyWith(fullscreen: false, pip: true));
    await _settle(t);
    expect(_routePlayer, findsNothing);
    expect(other.state.pip, isFalse);
    api.push(api.state.copyWith(pip: false));
    await _settle(t);
    expect(_routePlayer, findsNothing);
    await api.setFullscreen(true);
    await _settle(t);
    expect(_routePlayer, findsOneWidget);
    await api.setMini(true);
    await _settle(t);
    expect(_routePlayer, findsNothing);
    api.push(api.state.copyWith(mini: false, fullscreen: false));
    await _settle(t);
    expect(_routePlayer, findsNothing);
    expect(other.calls, isEmpty);
    await _cleanup(t, api);
    await other.dispose();
  });
}
