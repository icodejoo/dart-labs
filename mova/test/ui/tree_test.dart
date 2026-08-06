import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mova/src/core/api.dart';
import 'package:mova/src/ui/slots/component.dart';
import 'package:mova/src/ui/slots/patch.dart';
import 'package:mova/src/ui/slots/slot.dart';
import 'package:mova/src/ui/slots/tree.dart';

import '../support/fake_api.dart';

/// Minimal leaf used to assert tree shape.
///
/// 用于断言组件树形状的最小叶子组件。
class _Leaf extends MovaComp {
  @override
  final String name;
  @override
  final MovaSlot slot;
  @override
  final int order;
  _Leaf(this.name, {this.slot = MovaSlot.top, this.order = 0});
  @override
  Widget build(BuildContext c, MovaApi api, List<Widget> children) => Text(name);
}

/// Minimal composite that lays its children out in a row.
///
/// 把子组件横向排布的最小组合组件。
class _Group extends MovaComp {
  @override
  final String name;
  @override
  final MovaSlot slot;
  @override
  final List<MovaComp> children;
  _Group(this.name, this.children, {this.slot = MovaSlot.top});
  @override
  Widget build(BuildContext c, MovaApi api, List<Widget> children) => Row(children: children);
}

List<String> _names(List<MovaComp> t) =>
    t.expand((c) => [c.name, ...c.children.map((k) => '${c.name}/${k.name}')]).toList();

void main() {
  List<MovaComp> tree() => [
        _Group('topBar', [_Leaf('title'), _Leaf('pip'), _Leaf('lock')], slot: MovaSlot.top),
      ];

  test('replace swaps a nested component by path', () {
    final out = applyPatches(tree(), [MovaPatch.replace('topBar/pip', _Leaf('cast'))]);
    expect(_names(out), ['topBar', 'topBar/title', 'topBar/cast', 'topBar/lock']);
  });

  test('replace swaps a whole composite by path', () {
    final out = applyPatches(tree(), [MovaPatch.replace('topBar', _Leaf('bare'))]);
    expect(_names(out), ['bare']);
  });

  test('remove drops a nested component', () {
    final out = applyPatches(tree(), [MovaPatch.remove('topBar/pip')]);
    expect(_names(out), ['topBar', 'topBar/title', 'topBar/lock']);
  });

  test('insertAfter puts the new component right after the anchor', () {
    final out = applyPatches(tree(), [MovaPatch.insertAfter('topBar/title', _Leaf('x'))]);
    expect(_names(out), ['topBar', 'topBar/title', 'topBar/x', 'topBar/pip', 'topBar/lock']);
  });

  test('add appends a new top-level component to a slot', () {
    final out = applyPatches(tree(), [MovaPatch.add(MovaSlot.overlay, _Leaf('ad', slot: MovaSlot.overlay))]);
    expect(out.last.name, 'ad');
    expect(out.last.slot, MovaSlot.overlay);
  });

  test('add tags the appended component with the patch\'s slot/order, not its own', () {
    // The leaf's own slot/order (top, 5) deliberately differ from what the
    // patch requests (bottom, 9) — the patch's values must win.
    //
    // 叶子自身的 slot/order（top, 5）故意与补丁请求的（bottom, 9）不同——
    // 补丁的值必须生效。
    final own = _Leaf('ad', slot: MovaSlot.top, order: 5);
    final out = applyPatches(tree(), [MovaPatch.add(MovaSlot.bottom, own, order: 9)]);
    expect(out.last.name, 'ad');
    expect(out.last.slot, MovaSlot.bottom);
    expect(out.last.order, 9);
  });

  test('an unmatched path is a no-op, not a crash', () {
    final out = applyPatches(tree(), [MovaPatch.remove('nope/nope')]);
    expect(_names(out), _names(tree()));
  });

  testWidgets('buildSlots groups widgets by slot and sorts by order', (t) async {
    final api = FakeMovaApi();
    final treeIn = <MovaComp>[
      _Leaf('b', slot: MovaSlot.top, order: 2),
      _Leaf('a', slot: MovaSlot.top, order: 1),
      _Leaf('o', slot: MovaSlot.overlay),
    ];
    late MovaSlotBundle bundle;
    await t.pumpWidget(MaterialApp(home: Builder(builder: (c) {
      bundle = buildSlots(c, api, treeIn);
      return Column(children: bundle[MovaSlot.top]);
    })));
    expect(bundle[MovaSlot.top].length, 2);
    expect(bundle[MovaSlot.overlay].length, 1);
    expect(find.text('a'), findsOneWidget);
  });
}
