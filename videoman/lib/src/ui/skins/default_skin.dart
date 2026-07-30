import 'package:flutter/material.dart';

import '../../core/model/source.dart';
import '../../core/state/state.dart';
import '../components/bottom_bar.dart';
import '../components/center_play.dart';
import '../components/gesture_layer.dart';
import '../components/hud_layer.dart';
import '../components/live_bar.dart';
import '../components/overlays.dart';
import '../components/top_bar.dart';
import '../scope/scope.dart';
import '../scope/selector.dart';
import '../slots/component.dart';
import '../slots/patch.dart';
import '../slots/slot.dart';
import '../slots/tree.dart';
import 'skin.dart';

/// The built-in [VmSkin]: reproduces 0.1.0's default look for both VOD and
/// live sources, extended with the new buffering/error/lock overlays that
/// 0.1.0 never had.
///
/// [components] swaps [BottomBarComponent] for [LiveBarComponent] based on
/// [VmState.type] — both share the top-level name `bottomBar`, which is the
/// intentional swap point between the VOD and live trees. [assemble]
/// reproduces 0.1.0's `Column`-based bar layout: video → gesture layer →
/// top/center/bottom chrome → HUD → full-bleed overlays, with the top/bottom
/// bars fading and becoming tap-through via [VmUiState.controlsVisible].
///
/// 内置 [VmSkin]：对点播与直播都复刻 0.1.0 的默认外观，并扩展了 0.1.0 从未有
/// 过的缓冲/错误/锁定叠加层。
///
/// [components] 依据 [VmState.type] 在 [BottomBarComponent] 与
/// [LiveBarComponent] 之间切换——二者顶层 `name` 都是 `bottomBar`，这正是
/// 点播树与直播树之间刻意设计的替换点。[assemble] 复刻 0.1.0 基于 `Column`
/// 的分栏布局：视频画面 → 手势层 → 顶/中/底栏 chrome → HUD → 全屏叠加层，
/// 顶/底栏随 [VmUiState.controlsVisible] 渐隐并变为可穿透点击。
class VmDefaultSkin implements VmSkin {
  /// Creates the default skin, optionally applying [patches] to its tree.
  ///
  /// 创建默认皮肤，可选地对其组件树应用 [patches]。
  const VmDefaultSkin({this.patches = const []});

  /// Structural patches applied to the base tree in [components], in order.
  ///
  /// [components] 中基础组件树依序应用的结构性补丁。
  final List<VmPatch> patches;

  @override
  List<VmComponent> components(VmState s) => applyPatches([
        GestureLayerComponent(),
        HudLayerComponent(),
        TopBarComponent(),
        CenterPlayComponent(),
        s.type == VmStreamType.live ? LiveBarComponent() : BottomBarComponent(),
        BufferingComponent(),
        ErrorComponent(),
        LockMaskComponent(),
      ], patches);

  @override
  Widget assemble(BuildContext context, VmSlotBundle slots, Widget video) {
    return Stack(
      children: [
        Positioned.fill(child: video),
        Positioned.fill(child: Stack(children: slots[VmSlot.gesture])),
        Positioned.fill(
          child: Column(
            children: [
              _BarVisibility(child: Column(children: slots[VmSlot.top])),
              Expanded(child: Stack(children: slots[VmSlot.center])),
              _BarVisibility(
                child: Column(
                  children: [...slots[VmSlot.bottomAbove], ...slots[VmSlot.bottom]],
                ),
              ),
            ],
          ),
        ),
        Positioned.fill(child: Stack(children: slots[VmSlot.hud])),
        Positioned.fill(child: Stack(children: slots[VmSlot.overlay])),
      ],
    );
  }
}

/// Fades [child] in/out with [VmUiState.controlsVisible] and, while hidden,
/// lets taps pass through to the gesture layer below instead of absorbing
/// them — reproducing 0.1.0's "hidden bars are tap-through" rule for the
/// top/bottom chrome.
///
/// 依据 [VmUiState.controlsVisible] 渐显/渐隐 [child]；隐藏时点击会穿透到
/// 下方的手势层，而非被自身吸收——复刻 0.1.0"隐藏时的栏可被穿透点击"的规则。
class _BarVisibility extends StatelessWidget {
  /// Creates the visibility wrapper around [child].
  ///
  /// 创建包裹 [child] 的显隐控制组件。
  const _BarVisibility({required this.child});

  /// The bar content whose visibility/hit-testing this widget controls.
  ///
  /// 该组件控制其显隐/点击测试的栏内容。
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final fadeDuration = VmScope.of(context).options.controls.fadeDuration;
    return VmUiSelector<bool>(
      selector: (s) => s.controlsVisible,
      builder: (context, visible) {
        return IgnorePointer(
          ignoring: !visible,
          child: AnimatedOpacity(
            opacity: visible ? 1 : 0,
            duration: fadeDuration,
            child: child,
          ),
        );
      },
    );
  }
}
