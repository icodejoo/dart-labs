import 'package:flutter/widgets.dart';

import '../../core/api.dart';
import 'component.dart';
import 'patch.dart';
import 'slot.dart';

/// Applies [patches] to [tree] and returns a new tree; never mutates the
/// input and never throws — an unmatched path is silently a no-op.
///
/// Paths are dotted by nesting: a top-level component's path is its
/// [VmComponent.name]; a nested component's path is
/// `<parent.name>/<child.name>`, recursing to arbitrary depth by joining
/// each ancestor's name in order.
///
/// 把 [patches] 应用到 [tree] 上并返回一棵新树；绝不修改输入，也绝不抛出
/// 异常——未匹配到的路径静默地什么都不做。
///
/// 路径按嵌套层级用 `/` 拼接：顶层组件的路径就是其 [VmComponent.name]；
/// 嵌套组件的路径是 `<parent.name>/<child.name>`，可递归拼接到任意深度。
List<VmComponent> applyPatches(List<VmComponent> tree, List<VmPatch> patches) {
  var result = tree;
  for (final patch in patches) {
    result = _applyOne(result, patch);
  }
  return result;
}

/// Applies a single [patch] to [tree] and returns the resulting tree.
///
/// 把单个 [patch] 应用到 [tree] 上并返回结果树。
List<VmComponent> _applyOne(List<VmComponent> tree, VmPatch patch) {
  switch (patch) {
    case VmPatchAdd():
      return [
        ...tree,
        _CopyComponent(
          patch.component,
          patch.component.children,
          slotOverride: patch.slot,
          orderOverride: patch.order,
        ),
      ];
    case VmPatchReplace():
      return _replaceAt(tree, patch.path, patch.component);
    case VmPatchRemove():
      return _removeAt(tree, patch.path);
    case VmPatchInsertAfter():
      return _insertAfterAt(tree, patch.path, patch.component);
  }
}

/// Recursively replaces the node at [path] within [nodes] with
/// [replacement], returning a new list. If [path] has no more `/` segments
/// left to descend, the direct match (if any) is swapped; otherwise the
/// match's `children` are recursed into with the remaining path.
///
/// 递归地把 [nodes] 中 [path] 处的节点替换为 [replacement]，返回新列表。
/// 若 [path] 已无剩余的 `/` 分段，直接替换匹配到的节点；否则递归进入匹配
/// 节点的 `children`，用剩余路径继续查找。
List<VmComponent> _replaceAt(List<VmComponent> nodes, String path, VmComponent replacement) {
  final segments = path.split('/');
  final head = segments.first;
  final rest = segments.skip(1).join('/');
  return nodes.map((node) {
    if (node.name != head) return node;
    if (rest.isEmpty) return replacement;
    return _CopyComponent(node, _replaceAt(node.children, rest, replacement));
  }).toList();
}

/// Recursively removes the node at [path] from [nodes], returning a new
/// list. A top-level match (no remaining path) drops the whole entry; a
/// deeper match drops only that child from its parent's children.
///
/// 递归地从 [nodes] 中移除 [path] 处的节点，返回新列表。顶层匹配（路径已
/// 无剩余分段）会丢弃整个条目；更深层的匹配只会从其父节点的 children 中
/// 丢弃该子节点。
List<VmComponent> _removeAt(List<VmComponent> nodes, String path) {
  final segments = path.split('/');
  final head = segments.first;
  final rest = segments.skip(1).join('/');
  if (rest.isEmpty) {
    return nodes.where((n) => n.name != head).toList();
  }
  return nodes.map((node) {
    if (node.name != head) return node;
    return _CopyComponent(node, _removeAt(node.children, rest));
  }).toList();
}

/// Recursively inserts [addition] immediately after the node at [path]
/// within [nodes], at the same nesting level as that anchor, returning a
/// new list. If the anchor isn't found anywhere, [nodes] is returned
/// unchanged.
///
/// 递归地在 [nodes] 中把 [addition] 插入到 [path] 处节点之后，插入位置与
/// 该锚点同级，返回新列表。若找不到锚点，[nodes] 原样返回。
List<VmComponent> _insertAfterAt(List<VmComponent> nodes, String path, VmComponent addition) {
  final segments = path.split('/');
  final head = segments.first;
  final rest = segments.skip(1).join('/');
  if (rest.isEmpty) {
    final idx = nodes.indexWhere((n) => n.name == head);
    if (idx == -1) return nodes;
    final copy = [...nodes];
    copy.insert(idx + 1, addition);
    return copy;
  }
  return nodes.map((node) {
    if (node.name != head) return node;
    return _CopyComponent(node, _insertAfterAt(node.children, rest, addition));
  }).toList();
}

/// A structural copy of [source] that keeps its identity (name/build) but
/// swaps in [newChildren], and optionally overrides [slot]/[order] — used by
/// the recursive patch helpers to rebuild ancestors of a matched descendant
/// without mutating anything, and by [VmPatchAdd] to tag an appended
/// component with the patch's own slot/order rather than the component's own.
///
/// Note: this wrapper does not preserve [source]'s concrete runtime type —
/// an `is SomeConcreteType` check against a patched ancestor will not match.
///
/// [source] 的结构性拷贝，保留其身份（name/build）但替换为 [newChildren]，
/// 并可选地覆盖 [slot]/[order]——供递归补丁辅助函数在重建匹配后代的祖先节点
/// 时使用（不修改任何原始对象），也供 [VmPatchAdd] 用来给新增的组件打上
/// 补丁自带的 slot/order，而不是组件自身的。
///
/// 注意：此包装不保留 [source] 的具体运行时类型——对被打过补丁的祖先节点做
/// `is SomeConcreteType` 判断不会命中。
class _CopyComponent extends VmComponent {
  _CopyComponent(this._source, this.children, {this.slotOverride, this.orderOverride});

