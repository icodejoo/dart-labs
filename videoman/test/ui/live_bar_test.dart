import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:videoman/src/core/model/source.dart';
import 'package:videoman/src/core/state/state.dart';
import 'package:videoman/src/ui/components/live_bar.dart';

import '../support/fake_api.dart';
import '../support/pump.dart';

void main() {
  testWidgets('live bar shows the LIVE badge and no seek bar by default', (t) async {
    final api = FakeVmApi();
    api.push(const VmState(type: VmStreamType.live));
    await pumpComponent(t, api, LiveBarComponent());
    expect(find.text('LIVE'), findsOneWidget);
    expect(find.byType(Slider), findsNothing);
    await api.dispose();
  });

  testWidgets('back-to-edge button reloads the stream', (t) async {
    final api = FakeVmApi();
    api.push(const VmState(type: VmStreamType.live));
    await pumpComponent(t, api, LiveBarComponent());
    await t.tap(find.byIcon(Icons.sync_rounded));
    await t.pump();
    expect(api.calls, contains('reload'));
    await api.dispose();
  });
}
