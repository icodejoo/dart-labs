import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:videoman/src/core/state/state.dart';
import 'package:videoman/src/ui/player.dart';
import 'package:videoman/src/ui/scope/scope.dart';
import 'package:videoman/src/ui/skins/default_skin.dart';

import '../support/fake_api.dart';

void main() {
  testWidgets('VmPlayer provides its api down the tree and renders the skin', (t) async {
    final api = FakeVmApi();
    await t.pumpWidget(MaterialApp(home: VmPlayer(api: api, skin: const VmDefaultSkin())));
    await t.pump();
    expect(find.byType(VmScope), findsOneWidget);
    await api.dispose();
  });

  testWidgets('VmPlayer applies zoom from state via Transform.scale', (t) async {
    final api = FakeVmApi();
    api.push(const VmState(zoom: 2.0));
    await t.pumpWidget(MaterialApp(home: VmPlayer(api: api)));
    await t.pump();
    final ts = t.widget<Transform>(find.byType(Transform).first);
    expect(ts.transform.getMaxScaleOnAxis(), closeTo(2.0, 0.001));
    await api.dispose();
  });
}
