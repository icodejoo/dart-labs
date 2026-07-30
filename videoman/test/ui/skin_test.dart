import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:videoman/src/core/model/source.dart';
import 'package:videoman/src/core/state/state.dart';
import 'package:videoman/src/ui/scope/scope.dart';
import 'package:videoman/src/ui/skins/default_skin.dart';
import 'package:videoman/src/ui/slots/patch.dart';
import 'package:videoman/src/ui/slots/tree.dart';

import '../support/fake_api.dart';

void main() {
  test('default skin emits the VOD tree for a vod source', () {
    const skin = VmDefaultSkin();
    final names = skin.components(const VmState()).map((c) => c.name).toList();
    expect(names, containsAll(['gestureLayer', 'hudLayer', 'topBar', 'centerPlay', 'bottomBar']));
    final bottom = skin.components(const VmState()).firstWhere((c) => c.name == 'bottomBar');
    expect(bottom.children.map((c) => c.name), ['positionLabel', 'seekBar', 'durationLabel']);
  });

  test('default skin emits the live tree for a live source', () {
    const skin = VmDefaultSkin();
    final bottom = skin
        .components(const VmState(type: VmStreamType.live))
        .firstWhere((c) => c.name == 'bottomBar');
    expect(bottom.children.map((c) => c.name), ['liveBadge', 'backToEdge']);
  });

  test('patches passed to the default skin are applied to its tree', () {
    final skin = VmDefaultSkin(patches: [VmPatch.remove('topBar/pipButton')]);
    final top = skin.components(const VmState()).firstWhere((c) => c.name == 'topBar');
    expect(top.children.map((c) => c.name), isNot(contains('pipButton')));
  });

  testWidgets('assemble stacks video at the bottom and overlays on top', (t) async {
    final api = FakeVmApi();
    const skin = VmDefaultSkin();
    await t.pumpWidget(MaterialApp(
      home: VmScope(
        api: api,
        child: Builder(builder: (c) {
          final bundle = buildSlots(c, api, skin.components(api.state));
          return skin.assemble(c, bundle, const ColoredBox(color: Color(0xFF000000)));
        }),
      ),
    ));
    expect(find.byType(Stack), findsWidgets);
    await api.dispose();
  });
}
