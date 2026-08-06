import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mova/src/core/state/progress.dart';
import 'package:mova/src/core/state/state.dart';
import 'package:mova/src/ui/components/bottom_bar.dart';

import '../support/fake_api.dart';
import '../support/pump.dart';

void main() {
  testWidgets('seek bar commits the dragged position on release', (t) async {
    final api = FakeMovaApi();
    api.push(const MovaState(duration: Duration(minutes: 2)));
    await pumpComponent(t, api, BottomBarComponent());
    await t.drag(find.byType(Slider), const Offset(200, 0));
    await t.pumpAndSettle();
    expect(api.calls, contains('seek'));
    await api.dispose();
  });

  testWidgets('seek bar is disabled when duration is zero', (t) async {
    final api = FakeMovaApi();
    await pumpComponent(t, api, BottomBarComponent());
    expect(t.widget<Slider>(find.byType(Slider)).onChanged, isNull);
    await api.dispose();
  });

  testWidgets('position label follows the throttled progress stream', (t) async {
    final api = FakeMovaApi();
    api.push(const MovaState(duration: Duration(minutes: 2)));
    await pumpComponent(t, api, BottomBarComponent());
    api.pushProgress(const MovaProg(position: Duration(seconds: 65)));
    await t.pump();
    await t.pump();
    expect(find.text('01:05'), findsOneWidget);
    await api.dispose();
  });
}
