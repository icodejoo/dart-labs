import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mova/src/core/state/state.dart';
import 'package:mova/src/ui/components/overlays.dart';

import 'package:mova/src/ui/player.dart';
import 'package:mova/src/ui/ui_kits/default_ui_kit.dart';
import 'package:mova/src/core/state/ui_state.dart';

import '../support/fake_api.dart';
import '../support/pump.dart';

void main() {
  testWidgets('隐藏控制条仍显示缓冲状态', (t) async {
    final api = FakeMovaApi();
    api.push(const MovaState(buffering: true));
    api.pushUi(const MovaUiState(controlsVisible: false));
    await t.pumpWidget(MaterialApp(home: MovaPlayer(api: api)));
    expect(
      find.byType(CircularProgressIndicator).hitTestable(),
      findsOneWidget,
    );
    await api.dispose();
  });

  testWidgets('锁定时错误层仍可重试', (t) async {
    final api = FakeMovaApi();
    api.push(const MovaState(locked: true, error: 'boom'));
    await t.pumpWidget(MaterialApp(home: MovaPlayer(api: api)));
    await t.tap(find.byIcon(Icons.refresh_rounded));
    expect(api.calls, contains('reload'));
    await api.dispose();
  });

  testWidgets('pip 和 mini 仍隐藏状态层', (t) async {
    final api = FakeMovaApi();
    for (final state in [
      const MovaState(pip: true, buffering: true),
      const MovaState(mini: true, error: 'boom'),
    ]) {
      api.push(state);
      await t.pumpWidget(MaterialApp(home: MovaPlayer(api: api)));
      await t.pump();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('boom'), findsNothing);
    }
    await api.dispose();
  });

  testWidgets('自定义 UI 套件可保留原 center 门控', (t) async {
    final api = FakeMovaApi();
    api.push(const MovaState(locked: true, error: 'boom'));
    await t.pumpWidget(
      MaterialApp(
        home: MovaPlayer(
          api: api,
          uiKit: const MovaDefaultUiKit(statusLayerNames: {}),
        ),
      ),
    );
    expect(find.text('boom'), findsNothing);
    await api.dispose();
  });
  testWidgets('buffering overlay shows only while buffering', (t) async {
    final api = FakeMovaApi();
    await pumpComponent(t, api, MovaBufferingComponent());
    expect(find.byType(CircularProgressIndicator), findsNothing);
    api.push(const MovaState(buffering: true));
    await t.pump();
    await t.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await api.dispose();
  });

  testWidgets('lock mask swallows taps when locked', (t) async {
    final api = FakeMovaApi();
    api.push(const MovaState(locked: true));
    await pumpComponent(t, api, MovaLockMaskComponent());
    await t.tapAt(const Offset(200, 200));
    await t.pump();
    expect(api.calls.where((c) => c == 'playOrPause'), isEmpty);
    await api.dispose();
  });

  testWidgets('lock mask renders nothing when not locked', (t) async {
    final api = FakeMovaApi();
    await pumpComponent(t, api, MovaLockMaskComponent());
    expect(find.byType(GestureDetector), findsNothing);
    await api.dispose();
  });

  testWidgets('error overlay shows message and retry calls reload', (t) async {
    final api = FakeMovaApi();
    api.push(const MovaState(error: 'boom'));
    await pumpComponent(t, api, MovaErrorComponent());
    expect(find.text('boom'), findsOneWidget);
    await t.tap(find.byIcon(Icons.refresh_rounded));
    await t.pump();
    expect(api.calls, contains('reload'));
    await api.dispose();
  });

  testWidgets('error overlay is hidden when there is no error', (t) async {
    final api = FakeMovaApi();
    await pumpComponent(t, api, MovaErrorComponent());
    expect(find.byIcon(Icons.refresh_rounded), findsNothing);
    await api.dispose();
  });
}
