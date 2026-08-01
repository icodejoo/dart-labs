import '../components/danmaku.dart';
import '../components/speed_button.dart';
import '../slots/patch.dart';
import '../slots/slot.dart';
import 'default_skin.dart';

/// A ready-to-use bilibili-style VOD skin: [VmDefaultSkin] plus a
/// [DanmakuTrackComponent] and a top-bar [SpeedButtonComponent].
///
/// Deliberately a thin preset, not a new layout: bilibili's control-bar
/// layout and gesture side↔action mapping (left brightness / right volume)
/// already match videoman's 0.3.0 defaults, so this skin only needs the two
/// bilibili-specific additions on top of [VmDefaultSkin], expressed as
/// [VmPatch]es — the same customisation mechanism any host skin uses (见
/// doc/DESIGN-0.3.0-plugin-skin.md §7.1 "补丁档"). The speed button lands in
/// the top bar rather than the bottom bar because [TopBarComponent] renders
/// every child after the title in order (`...children.sublist(1)`), while
/// the adaptive [BottomBarComponent] indexes its children explicitly and
/// would silently drop an inserted sibling.
///
/// Danmaku stays off (`VmOptions.danmaku.enabled == false`) unless the host
/// opts in — this skin only supplies the *rendering* component, not any
/// comment data.
///
/// 开箱即用的 bilibili 风格点播皮肤：[VmDefaultSkin] 之上叠加
/// [DanmakuTrackComponent] 与顶栏 [SpeedButtonComponent]。
///
/// 刻意做成一个薄预设，而非新布局：bilibili 的控制条布局与手势侧别↔动作映射
/// （左亮度/右音量）本就与 videoman 0.3.0 的默认值一致，因此本皮肤只需在
/// [VmDefaultSkin] 之上补两个 bilibili 特有的新增，以 [VmPatch] 表达——与任何
/// 宿主皮肤定制用的是同一套机制（见
/// doc/DESIGN-0.3.0-plugin-skin.md §7.1"补丁档"）。倍速按钮放在顶栏而非底栏，
/// 是因为 `TopBarComponent` 会按顺序渲染标题之后的每个子节点
/// （`...children.sublist(1)`），而自适应的 `BottomBarComponent` 是按下标显式
/// 取子节点的，插入的新兄弟节点会被静默丢弃。
///
/// 弹幕默认保持关闭（`VmOptions.danmaku.enabled == false`），除非宿主主动
/// 开启——本皮肤只提供**渲染**组件，不提供任何弹幕数据。
class VmBilibiliSkin extends VmDefaultSkin {
  /// Creates the bilibili-style skin, optionally applying additional
  /// [patches] on top of the danmaku/speed-button additions.
  ///
  /// 创建 bilibili 风格皮肤，可选地在弹幕/倍速按钮之上应用额外的 [patches]。
  VmBilibiliSkin({List<VmPatch> patches = const []})
      : super(patches: [..._bilibiliPatches, ...patches]);

  /// The two patches that turn [VmDefaultSkin] into the bilibili preset.
  ///
  /// 把 [VmDefaultSkin] 变成 bilibili 预设的两个补丁。
  static final List<VmPatch> _bilibiliPatches = [
    VmPatch.add(VmSlot.overlay, DanmakuTrackComponent()),
    VmPatch.insertAfter('topBar/qualityButton', SpeedButtonComponent()),
  ];
}
