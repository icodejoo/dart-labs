import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mova/src/core/state/progress.dart';
import 'package:mova/src/core/state/state.dart';
import 'package:mova/src/ui/player.dart';
import 'package:mova/src/ui/scope/scope.dart';
import 'package:mova/src/ui/skins/default_skin.dart';

import '../support/fake_api.dart';

void main() {
  testWidgets('MovaPlayer provides its api down the tree and renders the skin', (t) async {
    final api = FakeMovaApi();
    await t.pumpWidget(MaterialApp(home: MovaPlayer(api: api, skin: const MovaDefSkin())));
    await t.pump();
    expect(find.byType(MovaScope), findsOneWidget);
    await api.dispose();
  });

  testWidgets('MovaPlayer applies zoom from state via Transform.scale', (t) async {
    final api = FakeMovaApi();
    api.push(const MovaState(zoom: 2.0));
    await t.pumpWidget(MaterialApp(home: MovaPlayer(api: api)));
    await t.pump();
    final ts = t.widget<Transform>(find.byType(Transform).first);
    expect(ts.transform.getMaxScaleOnAxis(), closeTo(2.0, 0.001));
    await api.dispose();
  });

  testWidgets(
    'swapping to a different api remounts the component subtree, so the seek '
    'bar reflects the new engine instead of freezing on the old one '
    '(regression: switching engines under a live MovaPlayer left the seek bar '
    'stuck, since the old stateful subtree never unmounted its subscription '
    'to the disposed engine)',
    (t) async {
      final api1 = FakeMovaApi();
      api1.push(const MovaState(duration: Duration(seconds: 100)));
      await t.pumpWidget(MaterialApp(home: MovaPlayer(api: api1)));
      await t.pump();
      api1.pushProgress(const MovaProg(position: Duration(seconds: 40)));
      await t.pump();
      await t.pump();
      expect(t.widget<Slider>(find.byType(Slider)).value, 40000);

      // Same widget position, same type, no key — exactly what the demo app
      // does when switching sources by rebuilding with a fresh MovaEngine.
      final api2 = FakeMovaApi();
      api2.push(const MovaState(duration: Duration(seconds: 100)));
      await t.pumpWidget(MaterialApp(home: MovaPlayer(api: api2)));
      await t.pump();
      api2.pushProgress(const MovaProg(position: Duration(seconds: 5)));
      await t.pump();
      await t.pump();

      expect(t.widget<Slider>(find.byType(Slider)).value, 5000);

      await api1.dispose();
      await api2.dispose();
    },
  );

  testWidgets(
    'backgrounding while playing pauses, and returning to the foreground '
    'resumes — but backgrounding while already paused (a user pause) leaves '
    'it paused on return',
    (t) async {
      final api = FakeMovaApi();
      api.push(const MovaState(playing: true));
      await t.pumpWidget(MaterialApp(home: MovaPlayer(api: api)));
      await t.pump();

      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      expect(api.calls, contains('pause'));

      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      expect(api.calls, contains('play'));

      api.calls.clear();
      api.push(const MovaState(playing: false));
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      expect(api.calls, isNot(contains('pause')));

      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      expect(api.calls, isNot(contains('play')));

      await api.dispose();
    },
  );
}
