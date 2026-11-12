import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mova/src/core/state/state.dart';
import 'package:mova/src/ui/mini/mini_skin.dart';
import 'package:mova/src/ui/player.dart';
import 'package:mova/src/ui/skins/default_skin.dart';

import '../../support/fake_api.dart';

void main() {
  test('MovaMiniSkin.components() returns exactly centerPlay, buffering, miniClose', () {
    final names = const MovaMiniSkin().components().map((c) => c.name).toList();
    expect(names, ['centerPlay', 'buffering', 'miniClose']);
  });

  testWidgets('no seek bar / quality button / fullscreen button inside the mini window chrome', (tester) async {
    final api = FakeMovaApi();
    await tester.pumpWidget(MaterialApp(
      home: MovaPlayer(api: api, skin: const MovaMiniSkin()),
    ));
    expect(find.byIcon(Icons.fullscreen_rounded), findsNothing);
    expect(find.byType(Slider), findsNothing, reason: 'the seek bar is a Slider; mini chrome has no bottom bar at all');
    expect(find.byIcon(Icons.high_quality_rounded), findsNothing);
  });

  testWidgets('tapping the close button triggers the injected callback', (tester) async {
    var closed = false;
    final api = FakeMovaApi();
    await tester.pumpWidget(MaterialApp(
      home: MovaPlayer(api: api, skin: MovaMiniSkin(onClose: () => closed = true)),
    ));
    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();
    expect(closed, isTrue);
  });

  testWidgets('MovaState.mini true hides MovaDefaultSkin top/bottom/gesture chrome and lock toggle', (tester) async {
    final api = FakeMovaApi();
    api.push(const MovaState(mini: true));
    await tester.pumpWidget(MaterialApp(
      home: MovaPlayer(api: api, skin: const MovaDefaultSkin()),
    ));
    expect(find.byIcon(Icons.fullscreen_rounded), findsNothing, reason: 'top bar hidden while mini');
    expect(find.byType(Slider), findsNothing, reason: 'bottom bar hidden while mini');
    expect(find.byIcon(Icons.lock_open_rounded), findsNothing,
        reason: '页面控制条交给小窗后，页面锁定入口也隐藏');
  });

  testWidgets('MovaState.mini false leaves MovaDefaultSkin chrome unaffected (closed-state regression)', (tester) async {
    final api = FakeMovaApi();
    await tester.pumpWidget(MaterialApp(
      home: MovaPlayer(api: api, skin: const MovaDefaultSkin()),
    ));
    expect(find.byIcon(Icons.fullscreen_rounded), findsOneWidget);
    expect(find.byIcon(Icons.lock_open_rounded), findsOneWidget);
  });
}
