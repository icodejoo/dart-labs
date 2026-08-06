import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mova/src/ui/components/speed_button.dart';

import '../support/fake_api.dart';
import '../support/pump.dart';

void main() {
  testWidgets('shows the current rate and cycles through the fixed steps on tap', (t) async {
    final api = FakeMovaApi();
    await pumpComponent(t, api, SpeedButtonComponent());

    expect(find.text('1x'), findsOneWidget);

    await t.tap(find.byIcon(Icons.speed_rounded));
    await t.pump();
    expect(api.calls, contains('setRate'));
    expect(api.lastRate, 1.25);

    api.push(api.state.copyWith(rate: 1.25));
    await t.pump();
    await t.pump();
    await t.tap(find.byIcon(Icons.speed_rounded));
    await t.pump();
    expect(api.lastRate, 1.5);

    await api.dispose();
  });

  testWidgets('wraps from the last step back to the first', (t) async {
    final api = FakeMovaApi();
    api.push(api.state.copyWith(rate: 2.0));
    await pumpComponent(t, api, SpeedButtonComponent());

    expect(find.text('2x'), findsOneWidget);
    await t.tap(find.byIcon(Icons.speed_rounded));
    await t.pump();
    expect(api.lastRate, 0.5);

    await api.dispose();
  });
}
