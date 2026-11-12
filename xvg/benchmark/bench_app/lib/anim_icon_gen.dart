// Icon source for the 1000-icon animated-scroll FPS benchmark: tiles the
// real SMIL-animated icon SVGs baked by tool/gen_anim_icons.dart from the
// pinned official @iconify-json/line-md and @iconify-json/eos-icons packages
// up to [count]. Only the roster and order come from iconify_flutter 0.0.7.
// See anim_icons_real.dart for versions, licenses and skip reports.
// The selected corpus has fewer than 1000 entries, so the grid has some
// repetition — each repeated icon is still a real, independently-parsed and
// independently-ticking `<animate>`/`<animateTransform>` SVG, not a
// synthetic shape, so parse/build/animation-driver cost per cell is
// representative of the real engine's per-icon cost.
//
// 1000 图标动画滚动 FPS 基准的图标来源：把 tool/gen_anim_icons.dart 从固定版本的
// 官方 @iconify-json/line-md 和 @iconify-json/eos-icons 包烘焙出的真实 SMIL 动画
// 图标 SVG 平铺到 [count] 个；仅名单与顺序来自 iconify_flutter 0.0.7。
// 版本、许可证和跳过报告见 anim_icons_real.dart。选定语料不足 1000 条，填满
// 1000 格网格会有重复；但每个重复出来的图标依然是真实、
// 独立解析且独立 ticking 的 `<animate>`/`<animateTransform>` SVG，不是合成
// 形状，每格的解析/构建/动画驱动开销仍能代表引擎真实的单图标开销。
import 'anim_icons_real.dart';

/// Returns [count] animated icon SVG strings, tiling the official real-world
/// icons baked in [animIconsReal].
///
/// 返回 [count] 个动画图标 SVG 字符串，由 [animIconsReal] 里烘焙的官方
/// 真实图标平铺而成。
///
/// Example:
/// ```dart
/// final icons = generateAnimIcons(1000);
/// ```
List<String> generateAnimIcons(int count) => List<String>.generate(
  count,
  (i) => animIconsReal[i % animIconsReal.length],
);
