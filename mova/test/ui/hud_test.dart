import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mova/src/core/options/options.dart';
import 'package:mova/src/core/state/state.dart';
import 'package:mova/src/core/state/ui_state.dart';
import 'package:mova/src/ui/components/hud_layer.dart';

import '../support/fake_api.dart';
import '../support/pump.dart';

void main() {
  testWidgets('volume HUD shows a speaker icon and NN%', (t) async {
    final api = FakeMovaApi();
    api.push(const MovaState(volume: 30));
    api.pushUi(const MovaUiState(hud: MovaHud.volume));
    await pumpComponent(t, api, MovaHudLayerComponent());
    await t.pump();
    expect(find.text('30%'), findsOneWidget);
    expect(find.byIcon(Icons.volume_up_rounded), findsOneWidget);
    await api.dispose();
  });

  testWidgets('volume HUD shows the muted icon at zero', (t) async {
    final api = FakeMovaApi();
    api.push(const MovaState(volume: 0));
    api.pushUi(const MovaUiState(hud: MovaHud.volume));
    await pumpComponent(t, api, MovaHudLayerComponent());
    await t.pump();
    expect(find.text('0%'), findsOneWidget);
    expect(find.byIcon(Icons.volume_off_rounded), findsOneWidget);
    await api.dispose();
  });

  testWidgets('brightness HUD shows a brightness icon and NN%', (t) async {
    final api = FakeMovaApi();
    api.push(const MovaState(brightness: 0.4));
    api.pushUi(const MovaUiState(hud: MovaHud.brightness));
    await pumpComponent(t, api, MovaHudLayerComponent());
    await t.pump();
    expect(find.text('40%'), findsOneWidget);
    expect(find.byIcon(Icons.brightness_6_rounded), findsOneWidget);
    await api.dispose();
  });

  testWidgets('seek HUD shows hudText when set (double-tap path)', (t) async {
    final api = FakeMovaApi();
    api.pushUi(const MovaUiState(hud: MovaHud.seek, hudText: '00:20'));
    await pumpComponent(t, api, MovaHudLayerComponent());
    await t.pump();
    expect(find.text('00:20'), findsOneWidget);
    await api.dispose();
  });

  testWidgets('seek HUD falls back to previewAt when hudText is absent (drag path)', (t) async {
    final api = FakeMovaApi();
    api.pushUi(const MovaUiState(hud: MovaHud.seek, previewAt: Duration(seconds: 20)));
    await pumpComponent(t, api, MovaHudLayerComponent());
    await t.pump();
    expect(find.text('00:20'), findsOneWidget);
    await api.dispose();
  });

  testWidgets('seek HUD shows nothing (not a blank badge) when neither is set', (t) async {
    final api = FakeMovaApi();
    api.pushUi(const MovaUiState(hud: MovaHud.seek));
    await pumpComponent(t, api, MovaHudLayerComponent());
    await t.pump();
    expect(find.text(''), findsNothing);
    await api.dispose();
  });

  testWidgets('no HUD is shown when hud is none', (t) async {
    final api = FakeMovaApi();
    api.pushUi(const MovaUiState(hud: MovaHud.none));
    await pumpComponent(t, api, MovaHudLayerComponent());
    await t.pump();
    expect(find.byType(Icon), findsNothing);
    await api.dispose();
  });

  testWidgets('zoom HUD shows the scale to one decimal with the configured suffix', (t) async {
    final api = FakeMovaApi();
    api.push(const MovaState(zoom: 2.25));
    api.pushUi(const MovaUiState(hud: MovaHud.zoom));
    await pumpComponent(t, api, MovaHudLayerComponent());
    await t.pump();
    expect(find.text('2.3${api.options.strings.zoomSuffix}'), findsOneWidget);
    await api.dispose();
  });

  testWidgets('zoom HUD follows a replaced zoomSuffix', (t) async {
    final api = FakeMovaApi(options: const MovaOpts(strings: MovaStrs(zoomSuffix: ' times')));
    api.push(const MovaState(zoom: 1.5));
    api.pushUi(const MovaUiState(hud: MovaHud.zoom));
    await pumpComponent(t, api, MovaHudLayerComponent());
    await t.pump();
    expect(find.text('1.5 times'), findsOneWidget);
    await api.dispose();
  });

  testWidgets('zoom HUD is absent while a different HUD kind is active', (t) async {
    final api = FakeMovaApi();
    api.push(const MovaState(zoom: 2, volume: 10));
    api.pushUi(const MovaUiState(hud: MovaHud.volume));
    await pumpComponent(t, api, MovaHudLayerComponent());
    await t.pump();
    expect(find.textContaining(api.options.strings.zoomSuffix), findsNothing);
    expect(find.text('10%'), findsOneWidget);
    await api.dispose();
  });

  // MovaHud.fit / MovaHud.quality exist as enum values but no HUD leaf renders
  // them: pin the current "renders nothing" behavior.
  // MovaHud.fit / MovaHud.quality 虽是枚举值，但没有对应的 HUD 叶子组件；固定现行"什么都不渲染"的行为。
  for (final kind in [MovaHud.fit, MovaHud.quality]) {
    testWidgets('${kind.name} HUD currently renders nothing', (t) async {
      final api = FakeMovaApi();
      api.push(const MovaState(zoom: 2, volume: 10, brightness: 0.5));
      api.pushUi(MovaUiState(hud: kind, hudText: 'x'));
      await pumpComponent(t, api, MovaHudLayerComponent());
      await t.pump();
      expect(find.byType(Icon), findsNothing);
      expect(find.byType(Text), findsNothing);
      await api.dispose();
    });
  }
}
