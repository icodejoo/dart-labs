import 'package:flutter/material.dart';

import '../../core/model/source.dart';
import '../../core/state/state.dart';
import '../components/bottom_bar.dart';
import '../components/center_play.dart';
import '../components/common.dart';
import '../components/gesture_layer.dart';
import '../components/hud_layer.dart';
import '../components/live_bar.dart';
import '../components/overlays.dart';
import '../components/preview.dart';
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
/// intentional swap point between the VOD and live trees.
///
/// [assemble] renders three layers, back to front:
///
/// 1. **播放层 / playback layer** — the raw [video] surface.
/// 2. **操作层 / operable layer** — gesture detection plus the top/center/
///    bottom chrome, all fading and becoming tap-through together as *one*
///    [_BarVisibility] instance on [VmUiState.controlsVisible] (idle
///    auto-hide); hidden outright while locked or in picture-in-picture
///    ([_LockedHidden]/[_PipHidden]), since neither state has any use for it.
/// 3. **常驻层 / persistent layer** — the lock mask and lock/unlock toggle.
///    Always mounted, transparent to hits by default; only the pieces that
///    actually need to intercept touches (the opaque mask while locked) do
///    so. Never gated by auto-hide/pip/lock, because it is what *controls*
///    those states in the first place.
///
/// This structure is the built-in skin's own coherent whole — a from-scratch
/// [VmSkin] is free to lay its layers out completely differently; that
/// customisation is the customiser's business, not this class's.
///
/// 内置 [VmSkin]：对点播与直播都复刻 0.1.0 的默认外观，并扩展了 0.1.0 从未有
/// 过的缓冲/错误/锁定叠加层。
///
/// [components] 依据 [VmState.type] 在 [BottomBarComponent] 与
/// [LiveBarComponent] 之间切换——二者顶层 `name` 都是 `bottomBar`，这正是
/// 点播树与直播树之间刻意设计的替换点。
///
/// [assemble] 由后到前渲染三层：
///
/// 1. **播放层**——原始 [video] 画面。
/// 2. **操作层**——手势探测 + 顶/中/底栏 chrome，全部作为**同一个**
///    [_BarVisibility] 实例随 [VmUiState.controlsVisible]（闲置自动隐藏）一起
///    渐隐并变为可穿透点击；锁定或画中画时整体隐藏（[_LockedHidden]/
///    [_PipHidden]），因为这两种状态下它都毫无用处。
/// 3. **常驻层**——锁定遮罩与锁定/解锁切换按钮。恒定挂载，默认对点击穿透；
///    只有真正需要拦截点击的部分（锁定时的不透明遮罩）才会吸收事件。不受
///    自动隐藏/画中画/锁定门控，因为它本身就是控制这些状态的入口。
///
/// 这套结构是内置皮肤自己的统一整体——完全自建的 [VmSkin] 可以把层次布局得
/// 完全不同；那是定制方自己的事，不是这个类要操心的。
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
        PreviewComponent(),
        s.type == VmStreamType.live
            ? LiveBarComponent(seekable: s.liveSeekable)
            : BottomBarComponent(),
        BufferingComponent(),
        ErrorComponent(),
        LockMaskComponent(),
      ], patches);

  @override
  Widget assemble(BuildContext context, VmSlotBundle slots, Widget video) {
    return Stack(
      children: [
        // 1. 播放层
        Positioned.fill(child: video),
        // 2. 操作层：手势 + 顶/中/底栏，同一个 _BarVisibility 一起淡入淡出；
        //    锁定/画中画时整体隐藏。
        Positioned.fill(
          child: _PipHidden(
            child: _LockedHidden(
              child: Stack(
                children: [
                  Positioned.fill(child: Stack(children: slots[VmSlot.gesture])),
                  Positioned.fill(
                    child: _BarVisibility(
                      child: Column(
                        children: [
                          Column(children: slots[VmSlot.top]),
                          Expanded(child: Stack(children: slots[VmSlot.center])),
                          Column(
                            children: [
                              ...slots[VmSlot.bottomAbove],
                              ...slots[VmSlot.bottom],
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  Positioned.fill(child: Stack(children: slots[VmSlot.hud])),
                ],
              ),
            ),
          ),
        ),
        // 3. 常驻层：锁定遮罩 + 锁定/解锁按钮，恒定挂载、默认穿透，只有真正需要
        //    拦截点击的部分（锁定遮罩）才吸收事件；不受操作层的门控影响，因为
        //    它本身就是控制那些状态的入口。
        Positioned.fill(child: Stack(children: slots[VmSlot.overlay])),
        const Positioned.fill(child: _LockToggleButton()),
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

/// Hides [child] outright while [VmState.pip] is active.
///
/// A floating system picture-in-picture window is a few dozen logical pixels
/// across and offers no gesture surface of its own — the host OS supplies
/// its own play/pause/close affordances — so videoman's entire chrome (gesture
/// layer, bars, HUD) has no useful role there and would only draw over the
/// system's controls.
///
/// [VmState.pip] 生效期间直接隐藏 [child]。
///
/// 系统级画中画悬浮窗只有几十逻辑像素见方，也没有自己的手势操作面——宿主
/// 系统会提供自己的播放/暂停/关闭按钮——因此 videoman 的整套 chrome（手势层、
/// 各栏、HUD）在其中毫无用处，反而会盖住系统自带的控制。
class _PipHidden extends StatelessWidget {
  /// Creates the pip-visibility wrapper around [child].
  ///
  /// 创建包裹 [child] 的画中画显隐控制组件。
  const _PipHidden({required this.child});

  /// The chrome whose visibility this widget controls.
  ///
  /// 该组件控制其显隐的 chrome 内容。
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return VmSelector<bool>(
      selector: (s) => s.pip,
      builder: (context, pip) => pip ? const SizedBox.shrink() : child,
    );
  }
}

/// Hides [child] outright while [VmState.locked] is active.
///
/// Locking is meant to prevent accidental touches during e.g. in-pocket
/// playback; leaving every button visible-but-inert (the pre-fix behaviour)
/// still invites taps that silently do nothing. Hiding the whole chrome and
/// leaving only [LockMaskComponent]'s own unlock affordance (rendered in
/// [VmSlot.overlay], unaffected by this wrapper) matches what users expect
/// from a "locked" screen.
///
/// [VmState.locked] 生效期间直接隐藏 [child]。
///
/// 锁定的本意是防止兜里误触之类的意外点击；此前的行为是把所有按钮留着但让它们
/// 失效，反而诱使用户点一个悄无声息没反应的东西。隐藏整套 chrome、只留
/// [LockMaskComponent] 自带的解锁入口（渲染在 [VmSlot.overlay]，不受本组件
/// 影响），更符合"锁定屏"该有的样子。
class _LockedHidden extends StatelessWidget {
  /// Creates the lock-visibility wrapper around [child].
  ///
  /// 创建包裹 [child] 的锁定显隐控制组件。
  const _LockedHidden({required this.child});

  /// The chrome whose visibility this widget controls.
  ///
  /// 该组件控制其显隐的 chrome 内容。
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return VmSelector<bool>(
      selector: (s) => s.locked,
      builder: (context, locked) => locked ? const SizedBox.shrink() : child,
    );
  }
}

/// The single lock/unlock toggle button, in both directions.
///
/// Lives in the skin's persistent layer (see [VmDefaultSkin.assemble]):
/// always mounted, never gated by [_BarVisibility]'s idle auto-hide, by
/// [_LockedHidden], or by [_PipHidden]. It has to stay reachable regardless of
/// any of those states, because it is the one control that *changes* them —
/// an auto-hidden lock button would leave no way to lock in the first place,
/// and a lock-hidden one no way to unlock.
///
/// 唯一的锁定/解锁切换按钮，两个方向共用同一个组件。
///
/// 位于皮肤的常驻层（见 [VmDefaultSkin.assemble]）：恒定挂载，不受
/// [_BarVisibility] 的闲置自动隐藏、[_LockedHidden]、[_PipHidden] 任何一个门控。
/// 它必须在这些状态下都可达，因为它本身就是**改变**这些状态的那个控制——
/// 若被自动隐藏隐去，压根没法锁定；若被锁定隐去，压根没法解锁。
class _LockToggleButton extends StatelessWidget {
  /// Creates the lock-toggle layer.
  ///
  /// 创建锁定切换按钮层。
  const _LockToggleButton();

  @override
  Widget build(BuildContext context) {
    final api = VmScope.of(context);
    return VmSelector<bool>(
      selector: (s) => s.locked,
      builder: (context, locked) {
        return Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: VmIconButton(
              icon: locked ? Icons.lock_rounded : Icons.lock_open_rounded,
              theme: api.options.theme,
              onPressed: () => api.setLocked(!locked),
            ),
          ),
        );
      },
    );
  }
}
