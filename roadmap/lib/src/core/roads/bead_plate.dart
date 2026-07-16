/// 珠盘路插件：将每局结果顺序填入格子（蛇形排列）。
///
/// 完全由 [GameSpec] 驱动，不含任何游戏硬编码：
/// - 圆色：`colorForToken`（outcome 的 paletteKey → 主题色，可被
///   `theme.palette.outcomes[code]` 覆盖）
/// - 文字：`labelForToken`（outcome label，可被 `theme.labels.outcomes[code]` 覆盖）
/// - 点数模式：`OutcomeDef.beadTextField` 指定从该局 extras 里取哪个数值
/// - 角标：`spec.markers` 中 dot 形状的标记按 position 画角点
///
/// 因此百家乐/龙虎/骰宝/轮盘露珠共用这一个插件，差异全部在规格与主题里。
///
/// 移植自 `src/core/roads/bead-plate.ts`。
library;

import '../game_spec.dart';
import '../grid_layout.dart';
import '../stream.dart';
import '../types.dart';

/// 珠盘路圆内文字模式。
/// - `label`：显示结果文字（outcome label），默认行为。
/// - `points`：显示 `OutcomeDef.beadTextField` 指向的数值（如百家乐获胜方点数、
///   骰宝总点、轮盘号码），字段缺数据时自动回退 label。
enum BeadTextMode { label, points }

/// 珠盘路插件：将每局结果顺序填入格子（蛇形排列）。
class BeadPlatePlugin extends RoadPlugin<List<RawResult>> {
  @override
  String get id => 'beadPlate';

  @override
  RoadKind get kind => RoadKind.grid;

  @override
  Map<String, ConfigField> get configSchema => const {
    'textMode': ConfigField(
      type: ConfigFieldType.select,
      label: '圆内文字',
      defaultValue: 'label',
      options: [
        ConfigFieldOption(value: 'label', label: '结果文字'),
        ConfigFieldOption(value: 'points', label: '点数'),
      ],
    ),
  };

  @override
  List<RawResult> derive(RoadContext ctx) => ctx.results;

  @override
  RoadLayout layout(List<RawResult> data, LayoutConfig cfg, RoadContext ctx) {
    final cellSize = cfg.cellSize;
    final rows = cfg.rows;
    final theme = cfg.theme;
    final palette = theme.palette;
    final fonts = theme.fonts;
    final spec = ctx.spec;
    final cells = <LayoutCell>[];

    // 读取珠盘路专属 textMode 配置，默认 label。配置路径：theme.roads['beadPlate'].textMode
    final textModeRaw = theme.roads['beadPlate']?.get<String>('textMode', 'label') ?? 'label';
    final textMode = textModeRaw == 'points' ? BeadTextMode.points : BeadTextMode.label;

    // outcome code → 定义的查找表（取 beadTextField 用），按 spec 实例缓存。
    final outcomeByCode = outcomeIndexOf(spec);

    for (var i = 0; i < data.length; i++) {
      final r = data[i];
      final g = toGenericResult(r);
      final p = placeSequential(i, rows);
      final px = cellToPixel(p.physCol, p.physRow, cellSize);
      final fill = colorForToken(spec, 'main', g.outcome, theme);
      final label = labelForToken(spec, g.outcome, theme);

      String badgeText = label;
      if (textMode == BeadTextMode.points) {
        // beadTextField 由规格声明（如百家乐 B→bankerTotal、骰宝→total），
        // 字段缺失时回退 label。
        final field = outcomeByCode[g.outcome]?.beadTextField;
        final value = field == null ? null : g.extras?[field];
        if (value != null) badgeText = '$value';
      }

      final radius = cellSize * 0.42;
      final commands = <DrawCommand>[
        CircleCommand(x: px.x, y: px.y, r: radius, fill: fill),
        BadgeCommand(
          x: px.x,
          y: px.y,
          text: badgeText,
          fill: palette.text,
          fontSize: (cellSize * fonts.sizeRatio).round().toDouble(),
        ),
      ];

      // 角标：规格声明的 dot 形状标记（如庄对/闲对）。innerDot（例牌内圆）是
      // 大路的呈现惯例，珠盘路不画，保持与 TS 版行为一致。
      // 角标偏移 0.36：偏移 + 角标半径(0.12) 必须 ≤0.5，否则会探出本格边界，
      // 被下一格晚绘制的圆盖住一块（跟 big_road.dart 同一个坑）。
      for (final m in spec.markers ?? const <MarkerDef>[]) {
        if (m.shape != MarkerShape.dot) continue;
        if (!(g.marks?[m.code] ?? false)) continue;
        final (sx, sy) = switch (m.position) {
          MarkerPosition.topLeft => (-1, -1),
          MarkerPosition.topRight => (1, -1),
          MarkerPosition.bottomLeft => (-1, 1),
          MarkerPosition.bottomRight => (1, 1),
        };
        final color = palette.outcomes?[m.code] ?? colorForPaletteKey(m.paletteKey, theme);
        commands.add(
          DotCommand(
            x: px.x + sx * cellSize * 0.36,
            y: px.y + sy * cellSize * 0.36,
            r: cellSize * 0.12,
            fill: color,
          ),
        );
      }

      cells.add(
        LayoutCell(
          key: '${r.no}',
          x: p.physCol * cellSize,
          y: p.physRow * cellSize,
          w: cellSize,
          h: cellSize,
          resultNo: r.no,
          commands: commands,
        ),
      );
    }

    final colCount = data.isEmpty ? 0 : ((data.length - 1) ~/ rows) + 1;
    return RoadLayout(cells: cells, contentWidth: colCount * cellSize, contentHeight: rows * cellSize);
  }
}

/// [BeadPlatePlugin] 的单例实例。
final beadPlatePlugin = BeadPlatePlugin();
