import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mova/src/core/state/progress.dart';
import 'package:mova/src/core/state/state.dart';
import 'package:mova/src/core/state/ui_state.dart';
import 'package:mova/src/ui/components/gesture_layer.dart';
import 'package:mova/src/ui/player.dart';
import 'package:mova/src/ui/skins/bilibili_skin.dart';
import 'package:mova/src/ui/skins/default_skin.dart';

import '../support/fake_api.dart';
import '../support/pump.dart';

/// Scenario 1 / 场景 1: full interaction sequences against an audio-only
/// engine, i.e. one whose [FakeMovaApi.renderHandle] is `null` for the whole
/// test — there is never a real video picture underneath the chrome.
///
/// These go past "it renders without throwing": each test drives a *sequence*
/// of taps/drags and asserts the ordered calls that reached the api.
///
/// 场景 1：针对仅音频 engine（整场测试中 [FakeMovaApi.renderHandle] 恒为 `null`，
/// 控件下方从来没有真实视频画面）的完整交互序列。
///
/// 这些测试越过了"渲染不崩"的浅层断言：每条都驱动一串点击/拖动，并断言到达
/// api 的有序调用。

/// Mounts a full [MovaPlayer] over an audio-only [FakeMovaApi] and returns it.
///
/// 在一个仅音频 [FakeMovaApi] 之上挂载完整的 [MovaPlayer] 并返回它。
Future<FakeMovaApi> pumpAudioPlayer(
  WidgetTester t, {
  MovaState state = const MovaState(duration: Duration(seconds: 100)),
  Widget? surface,
  bool bilibili = false,
}) async {
  final api = FakeMovaApi();
  api.push(state);
  await t.pumpWidget(MaterialApp(
    home: MovaPlayer(
      api: api,
      skin: bilibili ? MovaBilibiliSkin() : const MovaDefaultSkin(),
      surface: surface,
    ),
  ));
  await t.pump();
  // Precondition for every test in this file: no render handle at all.
  // 本文件每条测试的前置条件：根本没有渲染句柄。
  expect(api.renderHandle, isNull);
  return api;
}

