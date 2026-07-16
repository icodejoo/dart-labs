/// 公共类型定义。
///
/// 所有路插件、渲染层、引擎共享的数据结构，本文件不依赖 Flutter/dart:ui，
/// 可在纯 Dart 环境（含服务端）直接使用。移植自 casino monorepo
/// `apps/baccarat-roadmap` 的 `src/core/types.ts`。
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

/// 百家乐局结果中的胜者。
///
/// 已废弃，请使用 [GenericResult.outcome] 替代；仅供适配层与向后兼容使用。
@Deprecated('请使用 GenericResult.outcome 替代')
typedef Winner = String; // "B" | "P" | "T"

/// 单局原始结果（百家乐外部格式，对外保留向后兼容）。
///
/// core 内部使用 [GenericResult]；通过 [toGenericResult] 转换。
class RawResult {
  /// 局号，从 1 开始单调递增。
  final int no;

  /// 胜者："B" | "P" | "T"。
  final String winner;

  /// 庄对子。
  final bool bankerPair;

  /// 闲对子。
  final bool playerPair;

  /// 是否例牌（天生赢家）。
  final bool? natural;

  /// 庄点数（0-9）。
  final int? bankerTotal;

  /// 闲点数（0-9）。
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

  /// 从 JSON（`mock.json` 的一条局结果）构造。
  factory RawResult.fromJson(Map<String, dynamic> json) => RawResult(
    no: json['no'] as int,
    winner: json['winner'] as String,
    bankerPair: json['bankerPair'] as bool? ?? false,
    playerPair: json['playerPair'] as bool? ?? false,
    natural: json['natural'] as bool?,
    bankerTotal: json['bankerTotal'] as int?,
    playerTotal: json['playerTotal'] as int?,
  );

  /// 序列化为 JSON。
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

/// 靴（一副牌的全部局）。
class Shoe {
  /// 靴 id。
  final String shoeId;

  /// 桌台 id。
  final String tableId;

  /// 开始时间 ISO 字符串。
  final String startedAt;

  /// 局结果列表。
  final List<RawResult> results;

  const Shoe({
    required this.shoeId,
    required this.tableId,
    required this.startedAt,
    required this.results,
  });

