import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:videoman/src/core/options/options.dart';
import 'package:videoman/src/ui/scope/scope.dart';
import 'package:videoman/src/ui/skins/bilibili_skin.dart';
import 'package:videoman/src/ui/slots/slot.dart';
import 'package:videoman/src/ui/slots/tree.dart';

import '../support/fake_api.dart';

void main() {
  test('adds a danmaku track and a speed button on top of the default tree', () {
    final skin = VmBilibiliSkin();
    final names = skin.components().map((c) => c.name).toList();
    expect(names, contains('danmakuTrack'));

    final topBar = skin.components().firstWhere((c) => c.name == 'topBar');
    final childNames = topBar.children.map((c) => c.name).toList();
    expect(childNames.indexOf('speedButton'), childNames.indexOf('qualityButton') + 1);
  });

  test('the danmaku track is tagged VmSlot.overlay', () {
    final skin = VmBilibiliSkin();
    final track = skin.components().firstWhere((c) => c.name == 'danmakuTrack');
    expect(track.slot, VmSlot.overlay);
  });

  testWidgets('renders bilibili chrome end to end when danmaku is enabled', (t) async {
    final api = FakeVmApi(options: const VmOptions(danmaku: VmDanmakuConfig(enabled: true)));
    await t.pumpWidget(MaterialApp(
      home: VmScope(
        api: api,
        child: Builder(builder: (c) {
          final skin = VmBilibiliSkin();
          final bundle = buildSlots(c, api, skin.components());
          return skin.assemble(c, bundle, const SizedBox.expand());
        }),
      ),
    ));
    await t.pump();

    expect(find.byIcon(Icons.speed_rounded), findsOneWidget);
    await api.dispose();
  });
}
