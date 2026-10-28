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
    await pumpComponent(tester, api, MovaGestureLayerComponent());
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
    await pumpComponent(tester, api, MovaGestureLayerComponent());
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

  testWidgets('the side↔action mapping is configurable (cutover left back to volume)', (tester) async {
    final api = FakeMovaApi(
      options: const MovaOpts(
        gesture: MovaGestureConfig(
          leftVertical: MovaGestureAction.volume,
          rightVertical: MovaGestureAction.brightness,
        ),
      ),
    );
    api.push(const MovaState(volume: 50, brightness: 0.5));
    await pumpComponent(tester, api, MovaGestureLayerComponent());
    await tester.dragFrom(const Offset(200, 300), const Offset(0, -150));
    await tester.pumpAndSettle();
    expect(api.calls, contains('setVolume'));
    expect(api.calls, isNot(contains('setBrightness')));
    await api.dispose();
  });

  testWidgets('horizontal drag commits a forward seek (~90s full width)', (tester) async {
    final api = FakeMovaApi();
    await pumpComponent(tester, api, MovaGestureLayerComponent());
    // +240px over an 800px width ⇒ roughly +240/800*90 ≈ 27s (minus touch slop).
    await tester.dragFrom(const Offset(400, 300), const Offset(240, 0));
    await tester.pumpAndSettle();
    expect(api.calls, contains('seek'));
    expect(api.lastSeek, isNotNull);
    expect(api.lastSeek!.inSeconds, closeTo(24, 6));
    await api.dispose();
  });

  testWidgets('a horizontal drag mapped to volume reads the horizontal axis', (tester) async {
    final api = FakeMovaApi(
      options: const MovaOpts(gesture: MovaGestureConfig(horizontal: MovaGestureAction.volume)),
    );
    api.push(const MovaState(volume: 50, brightness: 0.5));
    await pumpComponent(tester, api, MovaGestureLayerComponent());
    await tester.dragFrom(const Offset(400, 300), const Offset(240, 0));
    await tester.pumpAndSettle();
    // +240px of 800px ⇒ about +30 on top of 50 (minus touch slop).
    expect(api.lastVolume, greaterThan(65));
    await api.dispose();
  });

  testWidgets('a vertical drag mapped to seek reads the vertical axis (up = forward)', (tester) async {
    final api = FakeMovaApi(
      options: const MovaOpts(gesture: MovaGestureConfig(leftVertical: MovaGestureAction.seek)),
    );
    await pumpComponent(tester, api, MovaGestureLayerComponent());
    await tester.dragFrom(const Offset(200, 400), const Offset(0, -150));
    await tester.pumpAndSettle();
    expect(api.calls, contains('seek'));
    expect(api.lastSeek!.inSeconds, greaterThan(10));
    await api.dispose();
  });

  testWidgets('horizontal drag is ignored for live streams', (tester) async {
    final api = FakeMovaApi();
    api.push(const MovaState(type: MovaStreamType.live, liveSeekable: false));
    await pumpComponent(tester, api, MovaGestureLayerComponent());
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
    await pumpComponent(t, api, MovaGestureLayerComponent());
    await t.dragFrom(t.getCenter(find.byType(GestureDetector)), const Offset(100, 0));
    await t.pumpAndSettle();
    expect(api.calls, contains('seek'));
    await api.dispose();
  });

  testWidgets('allowWhenLive=false blocks seeking even when liveSeekable', (t) async {
    final api = FakeMovaApi(
      options: const MovaOpts(gesture: MovaGestureConfig(allowWhenLive: false)),
    );
    api.push(const MovaState(
      type: MovaStreamType.live,
      liveSeekable: true,
      seekableWindow: Duration(seconds: 300),
    ));
    await pumpComponent(t, api, MovaGestureLayerComponent());
    await t.dragFrom(t.getCenter(find.byType(GestureDetector)), const Offset(100, 0));
    await t.pumpAndSettle();
    expect(api.calls, isNot(contains('seek')));
    await api.dispose();
  });

  testWidgets('double tap raises the seek HUD with the target duration as text '
      '(regression: toast used to render empty)', (t) async {
    final api = FakeMovaApi();
    await pumpComponent(t, api, MovaGestureLayerComponent());
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
    await pumpComponent(t, seekable, MovaGestureLayerComponent());
    final center = t.getCenter(find.byType(GestureDetector));
    await t.tapAt(center);
    await t.pump(const Duration(milliseconds: 50));
    await t.tapAt(center);
    await t.pumpAndSettle();
    expect(seekable.calls, contains('seek'));
    await seekable.dispose();

    final blocked = FakeMovaApi();
    blocked.push(const MovaState(type: MovaStreamType.live, liveSeekable: false));
    await pumpComponent(t, blocked, MovaGestureLayerComponent());
    final center2 = t.getCenter(find.byType(GestureDetector));
    await t.tapAt(center2);
    await t.pump(const Duration(milliseconds: 50));
    await t.tapAt(center2);
    await t.pumpAndSettle();
    expect(blocked.calls, isNot(contains('seek')));
    await blocked.dispose();
  });

  group('pinch zoom', () {
    /// Spreads two fingers apart around the layer's centre in small steps, from
    /// [start] px apart to [start] + 2 * [spread] px. Small steps matter: the
    /// recognizer measures the scale from the moment it accepts the gesture.
    ///
    /// 在手势层中心附近分小步把两指张开，间距从 [start] px 张到 [start] + 2 * [spread] px。
    /// 小步很重要：识别器是从接受手势那一刻起量缩放比例的。
    Future<void> pinchOut(WidgetTester t, {double start = 20, double spread = 300}) async {
      final c = t.getCenter(find.byType(GestureDetector));
      final a = await t.startGesture(c - Offset(start / 2, 0), pointer: 1);
      final b = await t.startGesture(c + Offset(start / 2, 0), pointer: 2);
      const steps = 30;
      for (var i = 0; i < steps; i++) {
        await a.moveBy(Offset(-spread / steps, 0));
        await b.moveBy(Offset(spread / steps, 0));
        await t.pump();
      }
      await a.up();
      await b.up();
      await t.pumpAndSettle();
    }

    testWidgets('spreading past maxZoom is clamped to maxZoom', (t) async {
      final api = FakeMovaApi();
      await pumpComponent(t, api, MovaGestureLayerComponent());
      await pinchOut(t); // 20px -> 620px, far beyond the default 3.0 cap
      expect(api.calls, contains('setZoom'));
      expect(api.lastZoom, api.options.gesture.maxZoom);
      await api.dispose();
    });

    testWidgets('a custom maxZoom is the ceiling', (t) async {
      final api = FakeMovaApi(
        options: const MovaOpts(gesture: MovaGestureConfig(maxZoom: 2.0)),
      );
      await pumpComponent(t, api, MovaGestureLayerComponent());
      await pinchOut(t);
      expect(api.lastZoom, 2.0);
      await api.dispose();
    });

    testWidgets('a modest spread scales from the current zoom and never goes below 1.0', (t) async {
      final api = FakeMovaApi();
      api.push(const MovaState(zoom: 1.0));
      await pumpComponent(t, api, MovaGestureLayerComponent());
      // 100px apart pinching in to 60px: scale < 1 from a 1.0 baseline.
      // 间距 100px 捏到 60px：从 1.0 基准出发缩小。
      final c = t.getCenter(find.byType(GestureDetector));
      final a = await t.startGesture(c - const Offset(50, 0), pointer: 1);
      final b = await t.startGesture(c + const Offset(50, 0), pointer: 2);
      await a.moveBy(const Offset(20, 0));
      await b.moveBy(const Offset(-20, 0));
      await t.pump();
      await a.up();
      await b.up();
      await t.pumpAndSettle();
      expect(api.calls, contains('setZoom'));
      expect(api.lastZoom, 1.0);
      await api.dispose();
    });

    testWidgets('pinchZoom: false ignores a two-finger spread', (t) async {
      final api = FakeMovaApi(
        options: const MovaOpts(gesture: MovaGestureConfig(pinchZoom: false)),
      );
      await pumpComponent(t, api, MovaGestureLayerComponent());
      await pinchOut(t);
      expect(api.calls, isNot(contains('setZoom')));
      await api.dispose();
    });
  });

  group('single tap', () {
    testWidgets('hides the controls when they are showing', (t) async {
      final api = FakeMovaApi();
      api.pushUi(const MovaUiState(controlsVisible: true));
      await pumpComponent(t, api, MovaGestureLayerComponent());
      await t.tapAt(t.getCenter(find.byType(GestureDetector)));
      // A lone tap resolves only after the double-tap window closes.
      // 单击要等双击窗口关闭后才会判定。
      await t.pump(const Duration(milliseconds: 400));
      expect(api.calls, contains('hideControls'));
      expect(api.calls, isNot(contains('showControls')));
      await api.dispose();
    });

    testWidgets('shows the controls when they are hidden', (t) async {
      final api = FakeMovaApi();
      api.pushUi(const MovaUiState(controlsVisible: false));
      await pumpComponent(t, api, MovaGestureLayerComponent());
      await t.tapAt(t.getCenter(find.byType(GestureDetector)));
      await t.pump(const Duration(milliseconds: 400));
      expect(api.calls, contains('showControls'));
      expect(api.calls, isNot(contains('hideControls')));
      await api.dispose();
    });
  });
}
