/// Shared logic for merging multiple sub-roads into a single grid (used by derivedTrio / compactRoadSheet).
///
/// Ported from `src/core/roads/band-merge.ts`.
library;

import '../animation.dart' show translateCommands;
import '../types.dart';

/// A sub-road layout with a key prefix and translation offset.
class Band {
  /// Key namespace prefix, to avoid key collisions across sub-roads (e.g. "eye"/"small"/"roach"/"big").
  final String prefix;

  /// Layout in the sub-road's own coordinate system (not yet translated).
  final RoadLayout layout;

  /// Horizontal translation (logical pixels), defaults to 0.
  final double dx;

  /// Vertical translation (logical pixels), defaults to 0.
  final double dy;

  const Band({required this.prefix, required this.layout, this.dx = 0, this.dy = 0});
}

/// The merged cells and decorations (excludes contentWidth/Height, computed by the caller).
class MergedBands {
  final List<LayoutCell> cells;
  final List<DrawCommand> decorations;
  const MergedBands({required this.cells, required this.decorations});
}

/// Merges multiple [Band]s: prefixes each key, and translates cell x/y along with commands and decorations.
///
/// `cell.x`/`cell.y` must be translated in sync with commands — hit-testing (tooltips/linked
/// highlighting) uses the cell rectangle, so translating only the commands without cell.x/y
/// would break hit detection.
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
