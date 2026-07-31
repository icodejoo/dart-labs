import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:videoman/src/core/api.dart';
import 'package:videoman/src/core/model/source.dart';
import 'package:videoman/src/core/state/state.dart';
import 'package:videoman/src/ui/scope/scope.dart';
import 'package:videoman/src/ui/skins/default_skin.dart';
import 'package:videoman/src/ui/slots/component.dart';
import 'package:videoman/src/ui/slots/patch.dart';
import 'package:videoman/src/ui/slots/slot.dart';
import 'package:videoman/src/ui/slots/tree.dart';

import '../support/fake_api.dart';

/// Minimal leaf carrying a [Key], used to locate where a slot renders.
///
/// 携带 [Key] 的最小叶子组件，用于定位某槽位渲染到何处。
class _Marker extends VmComponent {
  _Marker(this.name, this.slot);
  @override
  final String name;
  @override
  final VmSlot slot;
  @override
  Widget build(BuildContext c, VmApi api, List<Widget> children) =>
      SizedBox(key: ValueKey(name), width: 20, height: 20);
}

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
    expect(bottom.children.map((c) => c.name),
        ['liveBadge', 'seekBar', 'timeshift', 'backToLive']);
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

  test('the default tree mounts the preview bubble in the bottomAbove slot', () {
    final tree = const VmDefaultSkin().components(const VmState());
    final preview = tree.firstWhere((c) => c.name == 'preview');
    expect(preview.slot, VmSlot.bottomAbove);
  });

  testWidgets('assemble renders left/right slot content on the matching edge', (t) async {
    final api = FakeVmApi();
    final skin = VmDefaultSkin(patches: [
      VmPatch.add(VmSlot.left, _Marker('leftMark', VmSlot.left)),
      VmPatch.add(VmSlot.right, _Marker('rightMark', VmSlot.right)),
    ]);
    await t.pumpWidget(MaterialApp(
      home: VmScope(
        api: api,
        child: Builder(builder: (c) {
          final bundle = buildSlots(c, api, skin.components(api.state));
          return skin.assemble(c, bundle, const ColoredBox(color: Color(0xFF000000)));
        }),
      ),
    ));
    final leftBox = t.getRect(find.byKey(const ValueKey('leftMark')));
    final rightBox = t.getRect(find.byKey(const ValueKey('rightMark')));
    final screen = t.getSize(find.byType(MaterialApp));
    // Left marker hugs the left edge; right marker hugs the right edge.
    // 左标记贴左缘，右标记贴右缘。
    expect(leftBox.left, 0);
    expect(rightBox.right, screen.width);
    await api.dispose();
  });
}
