import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mova/src/core/model/source.dart';
import 'package:mova/src/core/options/options.dart';
import 'package:mova/src/core/state/state.dart';
import 'package:mova/src/core/state/ui_state.dart';
import 'package:mova/src/ui/components/gesture_layer.dart';

import '../support/fake_api.dart';
import '../support/pump.dart';

void main() {
  testWidgets('left vertical drag raises brightness (mainstream default)', (tester) async {
    final api = FakeMovaApi();
    api.push(const MovaState(volume: 50, brightness: 0.5));
    await pumpComponent(tester, api, GestureLayerComponent());
    await tester.dragFrom(const Offset(200, 300), const Offset(0, -150));
    await tester.pumpAndSettle();
    expect(api.calls, contains('setBrightness'));
    expect(api.lastBrightness, isNotNull);
    expect(api.lastBrightness, greaterThan(0.5));
    expect(api.calls, isNot(contains('setVolume')));
    // The gesture also raises the brightness HUD for feedback.
    // 手势同时抬起亮度 HUD 作为反馈。
    expect(api.lastHud, MovaHud.brightness);
    await api.dispose();
  });

  testWidgets('right vertical drag raises volume (mainstream default)', (tester) async {
    final api = FakeMovaApi();
    api.push(const MovaState(volume: 50, brightness: 0.5));
    await pumpComponent(tester, api, GestureLayerComponent());
    await tester.dragFrom(const Offset(600, 300), const Offset(0, -150));
    await tester.pumpAndSettle();
    expect(api.calls, contains('setVolume'));
    expect(api.lastVolume, isNotNull);
    expect(api.lastVolume, greaterThan(50));
    expect(api.calls, isNot(contains('setBrightness')));
    // The gesture also raises the volume HUD for feedback.
    // 手势同时抬起音量 HUD 作为反馈。
    expect(api.lastHud, MovaHud.volume);
    await api.dispose();
  });

  testWidgets('the side↔action mapping is configurable (swap left back to volume)', (tester) async {
    final api = FakeMovaApi(
      options: const MovaOpts(
        gesture: MovaGestConfig(
          leftVertical: MovaGestAction.volume,
          rightVertical: MovaGestAction.brightness,
        ),
      ),
    );
    api.push(const MovaState(volume: 50, brightness: 0.5));
    await pumpComponent(tester, api, GestureLayerComponent());
    await tester.dragFrom(const Offset(200, 300), const Offset(0, -150));
    await tester.pumpAndSettle();
    expect(api.calls, contains('setVolume'));
    expect(api.calls, isNot(contains('setBrightness')));
    await api.dispose();
  });

  testWidgets('horizontal drag commits a forward seek (~90s full width)', (tester) async {
    final api = FakeMovaApi();
    await pumpComponent(tester, api, GestureLayerComponent());
    // +240px over an 800px width ⇒ roughly +240/800*90 ≈ 27s (minus touch slop).
    await tester.dragFrom(const Offset(400, 300), const Offset(240, 0));
    await tester.pumpAndSettle();
    expect(api.calls, contains('seek'));
    expect(api.lastSeek, isNotNull);
    expect(api.lastSeek!.inSeconds, closeTo(24, 6));
    await api.dispose();
  });

  testWidgets('horizontal drag is ignored for live streams', (tester) async {
    final api = FakeMovaApi();
    api.push(const MovaState(type: MovaStreamType.live, liveSeekable: false));
    await pumpComponent(tester, api, GestureLayerComponent());
    await tester.dragFrom(const Offset(400, 300), const Offset(240, 0));
    await tester.pumpAndSettle();
    expect(api.calls, isNot(contains('seek')));
    expect(api.calls, isNot(contains('setDragging')));
    await api.dispose();
  });

  testWidgets('horizontal drag seeks a live source when liveSeekable is true', (t) async {
    final api = FakeMovaApi();
    api.push(const MovaState(
      type: MovaStreamType.live,
      liveSeekable: true,
      seekableWindow: Duration(minutes: 5),
      duration: Duration(minutes: 5),
    ));
    await pumpComponent(t, api, GestureLayerComponent());
    await t.dragFrom(t.getCenter(find.byType(GestureDetector)), const Offset(100, 0));
    await t.pumpAndSettle();
    expect(api.calls, contains('seek'));
    await api.dispose();
  });

  testWidgets('allowWhenLive=false blocks seeking even when liveSeekable', (t) async {
    final api = FakeMovaApi(
      options: const MovaOpts(gesture: MovaGestConfig(allowWhenLive: false)),
    );
    api.push(const MovaState(
      type: MovaStreamType.live,
      liveSeekable: true,
      seekableWindow: Duration(seconds: 300),
    ));
    await pumpComponent(t, api, GestureLayerComponent());
    await t.dragFrom(t.getCenter(find.byType(GestureDetector)), const Offset(100, 0));
    await t.pumpAndSettle();
    expect(api.calls, isNot(contains('seek')));
    await api.dispose();
  });

  testWidgets('double tap raises the seek HUD with the target duration as text '
      '(regression: toast used to render empty)', (t) async {
    final api = FakeMovaApi();
    await pumpComponent(t, api, GestureLayerComponent());
    final size = t.getSize(find.byType(GestureDetector));
    // Tap the right half so the step seeks forward from position zero.
    final rightSide = t.getTopLeft(find.byType(GestureDetector)) +
        Offset(size.width * 0.75, size.height / 2);
    await t.tapAt(rightSide);
    await t.pump(const Duration(milliseconds: 50));
    await t.tapAt(rightSide);
    await t.pumpAndSettle();

    expect(api.calls, contains('seek'));
    expect(api.lastSeek, const Duration(seconds: 10)); // default doubleTapStep
    expect(api.lastHud, MovaHud.seek);
    expect(api.lastHudText, isNotNull);
    expect(api.lastHudText, isNot(isEmpty));

    await api.dispose();
  });

  testWidgets('double tap seeks a seekable live stream and is blocked otherwise', (t) async {
    final seekable = FakeMovaApi();
    seekable.push(const MovaState(
      type: MovaStreamType.live,
      liveSeekable: true,
      seekableWindow: Duration(minutes: 5),
    ));
    await pumpComponent(t, seekable, GestureLayerComponent());
    final center = t.getCenter(find.byType(GestureDetector));
    await t.tapAt(center);
    await t.pump(const Duration(milliseconds: 50));
    await t.tapAt(center);
    await t.pumpAndSettle();
    expect(seekable.calls, contains('seek'));
    await seekable.dispose();

    final blocked = FakeMovaApi();
    blocked.push(const MovaState(type: MovaStreamType.live, liveSeekable: false));
    await pumpComponent(t, blocked, GestureLayerComponent());
    final center2 = t.getCenter(find.byType(GestureDetector));
    await t.tapAt(center2);
    await t.pump(const Duration(milliseconds: 50));
    await t.tapAt(center2);
    await t.pumpAndSettle();
    expect(blocked.calls, isNot(contains('seek')));
    await blocked.dispose();
  });
}
