/// 主题体系（Theme）。
///
/// 定义路图渲染所需的全部样式参数，支持深合并覆盖。插件内读取顺序：
/// `theme.roads[id]?.field ?? theme.cell.field`。颜色统一用 ARGB 32 位整数
/// （对应 Flutter `Color.value`），核心层不依赖 `dart:ui`，渲染层用
/// `Color(value)` 包一层即可。移植自 `src/core/theme.ts`。
library;

/// 颜色调色板，定义庄/闲/和及通用颜色。
class Palette {
  /// 庄颜色（红色系）。
  final int banker;

  /// 闲颜色（蓝色系）。
  final int player;

  /// 和颜色（绿色系）。
  final int tie;

  /// 通用红色（衍生路红色圆/斜线）。
  final int red;

  /// 通用蓝色（衍生路蓝色圆/斜线）。
  final int blue;

  /// 高亮色（长龙/单跳/双跳背景色，ARGB 含 alpha）。
  final int highlight;

  /// 文字颜色（圆内 badge 文本）。
  final int text;

  /// 瓷砖背景填充色（合板/紧凑路纸的大格圆角瓷砖底色）。
  final int tileFill;

  /// 自定义 outcome/token 颜色扩展槽（GameSpec 泛化用）。
  ///
  /// 键为 outcome code 或 token 字符串，值为颜色；`colorForToken` 最高优先级读取此处。
  final Map<String, int>? outcomes;

  const Palette({
    required this.banker,
    required this.player,
    required this.tie,
    required this.red,
    required this.blue,
    required this.highlight,
    required this.text,
    required this.tileFill,
    this.outcomes,
  });

  /// 基于当前调色板派生一份新调色板，未指定字段沿用原值；[outcomes] 整体替换（不合并）。
  Palette copyWith({
    int? banker,
    int? player,
    int? tie,
    int? red,
    int? blue,
    int? highlight,
    int? text,
    int? tileFill,
    Map<String, int>? outcomes,
  }) => Palette(
    banker: banker ?? this.banker,
    player: player ?? this.player,
    tie: tie ?? this.tie,
    red: red ?? this.red,
    blue: blue ?? this.blue,
    highlight: highlight ?? this.highlight,
    text: text ?? this.text,
    tileFill: tileFill ?? this.tileFill,
    outcomes: outcomes ?? this.outcomes,
  );
}

/// 画布背景配置。
class CanvasTheme {
  /// 画布背景色（渲染层每帧铺底，保证导出/截图含背景）。
  final int background;

  const CanvasTheme({required this.background});

  CanvasTheme copyWith({int? background}) =>
      CanvasTheme(background: background ?? this.background);
}

/// 网格线样式。
class GridTheme {
  /// 网格线颜色。
  final int stroke;

  /// 网格线宽。
  final double lineWidth;

  const GridTheme({required this.stroke, required this.lineWidth});

  GridTheme copyWith({int? stroke, double? lineWidth}) =>
      GridTheme(stroke: stroke ?? this.stroke, lineWidth: lineWidth ?? this.lineWidth);
}

/// 格子全局默认样式。
class CellTheme {
  /// 圆的半径比例（相对 cellSize）。
  final double radiusRatio;

  /// 描边线宽。
  final double lineWidth;

  const CellTheme({required this.radiusRatio, required this.lineWidth});

  CellTheme copyWith({double? radiusRatio, double? lineWidth}) =>
      CellTheme(radiusRatio: radiusRatio ?? this.radiusRatio, lineWidth: lineWidth ?? this.lineWidth);
}

/// 文案/i18n。`outcomes` 扩展槽供 GameSpec 泛化：键为 outcome code 或 token，
/// 值为 UI 文案；`labelForToken` 优先读取此处。
class LabelsTheme {
  final String banker;
  final String player;
  final String tie;
  final String empty;

  /// 自定义 outcome/token 文案覆盖槽。
  final Map<String, String>? outcomes;

  const LabelsTheme({
    required this.banker,
    required this.player,
    required this.tie,
    required this.empty,
    this.outcomes,
  });

  LabelsTheme copyWith({
    String? banker,
    String? player,
    String? tie,
    String? empty,
    Map<String, String>? outcomes,
  }) => LabelsTheme(
    banker: banker ?? this.banker,
    player: player ?? this.player,
    tie: tie ?? this.tie,
    empty: empty ?? this.empty,
    outcomes: outcomes ?? this.outcomes,
  );
}

/// 字体配置。
class FontsTheme {
  /// 字体族。
  final String family;

  /// 字号比例（相对 cellSize）。
  final double sizeRatio;

  const FontsTheme({required this.family, required this.sizeRatio});

  FontsTheme copyWith({String? family, double? sizeRatio}) =>
      FontsTheme(family: family ?? this.family, sizeRatio: sizeRatio ?? this.sizeRatio);
}

/// 单路主题覆盖，可覆盖全局 cell 参数并添加路专属参数。
class RoadTheme {
  /// 圆的半径比例（相对 cellSize），覆盖全局 `cell.radiusRatio`。
  final double? radiusRatio;

  /// 描边线宽，覆盖全局 `cell.lineWidth`。
  final double? lineWidth;

  /// 路专属参数（如 naturalRoad 的金边色、beadPlate 的 textMode），由各路插件文档定义。
  final Map<String, Object?> extra;

  const RoadTheme({this.radiusRatio, this.lineWidth, this.extra = const {}});

  /// 读取一个路专属参数，找不到时返回 [orElse]。
  T get<T>(String key, T orElse) => (extra[key] as T?) ?? orElse;
}

