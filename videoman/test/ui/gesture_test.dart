import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:videoman/src/core/model/source.dart';
import 'package:videoman/src/core/options/options.dart';
import 'package:videoman/src/core/state/state.dart';
import 'package:videoman/src/ui/components/gesture_layer.dart';

import '../support/fake_api.dart';
import '../support/pump.dart';

void main() {
  testWidgets('left vertical drag raises brightness (mainstream default)', (tester) async {
    final api = FakeVmApi();
    api.push(const VmState(volume: 50, brightness: 0.5));
    await pumpComponent(tester, api, GestureLayerComponent());
    await tester.dragFrom(const Offset(200, 300), const Offset(0, -150));
    await tester.pumpAndSettle();
    expect(api.calls, contains('setBrightness'));
    expect(api.lastBrightness, isNotNull);
    expect(api.lastBrightness, greaterThan(0.5));
    expect(api.calls, isNot(contains('setVolume')));
    await api.dispose();
  });

  testWidgets('right vertical drag raises volume (mainstream default)', (tester) async {
    final api = FakeVmApi();
    api.push(const VmState(volume: 50, brightness: 0.5));
    await pumpComponent(tester, api, GestureLayerComponent());
    await tester.dragFrom(const Offset(600, 300), const Offset(0, -150));
    await tester.pumpAndSettle();
    expect(api.calls, contains('setVolume'));
    expect(api.lastVolume, isNotNull);
    expect(api.lastVolume, greaterThan(50));
    expect(api.calls, isNot(contains('setBrightness')));
    await api.dispose();
  });

  testWidgets('the side↔action mapping is configurable (swap left back to volume)', (tester) async {
    final api = FakeVmApi(
      options: const VmOptions(
        gesture: VmGestureConfig(
          leftVertical: VmGestureAction.volume,
          rightVertical: VmGestureAction.brightness,
        ),
      ),
    );
    api.push(const VmState(volume: 50, brightness: 0.5));
    await pumpComponent(tester, api, GestureLayerComponent());
    await tester.dragFrom(const Offset(200, 300), const Offset(0, -150));
    await tester.pumpAndSettle();
    expect(api.calls, contains('setVolume'));
    expect(api.calls, isNot(contains('setBrightness')));
    await api.dispose();
  });

  testWidgets('horizontal drag commits a forward seek (~90s full width)', (tester) async {
    final api = FakeVmApi();
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
    final api = FakeVmApi();
    api.push(const VmState(type: VmStreamType.live, liveSeekable: false));
    await pumpComponent(tester, api, GestureLayerComponent());
    await tester.dragFrom(const Offset(400, 300), const Offset(240, 0));
    await tester.pumpAndSettle();
    expect(api.calls, isNot(contains('seek')));
    expect(api.calls, isNot(contains('setDragging')));
    await api.dispose();
  });

  testWidgets('horizontal drag seeks a live source when liveSeekable is true', (t) async {
    final api = FakeVmApi();
    api.push(const VmState(
      type: VmStreamType.live,
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
    final api = FakeVmApi(
      options: const VmOptions(gesture: VmGestureConfig(allowWhenLive: false)),
    );
    api.push(const VmState(
      type: VmStreamType.live,
      liveSeekable: true,
      seekableWindow: Duration(seconds: 300),
    ));
    await pumpComponent(t, api, GestureLayerComponent());
    await t.dragFrom(t.getCenter(find.byType(GestureDetector)), const Offset(100, 0));
    await t.pumpAndSettle();
    expect(api.calls, isNot(contains('seek')));
    await api.dispose();
  });

  testWidgets('double tap seeks a seekable live stream and is blocked otherwise', (t) async {
    final seekable = FakeVmApi();
    seekable.push(const VmState(
      type: VmStreamType.live,
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

    final blocked = FakeVmApi();
    blocked.push(const VmState(type: VmStreamType.live, liveSeekable: false));
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
