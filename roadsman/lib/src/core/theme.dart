/// Theme system (Theme).
///
/// Defines all style parameters required for road map rendering, supporting deep merge override. Read order in plugins:
/// `theme.roads[id]?.field ?? theme.cell.field`. Colors uniformly use ARGB 32-bit integer
/// (corresponding to Flutter `Color.value`), core layer does not depend on `dart:ui`, rendering layer uses
/// `Color(value)` wrapper. Ported from `src/core/theme.ts`.
library;

/// Color palette, defines banker/player/tie and common colors.
class Palette {
  /// Banker color (red series).
  final int banker;

  /// Player color (blue series).
  final int player;

  /// Tie color (green series).
  final int tie;

  /// Common red (derived road red circle/slash).
  final int red;

  /// Common blue (derived road blue circle/slash).
  final int blue;

  /// Highlight color (long dragon/single jump/double jump background color, ARGB with alpha).
  final int highlight;

  /// Text color (in-circle badge text).
  final int text;

  /// Tile background fill color (large rounded tile bottom color for beadplate/compact road sheet).
  final int tileFill;

  /// Custom outcome/token color extension slot (for GameSpec generalization).
  ///
  /// Key is outcome code or token string, value is color; `colorForToken` reads here with highest priority.
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

  /// Derive a new palette based on the current palette, unspecified fields keep original values; [outcomes] is completely replaced (not merged).
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

/// Canvas background configuration.
class CanvasTheme {
  /// Canvas background color (rendering layer fills bottom each frame, ensuring export/screenshot contains background).
  final int background;

  const CanvasTheme({required this.background});

  CanvasTheme copyWith({int? background}) =>
      CanvasTheme(background: background ?? this.background);
}

/// Grid line style.
class GridTheme {
  /// Grid line color.
  final int stroke;

  /// Grid line width.
  final double lineWidth;

  const GridTheme({required this.stroke, required this.lineWidth});

  GridTheme copyWith({int? stroke, double? lineWidth}) =>
      GridTheme(stroke: stroke ?? this.stroke, lineWidth: lineWidth ?? this.lineWidth);
}

/// Cell global default style.
class CellTheme {
  /// Circle radius ratio (relative to cellSize).
  final double radiusRatio;

  /// Stroke line width.
  final double lineWidth;

  const CellTheme({required this.radiusRatio, required this.lineWidth});

  CellTheme copyWith({double? radiusRatio, double? lineWidth}) =>
      CellTheme(radiusRatio: radiusRatio ?? this.radiusRatio, lineWidth: lineWidth ?? this.lineWidth);
}

/// Copy text / i18n. `outcomes` extension slot for GameSpec generalization: key is outcome code or token,
/// value is UI copy; `labelForToken` reads here with priority.
class LabelsTheme {
  final String banker;
  final String player;
  final String tie;
  final String empty;

  /// Custom outcome/token copy override slot.
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

/// Font configuration.
class FontsTheme {
  /// Font family.
  final String family;

  /// Font size ratio (relative to cellSize).
  final double sizeRatio;

  const FontsTheme({required this.family, required this.sizeRatio});

  FontsTheme copyWith({String? family, double? sizeRatio}) =>
      FontsTheme(family: family ?? this.family, sizeRatio: sizeRatio ?? this.sizeRatio);
}

/// Single road theme override, can override global cell parameters and add road-specific parameters.
class RoadTheme {
  /// Circle radius ratio (relative to cellSize), overrides global `cell.radiusRatio`.
  final double? radiusRatio;

  /// Stroke line width, overrides global `cell.lineWidth`.
  final double? lineWidth;

  /// Road-specific parameters (e.g., gold edge color for naturalRoad, textMode for beadPlate), defined by each road plugin documentation.
  final Map<String, Object?> extra;

  const RoadTheme({this.radiusRatio, this.lineWidth, this.extra = const {}});

  /// Read a road-specific parameter, return [orElse] if not found.
  T get<T>(String key, T orElse) => (extra[key] as T?) ?? orElse;
}

/// Complete theme structure.
class Theme {
  /// Color palette.
  final Palette palette;

  /// Canvas background.
  final CanvasTheme canvas;

  /// Grid line style.
  final GridTheme grid;

  /// Cell global default style.
  final CellTheme cell;

  /// Copy / i18n.
  final LabelsTheme labels;

  /// Font configuration.
  final FontsTheme fonts;

  /// Override by road ID, only need to fill fields to override.
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

  /// Derive a new theme; [palette]/[canvas]/[grid]/[cell]/[labels]/[fonts] are completely replaced individually,
  /// [roads] is merged with existing entries by road ID (not completely replaced).
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

/// Default theme (dark color scheme).
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
    // Natural orange inner circle: the color of big road natural marker is centrally managed here, not hard-coded in rendering.
    outcomes: const {'natural': 0xFFFB8C00},
  ),
  canvas: const CanvasTheme(background: 0xFF1A1A2E),
  grid: const GridTheme(stroke: 0x14FFFFFF, lineWidth: 0.5),
  cell: const CellTheme(radiusRatio: 0.38, lineWidth: 2),
  labels: const LabelsTheme(banker: 'Banker', player: 'Player', tie: 'Tie', empty: 'Waiting for a new shoe'),
  fonts: const FontsTheme(family: 'sans-serif', sizeRatio: 0.4),
  roads: const {},
);

/// Dark theme: default theme itself is already dark color scheme, directly reuse the same instance.
final Theme darkTheme = defaultTheme;

/// Light theme (white background color scheme, suitable for daytime mode).
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
  labels: const LabelsTheme(banker: 'Banker', player: 'Player', tie: 'Tie', empty: 'Waiting for a new shoe'),
  fonts: const FontsTheme(family: 'sans-serif', sizeRatio: 0.4),
  roads: const {},
);

/// Resolve theme: overlay user overrides using [Theme.copyWith] onto [defaultTheme], return complete [Theme].
///
/// TS version uses generic deep merge function to handle `DeepPartial<Theme>` of any depth; Dart version uses explicit
/// `copyWith` chains instead -- `Theme` fields have fixed depth (not infinitely nested user data), explicit assignment is more readable
/// than a reflection-based deep merge function and conforms better to Dart's strong typing habits.
///
/// ```dart
/// // Use default theme
/// final theme = resolveTheme();
///
/// // Only change banker color
/// final theme = resolveTheme(palette: (p) => p.copyWith(banker: 0xFFFF0000));
///
/// // Override line width of a single road
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
