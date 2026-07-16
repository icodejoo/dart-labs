/// 珠盘路插件：将每局结果顺序填入格子（蛇形排列）。
///
/// 移植自 `src/core/roads/bead-plate.ts`。
library;

import '../grid_layout.dart';
import '../types.dart';

/// 珠盘路圆内文字模式。
/// - `label`：显示结果文字（庄/闲/和），默认行为。
/// - `points`：显示获胜方点数（bankerTotal / playerTotal），缺数据时自动回退 label。
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
    final labels = theme.labels;
    final fonts = theme.fonts;
    final cells = <LayoutCell>[];

    // 读取珠盘路专属 textMode 配置，默认 label。配置路径：theme.roads['beadPlate'].textMode
    final textModeRaw = theme.roads['beadPlate']?.get<String>('textMode', 'label') ?? 'label';
    final textMode = textModeRaw == 'points' ? BeadTextMode.points : BeadTextMode.label;

    for (var i = 0; i < data.length; i++) {
      final r = data[i];
      final p = placeSequential(i, rows);
      final px = cellToPixel(p.physCol, p.physRow, cellSize);
      final fill = r.winner == 'B' ? palette.banker : (r.winner == 'P' ? palette.player : palette.tie);
      final label = r.winner == 'B' ? labels.banker : (r.winner == 'P' ? labels.player : labels.tie);

      String badgeText;
      if (textMode == BeadTextMode.points) {
        // tie: bankerTotal 作为代表。
        final total = r.winner == 'B' ? r.bankerTotal : (r.winner == 'P' ? r.playerTotal : r.bankerTotal);
        badgeText = total != null ? '$total' : label;
      } else {
        badgeText = label;
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

      // 角标偏移 0.36：偏移 + 角标半径(0.12) 必须 ≤0.5，否则会探出本格边界，
      // 被下一格晚绘制的圆盖住一块（跟 big_road.dart 同一个坑）。
      if (r.bankerPair) {
        commands.add(
          DotCommand(x: px.x - cellSize * 0.36, y: px.y - cellSize * 0.36, r: cellSize * 0.12, fill: palette.banker),
        );
      }
      if (r.playerPair) {
        commands.add(
          DotCommand(x: px.x + cellSize * 0.36, y: px.y + cellSize * 0.36, r: cellSize * 0.12, fill: palette.player),
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
