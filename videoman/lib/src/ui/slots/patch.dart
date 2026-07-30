import 'component.dart';
import 'slot.dart';

/// A pending mutation to apply to a component tree via [applyPatches].
///
/// Patches are data, not actions — [applyPatches] is the only place that
/// interprets them, keeping tree mutation a pure, testable function.
///
/// 待应用到组件树的一次变更，通过 [applyPatches] 生效。
///
/// 补丁只是数据而非动作——只有 [applyPatches] 会解释它们，从而让树的变更
/// 保持为一个纯函数、便于测试。
sealed class VmPatch {
  const VmPatch();

  /// Replaces the component found at [path] with [component].
  ///
  /// If [path] has no `/` it targets a top-level tree entry and the whole
  /// entry (including its children) is swapped out. If [path] contains a
  /// `/` it targets a descendant, replacing only that node while leaving
  /// its parent's identity and other children untouched.
  ///
  /// 用 [component] 替换 [path] 处找到的组件。
  ///
  /// 若 [path] 不含 `/`，则指向顶层条目，整个条目（含其子节点）都会被替换；
  /// 若含 `/`，则指向某个后代节点，只替换该节点，父节点自身及其其他子节点
  /// 保持不变。
  const factory VmPatch.replace(String path, VmComponent component) = VmPatchReplace;

  /// Removes the component found at [path].
  ///
  /// A top-level [path] (no `/`) removes that whole tree entry; a nested
  /// [path] removes just that child from its parent's [VmComponent.children].
  ///
  /// 移除 [path] 处找到的组件。
  ///
  /// 顶层路径（不含 `/`）会移除整个树条目；嵌套路径只会从其父节点的
  /// [VmComponent.children] 中移除该子节点。
  const factory VmPatch.remove(String path) = VmPatchRemove;

  /// Inserts [component] as a new sibling immediately after the node at
  /// [path], at the same nesting level as that anchor.
  ///
  /// 在 [path] 处的节点之后插入 [component] 作为新的同级兄弟节点，嵌套层级
  /// 与该锚点相同。
  const factory VmPatch.insertAfter(String path, VmComponent component) = VmPatchInsertAfter;

  /// Appends a brand-new top-level [component] to the tree, tagged with
  /// [slot] and sorted by [order] within that slot.
  ///
  /// 向树追加一个全新的顶层组件 [component]，标记为 [slot]，并在该槽位内
  /// 按 [order] 排序。
  const factory VmPatch.add(VmSlot slot, VmComponent component, {int order}) = VmPatchAdd;
}

/// See [VmPatch.replace].
///
/// 参见 [VmPatch.replace]。
final class VmPatchReplace extends VmPatch {
  const VmPatchReplace(this.path, this.component);

  /// Target path of the node to replace.
  ///
  /// 待替换节点的目标路径。
  final String path;

  /// The replacement component.
  ///
  /// 用作替换的组件。
  final VmComponent component;
}

/// See [VmPatch.remove].
///
/// 参见 [VmPatch.remove]。
final class VmPatchRemove extends VmPatch {
  const VmPatchRemove(this.path);

  /// Target path of the node to remove.
  ///
  /// 待移除节点的目标路径。
  final String path;
}

/// See [VmPatch.insertAfter].
///
/// 参见 [VmPatch.insertAfter]。
final class VmPatchInsertAfter extends VmPatch {
  const VmPatchInsertAfter(this.path, this.component);

  /// Path of the anchor node the new component is inserted after.
  ///
  /// 新组件将插入其后的锚点节点路径。
  final String path;

  /// The component to insert.
  ///
  /// 要插入的组件。
  final VmComponent component;
}

/// See [VmPatch.add].
///
/// 参见 [VmPatch.add]。
final class VmPatchAdd extends VmPatch {
  const VmPatchAdd(this.slot, this.component, {this.order = 0});

  /// Slot the new top-level component is tagged with.
  ///
  /// 新顶层组件所标记的槽位。
  final VmSlot slot;

  /// The component to append.
  ///
  /// 要追加的组件。
  final VmComponent component;

  /// Sort order within [slot].
  ///
  /// 在 [slot] 内的排序值。
  final int order;
}
