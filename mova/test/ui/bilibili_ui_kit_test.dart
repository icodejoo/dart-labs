import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mova/src/core/options/options.dart';
import 'package:mova/src/ui/scope/scope.dart';
import 'package:mova/src/ui/ui_kits/bilibili_ui_kit.dart';
import 'package:mova/src/ui/slots/slot.dart';
import 'package:mova/src/ui/slots/tree.dart';

import '../support/fake_api.dart';

void main() {
  test('adds a danmaku track and a speed button on top of the default tree', () {
    final uiKit = MovaBilibiliUiKit();
    final names = uiKit.components().map((c) => c.name).toList();
    expect(names, contains('danmakuTrack'));

    final topBar = uiKit.components().firstWhere((c) => c.name == 'topBar');
    final childNames = topBar.children.map((c) => c.name).toList();
    expect(childNames.indexOf('speedButton'), childNames.indexOf('qualityButton') + 1);
  });

  test('the danmaku track is tagged MovaSlot.overlay', () {
    final uiKit = MovaBilibiliUiKit();
    final track = uiKit.components().firstWhere((c) => c.name == 'danmakuTrack');
    expect(track.slot, MovaSlot.overlay);
  });

  testWidgets('renders bilibili chrome end to end when danmaku is enabled', (t) async {
    final api = FakeMovaApi(options: const MovaOpts(danmaku: MovaDanmakuOpts(enabled: true)));
    await t.pumpWidget(MaterialApp(
      home: MovaScope(
        api: api,
        child: Builder(builder: (c) {
          final uiKit = MovaBilibiliUiKit();
          final bundle = buildSlots(c, api, uiKit.components());
          return uiKit.assemble(c, bundle, const SizedBox.expand());
        }),
      ),
    ));
    await t.pump();

    expect(find.byIcon(Icons.speed_rounded), findsOneWidget);
    await api.dispose();
  });
}
