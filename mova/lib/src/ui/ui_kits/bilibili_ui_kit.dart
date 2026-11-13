import '../components/danmaku.dart';
import '../components/speed_button.dart';
import '../components/top_bar.dart';
import '../slots/patch.dart';
import '../slots/slot.dart';
import 'default_ui_kit.dart';

/// A ready-to-use bilibili-style VOD UI kit: [MovaDefaultUiKit] plus a
/// [MovaDanmakuTrackComponent] and a top-bar [MovaSpeedButtonComponent].
///
/// Deliberately a thin preset, not a new layout: bilibili's control-bar
/// layout and gesture side↔action mapping (left brightness / right volume)
/// already match mova's 0.3.0 defaults, so this UI kit only needs the two
/// bilibili-specific additions on top of [MovaDefaultUiKit], expressed as
/// [MovaPatch]es — the same customisation mechanism any host UI kit uses (见
/// doc/DESIGN-0.3.0-plugin-ui-kit.md §7.1 "补丁档"). The speed button lands in
/// the top bar rather than the bottom bar because [MovaTopBarComponent] renders
/// every child after the title in order (`...children.sublist(1)`), while
/// the adaptive [MovaBottomBarComponent] indexes its children explicitly and
/// would silently drop an inserted sibling.
///
/// Danmaku stays off (`MovaOpts.danmaku.enabled == false`) unless the host
/// opts in — this UI kit only supplies the *rendering* component, not any
/// comment data.
///
/// 开箱即用的 bilibili 风格点播 UI 套件：[MovaDefaultUiKit] 之上叠加
/// [MovaDanmakuTrackComponent] 与顶栏 [MovaSpeedButtonComponent]。
///
/// 刻意做成一个薄预设，而非新布局：bilibili 的控制条布局与手势侧别↔动作映射
/// （左亮度/右音量）本就与 mova 0.3.0 的默认值一致，因此本 UI 套件只需在
/// [MovaDefaultUiKit] 之上补两个 bilibili 特有的新增，以 [MovaPatch] 表达——与任何
/// 宿主 UI 套件定制用的是同一套机制（见
/// doc/DESIGN-0.3.0-plugin-ui-kit.md §7.1"补丁档"）。倍速按钮放在顶栏而非底栏，
/// 是因为 `MovaTopBarComponent` 会按顺序渲染标题之后的每个子节点
/// （`...children.sublist(1)`），而自适应的 `MovaBottomBarComponent` 是按下标显式
/// 取子节点的，插入的新兄弟节点会被静默丢弃。
///
/// 弹幕默认保持关闭（`MovaOpts.danmaku.enabled == false`），除非宿主主动
/// 开启——本 UI 套件只提供**渲染**组件，不提供任何弹幕数据。
class MovaBilibiliUiKit extends MovaDefaultUiKit {
  /// Creates the bilibili-style UI kit, optionally applying additional
  /// [patches] on top of the danmaku/speed-button additions.
  ///
  /// 创建 bilibili 风格 UI 套件，可选地在弹幕/倍速按钮之上应用额外的 [patches]。
  MovaBilibiliUiKit({List<MovaPatch> patches = const []})
      : super(patches: [..._bilibiliPatches, ...patches]);

  /// The two patches that turn [MovaDefaultUiKit] into the bilibili preset.
  ///
  /// 把 [MovaDefaultUiKit] 变成 bilibili 预设的两个补丁。
  static final List<MovaPatch> _bilibiliPatches = [
    MovaPatch.add(MovaSlot.overlay, MovaDanmakuTrackComponent()),
    MovaPatch.insertAfter(
      '${MovaTopBarComponent.componentName}/${MovaQualityButtonComponent.componentName}',
      MovaSpeedButtonComponent(),
    ),
  ];
}