  /// 从 JSON 构造一份完整的靴数据。
  factory Shoe.fromJson(Map<String, dynamic> json) => Shoe(
    shoeId: json['shoeId'] as String,
    tableId: json['tableId'] as String,
    startedAt: json['startedAt'] as String,
    results: (json['results'] as List)
        .map((e) => RawResult.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
}

/// 大路格子（逻辑坐标）。
class BigRoadCell {
  /// 逻辑列（0-based，append 时不变）。
  final int col;

  /// 逻辑行（0-based）。
  final int row;

  /// 胜者（不含和局，和局累加到 [tieCount]）："B" | "P"。
  final String winner;

  /// 当格累计和局数。
  final int tieCount;

  /// 是否庄对子。
  final bool bankerPair;

  /// 是否闲对子。
  final bool playerPair;

  /// 是否例牌（天生 8/9），缺省视为 false。
  final bool natural;

  /// 对应的 [RawResult.no]。
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

/// 大路数据。
class BigRoadData {
  /// 大路格子列表（与 `placeOnGrid` 的放置结果一一对应）。
  final List<BigRoadCell> cells;

  /// 各逻辑列的高度（即该列有多少格）。
  final List<int> columns;

  /// 开局前的前置和局数。
  final int leadingTies;

  const BigRoadData({required this.cells, required this.columns, required this.leadingTies});
}

/// 衍生路（大眼仔/小路/曱甴路）的单格颜色。
enum DerivedColor {
  red,
  blue;

  /// 对应 TS 版本里的字符串字面量（`"red"`/`"blue"`），供渲染/序列化使用。
  String get label => this == DerivedColor.red ? 'red' : 'blue';
}

/// 衍生路数据。
class DerivedRoadData {
  /// 各格颜色。
  final List<DerivedColor> entries;

  /// entries[i] 对应大路 cells[sourceCellIndex[i]]，用于合并点标记。
  final List<int> sourceCellIndex;

  const DerivedRoadData({required this.entries, required this.sourceCellIndex});
}

/// 布局配置，传入每个 `layout()` 调用。所有样式均从 [theme] 读取。
class LayoutConfig {
  /// 格子尺寸（逻辑像素）。
  final double cellSize;

  /// 路图行数。
  final int rows;

  /// 完整主题，包含颜色/尺寸/文案等所有样式参数。
  final Theme theme;

  const LayoutConfig({required this.cellSize, required this.rows, required this.theme});
}

/// 绘制指令集合（sealed class，穷尽 switch 匹配）。
///
/// 渲染层是无状态回放器：收到指令列表，全量重绘。所有坐标均为内容坐标系
/// （未经 viewport 变换）。[alpha] 可选，动画层用于透明度插值。
sealed class DrawCommand {
  /// 透明度（0-1），动画层插值用，默认 1。
  final double? alpha;

  const DrawCommand({this.alpha});
}

/// 实心/空心圆。
final class CircleCommand extends DrawCommand {
  /// 圆心 X。
  final double x;

  /// 圆心 Y。
  final double y;

  /// 半径。
  final double r;

  /// 填充色（ARGB 32 位整数，兼容 `Color.value`）。
  final int? fill;

  /// 描边色。
  final int? stroke;

  /// 描边宽度。
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

/// 折线/多段线。
final class LineCommand extends DrawCommand {
  /// 点坐标：`[x0,y0,x1,y1,...]`。
  final List<double> points;

  /// 线颜色。
  final int stroke;

  /// 线宽。
  final double? lineWidth;

  const LineCommand({required this.points, required this.stroke, this.lineWidth, super.alpha});
}

/// 斜线（和局标记）。
final class SlashCommand extends DrawCommand {
  /// 中心 X。
  final double x;

  /// 中心 Y。
  final double y;

  /// 半长（左下→右上）。
  final double r;

  /// 线颜色。
  final int stroke;

  /// 线宽。
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

/// 实心小圆点（对子/合并标记）。
final class DotCommand extends DrawCommand {
  /// 圆心 X。
  final double x;

  /// 圆心 Y。
  final double y;

  /// 半径。
  final double r;

  /// 填充色。
  final int fill;

  const DotCommand({required this.x, required this.y, required this.r, required this.fill, super.alpha});
}

/// 文字标记（圆内字、多和计数等）。
final class BadgeCommand extends DrawCommand {
  /// 中心 X。
  final double x;

  /// 中心 Y。
  final double y;

  /// 文本内容。
  final String text;

  /// 文字颜色。
  final int? fill;

  /// 字号（逻辑像素）。
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

/// 矩形（高亮背景等）。
final class RectCommand extends DrawCommand {
  /// 左上角 X。
  final double x;

  /// 左上角 Y。
  final double y;

  /// 宽度。
  final double w;

  /// 高度。
  final double h;

  /// 填充色。
  final int? fill;

  /// 描边色。
  final int? stroke;

  /// 圆角半径（逻辑像素），缺省不画圆角（沿用原有直角矩形路径）。
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

/// 布局格子，携带稳定 [key] 供动画 diff 和命中检测使用。
///
/// key 取法：
/// - beadPlate / pairRoad / naturalRoad：`resultNo` 的字符串形式
/// - bigRoad：`col:row`（逻辑坐标，append 永不改变已有格子的逻辑坐标）
/// - 衍生路：`entryIndex` 的字符串形式（entries 下标，append-only 时稳定）
class LayoutCell {
  /// 稳定身份标识，用于 diff 和命中检测。
  final String key;

  /// 格子左上角内容坐标 X。
  final double x;

  /// 格子左上角内容坐标 Y。
  final double y;

  /// 格子宽度。
  final double w;

  /// 格子高度。
  final double h;

  /// 对应的 [RawResult.no]，用于联动高亮和 tooltip。
  final int resultNo;

  /// 该格子的绘制指令列表。
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

/// 路布局输出。
///
/// 渲染时展开顺序：decorations → cells（各自展开 commands）。
/// 动画 diff 基于 cells 的 key 进行；decorations 不参与 diff。
class RoadLayout {
  /// 格子列表。
  final List<LayoutCell> cells;

  /// 不属于任何格子的指令（如 streakHighlight 高亮矩形）。
  final List<DrawCommand>? decorations;

  /// 内容总宽（逻辑像素，用于 viewport bounds 计算）。
  final double contentWidth;

  /// 内容总高（逻辑像素）。
  final double contentHeight;

  /// 本路专属的背景网格规格，缺省时渲染层使用面板默认网格。
  final GridSpec? grid;

  const RoadLayout({
    required this.cells,
    this.decorations,
    required this.contentWidth,
    required this.contentHeight,
    this.grid,
  });
}

/// 背景网格呈现风格。
enum GridStyle { line, tile }

/// 背景网格呈现规格，供渲染层绘制（line 细线网格 / tile 圆角瓷砖），路插件可选返回。
///
/// 网格与画布内容共用同一份坐标变换（随 viewport 平移/缩放），按视口连续绘制，不受
/// 内容边界限制——避免"内容网格"与"渲染层背景网格"两套独立系统各自计算导致的错位。
class GridSpec {
  /// 网格最小单元格边长（逻辑像素，内容坐标系），对应 layout 逻辑格子的实际尺寸。
  final double cellSize;

  /// 网格线颜色（style=line 时使用），缺省由渲染层给默认值。
  final int? stroke;

  /// 视觉分组：每个可见网格单元横向跨越多少个 cellSize 步进，缺省 1（不分组）。
  final int colSpan;

  /// 视觉分组：每个可见网格单元纵向跨越多少个 cellSize 步进，缺省 1（不分组）。
  final int rowSpan;

  /// 呈现风格：line 细线网格（默认）/ tile 圆角瓷砖填充。
  final GridStyle style;

  /// style=tile 时的填充色。
  final int? tileFill;

  /// style=tile 时的圆角半径比例（相对分组后的格子边长），缺省 0.15。
  final double tileRadiusRatio;

  /// style=tile 时瓷砖间缝隙比例（相对分组后的格子边长），缺省 0.06。
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

/// 路插件的计算上下文，供 derive/layout/predict 调用。
abstract class RoadContext {
  /// 当前靴的全部局结果（只读，向后兼容，插件内读取局结果请用此字段）。
  List<RawResult> get results;

  /// 当前游戏规格（引擎注入）。
  GameSpec get spec;

  /// 按 id 查询流定义，找不到时返回 main 流（引擎注入）。
  StreamDef stream(String id);

  /// 获取指定插件的 derive 计算结果（带缓存，按拓扑序预热）。
  T get<T>(String pluginId);
}

/// 将百家乐 [RawResult] 转为 [GenericResult]（配合 `BACCARAT_SPEC` 使用）。
///
/// marks 里缺省 false 的布尔键不写入，保持结构紧凑。
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

/// 将 [GenericResult] 转回 [RawResult]（用于 tooltip 等外部展示，仅百家乐规格有意义）。
RawResult fromGenericResult(GenericResult g) => RawResult(
  no: g.no,
  winner: g.outcome,
  bankerPair: g.marks?['bankerPair'] ?? false,
  playerPair: g.marks?['playerPair'] ?? false,
  natural: g.marks?['natural'] ?? false,
  bankerTotal: g.extras?['bankerTotal']?.toInt(),
  playerTotal: g.extras?['playerTotal']?.toInt(),
);

/// 路插件类型。
enum RoadKind { grid, overlay, summary }

/// 路插件接口，所有路均实现此接口。
abstract class RoadPlugin<TData> {
  /// 插件唯一 id。
  String get id;

  /// 插件类型。
  RoadKind get kind;

  /// 依赖的其他插件 id 列表（引擎自动处理传递依赖）。
  List<String> get dependsOn => const [];

  /// 从 `ctx.results` 派生本路的数据。
  TData derive(RoadContext ctx);

  /// 将派生数据转为格子化布局输出。
  RoadLayout? layout(TData data, LayoutConfig cfg, RoadContext ctx) => null;

  /// 问路：返回假设下一局为庄/闲时，本路下一格的颜色。
  PredictionForRoad? predict(RoadContext ctx) => null;

  /// 插件配置 schema（供 UI 自动生成设置面板，引擎校验并注入 config）。
  Map<String, ConfigField> get configSchema => const {};
}

/// 问路结果。
class PredictionForRoad {
  /// 假设下一局为庄时本路颜色。
  final DerivedColor? ifBanker;

  /// 假设下一局为闲时本路颜色。
  final DerivedColor? ifPlayer;

  const PredictionForRoad({this.ifBanker, this.ifPlayer});
}

/// 当前连庄/连闲状态。
class CurrentStreak {
  /// 连出的胜者："B" | "P"。
  final String winner;

  /// 连出长度。
  final int length;

  const CurrentStreak({required this.winner, required this.length});
}

/// 统计数据。
class StatsData {
  /// 总局数。
  final int total;

  /// 庄局数。
  final int banker;

  /// 闲局数。
  final int player;

  /// 和局数。
  final int tie;

  /// 庄对子数。
  final int bankerPair;

  /// 闲对子数。
  final int playerPair;

  /// 例牌数。
  final int natural;

  /// 庄局百分比（一位小数）。
  final double bankerPct;

  /// 闲局百分比（一位小数）。
  final double playerPct;

  /// 和局百分比（一位小数）。
  final double tiePct;

  /// 庄最长连庄。
  final int longestBankerStreak;

  /// 闲最长连闲。
  final int longestPlayerStreak;

  /// 当前连庄/连闲状态。
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

/// 视口状态机阶段。
enum ViewportPhase { idle, dragging, inertia, rebound, autoScroll }

/// 视口状态（不可变，纯函数操作）。
class ViewportState {
  /// 内容层水平偏移（逻辑像素）。
  final double offsetX;

  /// 内容层垂直偏移（逻辑像素）。
  final double offsetY;

  /// 缩放倍率。
  final double scale;

  /// 水平速度（逻辑像素/ms）。
  final double velocityX;

  /// 垂直速度（逻辑像素/ms）。
  final double velocityY;

  /// 当前状态机阶段。
  final ViewportPhase phase;

  /// autoScroll 阶段的目标 X（内部使用）。
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

  /// 基于当前状态派生一份新状态，未指定字段沿用原值。
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

/// 视口边界。
class ViewportBounds {
  /// 最小 offsetX（内容右对齐面板左边）。
  final double minX;

  /// 最大 offsetX（内容左对齐面板左边，通常为 0）。
  final double maxX;

  /// 最小 offsetY。
  final double minY;

  /// 最大 offsetY。
  final double maxY;

  const ViewportBounds({required this.minX, required this.maxX, required this.minY, required this.maxY});
}

/// 视口物理参数配置。
class ViewportConfig {
  /// 拖出边界的橡皮筋阻尼（越小越"沉"，0-1）。
  final double rubberBandFactor;

  /// 惯性摩擦系数（越小停得越快，0-1）。
  final double friction;

  /// 惯性停止速度阈值（px/ms）。
  final double minVelocity;

  /// 回弹时间常数（ms，越大回弹越慢）。
  final double reboundTau;

  /// 贴边吸附阈值（px）。
  final double snapEpsilon;

  const ViewportConfig({
    required this.rubberBandFactor,
    required this.friction,
    required this.minVelocity,
    required this.reboundTau,
    required this.snapEpsilon,
  });
}

/// 配置字段类型。
enum ConfigFieldType { boolean, number, select, color }

/// select 类型配置项的一个选项。
class ConfigFieldOption {
  /// 选项值。
  final String value;

  /// 选项显示名。
  final String label;

  const ConfigFieldOption({required this.value, required this.label});
}

/// 配置字段描述（自描述，用于自动生成 UI）。
class ConfigField {
  /// 字段类型。
  final ConfigFieldType type;

  /// UI 显示名。
  final String label;

  /// 默认值。
  final Object? defaultValue;

  /// number 类型：最小值。
  final double? min;

  /// number 类型：最大值。
  final double? max;

  /// number 类型：步进值。
  final double? step;

  /// select 类型：选项列表。
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
