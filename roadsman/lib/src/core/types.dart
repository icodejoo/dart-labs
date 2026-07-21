/// Common type definitions.
///
/// Data structures shared by all road plugins, rendering layer, and engine. This file does not depend on Flutter/dart:ui
/// and can be used directly in pure Dart environments (including server). Ported from the casino monorepo's
/// `apps/baccarat-roadmap` `src/core/types.ts`.
library;

import 'theme.dart';
import 'game_spec.dart';

export 'theme.dart' show Theme, Palette;
export 'game_spec.dart'
    show
        GameSpec,
        GenericResult,
        StreamDef,
        validateGameSpecJson,
        ValidateJsonResult,
        ValidateJsonOk,
        ValidateJsonError;

/// Winner in a baccarat round result.
///
/// Deprecated: use [GenericResult.outcome] instead; kept for adapter layer compatibility and backward compatibility.
@Deprecated('请使用 GenericResult.outcome 替代')
typedef Winner = String; // "B" | "P" | "T"

/// Raw result of a single round (baccarat external format, kept for backward compatibility).
///
/// Internally, core uses [GenericResult]; convert via [toGenericResult].
class RawResult {
  /// Round number, monotonically increasing starting from 1.
  final int no;

  /// Winner: "B" | "P" | "T".
  final String winner;

  /// Banker pair.
  final bool bankerPair;

  /// Player pair.
  final bool playerPair;

  /// Whether it is a natural (instant win).
  final bool? natural;

  /// Banker total points (0-9).
  final int? bankerTotal;

  /// Player total points (0-9).
  final int? playerTotal;

  const RawResult({
    required this.no,
    required this.winner,
    required this.bankerPair,
    required this.playerPair,
    this.natural,
    this.bankerTotal,
    this.playerTotal,
  });

  /// Construct from JSON (a round result from `mock.json`).
  factory RawResult.fromJson(Map<String, dynamic> json) => RawResult(
    no: json['no'] as int,
    winner: json['winner'] as String,
    bankerPair: json['bankerPair'] as bool? ?? false,
    playerPair: json['playerPair'] as bool? ?? false,
    natural: json['natural'] as bool?,
    bankerTotal: json['bankerTotal'] as int?,
    playerTotal: json['playerTotal'] as int?,
  );

  /// Serialize to JSON.
  Map<String, dynamic> toJson() => {
    'no': no,
    'winner': winner,
    'bankerPair': bankerPair,
    'playerPair': playerPair,
    if (natural != null) 'natural': natural,
    if (bankerTotal != null) 'bankerTotal': bankerTotal,
    if (playerTotal != null) 'playerTotal': playerTotal,
  };
}

/// Shoe (all rounds of a deck).
class Shoe {
  /// Shoe ID.
  final String shoeId;

  /// Table ID.
  final String tableId;

  /// Start time ISO string.
  final String startedAt;

  /// List of round results.
  final List<RawResult> results;

  const Shoe({
    required this.shoeId,
    required this.tableId,
    required this.startedAt,
    required this.results,
  });

