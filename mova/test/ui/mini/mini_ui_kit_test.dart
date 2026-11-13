import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mova/src/core/state/state.dart';
import 'package:mova/src/ui/mini/mini_ui_kit.dart';
import 'package:mova/src/ui/player.dart';
import 'package:mova/src/ui/ui_kits/default_ui_kit.dart';

import '../../support/fake_api.dart';

void main() {
  test('MovaMiniUiKit.components() returns exactly centerPlay, buffering, miniClose', () {
    final names = const MovaMiniUiKit().components().map((c) => c.name).toList();
    expect(names, ['centerPlay', 'buffering', 'miniClose']);
  });

  testWidgets('no seek bar / quality button / fullscreen button inside the mini window chrome', (tester) async {
    final api = FakeMovaApi();
    await tester.pumpWidget(MaterialApp(
      home: MovaPlayer(api: api, uiKit: const MovaMiniUiKit()),
    ));
    expect(find.byIcon(Icons.fullscreen_rounded), findsNothing);
    expect(find.byType(Slider), findsNothing, reason: 'the seek bar is a Slider; mini chrome has no bottom bar at all');
    expect(find.byIcon(Icons.high_quality_rounded), findsNothing);
  });

  testWidgets('tapping the close button triggers the injected callback', (tester) async {
    var closed = false;
    final api = FakeMovaApi();
    await tester.pumpWidget(MaterialApp(
      home: MovaPlayer(api: api, uiKit: MovaMiniUiKit(onClose: () => closed = true)),
    ));
    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();
    expect(closed, isTrue);
  });

  testWidgets('MovaState.mini true hides MovaDefaultUiKit top/bottom/gesture chrome and lock toggle', (tester) async {
    final api = FakeMovaApi();
    api.push(const MovaState(mini: true));
    await tester.pumpWidget(MaterialApp(
      home: MovaPlayer(api: api, uiKit: const MovaDefaultUiKit()),
    ));
    expect(find.byIcon(Icons.fullscreen_rounded), findsNothing, reason: 'top bar hidden while mini');
    expect(find.byType(Slider), findsNothing, reason: 'bottom bar hidden while mini');
    expect(find.byIcon(Icons.lock_open_rounded), findsNothing,
        reason: '页面控制条交给小窗后，页面锁定入口也隐藏');
  });

  testWidgets('MovaState.mini false leaves MovaDefaultUiKit chrome unaffected (closed-state regression)', (tester) async {
    final api = FakeMovaApi();
    await tester.pumpWidget(MaterialApp(
      home: MovaPlayer(api: api, uiKit: const MovaDefaultUiKit()),
    ));
    expect(find.byIcon(Icons.fullscreen_rounded), findsOneWidget);
    expect(find.byIcon(Icons.lock_open_rounded), findsOneWidget);
  });
}
