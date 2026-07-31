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
        Positioned.fill(child: video),
        Positioned.fill(
          child: _PipHidden(
            child: _LockedHidden(
              child: Stack(
                children: [
                  Positioned.fill(child: Stack(children: slots[VmSlot.gesture])),
                  Positioned.fill(
                    child: Column(
                      children: [
                        _BarVisibility(child: Column(children: slots[VmSlot.top])),
                        Expanded(child: Stack(children: slots[VmSlot.center])),
                        _BarVisibility(
                          child: Column(
                            children: [
                              ...slots[VmSlot.bottomAbove],
                              ...slots[VmSlot.bottom],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Positioned.fill(child: Stack(children: slots[VmSlot.hud])),
                ],
              ),
            ),
          ),
        ),
        // Always mounted, never gated by _LockedHidden/_PipHidden: it is what
        // *renders* the lock mask and pip-hidden state in the first place,
        // and stays inert (SizedBox.shrink) on its own when unlocked.
        //
        // 恒定挂载，不受 _LockedHidden/_PipHidden 门控：它自己就是负责渲染
        // 锁定遮罩的组件，未锁定时自行收缩为空。
        Positioned.fill(child: Stack(children: slots[VmSlot.overlay])),
        // Its own independent, always-on-top layer — deliberately placed
        // after (i.e. above) the overlay/lock-mask layer in this Stack, so it
        // can never end up underneath the opaque mask regardless of slot
        // ordering.
        //
        // 独立的一层，恒定处于最上方——刻意排在这个 Stack 里 overlay/锁定遮罩层
        // 之后（即其上方），因此无论槽位顺序如何都不会被不透明遮罩盖住。
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
/// Kept as its own top-most [Stack] entry in [VmDefaultSkin.assemble] —
/// deliberately not part of the (hidden-while-locked) top bar or
/// [LockMaskComponent] — so the same one button handles both "lock" (normal
/// playback) and "unlock" (locked) without ever risking being covered by the
/// opaque tap-absorbing lock mask, regardless of slot/patch ordering.
///
/// 唯一的锁定/解锁切换按钮，两个方向共用同一个组件。
///
/// 在 [VmDefaultSkin.assemble] 里作为独立的、恒定处于最上层的 [Stack] 条目——
/// 刻意不归入（锁定时隐藏的）顶栏或 [LockMaskComponent]，因此"锁定"（正常播放
/// 态）与"解锁"（锁定态）由同一个按钮处理，且无论槽位/补丁顺序如何，都不会
/// 被不透明的锁定遮罩盖住。
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