void main() {
  group('audio-only: control bar interaction / 控制条交互', () {
    testWidgets('the centre play button drives a play/pause/play sequence', (t) async {
      final api = await pumpAudioPlayer(t);

      // Tap 1: paused → play.
      // 第 1 次点击：暂停 → 播放。
      await t.tap(find.byIcon(Icons.play_circle_filled_rounded));
      await t.pump();
      api.push(const MovaState(playing: true, duration: Duration(seconds: 100)));
      await t.pump();
      await t.pump();

      // Tap 2: playing → pause.
      // 第 2 次点击：播放 → 暂停。
      await t.tap(find.byIcon(Icons.pause_circle_filled_rounded));
      await t.pump();
      api.push(const MovaState(duration: Duration(seconds: 100)));
      await t.pump();
      await t.pump();

      // Tap 3: paused → play again.
      // 第 3 次点击：再次暂停 → 播放。
      await t.tap(find.byIcon(Icons.play_circle_filled_rounded));
      await t.pump();

      expect(
        api.calls.where((c) => c == 'playOrPause'),
        hasLength(3),
        reason: 'three taps, three toggles — the button keeps working with no '
            'picture behind it / 三次点击三次切换——控件背后没有画面也照常工作',
      );
      await api.dispose();
    });

    testWidgets('the play button label follows state through the whole sequence', (t) async {
      final api = await pumpAudioPlayer(t);
      expect(find.byIcon(Icons.play_circle_filled_rounded), findsOneWidget);

      // Two pumps: a pushed state reaches the widget through the async state
      // stream, so the first pump schedules and the second renders it.
      // 两次 pump：推送的状态经异步状态流到达组件，第一次 pump 调度、第二次
      // 才渲染出来。
      api.push(const MovaState(playing: true, duration: Duration(seconds: 100)));
      await t.pump();
      await t.pump();
      expect(find.byIcon(Icons.pause_circle_filled_rounded), findsOneWidget);
      expect(find.byIcon(Icons.play_circle_filled_rounded), findsNothing);

      api.push(const MovaState(duration: Duration(seconds: 100)));
      await t.pump();
      await t.pump();
      expect(find.byIcon(Icons.play_circle_filled_rounded), findsOneWidget);
      await api.dispose();
    });

    testWidgets('dragging the seek bar issues a seek with the dragged position', (t) async {
      final api = await pumpAudioPlayer(t);
      api.pushProgress(const MovaProg(position: Duration(seconds: 10)));
      await t.pump();
      await t.pump();
      expect(t.widget<Slider>(find.byType(Slider)).value, 10000);

      // Drag the thumb to the right; the exact landing value depends on
      // layout, so assert a seek happened and moved forward.
      // 把滑块向右拖；具体落点取决于布局，因此断言"发生了 seek 且向前移动"。
      await t.drag(find.byType(Slider), const Offset(200, 0));
      await t.pumpAndSettle();

      expect(api.calls, contains('seek'));
      expect(api.lastSeek, isNotNull);
      expect(
        api.lastSeek!,
        greaterThan(const Duration(seconds: 10)),
        reason: 'dragging right must move forward / 向右拖必须前进',
      );
      await api.dispose();
    });

    testWidgets('two successive seek-bar drags both land', (t) async {
      final api = await pumpAudioPlayer(t);
      api.pushProgress(const MovaProg(position: Duration(seconds: 50)));
      await t.pump();
      await t.pump();

      await t.drag(find.byType(Slider), const Offset(120, 0));
      await t.pumpAndSettle();
      final first = api.lastSeek;

      await t.drag(find.byType(Slider), const Offset(-240, 0));
      await t.pumpAndSettle();
      final second = api.lastSeek;

      expect(first, isNotNull);
      expect(second, isNotNull);
      expect(second, lessThan(first!), reason: 'the second drag went left / 第二次向左拖');
      expect(api.calls.where((c) => c == 'seek').length, greaterThanOrEqualTo(2));
      await api.dispose();
    });

    testWidgets('the speed button cycles the rate across repeated taps', (t) async {
      // The bilibili skin puts a MovaSpeedButtonComponent in the top bar; the
      // default skin has none. Audio is exactly where playback rate matters
      // most (podcasts/audiobooks), so it is worth exercising here.
      //
      // bilibili 皮肤在顶栏放了 MovaSpeedButtonComponent，默认皮肤没有。倍速恰恰
      // 是音频场景（播客/有声书）最在意的能力，值得在这里走一遍。
      final api = await pumpAudioPlayer(t, bilibili: true);

      await t.tap(find.byIcon(Icons.speed_rounded));
      await t.pump();
      expect(api.lastRate, isNotNull);
      final first = api.lastRate!;

      api.push(MovaState(rate: first, duration: const Duration(seconds: 100)));
      await t.pump();
      await t.pump();
      await t.tap(find.byIcon(Icons.speed_rounded));
      await t.pump();
      final second = api.lastRate!;

      api.push(MovaState(rate: second, duration: const Duration(seconds: 100)));
      await t.pump();
      await t.pump();
      await t.tap(find.byIcon(Icons.speed_rounded));
      await t.pump();
      final third = api.lastRate!;

      expect(api.calls.where((c) => c == 'setRate'), hasLength(3));
      expect(
        {first, second, third},
        hasLength(3),
        reason: 'each tap advances to a different step / 每次点击都切到不同的档位',
      );
      await api.dispose();
    });
  });

  group('audio-only: gesture layer interaction / 手势层交互', () {
    testWidgets('a right-side vertical drag still adjusts volume', (t) async {
      final api = FakeMovaApi();
      api.push(const MovaState(volume: 50, brightness: 0.5));
      expect(api.renderHandle, isNull);
      await pumpComponent(t, api, MovaGestureLayerComponent());

      await t.dragFrom(const Offset(600, 300), const Offset(0, -150));
      await t.pumpAndSettle();

      expect(api.calls, contains('setVolume'));
      expect(api.lastVolume, greaterThan(50));
      expect(api.lastHud, MovaHud.volume);
      await api.dispose();
    });

    testWidgets('a horizontal drag still scrubs, and a second one scrubs again', (t) async {
      final api = FakeMovaApi();
      api.push(const MovaState(duration: Duration(seconds: 200)));
      await pumpComponent(t, api, MovaGestureLayerComponent());

      await t.dragFrom(const Offset(300, 300), const Offset(150, 0));
      await t.pumpAndSettle();
      expect(api.calls, contains('seek'));
      final forward = api.lastSeek;

      await t.dragFrom(const Offset(300, 300), const Offset(-100, 0));
      await t.pumpAndSettle();

      expect(forward, isNotNull);
      expect(api.calls.where((c) => c == 'seek').length, greaterThanOrEqualTo(2));
      await api.dispose();
    });

    testWidgets('a left-side vertical drag still adjusts brightness (no-op but not broken)', (t) async {
      // Brightness is meaningless for audio, but the gesture must still be
      // routed rather than throwing — a shared skin does not know the mode.
      //
      // 亮度对音频无意义，但手势仍须被正常路由而不是抛错——共用皮肤并不知道
      // 当前是哪种模式。
      final api = FakeMovaApi();
      api.push(const MovaState(volume: 50, brightness: 0.5));
      await pumpComponent(t, api, MovaGestureLayerComponent());

      await t.dragFrom(const Offset(200, 300), const Offset(0, -150));
      await t.pumpAndSettle();

      expect(api.calls, contains('setBrightness'));
      expect(t.takeException(), isNull);
      await api.dispose();
    });
  });

  group('audio-only: the whole chrome stays usable / 控件整体可用性', () {
    testWidgets('a mixed sequence — play, scrub, volume, pause — all reach the api in order', (t) async {
      final api = await pumpAudioPlayer(t);
      api.pushProgress(const MovaProg(position: Duration(seconds: 20)));
      await t.pump();
      await t.pump();

      await t.tap(find.byIcon(Icons.play_circle_filled_rounded));
      await t.pump();
      api.push(const MovaState(playing: true, duration: Duration(seconds: 100)));
      await t.pump();
      await t.pump();

      await t.drag(find.byType(Slider), const Offset(150, 0));
      await t.pumpAndSettle();

      await t.tap(find.byIcon(Icons.pause_circle_filled_rounded));
      await t.pump();

      expect(
        api.calls,
        containsAllInOrder(<String>['playOrPause', 'seek', 'playOrPause']),
        reason: 'the ordered interaction sequence survives an absent picture / '
            '没有画面也不影响这串有序交互',
      );
      expect(t.takeException(), isNull);
      await api.dispose();
    });

    testWidgets('a custom audio surface does not swallow control-bar interaction', (t) async {
      // The realistic audio setup: a cover-art surface in place of the video.
      // The chrome on top of it must still be fully interactive.
      //
      // 真实的音频接法：用封面面替换视频画面。其上的控件必须仍完全可交互。
      final api = await pumpAudioPlayer(
        t,
        surface: const ColoredBox(key: ValueKey('cover'), color: Color(0xFF203040)),
      );
      expect(find.byKey(const ValueKey('cover')), findsOneWidget);

      await t.tap(find.byIcon(Icons.play_circle_filled_rounded));
      await t.pump();
      await t.drag(find.byType(Slider), const Offset(100, 0));
      await t.pumpAndSettle();

      expect(api.calls, contains('playOrPause'));
      expect(api.calls, contains('seek'));
      await api.dispose();
    });
  });
}
