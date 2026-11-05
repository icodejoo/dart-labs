import '../style/style.dart';

import 'package:flutter/material.dart';

import '../components/bottom_bar.dart';
import '../components/center_play.dart';
import '../components/common.dart';
import '../components/gesture_layer.dart';
import '../components/hud_layer.dart';
import '../components/overlays.dart';
import '../components/preview.dart';
import '../components/subtitle.dart';
import '../components/top_bar.dart';
import '../../core/api.dart';
import '../../core/state/state.dart';
import '../chrome/chrome.dart';
import '../scope/selector.dart';
import '../slots/component.dart';
import '../slots/patch.dart';
import '../slots/slot.dart';
import '../slots/tree.dart';
import 'skin.dart';

/// The built-in [MovaSkin]: reproduces 0.1.0's default look for both VOD and
/// live sources, extended with the new buffering/error/lock overlays that
/// 0.1.0 never had.
///
/// [components] is a single static tree — the adaptive [MovaBottomBarComponent]
/// renders its VOD or live layout internally from [MovaState.type], so the skin
/// no longer swaps whole subtrees by state.
///
/// [assemble] renders three layers, back to front, each via an overridable
/// protected method ([buildPlaybackLayer]/[buildOperableLayer]/
/// [buildPersistentLayer]) so a subclass can re-lay-out just one layer without
/// copying the whole thing — playback (raw video) / operable (gesture + bar
/// chrome, gated by auto-hide/pip/lock/mini) / persistent (lock mask +
/// toggle; the unlocked toggle follows control visibility). Full design rationale and the "override just one layer" contract:
/// doc/DESIGN-0.3.0-plugin-skin.md §7.2.
///
/// 内置 [MovaSkin]：对点播与直播都复刻 0.1.0 的默认外观，并扩展了 0.1.0 从未有
/// 过的缓冲/错误/锁定叠加层。
///
/// [components] 是单一静态树——自适应的 [MovaBottomBarComponent] 依据
/// [MovaState.type] 在内部渲染点播或直播布局，皮肤不再按状态整体替换子树。
///
/// [assemble] 由后到前渲染三层，每层经一个可覆写的受保护方法
/// （[buildPlaybackLayer]/[buildOperableLayer]/[buildPersistentLayer]），使
/// 子类无需整体照抄即可只重排其中一层——播放层（原始画面）/ 操作层（手势 +
/// 栏 chrome，受自动隐藏/画中画/锁定/小窗门控）/ 常驻层（锁定遮罩 + 切换按钮，
/// 解锁入口常驻，未锁定的按钮跟随控制条显隐）。完整设计理由与"只
/// 覆写一层"的契约见 doc/DESIGN-0.3.0-plugin-skin.md §7.2。
class MovaDefaultSkin implements MovaSkin {
  /// Creates the default skin, optionally applying [patches] to its tree.
  ///
  /// 创建默认皮肤，可选地对其组件树应用 [patches]。
  const MovaDefaultSkin({
    this.patches = const [],
    this.statusLayerNames = const {
      MovaBufferingComponent.componentName,
      MovaErrorComponent.componentName,
    },
  });

  /// 独立于控制条和锁定的 center 组件名称；空集合保留原有分层。
  ///
  /// 示例：`MovaDefaultSkin(statusLayerNames: {'error'})` 只提升错误层。
  final Set<String> statusLayerNames;

  /// Structural patches applied to the base tree in [components], in order.
  ///
  /// [components] 中基础组件树依序应用的结构性补丁。
  final List<MovaPatch> patches;

  @override
  List<MovaComponent> components() => applyPatches([
    MovaGestureLayerComponent(),
    MovaHudLayerComponent(),
    MovaTopBarComponent(),
    MovaCenterPlayComponent(),
    MovaPreviewComponent(),
    MovaSubtitleOverlayComponent(),
    MovaBottomBarComponent(),
    MovaBufferingComponent(),
    MovaErrorComponent(),
    MovaLockMaskComponent(),
    MovaLockToggleComponent(),
  ], patches);

  @override
  Widget assemble(BuildContext context, MovaSlotBundle slots, Widget video) {
    return Stack(
      children: [
        buildPlaybackLayer(context, slots, video),
        buildOperableLayer(context, slots),
        buildPersistentLayer(context, slots),
      ],
    );
  }

  /// Layer 1 — the raw video surface. Override to wrap/replace the picture.
  ///
  /// Wrapped in a [RepaintBoundary] so the frequently-repainting operable
  /// layer (seek-bar ticks, HUD fades, bar-visibility animation) never forces
  /// this layer to re-raster, and vice versa.
  ///
  /// 第 1 层——原始视频画面。覆写以包裹/替换画面。
  ///
  /// 包了一层 [RepaintBoundary]，使频繁重绘的操作层（进度条 tick、HUD 淡出、
  /// 栏显隐动画）不会牵连本层重新光栅化，反之亦然。
  @protected
  Widget buildPlaybackLayer(
    BuildContext context,
    MovaSlotBundle slots,
    Widget video,
  ) {
    return Positioned.fill(child: RepaintBoundary(child: video));
  }

