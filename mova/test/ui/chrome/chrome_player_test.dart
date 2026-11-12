import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mova/mova.dart';

import '../../support/fake_api.dart';
import '../../support/fake_bridge_api.dart';

const _aKey = ValueKey('view-a');
const _bKey = ValueKey('view-b');

Widget _pair(MovaApi api, {MovaChrome? a, MovaChrome? b}) => MaterialApp(
  home: Column(
    children: [
      SizedBox(
        height: 280,
        child: MovaPlayer(key: _aKey, api: api, chrome: a),
      ),
      SizedBox(
        height: 280,
        child: MovaPlayer(key: _bKey, api: api, chrome: b),
      ),
    ],
  ),
);

Future<void> _tap(WidgetTester t, Key key) async {
  await t.tapAt(t.getCenter(find.byKey(key)) + const Offset(-100, 0));
  await t.pump(const Duration(milliseconds: 400));
  await t.pump();
}

List<double> _barOpacities(WidgetTester t, Key key) => t
    .widgetList<AnimatedOpacity>(
      find.descendant(
        of: find.byKey(key),
        matching: find.byType(AnimatedOpacity),
      ),
    )
    .map((w) => w.opacity)
    .toList();

Future<void> _unmount(WidgetTester t) async {
  await t.pumpWidget(const SizedBox.shrink());
  await t.pump(const Duration(milliseconds: 400));
}