/// 完整主题结构。
class Theme {
  /// 颜色调色板。
  final Palette palette;

  /// 画布背景。
  final CanvasTheme canvas;

  /// 网格线样式。
  final GridTheme grid;

  /// 格子全局默认样式。
  final CellTheme cell;

  /// 文案/i18n。
  final LabelsTheme labels;

  /// 字体配置。
  final FontsTheme fonts;

  /// 按路 id 覆盖，只需填需要覆盖的字段。
  final Map<String, RoadTheme> roads;

  const Theme({
    required this.palette,
    required this.canvas,
    required this.grid,
    required this.cell,
    required this.labels,
    required this.fonts,
    this.roads = const {},
  });

  /// 派生一份新主题；[palette]/[canvas]/[grid]/[cell]/[labels]/[fonts] 各自整体替换，
  /// [roads] 与已有条目按路 id 合并（不是整体替换）。
  Theme copyWith({
    Palette? palette,
    CanvasTheme? canvas,
    GridTheme? grid,
    CellTheme? cell,
    LabelsTheme? labels,
    FontsTheme? fonts,
    Map<String, RoadTheme>? roads,
  }) => Theme(
    palette: palette ?? this.palette,
    canvas: canvas ?? this.canvas,
    grid: grid ?? this.grid,
    cell: cell ?? this.cell,
    labels: labels ?? this.labels,
    fonts: fonts ?? this.fonts,
    roads: roads == null ? this.roads : {...this.roads, ...roads},
  );
}

/// 默认主题（深色配色）。
final Theme defaultTheme = Theme(
  palette: Palette(
    banker: 0xFFE53935,
    player: 0xFF1E88E5,
    tie: 0xFF43A047,
    red: 0xFFE53935,
    blue: 0xFF1E88E5,
    highlight: 0x40FFD500,
    text: 0xFFFFFFFF,
    tileFill: 0xFFEDE9F1,
    // 例牌橙色内圆：大路 natural 标记的颜色由此处统一管理，不在渲染代码中硬编码。
    outcomes: const {'natural': 0xFFFB8C00},
  ),
  canvas: const CanvasTheme(background: 0xFF1A1A2E),
  grid: const GridTheme(stroke: 0x14FFFFFF, lineWidth: 0.5),
  cell: const CellTheme(radiusRatio: 0.38, lineWidth: 2),
  labels: const LabelsTheme(banker: '庄', player: '闲', tie: '和', empty: '等待开局'),
  fonts: const FontsTheme(family: 'sans-serif', sizeRatio: 0.4),
  roads: const {},
);

/// 暗色主题（同 [defaultTheme]，深色 UI 配色）。
final Theme darkTheme = defaultTheme.copyWith(
  canvas: const CanvasTheme(background: 0xFF1A1A2E),
  grid: const GridTheme(stroke: 0x14FFFFFF, lineWidth: 0.5),
);

/// 浅色主题（白底配色，适用于日间模式）。
final Theme lightTheme = Theme(
  palette: Palette(
    banker: 0xFFC62828,
    player: 0xFF1565C0,
    tie: 0xFF2E7D32,
    red: 0xFFC62828,
    blue: 0xFF1565C0,
    highlight: 0x33FFC107,
    text: 0xFFFFFFFF,
    tileFill: 0xFFF2F0F4,
    outcomes: const {'natural': 0xFFFB8C00},
  ),
  canvas: const CanvasTheme(background: 0xFFF5F5F5),
  grid: const GridTheme(stroke: 0x1A000000, lineWidth: 0.5),
  cell: const CellTheme(radiusRatio: 0.38, lineWidth: 2),
  labels: const LabelsTheme(banker: '庄', player: '闲', tie: '和', empty: '等待开局'),
  fonts: const FontsTheme(family: 'sans-serif', sizeRatio: 0.4),
  roads: const {},
);

/// 解析主题：将用户覆盖以 [Theme.copyWith] 的方式叠加到 [defaultTheme]，返回完整 [Theme]。
///
/// TS 版本用通用深合并函数处理任意深度的 `DeepPartial<Theme>`；Dart 版本改用显式的
/// `copyWith` 链——`Theme` 的字段深度固定（不是无限嵌套的用户数据），显式赋值比一个
/// 反射式深合并函数更可读，也更符合 Dart 的强类型习惯。
///
/// ```dart
/// // 使用默认主题
/// final theme = resolveTheme();
///
/// // 只修改庄色
/// final theme = resolveTheme(palette: (p) => p.copyWith(banker: 0xFFFF0000));
///
/// // 覆盖单条路的线宽
/// final theme = resolveTheme(roads: {'bigEyeBoy': const RoadTheme(lineWidth: 4)});
/// ```
Theme resolveTheme({
  Theme? base,
  Palette Function(Palette)? palette,
  CanvasTheme Function(CanvasTheme)? canvas,
  GridTheme Function(GridTheme)? grid,
  CellTheme Function(CellTheme)? cell,
  LabelsTheme Function(LabelsTheme)? labels,
  FontsTheme Function(FontsTheme)? fonts,
  Map<String, RoadTheme>? roads,
}) {
  final b = base ?? defaultTheme;
  return b.copyWith(
    palette: palette != null ? palette(b.palette) : null,
    canvas: canvas != null ? canvas(b.canvas) : null,
    grid: grid != null ? grid(b.grid) : null,
    cell: cell != null ? cell(b.cell) : null,
    labels: labels != null ? labels(b.labels) : null,
    fonts: fonts != null ? fonts(b.fonts) : null,
    roads: roads,
  );
}
