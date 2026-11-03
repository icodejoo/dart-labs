import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mova/mova.dart';

import '../support/fake_api.dart';

/// 有画面且有播放意图；内核观测可独立滞后。
FakeMovaApi _api({bool playing = false, bool pip = false, bool video = true}) =>
    FakeMovaApi()
      ..renderHandle = video ? Object() : null
      ..push(MovaState(playbackIntent: true, playing: playing, pip: pip));

/// 使用默认渲染路径，避免真实 VideoController 或媒体后端。
Widget _player(FakeMovaApi api, {Widget? surface}) => MovaPlayer(
  api: api,
  autoLoadQualities: false,
  skin: const MovaMinimalSkin(),
  surface: surface,
);

/// 合法走回前台，供测试隔离与无自动恢复断言使用。
void _foreground(WidgetTester t) {
  if (t.binding.lifecycleState == AppLifecycleState.paused) {
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
  }
  if (t.binding.lifecycleState == AppLifecycleState.hidden) {
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  }
  if (t.binding.lifecycleState != AppLifecycleState.resumed) {
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  }
}

/// 按合法顺序进入后台；hidden 本身不触发播放器的兜底暂停。
void _background(WidgetTester t) {
  for (final state in [AppLifecycleState.inactive, AppLifecycleState.hidden, AppLifecycleState.paused]) {
    t.binding.handleAppLifecycleStateChanged(state);
  }
}

/// 挂载后清空准备阶段日志；退出时先拆监听再恢复测试生命周期。
Future<void> _mount(WidgetTester t, Widget child, List<FakeMovaApi> apis) async {
  _foreground(t);
  await t.pumpWidget(MaterialApp(home: SizedBox(width: 320, height: 180, child: child)));
  await t.pump();
  for (final api in apis) { api.calls.clear(); }
  addTearDown(() async {
    await t.pumpWidget(const SizedBox.shrink());
    _foreground(t);
    for (final api in apis) { await api.dispose(); }
  });
}

void main() {
  testWidgets('无守卫切后台：经 api.pause() 暂停、意图为假', (t) async {
    final api = _api();
    await _mount(t, _player(api), [api]);
    _background(t);
    await t.pump();
    expect(api.calls.where((c) => c == 'pause'), hasLength(1));
    expect(api.state.playbackIntent, isFalse);
    // detached 同样经过引擎；用独立播放意图验证这个入口。
    await api.play();
    api.calls.clear();
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.detached);
    await t.pump();
    expect(api.calls.where((c) => c == 'pause'), hasLength(1));
  });

  testWidgets('inactive/hidden 不动作', (t) async {
    final api = _api();
    await _mount(t, _player(api), [api]);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    await t.pump();
    expect(api.calls, isNot(contains('pause')));
    expect(api.state.playbackIntent, isTrue);
  });

  testWidgets('回前台不自动续播', (t) async {
    final api = _api();
    await _mount(t, _player(api), [api]);
    _background(t);
    await t.pump();
    expect(api.state.playbackIntent, isFalse);
    _foreground(t);
    await t.pump();
    expect(api.calls, isNot(contains('play')));
  });

  testWidgets('祖先守卫接管同一 api 时 MovaPlayer 不动作', (t) async {
    final api = _api(playing: true);
    await _mount(t, MovaAutoPause(api: api, child: _player(api)), [api]);
    _background(t);
    await t.pump();
    expect(api.calls.where((c) => c == 'pause'), hasLength(1));
    _foreground(t);
    await t.pump();
    await api.play();
    await t.pumpWidget(MaterialApp(home: MovaAutoPause(
      api: api,
      config: const MovaAutoPauseConfig(background: false),
      child: _player(api),
    )));
    await t.pump();
    api.calls.clear();
    _background(t);
    await t.pump();
    expect(api.calls, isNot(contains('pause')));
    expect(api.state.playbackIntent, isTrue);
  });

  testWidgets('祖先守卫管的是别的 api 时照常暂停', (t) async {
    final outer = _api();
    final inner = _api();
    await _mount(t, MovaAutoPause(api: outer, child: _player(inner)), [outer, inner]);
    _background(t);
    await t.pump();
    expect(inner.calls.where((c) => c == 'pause'), hasLength(1));
    expect(inner.state.playbackIntent, isFalse);
  });

  testWidgets('系统画中画中不暂停', (t) async {
    final api = _api(pip: true);
    await _mount(t, _player(api), [api]);
    _background(t);
    await t.pump();
    expect(api.calls, isNot(contains('pause')));
    expect(api.state.playbackIntent, isTrue);
  });

  testWidgets('audioOnly（无渲染面）后台继续播', (t) async {
    final api = _api(video: false);
    await _mount(t, _player(api), [api]);
    _background(t);
    await t.pump();
    expect(api.calls, isNot(contains('pause')));
    expect(api.state.playbackIntent, isTrue);
    // lazy VideoController 挂载后才出现，也应在下一次后台事件暂停。
    _foreground(t);
    api.renderHandle = Object();
    _background(t);
    await t.pump();
    expect(api.calls.where((c) => c == 'pause'), hasLength(1));
    _foreground(t);
    await api.play();
    await t.pumpWidget(MaterialApp(home: _player(api, surface: const SizedBox.shrink())));
    api.calls.clear();
    _background(t);
    await t.pump();
    expect(api.calls, isNot(contains('pause')));
  });

  testWidgets('同一 api 挂两个 MovaPlayer 只暂停一次', (t) async {
    final api = _api(playing: true);
    await _mount(t, Column(children: [Expanded(child: _player(api)), Expanded(child: _player(api))]), [api]);
    _background(t);
    await t.pump();
    expect(api.calls.where((c) => c == 'pause'), hasLength(1));
    expect(api.state.playbackIntent, isFalse);
  });

  test('Video 关闭自带后台暂停（源码守卫）', () {
    final source = File('lib/src/ui/player.dart').readAsStringSync();
    final video = source.substring(source.indexOf('? Video('), source.indexOf(': ColoredBox(', source.indexOf('? Video(')));
    expect(video, contains('pauseUponEnteringBackgroundMode: false'));
    expect(video, contains('resumeUponEnteringForegroundMode: false'));
  });
}
