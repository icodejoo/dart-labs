// Icon source for the fsvg-vs-flutter_svg benchmark: 1000 distinct, REAL
// icon SVGs from the iconify_flutter plugin's `Mdi` (Material Design Icons)
// set, baked at dev time by tool/gen_mdi_icons.dart into mdi_icons_1000.dart.
// Using real icon markup (rather than synthetic shapes) means parse/build
// cost reflects an actual icon set's structure/attribute mix.
//
// 基准测试的图标来源：来自 iconify_flutter 插件 `Mdi`（Material Design Icons）
// 图标集的 1000 个互不相同的真实图标 SVG，由 tool/gen_mdi_icons.dart 在开发期
// 烘焙进 mdi_icons_1000.dart。用真实图标标记（而非合成形状）能让解析/构建开销
// 反映真实图标集的结构与属性分布。

import 'mdi_icons_1000.dart';

/// Returns [count] distinct real icon SVG strings (from `Mdi`, capped at the
/// 1000 baked in [mdiIcons1000]). Selection order is fixed (declaration
/// order from the pinned iconify_flutter version), so the benchmark is
/// reproducible run to run.
///
/// 返回 [count] 个互不相同的真实图标 SVG 字符串（来自 `Mdi`，最多
/// [mdiIcons1000] 里烘焙的 1000 个）。选取顺序固定（来自锁定版本 iconify_flutter
/// 的声明顺序），保证基准可复现。
///
/// Example:
/// ```dart
/// final icons = generateIcons(1000);
/// ```
List<String> generateIcons(int count) {
  assert(count <= mdiIcons1000.length, 'only ${mdiIcons1000.length} icons baked');
  return mdiIcons1000.take(count).toList();
}