  /// The original component being wrapped.
  ///
  /// 被包装的原始组件。
  final VmComponent _source;

  /// Overridden slot, if provided; falls back to [_source]'s own slot.
  ///
  /// 覆盖用的 slot（若提供）；否则回退到 [_source] 自身的 slot。
  final VmSlot? slotOverride;

  /// Overridden order, if provided; falls back to [_source]'s own order.
  ///
  /// 覆盖用的 order（若提供）；否则回退到 [_source] 自身的 order。
  final int? orderOverride;

  @override
  final List<VmComponent> children;

  @override
  String get name => _source.name;

  @override
  VmSlot get slot => slotOverride ?? _source.slot;

  @override
  int get order => orderOverride ?? _source.order;

  @override
  Widget build(BuildContext context, VmApi api, List<Widget> builtChildren) =>
      _source.build(context, api, builtChildren);
}

/// Groups already-built top-level widgets by [VmSlot] for a single frame.
///
/// Returned by [buildSlots]; index with a [VmSlot] to get the ordered
/// widget list for that region, or an empty list if nothing occupies it.
///
/// 把已构建好的顶层 widget 按 [VmSlot] 分组，供单帧渲染使用。
///
/// 由 [buildSlots] 返回；用 [VmSlot] 取索引即可得到该区域已排序的 widget
/// 列表，若该区域无内容则返回空列表。
class VmSlotBundle {
  /// Creates a bundle backed by a pre-grouped [_bySlot] map.
  ///
  /// 用预先分好组的 [_bySlot] map 创建一个 bundle。
  VmSlotBundle(this._bySlot);

  /// Widgets grouped by slot, already sorted within each slot.
  ///
  /// 按槽位分组的 widget，每个槽位内部已排好序。
  final Map<VmSlot, List<Widget>> _bySlot;

  /// Returns the ordered widgets for [slot], or an empty list if none.
  ///
  /// 返回 [slot] 对应的已排序 widget 列表，若没有则返回空列表。
  List<Widget> operator [](VmSlot slot) => _bySlot[slot] ?? const [];
}

/// Builds every component in [tree] into widgets and groups the resulting
/// top-level widgets by [VmSlot].
///
/// Children are built depth-first before their parent — a composite's
/// [VmComponent.build] always receives already-built [Widget]s, never raw
/// [VmComponent]s. Within a slot, widgets are ordered primarily by
/// [VmComponent.order] ascending, with ties broken by original list
/// position (stable sort).
///
/// 把 [tree] 中的每个组件构建为 widget，并把结果中的顶层 widget 按 [VmSlot]
/// 分组。
///
/// 子节点总是先于父节点以深度优先方式构建——组合组件的 [VmComponent.build]
/// 收到的永远是已构建好的 [Widget]，绝不是原始的 [VmComponent]。同一槽位
/// 内的 widget 主要按 [VmComponent.order] 升序排列，相同值按原始列表位置
/// 决出先后（稳定排序）。
VmSlotBundle buildSlots(BuildContext context, VmApi api, List<VmComponent> tree) {
  final entries = <_BuiltEntry>[];
  for (var i = 0; i < tree.length; i++) {
    final component = tree[i];
    entries.add(_BuiltEntry(
      slot: component.slot,
      order: component.order,
      position: i,
      widget: _buildRecursive(context, api, component),
    ));
  }
  entries.sort((a, b) {
    final byOrder = a.order.compareTo(b.order);
    return byOrder != 0 ? byOrder : a.position.compareTo(b.position);
  });
  final bySlot = <VmSlot, List<Widget>>{};
  for (final entry in entries) {
    bySlot.putIfAbsent(entry.slot, () => []).add(entry.widget);
  }
  return VmSlotBundle(bySlot);
}

/// Builds [component]'s [VmComponent.children] first (recursively), then
/// builds [component] itself with those already-built widgets.
///
/// 先递归构建 [component] 的 [VmComponent.children]，再用这些已构建好的
/// widget 构建 [component] 本身。
Widget _buildRecursive(BuildContext context, VmApi api, VmComponent component) {
  final builtChildren = [
    for (final child in component.children) _buildRecursive(context, api, child),
  ];
  return component.build(context, api, builtChildren);
}

/// A built top-level widget plus the bookkeeping [buildSlots] needs to sort
/// it into the right slot and position.
///
/// 已构建好的顶层 widget，附带 [buildSlots] 用来把它排入正确槽位和位置的
/// 记账信息。
class _BuiltEntry {
  /// Creates an entry from its sort/group keys and the built [widget].
  ///
  /// 用排序/分组键和已构建的 [widget] 创建一个条目。
  _BuiltEntry({required this.slot, required this.order, required this.position, required this.widget});

  /// Slot this widget belongs to.
  ///
  /// 该 widget 所属的槽位。
  final VmSlot slot;

  /// Sort order within [slot].
  ///
  /// 在 [slot] 内的排序值。
  final int order;

  /// Original position in the input tree, used to break order ties.
  ///
  /// 在输入树中的原始位置，用于在 order 相同时决出先后。
  final int position;

  /// The already-built widget for this top-level component.
  ///
  /// 该顶层组件已构建好的 widget。
  final Widget widget;
}
