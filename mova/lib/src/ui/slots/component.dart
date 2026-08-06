import 'package:flutter/widgets.dart';

import '../../core/api.dart';
import 'slot.dart';

/// A single addressable node in the player's component tree.
///
/// Every node has a stable [name] used to build dotted/slashed paths for
/// [MovaPatch] targeting, a [slot] deciding which region of the overlay it
/// renders into, an [order] used for stable within-slot sorting, and
/// optional [children] for composite nodes (e.g. a control-bar group).
/// [build] receives its children already built as [Widget]s — composites
/// never see raw [MovaComp] children.
///
/// 播放器组件树中的可寻址节点。
///
/// 每个节点都有稳定的 [name]，用于拼接 [MovaPatch] 目标路径；[slot] 决定它
/// 渲染到叠加层的哪个区域；[order] 用于同槽位内的稳定排序；[children] 是
/// 组合节点（例如控制条分组）的可选子节点。[build] 收到的子节点已构建为
/// [Widget]——组合组件永远不会看到原始的 [MovaComp] 子节点。
abstract class MovaComp {
  /// Stable identifier used for path matching in [MovaPatch] operations.
  ///
  /// 用于 [MovaPatch] 操作路径匹配的稳定标识符。
  String get name;

  /// The overlay region this component renders into.
  ///
  /// This only takes effect for components at the top level of the tree
  /// (entries returned directly by [MovaSkin.components]) — [buildSlots]
  /// reads [slot]/[order] only from those top-level entries. For a node
  /// nested under another component's [children], this value is inert:
  /// its parent's [build] positions it directly via the built [children]
  /// list, not via slot placement.
  ///
  /// 该组件渲染到的叠加层区域。
  ///
  /// 该属性仅对树顶层的组件（即 [MovaSkin.components] 直接返回的条目）生效——
  /// [buildSlots] 只从这些顶层条目读取 [slot]/[order]。若节点是嵌套在另一
  /// 组件的 [children] 中，该值不会生效：其父组件的 [build] 会直接通过已
  /// 构建的 [children] 列表来布局它，而非按槽位放置。
  MovaSlot get slot;

  /// Sort key within a slot; ascending, ties broken by original position.
  ///
  /// 槽位内的排序键；升序排列，相同值按原始位置决出先后。
  int get order => 0;

  /// Nested child components, if this node is a composite. Empty for leaves.
  ///
  /// 若该节点为组合节点，则为其嵌套子组件；叶子节点为空列表。
  List<MovaComp> get children => const [];

  /// Builds the widget for this component.
  ///
  /// [context] is the current build context, [api] is the capability
  /// surface this component may read from, and [children] are this node's
  /// [children] already built into widgets in the same order. Returns the
  /// [Widget] to render for this node.
  ///
  /// 构建该组件对应的 widget。
  ///
  /// [context] 是当前构建上下文，[api] 是该组件可读取的能力面，[children]
  /// 是本节点的 [children] 已按相同顺序构建好的 widget 列表。返回该节点要
  /// 渲染的 [Widget]。
  Widget build(BuildContext context, MovaApi api, List<Widget> children);
}
