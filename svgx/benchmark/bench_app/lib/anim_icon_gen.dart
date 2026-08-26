// Icon source for the 1000-icon animated-scroll FPS benchmark: tiles the
// 399 REAL, distinct SMIL-animated icon SVGs baked by
// tool/gen_anim_icons.dart (from iconify_flutter's `LineMd` + `EosIcons`
// sets) up to [count]. Iconify doesn't ship 1000 distinct SMIL-animated
// icons in these two collections, so filling a 1000-cell grid means some
// repetition — each repeated icon is still a real, independently-parsed and
// independently-ticking `<animate>`/`<animateTransform>` SVG, not a
// synthetic shape, so parse/build/animation-driver cost per cell is
// representative of the real engine's per-icon cost.
//
// 1000 图标动画滚动 FPS 基准的图标来源：把 tool/gen_anim_icons.dart 从
// iconify_flutter 的 `LineMd`+`EosIcons` 集合烘焙出的 399 个真实、互不相同的
// SMIL 动画图标 SVG，平铺到 [count] 个。这两个集合凑不出 1000 个互不相同的
// SMIL 动画图标，填满 1000 格网格必然有重复；但每个重复出来的图标依然是真实、
// 独立解析且独立 ticking 的 `<animate>`/`<animateTransform>` SVG，不是合成
// 形状，每格的解析/构建/动画驱动开销仍能代表引擎真实的单图标开销。
import 'anim_icons_real.dart';

/// Returns [count] animated icon SVG strings, tiling the 399 real distinct
/// icons baked in [animIconsReal].
///
/// 返回 [count] 个动画图标 SVG 字符串，由 [animIconsReal] 里烘焙的 399 个
/// 真实互异图标平铺而成。
///
/// Example:
/// ```dart
/// final icons = generateAnimIcons(1000);
/// ```
List<String> generateAnimIcons(int count) =>
    List<String>.generate(count, (i) => animIconsReal[i % animIconsReal.length]);
