/// 例牌路插件：仅展示例牌（天生赢家）局，顺序蛇形排列。
///
/// 移植自 `src/core/roads/natural-road.ts`。
library;

import '../grid_layout.dart';
import '../types.dart';

/// 例牌路插件：仅展示例牌（天生赢家）局，顺序蛇形排列。
class NaturalRoadPlugin extends RoadPlugin<List<RawResult>> {
  @override
  String get id => 'naturalRoad';

  @override
  RoadKind get kind => RoadKind.grid;

  @override
  List<RawResult> derive(RoadContext ctx) => ctx.results.where((r) => r.natural == true).toList();

  @override
  RoadLayout layout(List<RawResult> data, LayoutConfig cfg, RoadContext ctx) {
    final cellSize = cfg.cellSize;
    final rows = cfg.rows;
    final theme = cfg.theme;
    final palette = theme.palette;
    final labels = theme.labels;
    final fonts = theme.fonts;
    final roadTheme = theme.roads['naturalRoad'];
    final goldStroke = roadTheme?.get<int>('goldStroke', 0xFFFFD700) ?? 0xFFFFD700;
    final lineWidth = roadTheme?.lineWidth ?? 2;

    final cells = <LayoutCell>[];

    for (var i = 0; i < data.length; i++) {
      final r = data[i];
      final p = placeSequential(i, rows);
      final px = cellToPixel(p.physCol, p.physRow, cellSize);
      final fill = r.winner == 'B' ? palette.banker : (r.winner == 'P' ? palette.player : palette.tie);
      final label = r.winner == 'B' ? labels.banker : (r.winner == 'P' ? labels.player : labels.tie);

      final commands = <DrawCommand>[
        CircleCommand(x: px.x, y: px.y, r: cellSize * 0.42, fill: fill, stroke: goldStroke, lineWidth: lineWidth),
        BadgeCommand(
          x: px.x,
          y: px.y,
          text: label,
          fill: palette.text,
          fontSize: (cellSize * fonts.sizeRatio).round().toDouble(),
        ),
      ];

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

/// [NaturalRoadPlugin] 的单例实例。
final naturalRoadPlugin = NaturalRoadPlugin();
