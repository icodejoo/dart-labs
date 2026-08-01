import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:videoman/src/core/state/progress.dart';
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

  testWidgets(
    'swapping to a different api remounts the component subtree, so the seek '
    'bar reflects the new engine instead of freezing on the old one '
    '(regression: switching engines under a live VmPlayer left the seek bar '
    'stuck, since the old stateful subtree never unmounted its subscription '
    'to the disposed engine)',
    (t) async {
      final api1 = FakeVmApi();
      api1.push(const VmState(duration: Duration(seconds: 100)));
      await t.pumpWidget(MaterialApp(home: VmPlayer(api: api1)));
      await t.pump();
      api1.pushProgress(const VmProgress(position: Duration(seconds: 40)));
      await t.pump();
      await t.pump();
      expect(t.widget<Slider>(find.byType(Slider)).value, 40000);

      // Same widget position, same type, no key — exactly what the demo app
      // does when switching sources by rebuilding with a fresh VmEngine.
      final api2 = FakeVmApi();
      api2.push(const VmState(duration: Duration(seconds: 100)));
      await t.pumpWidget(MaterialApp(home: VmPlayer(api: api2)));
      await t.pump();
      api2.pushProgress(const VmProgress(position: Duration(seconds: 5)));
      await t.pump();
      await t.pump();

      expect(t.widget<Slider>(find.byType(Slider)).value, 5000);

      await api1.dispose();
      await api2.dispose();
    },
  );
}
