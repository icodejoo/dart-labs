import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
    await pumpComponent(t, api, HudLayerComponent());
    await t.pump();
    expect(find.text('30%'), findsOneWidget);
    expect(find.byIcon(Icons.volume_up_rounded), findsOneWidget);
    await api.dispose();
  });

  testWidgets('volume HUD shows the muted icon at zero', (t) async {
    final api = FakeMovaApi();
    api.push(const MovaState(volume: 0));
    api.pushUi(const MovaUiState(hud: MovaHud.volume));
    await pumpComponent(t, api, HudLayerComponent());
    await t.pump();
    expect(find.text('0%'), findsOneWidget);
    expect(find.byIcon(Icons.volume_off_rounded), findsOneWidget);
    await api.dispose();
  });

  testWidgets('brightness HUD shows a brightness icon and NN%', (t) async {
    final api = FakeMovaApi();
    api.push(const MovaState(brightness: 0.4));
    api.pushUi(const MovaUiState(hud: MovaHud.brightness));
    await pumpComponent(t, api, HudLayerComponent());
    await t.pump();
    expect(find.text('40%'), findsOneWidget);
    expect(find.byIcon(Icons.brightness_6_rounded), findsOneWidget);
    await api.dispose();
  });

  testWidgets('seek HUD shows hudText when set (double-tap path)', (t) async {
    final api = FakeMovaApi();
    api.pushUi(const MovaUiState(hud: MovaHud.seek, hudText: '00:20'));
    await pumpComponent(t, api, HudLayerComponent());
    await t.pump();
    expect(find.text('00:20'), findsOneWidget);
    await api.dispose();
  });

  testWidgets('seek HUD falls back to previewAt when hudText is absent (drag path)', (t) async {
    final api = FakeMovaApi();
    api.pushUi(const MovaUiState(hud: MovaHud.seek, previewAt: Duration(seconds: 20)));
    await pumpComponent(t, api, HudLayerComponent());
    await t.pump();
    expect(find.text('00:20'), findsOneWidget);
    await api.dispose();
  });

  testWidgets('seek HUD shows nothing (not a blank badge) when neither is set', (t) async {
    final api = FakeMovaApi();
    api.pushUi(const MovaUiState(hud: MovaHud.seek));
    await pumpComponent(t, api, HudLayerComponent());
    await t.pump();
    expect(find.text(''), findsNothing);
    await api.dispose();
  });

  testWidgets('no HUD is shown when hud is none', (t) async {
    final api = FakeMovaApi();
    api.pushUi(const MovaUiState(hud: MovaHud.none));
    await pumpComponent(t, api, HudLayerComponent());
    await t.pump();
    expect(find.byType(Icon), findsNothing);
    await api.dispose();
  });
}
