import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mova/src/core/model/fit.dart';
import 'package:mova/src/core/model/orientation.dart';
import 'package:mova/src/core/model/quality.dart';
import 'package:mova/src/core/model/source.dart';
import 'package:mova/src/core/options/options.dart';
import 'package:mova/src/core/state/state.dart';
import 'package:mova/src/ui/components/top_bar.dart';

import '../support/fake_api.dart';
import '../support/pump.dart';

void main() {
  testWidgets('fit button cycles the fill mode and shows the configured label', (t) async {
    final api = FakeMovaApi();
    await pumpComponent(t, api, MovaTopBarComponent());
    expect(find.text('适应'), findsOneWidget);
    await t.tap(find.byIcon(Icons.aspect_ratio_rounded));
    await t.pump();
    expect(api.calls, contains('setFit'));
    expect(api.lastFit, MovaFit.cover);
    await api.dispose();
  });

  testWidgets('pip button is hidden when the platform reports no pip support', (t) async {
    final api = FakeMovaApi()..pipSupported = false;
    await pumpComponent(t, api, MovaTopBarComponent());
    expect(find.byIcon(Icons.picture_in_picture_alt_rounded), findsNothing);
    await api.dispose();
  });

  testWidgets('pip button shows and enters pip when supported', (t) async {
    final api = FakeMovaApi()..pipSupported = true;
    await pumpComponent(t, api, MovaTopBarComponent());
    await t.tap(find.byIcon(Icons.picture_in_picture_alt_rounded));
    await t.pump();
    expect(api.calls, contains('enterPip'));
    await api.dispose();
  });

  testWidgets('orientation button toggles the forced orientation on mobile', (t) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final api = FakeMovaApi();
    try {
      await pumpComponent(t, api, MovaTopBarComponent());
      expect(find.byIcon(Icons.screen_rotation_rounded), findsOneWidget);

      // From the default auto state, one tap forces landscape.
      await t.tap(find.byIcon(Icons.screen_rotation_rounded));
      await t.pump();
      expect(api.calls, contains('setOrientation'));
      expect(api.lastOrientation, MovaOrientation.landscape);

      // A second tap flips landscape → portrait.
      await t.tap(find.byIcon(Icons.screen_rotation_rounded));
      await t.pump();
      expect(api.lastOrientation, MovaOrientation.portrait);
    } finally {
      debugDefaultTargetPlatformOverride = null;
      await api.dispose();
    }
  });

  testWidgets('orientation button is hidden off mobile', (t) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    final api = FakeMovaApi();
    try {
      await pumpComponent(t, api, MovaTopBarComponent());
      expect(find.byIcon(Icons.screen_rotation_rounded), findsNothing);
    } finally {
      debugDefaultTargetPlatformOverride = null;
      await api.dispose();
    }
  });

  testWidgets('quality button is hidden when there are no variants', (t) async {
    final api = FakeMovaApi();
    api.push(const MovaState());
    await pumpComponent(t, api, MovaTopBarComponent());
    expect(find.byIcon(Icons.high_quality_rounded), findsNothing);
    await api.dispose();
  });

  testWidgets('replacing MovaStrs changes the fit label without touching components', (t) async {
    final api = FakeMovaApi(options: const MovaOpts(strings: MovaStrs(fitContain: 'Fit')));
    await pumpComponent(t, api, MovaTopBarComponent());
    expect(find.text('Fit'), findsOneWidget);
    await api.dispose();
  });

  testWidgets('title shows the current source title, empty when none', (t) async {
    final api = FakeMovaApi();
    await pumpComponent(t, api, MovaTopBarComponent());
    expect(find.text(''), findsOneWidget);

    await api.open(const MovaSource('https://host/video.mp4', title: 'My Video'));
    await t.pumpAndSettle();
    expect(find.text('My Video'), findsOneWidget);
    await api.dispose();
  });

  // Regression: re-opening a *different* source of the SAME MovaStreamType
  // (VOD -> VOD here) must still update the shown title. Round-1 of this
  // fix piggybacked reactivity on MovaState.type, which does not change in
  // this case, so the title stayed stuck on the first source — this test
  // exercises exactly that same-type re-open path.
  //
  // 回归测试：重新打开同一 MovaStreamType（此处为点播 -> 点播）的另一个源时，
  // 展示的标题也必须更新。本修复第一轮曾把响应式重建挂在 MovaState.type 上，
  // 而这种情况下 type 不会变化，导致标题停留在第一个源上——本测试专门覆盖
  // 这种同类型重开的路径。
  testWidgets('title updates when re-opening a different source of the same stream type', (t) async {
    final api = FakeMovaApi();
    await api.open(const MovaSource('https://host/a.mp4', title: 'A'));
    await pumpComponent(t, api, MovaTopBarComponent());
    expect(find.text('A'), findsOneWidget);
    expect(api.state.type, MovaStreamType.vod);

    await api.open(const MovaSource('https://host/b.mp4', title: 'B'));
    expect(api.state.type, MovaStreamType.vod);
    await t.pumpAndSettle();
    expect(find.text('B'), findsOneWidget);
    expect(find.text('A'), findsNothing);
    await api.dispose();
  });

  group('fullscreen button', () {
    testWidgets('enters fullscreen from the windowed state', (t) async {
      final api = FakeMovaApi();
      await pumpComponent(t, api, MovaTopBarComponent());
      expect(find.byIcon(Icons.fullscreen_rounded), findsOneWidget);
      expect(find.byIcon(Icons.fullscreen_exit_rounded), findsNothing);
      await t.tap(find.byIcon(Icons.fullscreen_rounded));
      await t.pump();
      expect(api.calls, contains('setFullscreen'));
      expect(api.lastFullscreen, isTrue);
      await api.dispose();
    });

    testWidgets('shows the exit glyph when fullscreen and leaves on tap', (t) async {
      final api = FakeMovaApi();
      api.push(const MovaState(fullscreen: true));
      await pumpComponent(t, api, MovaTopBarComponent());
      expect(find.byIcon(Icons.fullscreen_exit_rounded), findsOneWidget);
      await t.tap(find.byIcon(Icons.fullscreen_exit_rounded));
      await t.pump();
      expect(api.lastFullscreen, isFalse);
      await api.dispose();
    });
  });

  group('quality button', () {
    const auto = MovaQuality(label: '自动', uri: '', isAuto: true);
    const hd = MovaQuality(label: '1080p', uri: 'https://host/1080.m3u8', height: 1080);
    const sd = MovaQuality(label: '480p', uri: 'https://host/480.m3u8', height: 480);

    testWidgets('shows the current label as caption once variants exist', (t) async {
      final api = FakeMovaApi();
      api.push(const MovaState(qualities: [auto, hd, sd], currentQuality: hd));
      await pumpComponent(t, api, MovaTopBarComponent());
      expect(find.byIcon(Icons.high_quality_rounded), findsOneWidget);
      expect(find.text('1080p'), findsOneWidget);
      await api.dispose();
    });

    testWidgets('opens a sheet with every variant and checkmarks only the active one', (t) async {
      final api = FakeMovaApi();
      api.push(const MovaState(qualities: [auto, hd, sd], currentQuality: hd));
      await pumpComponent(t, api, MovaTopBarComponent());
      await t.tap(find.byIcon(Icons.high_quality_rounded));
      await t.pumpAndSettle();
      expect(find.widgetWithText(ListTile, '自动'), findsOneWidget);
      expect(find.widgetWithText(ListTile, '1080p'), findsOneWidget);
      expect(find.widgetWithText(ListTile, '480p'), findsOneWidget);
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
      expect(
        find.descendant(of: find.widgetWithText(ListTile, '1080p'), matching: find.byIcon(Icons.check_rounded)),
        findsOneWidget,
      );
      await api.dispose();
    });

    testWidgets('picking an item dismisses the sheet then calls switchQuality with that variant', (t) async {
      final api = FakeMovaApi();
      api.push(const MovaState(qualities: [auto, hd, sd], currentQuality: hd));
      await pumpComponent(t, api, MovaTopBarComponent());
      await t.tap(find.byIcon(Icons.high_quality_rounded));
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(ListTile, '480p'));
      await t.pumpAndSettle();
      expect(api.calls, contains('switchQuality'));
      expect(api.lastQuality, sd);
      expect(find.byType(ListTile), findsNothing, reason: 'the sheet is gone');
      await api.dispose();
    });

    testWidgets('the auto entry is the checked one when it is current', (t) async {
      final api = FakeMovaApi();
      api.push(const MovaState(qualities: [auto, hd], currentQuality: auto));
      await pumpComponent(t, api, MovaTopBarComponent());
      await t.tap(find.byIcon(Icons.high_quality_rounded));
      await t.pumpAndSettle();
      expect(
        find.descendant(of: find.widgetWithText(ListTile, '自动'), matching: find.byIcon(Icons.check_rounded)),
        findsOneWidget,
      );
      await api.dispose();
    });
  });
}