  /// Construct a complete shoe data from JSON.
  factory Shoe.fromJson(Map<String, dynamic> json) => Shoe(
    shoeId: json['shoeId'] as String,
    tableId: json['tableId'] as String,
    startedAt: json['startedAt'] as String,
    results: (json['results'] as List)
        .map((e) => RawResult.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
}

/// Big road cell (logical coordinates).
class BigRoadCell {
  /// Logical column (0-based, unchanged during append).
  final int col;

  /// Logical row (0-based).
  final int row;

  /// Winner (excluding ties, accumulated to [tieCount]): "B" | "P".
  final String winner;

  /// Cumulative tie count for this cell.
  final int tieCount;

  /// Whether banker pair.
  final bool bankerPair;

  /// Whether player pair.
  final bool playerPair;

  /// Whether natural (natural 8/9), defaults to false.
  final bool natural;

  /// Corresponding [RawResult.no].
  final int resultNo;

  const BigRoadCell({
    required this.col,
    required this.row,
    required this.winner,
    required this.tieCount,
    required this.bankerPair,
    required this.playerPair,
    required this.natural,
    required this.resultNo,
  });
}

/// Big road data.
class BigRoadData {
  /// List of big road cells (corresponding one-to-one with `placeOnGrid` placement results).
  final List<BigRoadCell> cells;

  /// Height of each logical column (number of cells in that column).
  final List<int> columns;

  /// Leading tie count before the game starts.
  final int leadingTies;

  const BigRoadData({required this.cells, required this.columns, required this.leadingTies});
}

/// Color of a single cell in derived roads (big eye boy / small road / cockroach road).
enum DerivedColor { red, blue }

/// Derived road data.
class DerivedRoadData {
  /// Color of each cell.
  final List<DerivedColor> entries;

  /// entries[i] corresponds to big road cells[sourceCellIndex[i]], used for merge mark.
  final List<int> sourceCellIndex;

  const DerivedRoadData({required this.entries, required this.sourceCellIndex});
}

/// Layout configuration, passed to each `layout()` call. All styles are read from [theme].
class LayoutConfig {
  /// Cell size (logical pixels).
  final double cellSize;

  /// Number of rows in the road diagram.
  final int rows;

  /// Complete theme, containing all style parameters including colors, sizes, and text.
  final Theme theme;

  const LayoutConfig({required this.cellSize, required this.rows, required this.theme});
}

/// Collection of drawing commands (sealed class, exhaustive switch matching).
///
/// The rendering layer is a stateless replayer: receives a list of commands and redraws completely. All coordinates are in content coordinate system
/// (not transformed by viewport). [alpha] is optional, used by animation layer for opacity interpolation.
sealed class DrawCommand {
  /// Opacity (0-1), used by animation layer for interpolation, defaults to 1.
  final double? alpha;

  const DrawCommand({this.alpha});
}

/// Filled or hollow circle.
final class CircleCommand extends DrawCommand {
  /// Center X.
  final double x;

  /// Center Y.
  final double y;

  /// Radius.
  final double r;

  /// Fill color (ARGB 32-bit integer, compatible with `Color.value`).
  final int? fill;

  /// Stroke color.
  final int? stroke;

  /// Stroke width.
  final double? lineWidth;

  const CircleCommand({
    required this.x,
    required this.y,
    required this.r,
    this.fill,
    this.stroke,
    this.lineWidth,
    super.alpha,
  });
}

/// Polyline / multi-segment line.
final class LineCommand extends DrawCommand {
  /// Point coordinates: `[x0,y0,x1,y1,...]`.
  final List<double> points;

  /// Line color.
  final int stroke;

  /// Line width.
  final double? lineWidth;

  const LineCommand({required this.points, required this.stroke, this.lineWidth, super.alpha});
}

/// Slash line (tie marker).
final class SlashCommand extends DrawCommand {
  /// Center X.
  final double x;

  /// Center Y.
  final double y;

  /// Half length (bottom-left to top-right).
  final double r;

  /// Line color.
  final int stroke;

  /// Line width.
  final double? lineWidth;

  const SlashCommand({
    required this.x,
    required this.y,
    required this.r,
    required this.stroke,
    this.lineWidth,
    super.alpha,
  });
}

/// Filled small dot (pair/merge marker).
final class DotCommand extends DrawCommand {
  /// Center X.
  final double x;

  /// Center Y.
  final double y;

  /// Radius.
  final double r;

  /// Fill color.
  final int fill;

  const DotCommand({required this.x, required this.y, required this.r, required this.fill, super.alpha});
}

/// Text marker (in-circle text, tie count, etc.).
final class BadgeCommand extends DrawCommand {
  /// Center X.
  final double x;

  /// Center Y.
  final double y;

  /// Text content.
  final String text;

  /// Text color.
  final int? fill;

  /// Font size (logical pixels).
  final double? fontSize;

  const BadgeCommand({
    required this.x,
    required this.y,
    required this.text,
    this.fill,
    this.fontSize,
    super.alpha,
  });
}

/// Rectangle (highlight background, etc.).
final class RectCommand extends DrawCommand {
  /// Top-left X.
  final double x;

  /// Top-left Y.
  final double y;

  /// Width.
  final double w;

  /// Height.
  final double h;

  /// Fill color.
  final int? fill;

  /// Stroke color.
  final int? stroke;

  /// Corner radius (logical pixels), defaults to no rounded corners (uses original right-angle rectangle path).
  final double? radius;

  const RectCommand({
    required this.x,
    required this.y,
    required this.w,
    required this.h,
    this.fill,
    this.stroke,
    this.radius,
    super.alpha,
  });
}

/// Layout cell with stable [key] for animation diff and hit detection.
///
/// Key derivation:
/// - beadPlate / pairRoad / naturalRoad: string form of `resultNo`
/// - bigRoad: `col:row` (logical coordinates, append never changes logical coordinates of existing cells)
/// - derived roads: string form of `entryIndex` (index in entries, stable during append-only)
class LayoutCell {
  /// Stable identity for diff and hit detection.
  final String key;

  /// Top-left content X of the cell.
  final double x;

  /// Top-left content Y of the cell.
  final double y;

  /// Cell width.
  final double w;

  /// Cell height.
  final double h;

  /// Corresponding [RawResult.no], used for linked highlighting and tooltip.
  final int resultNo;

  /// List of draw commands for this cell.
  final List<DrawCommand> commands;

  const LayoutCell({
    required this.key,
    required this.x,
    required this.y,
    required this.w,
    required this.h,
    required this.resultNo,
    required this.commands,
  });
}

/// Road layout output.
///
/// Rendering expansion order: decorations → cells (each expands commands).
/// Animation diff is based on cells' key; decorations do not participate in diff.
class RoadLayout {
  /// List of cells.
  final List<LayoutCell> cells;

  /// Commands not belonging to any cell (e.g., streakHighlight highlight rectangle).
  final List<DrawCommand>? decorations;

  /// Total content width (logical pixels, used for viewport bounds calculation).
  final double contentWidth;

  /// Total content height (logical pixels).
  final double contentHeight;

  /// This road's exclusive background grid spec, defaults to using the panel's default grid when omitted.
  final GridSpec? grid;

  const RoadLayout({
    required this.cells,
    this.decorations,
    required this.contentWidth,
    required this.contentHeight,
    this.grid,
  });
}

/// Background grid presentation style.
enum GridStyle { line, tile }

/// Background grid presentation spec for rendering layer (line fine grid / tile rounded tile), optionally returned by road plugins.
///
/// Grid and canvas content share the same coordinate transformation (moving/scaling with viewport), drawn continuously in viewport,
/// not limited by content boundaries -- avoiding misalignment caused by two independent systems each calculating "content grid" and "rendering layer background grid".
class GridSpec {
  /// Grid cell edge length (logical pixels, content coordinate system), corresponding to the actual size of layout logical cells.
  final double cellSize;

  /// Grid line color (used when style=line), defaults are set by rendering layer if omitted.
  final int? stroke;

  /// Visual grouping: how many cellSize steps each visible grid cell spans horizontally, defaults to 1 (no grouping).
  final int colSpan;

  /// Visual grouping: how many cellSize steps each visible grid cell spans vertically, defaults to 1 (no grouping).
  final int rowSpan;

  /// Presentation style: line fine grid (default) / tile rounded tile fill.
  final GridStyle style;

  /// Fill color when style=tile.
  final int? tileFill;

  /// Rounded corner radius ratio when style=tile (relative to grouped cell edge length), defaults to 0.15.
  final double tileRadiusRatio;

  /// Tile gap ratio when style=tile (relative to grouped cell edge length), defaults to 0.06.
  final double tileInsetRatio;

  const GridSpec({
    required this.cellSize,
    this.stroke,
    this.colSpan = 1,
    this.rowSpan = 1,
    this.style = GridStyle.line,
    this.tileFill,
    this.tileRadiusRatio = 0.15,
    this.tileInsetRatio = 0.06,
  });
}

/// Calculation context for road plugins, supplied to derive/layout/predict calls.
abstract class RoadContext {
  /// All round results of the current shoe (read-only, backward compatible, use this field to read results in plugins).
  List<RawResult> get results;

  /// Current game spec (injected by engine).
  GameSpec get spec;

  /// Query stream definition by id, returns main stream if not found (injected by engine).
  StreamDef stream(String id);

  /// Get derive calculation result of specified plugin (with caching, preheated in topological order).
  T get<T>(String pluginId);
}

/// Convert baccarat [RawResult] to [GenericResult] (use with `BACCARAT_SPEC`).
///
/// Boolean keys that default to false in marks are not written, keeping the structure compact.
///
/// ```dart
/// final g = toGenericResult(RawResult(no: 1, winner: 'B', bankerPair: true, playerPair: false));
/// // GenericResult(no: 1, outcome: 'B', marks: {'bankerPair': true})
/// ```
GenericResult toGenericResult(RawResult r) {
  final marks = <String, bool>{};
  if (r.bankerPair) marks['bankerPair'] = true;
  if (r.playerPair) marks['playerPair'] = true;
  if (r.natural == true) marks['natural'] = true;

  final extras = <String, num>{};
  if (r.bankerTotal != null) extras['bankerTotal'] = r.bankerTotal!;
  if (r.playerTotal != null) extras['playerTotal'] = r.playerTotal!;

  return GenericResult(
    no: r.no,
    outcome: r.winner,
    marks: marks.isNotEmpty ? marks : null,
    extras: extras.isNotEmpty ? extras : null,
  );
}

/// Convert [GenericResult] back to [RawResult] (for external display like tooltip, only meaningful for baccarat spec).
RawResult fromGenericResult(GenericResult g) => RawResult(
  no: g.no,
  winner: g.outcome,
  bankerPair: g.marks?['bankerPair'] ?? false,
  playerPair: g.marks?['playerPair'] ?? false,
  natural: g.marks?['natural'] ?? false,
  bankerTotal: g.extras?['bankerTotal']?.toInt(),
  playerTotal: g.extras?['playerTotal']?.toInt(),
);

/// Road plugin type.
enum RoadKind { grid, overlay, summary }

/// Road plugin interface, all roads implement this interface.
abstract class RoadPlugin<TData> {
  /// Unique plugin ID.
  String get id;

  /// Plugin type.
  RoadKind get kind;

  /// List of other plugin IDs this depends on (engine automatically handles transitive dependencies).
  List<String> get dependsOn => const [];

  /// Derive this road's data from `ctx.results`.
  TData derive(RoadContext ctx);

  /// Convert derived data to gridded layout output.
  RoadLayout? layout(TData data, LayoutConfig cfg, RoadContext ctx) => null;

  /// Prediction: return the color of this road's next cell assuming the next round is banker/player.
  PredictionForRoad? predict(RoadContext ctx) => null;

  /// Plugin configuration schema (for UI to auto-generate settings panel, engine validates and injects config).
  Map<String, ConfigField> get configSchema => const {};
}

/// Prediction result.
class PredictionForRoad {
  /// This road's color assuming the next round is banker.
  final DerivedColor? ifBanker;

  /// This road's color assuming the next round is player.
  final DerivedColor? ifPlayer;

  const PredictionForRoad({this.ifBanker, this.ifPlayer});
}

/// Current banker/player streak status.
class CurrentStreak {
  /// Streak winner: "B" | "P".
  final String winner;

  /// Streak length.
  final int length;

  const CurrentStreak({required this.winner, required this.length});
}

/// Statistics data.
class StatsData {
  /// Total number of rounds.
  final int total;

  /// Number of banker rounds.
  final int banker;

  /// Number of player rounds.
  final int player;

  /// Number of tie rounds.
  final int tie;

  /// Number of banker pairs.
  final int bankerPair;

  /// Number of player pairs.
  final int playerPair;

  /// Number of naturals.
  final int natural;

  /// Banker round percentage (one decimal place).
  final double bankerPct;

  /// Player round percentage (one decimal place).
  final double playerPct;

  /// Tie round percentage (one decimal place).
  final double tiePct;

  /// Longest banker streak.
  final int longestBankerStreak;

  /// Longest player streak.
  final int longestPlayerStreak;

  /// Current banker/player streak status.
  final CurrentStreak? currentStreak;

  const StatsData({
    required this.total,
    required this.banker,
    required this.player,
    required this.tie,
    required this.bankerPair,
    required this.playerPair,
    required this.natural,
    required this.bankerPct,
    required this.playerPct,
    required this.tiePct,
    required this.longestBankerStreak,
    required this.longestPlayerStreak,
    this.currentStreak,
  });
}

/// Viewport state machine phase.
enum ViewportPhase { idle, dragging, inertia, rebound, autoScroll }

/// Viewport state (immutable, pure function operations).
class ViewportState {
  /// Horizontal offset of content layer (logical pixels).
  final double offsetX;

  /// Vertical offset of content layer (logical pixels).
  final double offsetY;

  /// Scale factor.
  final double scale;

  /// Horizontal velocity (logical pixels/ms).
  final double velocityX;

  /// Vertical velocity (logical pixels/ms).
  final double velocityY;

  /// Current state machine phase.
  final ViewportPhase phase;

  /// Target X for autoScroll phase (internal use).
  final double? autoScrollTargetX;

  const ViewportState({
    required this.offsetX,
    required this.offsetY,
    required this.scale,
    required this.velocityX,
    required this.velocityY,
    required this.phase,
    this.autoScrollTargetX,
  });

  /// Derive a new state based on the current state, unspecified fields keep original values.
  ViewportState copyWith({
    double? offsetX,
    double? offsetY,
    double? scale,
    double? velocityX,
    double? velocityY,
    ViewportPhase? phase,
    double? autoScrollTargetX,
    bool clearAutoScrollTarget = false,
  }) => ViewportState(
    offsetX: offsetX ?? this.offsetX,
    offsetY: offsetY ?? this.offsetY,
    scale: scale ?? this.scale,
    velocityX: velocityX ?? this.velocityX,
    velocityY: velocityY ?? this.velocityY,
    phase: phase ?? this.phase,
    autoScrollTargetX: clearAutoScrollTarget ? null : (autoScrollTargetX ?? this.autoScrollTargetX),
  );
}

/// Viewport bounds.
class ViewportBounds {
  /// Minimum offsetX (content right-aligned to panel left).
  final double minX;

  /// Maximum offsetX (content left-aligned to panel left, usually 0).
  final double maxX;

  /// Minimum offsetY.
  final double minY;

  /// Maximum offsetY.
  final double maxY;

  const ViewportBounds({required this.minX, required this.maxX, required this.minY, required this.maxY});
}

/// Viewport physics parameter configuration.
class ViewportConfig {
  /// Rubber band damping when dragged out of bounds (smaller is "heavier", 0-1).
  final double rubberBandFactor;

  /// Inertial friction coefficient (smaller stops faster, 0-1).
  final double friction;

  /// Inertial stop velocity threshold (px/ms).
  final double minVelocity;

  /// Rebound time constant (ms, larger rebounds slower).
  final double reboundTau;

  /// Edge snap threshold (px).
  final double snapEpsilon;

  const ViewportConfig({
    required this.rubberBandFactor,
    required this.friction,
    required this.minVelocity,
    required this.reboundTau,
    required this.snapEpsilon,
  });
}

/// Configuration field type.
enum ConfigFieldType { boolean, number, select, color }

/// An option in a select type configuration item.
class ConfigFieldOption {
  /// Option value.
  final String value;

  /// Option display name.
  final String label;

  const ConfigFieldOption({required this.value, required this.label});
}

/// Configuration field description (self-describing, used for auto-generating UI).
class ConfigField {
  /// Field type.
  final ConfigFieldType type;

  /// UI display name.
  final String label;

  /// Default value.
  final Object? defaultValue;

  /// Number type: minimum value.
  final double? min;

  /// Number type: maximum value.
  final double? max;

  /// Number type: step value.
  final double? step;

  /// Select type: list of options.
  final List<ConfigFieldOption>? options;

  const ConfigField({
    required this.type,
    required this.label,
    required this.defaultValue,
    this.min,
    this.max,
    this.step,
    this.options,
  });
}
