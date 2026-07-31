import 'package:flutter/widgets.dart';

import '../slots/component.dart';
import '../slots/tree.dart';

/// A pluggable player "skin": decides which [VmComponent]s exist and how the
/// resulting [VmSlotBundle] plus the raw video surface are stacked into the
/// final widget tree.
///
/// Implementations own two independent concerns: [components] (data — the
/// static component tree) and [assemble] (layout — how the already-built slot
/// widgets and the video surface are composited). Splitting them lets
/// [VmSlotBundle] be built once (via [buildSlots]) and reused by callers that
/// only care about one side.
///
/// 可插拔的播放器"皮肤"：决定存在哪些 [VmComponent]，以及构建出的
/// [VmSlotBundle] 与原始视频画面如何叠装成最终 widget 树。
///
/// 实现方需关心两个独立职责：[components]（数据——静态组件树）与
/// [assemble]（布局——已构建好的槽位 widget 与视频画面如何合成）。二者拆开
/// 使得 [VmSlotBundle] 可以只构建一次（通过 [buildSlots]）并被只关心其中一侧
/// 的调用方复用。
abstract class VmSkin {
  /// Returns the static component tree.
  ///
  /// The tree does **not** vary by state: components self-gate their own
  /// visibility reactively (via `VmSelector`), so the skin builds the tree
  /// once instead of recomputing it on every state change. A component that
  /// only applies to some sources (e.g. the live badge) simply renders
  /// nothing when it doesn't apply.
  ///
  /// 返回静态组件树。
  ///
  /// 该树**不**随状态变化：组件通过 `VmSelector` 响应式地自我显隐，因此皮肤
  /// 只构建树一次，而非每次状态变化都重算。只适用于部分源的组件（如直播角标）
  /// 在不适用时直接不渲染任何内容即可。
  List<VmComponent> components();

  /// Composes the already-built [slots] and the raw [video] surface into the
  /// final widget tree for [context].
  ///
  /// [video] is the rendered video surface (owned by the caller, e.g.
  /// `VmPlayer`, not by this skin). [slots] holds every top-level component
  /// already built and grouped by [VmSlot] via [buildSlots]. Returns the
  /// composed [Widget] to mount.
  ///
  /// 把已构建好的 [slots] 与原始视频画面 [video] 合成为 [context] 下的最终
  /// widget 树。
  ///
  /// [video] 是已渲染好的视频画面（由调用方，例如 `VmPlayer`，持有，本皮肤
  /// 不拥有它）。[slots] 是通过 [buildSlots] 已构建并按 [VmSlot] 分组的全部
  /// 顶层组件。返回要挂载的合成后的 [Widget]。
  Widget assemble(BuildContext context, VmSlotBundle slots, Widget video);
}
