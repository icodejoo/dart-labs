import 'package:flutter/widgets.dart';

import '../../core/state/state.dart';
import '../slots/component.dart';
import '../slots/tree.dart';

/// A pluggable player "skin": decides which [VmComponent]s exist for a given
/// [VmState] and how the resulting [VmSlotBundle] plus the raw video surface
/// are stacked into the final widget tree.
///
/// Implementations own two independent concerns: [components] (data — the
/// component tree for the current state) and [assemble] (layout — how the
/// already-built slot widgets and the video surface are composited).
/// Splitting them lets [VmSlotBundle] be built once (via [buildSlots]) and
/// reused by callers that only care about one side.
///
/// 可插拔的播放器"皮肤"：决定给定 [VmState] 下存在哪些 [VmComponent]，以及
/// 构建出的 [VmSlotBundle] 与原始视频画面如何叠装成最终 widget 树。
///
/// 实现方需关心两个独立职责：[components]（数据——当前状态下的组件树）与
/// [assemble]（布局——已构建好的槽位 widget 与视频画面如何合成）。二者拆开
/// 使得 [VmSlotBundle] 可以只构建一次（通过 [buildSlots]）并被只关心其中一侧
/// 的调用方复用。
abstract class VmSkin {
  /// Returns the component tree to build for the current [s].
  ///
  /// Called on every relevant state change so the tree can differ by
  /// [VmState.type] (e.g. VOD vs live bottom bar) or any other field.
  ///
  /// 返回当前状态 [s] 下应构建的组件树。
  ///
  /// 每次相关状态变化都会调用，因此树可以按 [VmState.type]（例如点播/直播
  /// 底栏）或其他字段而不同。
  List<VmComponent> components(VmState s);

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
