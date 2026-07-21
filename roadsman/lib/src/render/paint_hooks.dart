/// Paint callback types: let the caller inject custom Canvas drawing before/after
/// the built-in painting, controlling layer order (before = drawn beneath the
/// built-in content, after = drawn on top of it), while the built-in painting
/// always still runs as normal — these callbacks are purely additive hooks,
/// they never replace or skip any built-in drawing.
///
/// Two hook groups:
/// - Grid tiles ([GridCellPaintCallback]): fires for each grid tile cell, only
///   under `GridStyle.tile`, for customizing bottom-layer background elements
///   (checkerboard coloring, textures, etc.).
/// - Draw commands ([CommandPaintCallback]): fires once for every [DrawCommand]
///   ([RoadPainter]/[RoadFramePainter] paint circles/lines/slashes/dots/text
///   badges/rects, including overlay layers), carrying the original command
///   object so a switch can access all of that command's coordinate/size/color
///   fields.
///
/// Zero overhead when no callback is set (the default) — the grid/content
/// layer's Picture cache fast path is completely unaffected; once a
/// corresponding callback is set, that layer falls back to per-item direct
/// drawing for the frame (the cache records pure raster data and can't fire a
/// Dart callback on replay), trading away some drag/fling-frame performance
/// for correctness.
library;

import 'dart:ui';

import '../core/types.dart';

/// Grid tile paint info: fired once both before and after the built-in fill is
/// executed.
///
/// [canvas] is already under the current viewport transform (content
/// coordinate space), so you can paint directly using [rect]'s coordinates
/// without handling translation/scaling yourself.
class GridCellPaintInfo {
  /// The current canvas, with the viewport transform already applied (content
  /// coordinate space).
  final Canvas canvas;

  /// The tile's position and size (content coordinate space, already shrunk
  /// per [GridSpec.tileInsetRatio]).
  final Rect rect;

  /// The built-in fill color ([GridSpec.tileFill], or the fallback default).
  final Color color;

  /// The tile's row index within this paint pass (starting at 0; this is just
  /// iteration order, not a logical grid row — the grid scrolls with the
  /// viewport phase, so the same row index can map to a different actual
  /// content position on different frames; a common use is checkerboard
  /// coloring by row/column parity).
  final int row;

  /// The tile's column index within this paint pass (same semantics as
  /// [row]).
  final int col;

  const GridCellPaintInfo({
    required this.canvas,
    required this.rect,
    required this.color,
    required this.row,
    required this.col,
  });
}

/// Before/after callback for grid tile painting; see [GridCellPaintInfo].
typedef GridCellPaintCallback = void Function(GridCellPaintInfo info);

/// Info for a single draw command: fired once both before and after the
/// built-in drawing is executed.
///
/// [canvas] is already under the current viewport transform (content
/// coordinate space). [command] is the original [DrawCommand]; switching on
/// its runtime type ([CircleCommand]/[LineCommand]/[SlashCommand]/
/// [DotCommand]/[BadgeCommand]/[RectCommand]) gives access to all of that
/// command's coordinate/size/color fields.
class CommandPaintInfo {
  /// The current canvas, with the viewport transform already applied (content
  /// coordinate space).
  final Canvas canvas;

  /// The command about to be / just painted by the built-in drawing.
  final DrawCommand command;

  const CommandPaintInfo({required this.canvas, required this.command});
}

/// Before/after callback for a draw command; see [CommandPaintInfo].
typedef CommandPaintCallback = void Function(CommandPaintInfo info);
