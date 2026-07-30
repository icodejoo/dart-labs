import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:videoman/src/core/api.dart';
import 'package:videoman/src/ui/slots/component.dart';
import 'package:videoman/src/ui/slots/patch.dart';
import 'package:videoman/src/ui/slots/slot.dart';
import 'package:videoman/src/ui/slots/tree.dart';

import '../support/fake_api.dart';

/// Minimal leaf used to assert tree shape.
///
/// 用于断言组件树形状的最小叶子组件。
class _Leaf extends VmComponent {
  @override
  final String name;
  @override
  final VmSlot slot;
  @override
  final int order;
  _Leaf(this.name, {this.slot = VmSlot.top, this.order = 0});
  @override
  Widget build(BuildContext c, VmApi api, List<Widget> children) => Text(name);
}

/// Minimal composite that lays its children out in a row.
///
/// 把子组件横向排布的最小组合组件。
class _Group extends VmComponent {
  @override
  final String name;
  @override
  final VmSlot slot;
  @override
  final List<VmComponent> children;
  _Group(this.name, this.children, {this.slot = VmSlot.top});
  @override
  Widget build(BuildContext c, VmApi api, List<Widget> children) => Row(children: children);
}

List<String> _names(List<VmComponent> t) =>
    t.expand((c) => [c.name, ...c.children.map((k) => '${c.name}/${k.name}')]).toList();

void main() {
  List<VmComponent> tree() => [
        _Group('topBar', [_Leaf('title'), _Leaf('pip'), _Leaf('lock')], slot: VmSlot.top),
      ];

  test('replace swaps a nested component by path', () {
    final out = applyPatches(tree(), [VmPatch.replace('topBar/pip', _Leaf('cast'))]);
    expect(_names(out), ['topBar', 'topBar/title', 'topBar/cast', 'topBar/lock']);
  });

  test('replace swaps a whole composite by path', () {
    final out = applyPatches(tree(), [VmPatch.replace('topBar', _Leaf('bare'))]);
    expect(_names(out), ['bare']);
  });

  test('remove drops a nested component', () {
    final out = applyPatches(tree(), [VmPatch.remove('topBar/pip')]);
    expect(_names(out), ['topBar', 'topBar/title', 'topBar/lock']);
  });

  test('insertAfter puts the new component right after the anchor', () {
    final out = applyPatches(tree(), [VmPatch.insertAfter('topBar/title', _Leaf('x'))]);
    expect(_names(out), ['topBar', 'topBar/title', 'topBar/x', 'topBar/pip', 'topBar/lock']);
  });

  test('add appends a new top-level component to a slot', () {
    final out = applyPatches(tree(), [VmPatch.add(VmSlot.overlay, _Leaf('ad', slot: VmSlot.overlay))]);
    expect(out.last.name, 'ad');
    expect(out.last.slot, VmSlot.overlay);
  });

  test('add tags the appended component with the patch\'s slot/order, not its own', () {
    // The leaf's own slot/order (top, 5) deliberately differ from what the
    // patch requests (bottom, 9) — the patch's values must win.
    //
    // 叶子自身的 slot/order（top, 5）故意与补丁请求的（bottom, 9）不同——
    // 补丁的值必须生效。
    final own = _Leaf('ad', slot: VmSlot.top, order: 5);
    final out = applyPatches(tree(), [VmPatch.add(VmSlot.bottom, own, order: 9)]);
    expect(out.last.name, 'ad');
    expect(out.last.slot, VmSlot.bottom);
    expect(out.last.order, 9);
  });

  test('an unmatched path is a no-op, not a crash', () {
    final out = applyPatches(tree(), [VmPatch.remove('nope/nope')]);
    expect(_names(out), _names(tree()));
  });

  testWidgets('buildSlots groups widgets by slot and sorts by order', (t) async {
    final api = FakeVmApi();
    final treeIn = <VmComponent>[
      _Leaf('b', slot: VmSlot.top, order: 2),
      _Leaf('a', slot: VmSlot.top, order: 1),
      _Leaf('o', slot: VmSlot.overlay),
    ];
    late VmSlotBundle bundle;
    await t.pumpWidget(MaterialApp(home: Builder(builder: (c) {
      bundle = buildSlots(c, api, treeIn);
      return Column(children: bundle[VmSlot.top]);
    })));
    expect(bundle[VmSlot.top].length, 2);
    expect(bundle[VmSlot.overlay].length, 1);
    expect(find.text('a'), findsOneWidget);
  });
}
