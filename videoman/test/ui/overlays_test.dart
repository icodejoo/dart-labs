import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:videoman/src/core/state/state.dart';
import 'package:videoman/src/ui/components/overlays.dart';

import '../support/fake_api.dart';
import '../support/pump.dart';

void main() {
  testWidgets('buffering overlay shows only while buffering', (t) async {
    final api = FakeVmApi();
    await pumpComponent(t, api, BufferingComponent());
    expect(find.byType(CircularProgressIndicator), findsNothing);
    api.push(const VmState(buffering: true));
    await t.pump();
    await t.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await api.dispose();
  });

  testWidgets('lock mask swallows taps when locked', (t) async {
    final api = FakeVmApi();
    api.push(const VmState(locked: true));
    await pumpComponent(t, api, LockMaskComponent());
    await t.tapAt(const Offset(200, 200));
    await t.pump();
    expect(api.calls.where((c) => c == 'playOrPause'), isEmpty);
    await api.dispose();
  });

  testWidgets('lock mask renders nothing when not locked', (t) async {
    final api = FakeVmApi();
    await pumpComponent(t, api, LockMaskComponent());
    expect(find.byType(GestureDetector), findsNothing);
    await api.dispose();
  });

  testWidgets('error overlay shows message and retry calls reload', (t) async {
    final api = FakeVmApi();
    api.push(const VmState(error: 'boom'));
    await pumpComponent(t, api, ErrorComponent());
    expect(find.text('boom'), findsOneWidget);
    await t.tap(find.byIcon(Icons.refresh_rounded));
    await t.pump();
    expect(api.calls, contains('reload'));
    await api.dispose();
  });

  testWidgets('error overlay is hidden when there is no error', (t) async {
    final api = FakeVmApi();
    await pumpComponent(t, api, ErrorComponent());
    expect(find.byIcon(Icons.refresh_rounded), findsNothing);
    await api.dispose();
  });
}
