/// 多子路合并成一张网格的公用逻辑（derivedTrio / compactRoadSheet 共用）。
///
/// 移植自 `src/core/roads/band-merge.ts`。
library;

import '../animation.dart' show translateCommands;
import '../types.dart';

/// 一条带前缀与平移量的子路布局。
class Band {
  /// key 命名空间前缀，防各子路 key 冲突（如 "eye"/"small"/"roach"/"big"）。
  final String prefix;

  /// 子路自身坐标系下的布局（未平移）。
  final RoadLayout layout;

  /// 水平平移（逻辑像素），缺省 0。
  final double dx;

  /// 垂直平移（逻辑像素），缺省 0。
  final double dy;

  const Band({required this.prefix, required this.layout, this.dx = 0, this.dy = 0});
}

/// 合并后的 cells 与 decorations（不含 contentWidth/Height，由调用方各自计算）。
class MergedBands {
  final List<LayoutCell> cells;
  final List<DrawCommand> decorations;
  const MergedBands({required this.cells, required this.decorations});
}

/// 合并多条 [Band]：key 加前缀，cell 的 x/y 与 commands、decorations 一并平移。
///
/// `cell.x`/`cell.y` 必须与 commands 同步平移——命中检测（tooltip/联动高亮）用的是
/// cell 矩形，只平移 commands 不平移 cell.x/y 会导致点不中。
///
/// ```dart
/// final merged = mergeBands([
///   Band(prefix: 'eye', layout: eyeLayout),
///   Band(prefix: 'small', layout: smallLayout, dy: 3 * cellSize),
/// ]);
/// ```
MergedBands mergeBands(List<Band> bands) {
  final cells = <LayoutCell>[];
  final decorations = <DrawCommand>[];

  for (final band in bands) {
    for (final cell in band.layout.cells) {
      cells.add(
        LayoutCell(
          key: '${band.prefix}:${cell.key}',
          x: cell.x + band.dx,
          y: cell.y + band.dy,
          w: cell.w,
          h: cell.h,
          resultNo: cell.resultNo,
          commands: translateCommands(cell.commands, band.dx, band.dy),
        ),
      );
    }
    final decos = band.layout.decorations;
    if (decos != null) {
      decorations.addAll(translateCommands(decos, band.dx, band.dy));
    }
  }

  return MergedBands(cells: cells, decorations: decorations);
}