void main() {
  testWidgets('同一引擎两个视图点击与控制条显隐独立', (t) async {
    final api = FakeBridgeApi();
    final a = MovaChrome(), b = MovaChrome();
    await t.pumpWidget(_pair(api, a: a, b: b));
    await _tap(t, _aKey);
    expect(a.value.controlsVisible, isFalse);
    expect(b.value.controlsVisible, isTrue);
    expect(_barOpacities(t, _aKey), contains(0));
    expect(_barOpacities(t, _bKey), everyElement(1));
    await _unmount(t);
    a.dispose();
    b.dispose();
    await api.dispose();
  });

  testWidgets('横滑只更新当前视图 HUD 和拖动预览', (t) async {
    final api = FakeBridgeApi();
    api.push(const MovaState(duration: Duration(seconds: 100)));
    final a = MovaChrome(), b = MovaChrome();
    await t.pumpWidget(_pair(api, a: a, b: b));
    await t.pump();
    final gesture = await t.startGesture(
      t.getCenter(find.byKey(_aKey)) + const Offset(-100, 0),
    );
    await gesture.moveBy(const Offset(100, 0));
    await t.pump();
    expect(a.value.dragging, isTrue);
    expect(a.value.previewAt, isNotNull);
    expect(a.value.hud, MovaHud.seek);
    expect(
      find.descendant(
        of: find.byKey(_aKey),
        matching: find.textContaining(':'),
      ),
      findsWidgets,
    );
    expect(b.value, const MovaUiState());
    expect(
      find.descendant(
        of: find.byKey(_bKey),
        matching: find.text(formatDuration(a.value.previewAt!)),
      ),
      findsNothing,
    );
    await gesture.up();
    await _unmount(t);
    a.dispose();
    b.dispose();
    await api.dispose();
  });

  testWidgets('旧动词广播到所有视图且常显不超时', (t) async {
    final api = FakeBridgeApi();
    final a = MovaChrome(), b = MovaChrome();
    await t.pumpWidget(_pair(api, a: a, b: b));
    api.hideControls();
    expect(a.value.controlsVisible, isFalse);
    expect(b.value.controlsVisible, isFalse);
    api.showControls(sticky: true);
    api.showHud(MovaHud.volume, text: 'x');
    api.setDragging(true, previewAt: const Duration(seconds: 3));
    expect(a.value, b.value);
    expect(a.value.hudText, 'x');
    expect(b.value.dragging, isTrue);
    api.setDragging(false);
    await t.pump(const Duration(seconds: 10));
    expect(a.value.controlsVisible, isTrue);
    expect(b.value.controlsVisible, isTrue);
    await _unmount(t);
    a.dispose();
    b.dispose();
    await api.dispose();
  });

  testWidgets('旧读者镜像以后变化的视图为准', (t) async {
    final api = FakeBridgeApi();
    final a = MovaChrome(), b = MovaChrome();
    await t.pumpWidget(_pair(api, a: a, b: b));
    await _tap(t, _aKey);
    expect(api.uiState.controlsVisible, isFalse);
    await _tap(t, _bKey);
    await _tap(t, _aKey);
    expect(api.uiState.controlsVisible, isTrue);
    expect(b.value.controlsVisible, isFalse);
    await _unmount(t);
    a.dispose();
    b.dispose();
    await api.dispose();
  });

  testWidgets('Ready 按各自配置显隐并开始自动隐藏', (t) async {
    for (final show in [true, false]) {
      final api = FakeBridgeApi(
        options: MovaOpts(controls: MovaCtrlsConfig(showOnStart: show)),
      );
      final a = MovaChrome(), b = MovaChrome();
      await t.pumpWidget(_pair(api, a: a, b: b));
      a.show(sticky: true);
      b.show(sticky: true);
      api.pushEvent(const MovaReady());
      await t.pump();
      expect(a.value.controlsVisible, show);
      expect(b.value.controlsVisible, show);
      await t.pump(const Duration(seconds: 3));
      expect(a.value.controlsVisible, isFalse);
      expect(b.value.controlsVisible, isFalse);
      await _unmount(t);
      a.dispose();
      b.dispose();
      await api.dispose();
    }
  });

  testWidgets('已就绪挂载立即计时，未就绪挂载等 Ready', (t) async {
    final ready = FakeBridgeApi()..ready = true, waiting = FakeBridgeApi();
    ready.pushUi(
      const MovaUiState(
        hud: MovaHud.seek,
        dragging: true,
        previewAt: Duration(seconds: 2),
      ),
    );
    final a = MovaChrome(), b = MovaChrome();
    await t.pumpWidget(
      MaterialApp(
        home: Column(
          children: [
            SizedBox(
              height: 280,
              child: MovaPlayer(api: ready, chrome: a),
            ),
            SizedBox(
              height: 280,
              child: MovaPlayer(api: waiting, chrome: b),
            ),
          ],
        ),
      ),
    );
    expect(a.value, const MovaUiState());
    await t.pump(const Duration(seconds: 10));
    expect(a.value.controlsVisible, isFalse);
    expect(b.value.controlsVisible, isTrue);
    waiting.pushEvent(const MovaReady());
    await t.pump();
    await t.pump(const Duration(seconds: 3));
    expect(b.value.controlsVisible, isFalse);
    await _unmount(t);
    a.dispose();
    b.dispose();
    await ready.dispose();
    await waiting.dispose();
  });

  testWidgets('默认 chrome 随视图销毁，借入实例可重新挂载', (t) async {
    final api = FakeBridgeApi();
    await t.pumpWidget(MaterialApp(home: MovaPlayer(api: api)));
    final owned = MovaChrome.of(t.element(find.byType(AnimatedOpacity).first));
    await _unmount(t);
    expect(api.sinks, isEmpty);
    expect(() => owned.addListener(() {}), throwsFlutterError);
    final last = await t.runAsync(
      () => owned.uiStates.toList().timeout(const Duration(seconds: 3)),
    );
    expect(last, [owned.value]);
    final borrowed = MovaChrome();
    await t.pumpWidget(
      MaterialApp(
        home: MovaPlayer(api: api, chrome: borrowed),
      ),
    );
    expect(api.sinks, hasLength(1));
    await _unmount(t);
    borrowed.hide();
    expect(borrowed.value.controlsVisible, isFalse);
    await t.pumpWidget(
      MaterialApp(
        home: MovaPlayer(api: api, chrome: borrowed),
      ),
    );
    expect(api.sinks, hasLength(1));
    await _unmount(t);
    borrowed.dispose();
    await api.dispose();
  });

  testWidgets('换 API 和 chrome 都解绑并重挂组件订阅', (t) async {
    final one = FakeBridgeApi(), two = FakeBridgeApi();
    final a = MovaChrome(), b = MovaChrome();
    Widget player(FakeBridgeApi api, MovaChrome chrome) => MaterialApp(
      home: MovaPlayer(api: api, chrome: chrome),
    );
    await t.pumpWidget(player(one, a));
    await t.pumpWidget(player(two, a));
    expect(one.sinks, isEmpty);
    expect(two.sinks, hasLength(1));
    one.hideControls();
    expect(a.value.controlsVisible, isTrue);
    await t.pumpWidget(player(two, b));
    expect(two.sinks, hasLength(1));
    a.hide();
    await t.pump();
    expect(
      t
          .widgetList<AnimatedOpacity>(find.byType(AnimatedOpacity))
          .map((w) => w.opacity),
      everyElement(1),
    );
    b.hide();
    await t.pump();
    await t.pump();
    expect(
      t
          .widgetList<AnimatedOpacity>(find.byType(AnimatedOpacity))
          .map((w) => w.opacity),
      contains(0),
    );
    await _unmount(t);
    a.dispose();
    b.dispose();
    await one.dispose();
    await two.dispose();
  });

  testWidgets('真实 cutover 换指及影子 Ready 重放不重置交互态', (t) async {
    Future<T> settle<T>(Future<T> future) async {
      var done = false;
      future.then((_) => done = true);
      for (var i = 0; i < 20 && !done; i++) {
        await t.pump();
        await t.runAsync(() => Future<void>.delayed(Duration.zero));
      }
      expect(done, isTrue, reason: '假引擎操作应在微任务推进后结束');
      return future;
    }

    final made = <FakeBridgeApi>[];
    final proxy = MovaCutoverEngine(
      engineFactory: () {
        final f = FakeBridgeApi(
          options: const MovaOpts(cutover: MovaCutoverConfig(enabled: true)),
        );
        made.add(f);
        return f;
      },
    );
    final c = MovaChrome();
    await t.pumpWidget(
      MaterialApp(
        home: MovaPlayer(key: _aKey, api: proxy, chrome: c),
      ),
    );
    await _tap(t, _aKey);
    final seen = <MovaUiState>[];
    final sub = c.uiStates.listen(seen.add);
    await t.pump();
    seen.clear();
    await settle(
      proxy.prepare(
        const MovaSource('https://host/b.mp4'),
        cue: const MovaWarmCue(
          remaining: Duration(seconds: 1),
          total: Duration(seconds: 10),
        ),
      ),
    );
    made[1].ready = true;
    made[1].pushEvent(const MovaReady());
    await t.pump();
    const tick = MovaProg(
      position: Duration(seconds: 5),
      buffer: Duration(seconds: 6),
    );
    made[1].pushProgress(tick);
    await t.pump();
    made[1].pushProgress(tick);
    await t.pump();
    expect(await settle(proxy.commit()), isTrue);
    made[1].pushUi(const MovaUiState());
    await t.pump();
    await t.pump();
    expect(proxy.state.renderEpoch, 1);
    expect(c.value.controlsVisible, isFalse);
    expect(proxy.uiState.controlsVisible, isFalse);
    expect(seen, isEmpty);
    expect(_barOpacities(t, _aKey), contains(0));
    await settle(sub.cancel());
    await _unmount(t);
    c.dispose();
    await settle(proxy.dispose());
  });

  testWidgets('非桥接 API 默认保持旧路径，显式 chrome 才启用', (t) async {
    final api = FakeMovaApi();
    await t.pumpWidget(
      MaterialApp(
        home: MovaPlayer(key: _aKey, api: api),
      ),
    );
    expect(
      MovaChrome.maybeOf(t.element(find.byType(AnimatedOpacity).first)),
      isNull,
    );
    await _tap(t, _aKey);
    expect(api.calls, contains('hideControls'));
    final c = MovaChrome();
    await t.pumpWidget(
      MaterialApp(
        home: MovaPlayer(key: _aKey, api: api, chrome: c),
      ),
    );
    api.calls.clear();
    await _tap(t, _aKey);
    expect(c.value.controlsVisible, isFalse);
    expect(api.calls, isEmpty);
    await _unmount(t);
    c.dispose();
    await api.dispose();
  });
}