  /// Layer 2 — the operable chrome (gesture + top/center/bottom/left/right
  /// bars + HUD), fading and hiding together. Override to re-lay-out the
  /// chrome (e.g. dock the control bar at the top).
  ///
  /// 第 2 层——操作层 chrome（手势 + 顶/中/底/左/右栏 + HUD），一起淡入淡出与
  /// 隐藏。覆写以重排 chrome（例如把控制条停靠到顶部）。
  ///
  /// Wrapped in a [RepaintBoundary]: this layer repaints most often (seek-bar
  /// ticks, HUD auto-hide fades, the bar-visibility animation), so isolating
  /// it keeps that churn from forcing the playback/persistent layers to
  /// re-raster alongside it.
  ///
  /// 包了一层 [RepaintBoundary]：本层重绘最频繁（进度条 tick、HUD 自动隐藏
  /// 淡出、栏显隐动画），隔离后这些变动不会连带播放层/常驻层一起重新光栅化。
  @protected
  Widget buildOperableLayer(BuildContext context, MovaSlotBundle slots) {
    return Positioned.fill(
      child: RepaintBoundary(
        child: _HideWhen(
          selector: (s) => s.mini,
          child: _HideWhen(
            selector: (s) => s.pip,
            child: _HideWhen(
              selector: (s) => s.locked,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Stack(children: slots[MovaSlot.gesture]),
                  ),
                  Positioned.fill(
                    child: _BarVisibility(
                      // A Stack of independently `Positioned` regions, not a
                      // Column: the bottom bar grows taller when the preview
                      // bubble appears above it (MovaSlot.bottomAbove), and a
                      // Column would re-flow every sibling in response —
                      // visibly nudging the center play/pause icon up and
                      // down as the bubble shows/hides. Positioning top/
                      // center/bottom independently means resizing one never
                      // moves another.
                      //
                      // 用 Stack + 各自独立的 Positioned，而非 Column：预览气泡
                      // 出现在底栏上方（MovaSlot.bottomAbove）时会撑高底栏，若用
                      // Column，兄弟节点都会跟着重新排布——中间的播放/暂停图标
                      // 就会随气泡出现/消失肉眼可见地上下跳动。顶/中/底各自
                      // 独立定位，意味着其中一个变高变矮，绝不会带动另一个。
                      child: Stack(
                        children: [
                          Positioned(
                            top: 0,
                            left: 0,
                            right: 0,
                            child: Column(children: slots[MovaSlot.top]),
                          ),
                          Positioned.fill(
                            child: Stack(
                              children: slots.named(
                                MovaSlot.center,
                                statusLayerNames,
                                exclude: true,
                              ),
                            ),
                          ),
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: Column(
                              children: [
                                ...slots[MovaSlot.bottomAbove],
                                ...slots[MovaSlot.bottom],
                              ],
                            ),
                          ),
                          // Left/right vertical edge bands (MovaSlot.left/right):
                          // full-height, centered content, for side chrome
                          // (sidebars, episode lists). Empty by default — a
                          // no-op unless a component is placed there.
                          //
                          // 左/右垂直边带（MovaSlot.left/right）：满高、内容居中，
                          // 用于侧边 chrome（侧栏、剧集列表）。默认为空——除非
                          // 有组件放进去，否则不产生任何效果。
                          Positioned(
                            top: 0,
                            bottom: 0,
                            left: 0,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: slots[MovaSlot.left],
                            ),
                          ),
                          Positioned(
                            top: 0,
                            bottom: 0,
                            right: 0,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: slots[MovaSlot.right],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Positioned.fill(child: Stack(children: slots[MovaSlot.hud])),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Layer 3 — persistent overlays, including the patchable lock toggle.
  /// Status overlays ignore control visibility; the unlocked toggle follows it.
  ///
  /// 第 3 层——常驻状态叠加层及可 patch 的锁定按钮。状态层独立于控制条；
  /// 未锁定的按钮跟随控制条隐藏，锁定后保留解锁入口，PiP/mini 时隐藏按钮。
  /// [context] 为当前上下文，[slots] 为组件槽；返回常驻层。
  /// 示例：子类可调用 `super.buildPersistentLayer(context, slots)` 复用本层。
  ///
  /// Wrapped in a [RepaintBoundary] for the same reason as the other two
  /// layers: this one rarely repaints (only on lock-state change), so
  /// isolating it keeps the operable layer's frequent churn from dragging it
  /// along.
  ///
  /// 同样包了一层 [RepaintBoundary]：本层极少重绘（仅锁定状态变化时），隔离后
  /// 操作层的频繁重绘不会连带它一起重新光栅化。
  @protected
  Widget buildPersistentLayer(BuildContext context, MovaSlotBundle slots) {
    return Positioned.fill(
      child: RepaintBoundary(
        child: Stack(
          children: [
            Stack(children: slots[MovaSlot.overlay]),
            _HideWhen(
              selector: (s) => s.pip || s.mini,
              child: Stack(
                children: slots.named(MovaSlot.center, statusLayerNames),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Fades [child] in/out with [MovaUiState.controlsVisible] and, while hidden,
/// lets taps pass through to the gesture layer below instead of absorbing
/// them — reproducing 0.1.0's "hidden bars are tap-through" rule for the
/// top/bottom chrome.
///
/// 依据 [MovaUiState.controlsVisible] 渐显/渐隐 [child]；隐藏时点击会穿透到
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
    final fadeDuration = MovaPlayerStyle.controlsOf(context).fadeDuration;
    return MovaUiSelect<bool>(
      selector: (s) => s.controlsVisible,
      builder: (context, visible) {
        return IgnorePointer(
          ignoring: !visible,
          child: AnimatedOpacity(
            opacity: visible ? 1 : 0,
            duration: fadeDuration,
            child: Listener(
              behavior: HitTestBehavior.deferToChild,
              onPointerDown: (_) => movaUiOf(context).touch(),
              child: child,
            ),
          ),
        );
      },
    );
  }
}

/// Hides [child] outright while [MovaState.pip] is active.
///
/// A floating system picture-in-picture window is a few dozen logical pixels
/// across and offers no gesture surface of its own — the host OS supplies
/// its own play/pause/close affordances — so mova's entire chrome (gesture
/// layer, bars, HUD) has no useful role there and would only draw over the
/// system's controls.
///
/// [MovaState.pip] 生效期间直接隐藏 [child]。
///
/// 系统级画中画悬浮窗只有几十逻辑像素见方，也没有自己的手势操作面——宿主
/// 系统会提供自己的播放/暂停/关闭按钮——因此 mova 的整套 chrome（手势层、
/// 各栏、HUD）在其中毫无用处，反而会盖住系统自带的控制。
///
/// Also used to hide [child] outright while [MovaState.mini]/[MovaState.locked]
/// is active — the picture has been handed to the in-app mini window (own
/// minimal chrome, `MovaMiniSkin`) or the screen is locked (leaving only
/// [MovaLockMaskComponent]'s own unlock affordance, unaffected by this
/// wrapper); in both cases the page-side chrome has no useful role and would
/// otherwise keep painting over/inviting taps on a surface that no longer
/// needs it.
///
/// 也用于 [MovaState.mini]/[MovaState.locked] 生效期间直接隐藏 [child]——画面
/// 已交给 App 内小窗（自带极简 chrome `MovaMiniSkin`）或屏幕已锁定（只留
/// [MovaLockMaskComponent] 自带的解锁入口，不受本组件影响）；两种情况下页面侧
/// chrome 都已毫无用处，否则会继续绘制在一个不再需要它的画面之上、或诱使误触。
class _HideWhen extends StatelessWidget {
  /// Creates the visibility wrapper: hides [child] whenever [selector]
  /// returns true for the current [MovaState].
  ///
  /// 创建显隐控制组件：当 [selector] 对当前 [MovaState] 返回 true 时隐藏 [child]。
  const _HideWhen({required this.selector, required this.child});

  /// Returns whether [child] should be hidden for the given state.
  ///
  /// 返回给定状态下是否应隐藏 [child]。
  final bool Function(MovaState) selector;

  /// The chrome whose visibility this widget controls.
  ///
  /// 该组件控制其显隐的 chrome 内容。
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MovaSelect<bool>(
      selector: selector,
      builder: (context, hide) => hide ? const SizedBox.shrink() : child,
    );
  }
}

/// 可通过 `lockToggle` 路径替换或移除的锁定按钮；解锁入口保持可达。
///
/// 示例：`MovaPatch.remove(MovaLockToggleComponent.componentName)`。
class MovaLockToggleComponent extends MovaComponent {
  /// 创建默认锁定按钮组件；无参数，供皮肤树使用。
  MovaLockToggleComponent();

  /// 组件路径名；示例：`MovaPatch.remove('lockToggle')`。
  static const String componentName = 'lockToggle';

  /// 返回锁定按钮的组件名。
  @override
  String get name => componentName;

  /// 返回常驻叠加槽，使锁定时仍能解锁。
  @override
  MovaSlot get slot => MovaSlot.overlay;

  /// 根据 [api] 构建锁定按钮；[children] 未使用，返回受显隐规则约束的按钮。
  ///
  /// 示例：通常由 `buildSlots(context, api, skin.components())` 调用。
  @override
  Widget build(BuildContext context, MovaApi api, List<Widget> children) {
    return _HideWhen(
      selector: (s) => s.pip || s.mini,
      child: MovaSelect<bool>(
        selector: (s) => s.locked,
        builder: (context, locked) {
          final button = Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: MovaIconButton(
                label: locked
                    ? MovaPlayerStyle.stringsOf(context).unlock
                    : MovaPlayerStyle.stringsOf(context).lock,
                icon: locked
                    ? MovaPlayerStyle.iconsOf(context).unlock
                    : MovaPlayerStyle.iconsOf(context).lock,
                theme: MovaPlayerStyle.themeOf(context),
                onPressed: () => api.setLocked(!locked),
              ),
            ),
          );
          return locked ? button : _BarVisibility(child: button);
        },
      ),
    );
  }
}
