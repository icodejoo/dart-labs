/// `CustomPainter` rendering layer: paints the [DrawCommand] list produced by
/// the core layer onto a Flutter Canvas.
///
/// Corresponds to the TS version's `renderer-canvas/canvas-renderer.ts`: every
/// frame fully repaints the command list, doing no incremental diffing (the
/// diffing happens one layer up in `panel/road_panel.dart`, which only decides
/// which interpolated commands to paint for the current frame — the canvas
/// itself is always "fully redrawn"). This model fits Flutter's
/// `CustomPainter` naturally: `shouldRepaint` corresponds to TS's "should we
/// call `render()` on the next frame".
///
/// Two painter entry points share the same drawing implementation
/// ([_paintRoad]):
/// - [RoadPainter]: stateless snapshot-style, fields are the current frame's
///   data, suited to direct external use;
/// - [RoadFramePainter] + [RoadFrameState]: the panel's internal "live frame"
///   path — the painter reads live from the state object, the `repaint`
///   Listenable drives repaints, and animation/drag frames trigger zero
///   widget rebuilds.
///
/// Ported from `src/renderer-canvas/canvas-renderer.ts`.
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../core/types.dart';
import 'paint_hooks.dart';

export 'paint_hooks.dart' show GridCellPaintInfo, GridCellPaintCallback, CommandPaintInfo, CommandPaintCallback;

/// Converts the core layer's ARGB integer color into a Flutter [Color].
Color colorFromArgb(int argb) => Color(argb);

/// [ui.Picture] cache for the content layer: the same command list is only
/// recorded once (including the most expensive parts — TextPainter layout,
/// Paint construction), and subsequent frames just replay via
/// `canvas.drawPicture` no matter how the viewport pans/scales — pure
/// viewport frames (drag/fling/auto-scroll) no longer run Dart drawing code
/// per command.
///
/// Picture is chosen over rasterizing to a [ui.Image]: a Picture is vector
/// replay, so scaling never blurs, there's no need to worry about DPR, and
/// recording completes synchronously; Image rasterization is asynchronous and
/// would need to prepare a backing image sized to the max scale factor × DPR
/// — disproportionate complexity.
///
/// Held by the panel layer (`RoadPanel`) and reused across painter instances
/// (a painter is rebuilt on every build, so a cache kept on the painter would
/// be lost each time); call [dispose] when the panel is destroyed. One per
/// panel — never share across panels (sharing across panels would let a
/// stale Picture get disposed mid-flight in another panel's frame).
class CommandLayerCache {
  /// The recorded content layer.
  ui.Picture? _picture;

  /// The command list this was recorded for (identity check decides a hit).
  List<DrawCommand>? _forCommands;

  /// Returns the cached picture directly on a hit; otherwise records a fresh
  /// one via [record] and replaces the old cache.
  ui.Picture resolve(List<DrawCommand> commands, void Function(Canvas canvas) record) {
    if (identical(_forCommands, commands) && _picture != null) return _picture!;
    final recorder = ui.PictureRecorder();
    record(Canvas(recorder));
    _picture?.dispose();
    _picture = recorder.endRecording();
    _forCommands = commands;
    return _picture!;
  }

  /// Releases the underlying Picture resource.
  void dispose() {
    _picture?.dispose();
    _picture = null;
    _forCommands = null;
  }
}

/// [ui.Picture] cache for the background grid. The grid is static in content
/// coordinate space (phase scrolling is just an overall translation), so it
/// records a single grid image keyed on (grid instance, scale, panel size)
/// that covers `[-span, w+span] × [-span, h+span]`; after that each frame just
/// needs `translate(phase - span) + drawPicture` — no more per-cell
/// drawRRect/drawLine during drag/fling (tile mode makes on the order of
/// hundreds of calls per frame, the main Dart cost of a drag frame).
///
/// During a pinch gesture, scale changes per event so it re-records each
/// time, at a cost on par with direct drawing; pan-only frames (the most
/// common case) hit the cache entirely. Same rule as [CommandLayerCache]: one
/// per panel, never share across panels.
class GridLayerCache {
  ui.Picture? _picture;
  GridSpec? _grid;
  double _scale = 0;
  double _w = 0;
  double _h = 0;

  /// Reuses the cache on a hit (grid identity, scale, and size all match);
  /// otherwise re-records.
  ui.Picture resolve(
    GridSpec grid,
    double scale,
    double w,
    double h,
    void Function(Canvas canvas) record,
  ) {
    if (_picture != null && identical(_grid, grid) && _scale == scale && _w == w && _h == h) {
      return _picture!;
    }
    final recorder = ui.PictureRecorder();
    record(Canvas(recorder));
    _picture?.dispose();
    _picture = recorder.endRecording();
    _grid = grid;
    _scale = scale;
    _w = w;
    _h = h;
    return _picture!;
  }

  /// Releases the underlying Picture resource.
  void dispose() {
    _picture?.dispose();
    _picture = null;
    _grid = null;
  }
}

/// `CustomPainter` for a single road panel: consumes [commands], paints them
/// transformed per [viewport], and optionally paints a background grid
/// [grid]. Fields are the current frame's snapshot; the painter instance is
/// rebuilt when data changes.
class RoadPainter extends CustomPainter {
  /// The list of commands to paint (already interpolated for the current
  /// frame, fully repainted).
  final List<DrawCommand> commands;

  /// Total content width (logical pixels), used for visibility culling.
  final double contentWidth;

  /// Current viewport offset/scale.
  final Offset viewportOffset;

  /// Current viewport scale factor.
  final double viewportScale;

  /// Background grid configuration; null means don't draw a grid.
  final GridSpec? grid;

  /// Canvas background color.
  final int background;

  /// Content layer Picture cache (optional, held across frames by the panel
  /// layer). When passed, the same [commands] list is only recorded once and
  /// pure-viewport frames just replay it; when omitted, falls back to
  /// per-command direct drawing (with visibility culling).
  final CommandLayerCache? layerCache;

  /// Background grid Picture cache (optional, held across frames by the panel
  /// layer).
  final GridLayerCache? gridCache;

  /// Overlay layer commands (a small number of per-frame-changing commands
  /// like breathing halos, animated cells), painted on top of the content
  /// layer, within the same viewport transform. Kept separate from
  /// [commands] so the underlying Picture cache isn't invalidated by
  /// per-frame animation.
  final List<DrawCommand> overlayCommands;

  /// Fires **before** the built-in grid tile fill (drawn beneath the tile),
  /// only in effect when `grid.style == GridStyle.tile`. Once set, that
  /// frame's grid skips the Picture cache and draws per-cell directly.
  final GridCellPaintCallback? onBeforePaintGridCell;

  /// Fires **after** the built-in grid tile fill (drawn on top of the tile).
  /// Same cache-bypass rule as [onBeforePaintGridCell].
  final GridCellPaintCallback? onAfterPaintGridCell;

  /// Fires **before** the built-in drawing of each command (circles, lines,
  /// slashes, dots, text, rects covered by [commands]/[overlayCommands]).
  /// Once set, the content layer skips the Picture cache and draws each
  /// command directly for that frame.
  final CommandPaintCallback? onBeforePaintCommand;

  /// Fires **after** the built-in drawing of each command. Same cache-bypass
  /// rule as [onBeforePaintCommand].
  final CommandPaintCallback? onAfterPaintCommand;

  const RoadPainter({
    required this.commands,
    required this.contentWidth,
    required this.viewportOffset,
    required this.viewportScale,
    this.grid,
    required this.background,
    this.layerCache,
    this.gridCache,
    this.overlayCommands = const [],
    this.onBeforePaintGridCell,
    this.onAfterPaintGridCell,
    this.onBeforePaintCommand,
    this.onAfterPaintCommand,
  });

  @override
  void paint(Canvas canvas, Size size) => _paintRoad(
    canvas,
    size,
    commands: commands,
    overlayCommands: overlayCommands,
    contentWidth: contentWidth,
    viewportOffset: viewportOffset,
    viewportScale: viewportScale,
    grid: grid,
    background: background,
    layerCache: layerCache,
    gridCache: gridCache,
    onBeforePaintGridCell: onBeforePaintGridCell,
    onAfterPaintGridCell: onAfterPaintGridCell,
    onBeforePaintCommand: onBeforePaintCommand,
    onAfterPaintCommand: onAfterPaintCommand,
  );

  @override
  bool shouldRepaint(covariant RoadPainter oldDelegate) =>
      !identical(oldDelegate.commands, commands) ||
      !identical(oldDelegate.overlayCommands, overlayCommands) ||
      oldDelegate.contentWidth != contentWidth ||
      oldDelegate.viewportOffset != viewportOffset ||
      oldDelegate.viewportScale != viewportScale ||
      oldDelegate.grid != grid ||
      oldDelegate.background != background ||
      oldDelegate.onBeforePaintGridCell != onBeforePaintGridCell ||
      oldDelegate.onAfterPaintGridCell != onAfterPaintGridCell ||
      oldDelegate.onBeforePaintCommand != onBeforePaintCommand ||
      oldDelegate.onAfterPaintCommand != onAfterPaintCommand;
}

/// "Live frame" state: everything the panel needs to change every frame
/// (commands, viewport, cache selection) is written here; [markFrame] drives
/// [RoadFramePainter] straight to `markNeedsPaint` via the `repaint`
/// Listenable — animation/drag frames completely bypass
/// setState/build/element diffing.
class RoadFrameState extends ChangeNotifier {
  /// Content layer commands (static or animated background art, replayed via
  /// Picture together with [layerCache]).
  List<DrawCommand> commands = const [];

  /// Overlay layer commands (breathing halos, animated cells), drawn directly
  /// every frame.
  List<DrawCommand> overlayCommands = const [];

  /// Current viewport offset.
  Offset viewportOffset = Offset.zero;

  /// Current viewport scale.
  double viewportScale = 1;

  /// The Picture cache applicable to the content layer for this frame (a
  /// separate one for static frames vs. animated background art); null means
  /// draw directly.
  CommandLayerCache? layerCache;

  /// Notifies the painter to repaint the current frame.
  void markFrame() => notifyListeners();
}

/// A `CustomPainter` that reads frame data live from [RoadFrameState].
///
/// The frame is passed to the base class as the `repaint` Listenable at
/// construction time: frame state changes only trigger `markNeedsPaint`,
/// never rebuild any widget. The painter's own fields are left with only the
/// low-churn static configuration (size/grid/background), which is rebuilt by
/// build when it changes and goes through shouldRepaint.
class RoadFramePainter extends CustomPainter {
  /// The frame state (also serves as the repaint Listenable).
  final RoadFrameState frame;

  /// Total content width (logical pixels), used for visibility culling on the
  /// direct-draw path.
  final double contentWidth;

  /// Background grid configuration; null means don't draw.
  final GridSpec? grid;

  /// Canvas background color.
  final int background;

  /// Background grid Picture cache.
  final GridLayerCache? gridCache;

  /// Fires **before** the built-in grid tile fill, only in effect when
  /// `grid.style == GridStyle.tile`; see [RoadPainter.onBeforePaintGridCell].
  final GridCellPaintCallback? onBeforePaintGridCell;

  /// Fires **after** the built-in grid tile fill; see
  /// [RoadPainter.onAfterPaintGridCell].
  final GridCellPaintCallback? onAfterPaintGridCell;

  /// Fires **before** the built-in drawing of each command; see
  /// [RoadPainter.onBeforePaintCommand].
  final CommandPaintCallback? onBeforePaintCommand;

  /// Fires **after** the built-in drawing of each command; see
  /// [RoadPainter.onAfterPaintCommand].
  final CommandPaintCallback? onAfterPaintCommand;

  RoadFramePainter({
    required this.frame,
    required this.contentWidth,
    this.grid,
    required this.background,
    this.gridCache,
    this.onBeforePaintGridCell,
    this.onAfterPaintGridCell,
    this.onBeforePaintCommand,
    this.onAfterPaintCommand,
  }) : super(repaint: frame);

  @override
  void paint(Canvas canvas, Size size) => _paintRoad(
    canvas,
    size,
    commands: frame.commands,
    overlayCommands: frame.overlayCommands,
    contentWidth: contentWidth,
    viewportOffset: frame.viewportOffset,
    viewportScale: frame.viewportScale,
    grid: grid,
    background: background,
    layerCache: frame.layerCache,
    gridCache: gridCache,
    onBeforePaintGridCell: onBeforePaintGridCell,
    onAfterPaintGridCell: onAfterPaintGridCell,
    onBeforePaintCommand: onBeforePaintCommand,
    onAfterPaintCommand: onAfterPaintCommand,
  );

  @override
  bool shouldRepaint(covariant RoadFramePainter oldDelegate) =>
      !identical(oldDelegate.frame, frame) ||
      oldDelegate.contentWidth != contentWidth ||
      oldDelegate.grid != grid ||
      oldDelegate.background != background ||
      oldDelegate.onBeforePaintGridCell != onBeforePaintGridCell ||
      oldDelegate.onAfterPaintGridCell != onAfterPaintGridCell ||
      oldDelegate.onBeforePaintCommand != onBeforePaintCommand ||
      oldDelegate.onAfterPaintCommand != onAfterPaintCommand;
}

// ─── Shared drawing implementation (used by both RoadPainter and RoadFramePainter) ───────────────────

/// Fill/stroke Paint objects reused by the direct-draw path. Since we're on a
/// single UI thread and `Canvas.draw*` copies the Paint state at call time,
/// it's safe to mutate and reuse the fields right after the call returns —
/// this avoids 1-2 Paint allocations (including native finalizer
/// registration) per command on animation frames. Every use must reset all
/// fields it relies on.
final Paint _fillPaint = Paint();
final Paint _strokePaint = Paint()..style = PaintingStyle.stroke;

/// Paints a full frame: background -> grid -> content layer (Picture cache or
/// direct draw + culling) -> overlay layer.
void _paintRoad(
  Canvas canvas,
  Size size, {
  required List<DrawCommand> commands,
  required List<DrawCommand> overlayCommands,
  required double contentWidth,
  required Offset viewportOffset,
  required double viewportScale,
  required GridSpec? grid,
  required int background,
  required CommandLayerCache? layerCache,
  required GridLayerCache? gridCache,
  GridCellPaintCallback? onBeforePaintGridCell,
  GridCellPaintCallback? onAfterPaintGridCell,
  CommandPaintCallback? onBeforePaintCommand,
  CommandPaintCallback? onAfterPaintCommand,
}) {
  final w = size.width;
  final h = size.height;
  final hasCommandHooks = onBeforePaintCommand != null || onAfterPaintCommand != null;

  canvas.drawRect(Rect.fromLTWH(0, 0, w, h), _fillPaint..color = colorFromArgb(background));

  // 1. Background grid: not subject to the scroll transform, always fills the panel.
  if (grid != null) {
    _paintGrid(
      canvas,
      w,
      h,
      grid,
      viewportOffset,
      viewportScale,
      gridCache,
      onBeforePaintGridCell: onBeforePaintGridCell,
      onAfterPaintGridCell: onAfterPaintGridCell,
    );
  }

  // 2. Content layer: apply the viewport transform.
  canvas.save();
  canvas.translate(viewportOffset.dx, viewportOffset.dy);
  canvas.scale(viewportScale);

  // If command hooks are set, fall back to direct drawing: the Picture cache
  // records pure raster data and replay won't fire a Dart callback, so it's
  // cache or callbacks, not both (callbacks win — correctness over the
  // performance of pure-viewport frames).
  if (layerCache != null && !hasCommandHooks) {
    // Cache path: record the whole layer as a Picture and replay it. No
    // visibility culling is applied while recording (the Picture must be
    // viewport-independent to be reusable across pans/zooms); clipping is
    // left to the canvas clip — replay cost is far lower than per-command
    // Paint/TextPainter construction.
    canvas.drawPicture(layerCache.resolve(commands, (c) {
      for (final cmd in commands) {
        _paintCommand(c, cmd);
      }
    }));
  } else {
    final visL = -viewportOffset.dx / viewportScale;
    final visR = (-viewportOffset.dx + w) / viewportScale;
    final margin = contentWidth > 0 ? contentWidth * 0.05 : 50;

    for (final cmd in commands) {
      if (_isOutside(cmd, visL - margin, visR + margin)) continue;
      _paintCommandWithHooks(canvas, cmd, onBeforePaintCommand, onAfterPaintCommand);
    }
  }

  // 3. Overlay layer (breathing halos, animated cells), very few of them, drawn directly.
  for (final cmd in overlayCommands) {
    _paintCommandWithHooks(canvas, cmd, onBeforePaintCommand, onAfterPaintCommand);
  }

  canvas.restore();
}

/// Paints one command, firing [onBefore]/[onAfter] around it as needed (when
/// both are null this is equivalent to calling [_paintCommand] directly, with
/// no extra branch/allocation overhead).
void _paintCommandWithHooks(
  Canvas canvas,
  DrawCommand cmd,
  CommandPaintCallback? onBefore,
  CommandPaintCallback? onAfter,
) {
  if (onBefore == null && onAfter == null) {
    _paintCommand(canvas, cmd);
    return;
  }
  final info = CommandPaintInfo(canvas: canvas, command: cmd);
  onBefore?.call(info);
  _paintCommand(canvas, cmd);
  onAfter?.call(info);
}

/// Renders the background grid (phase kept in sync with content coordinates,
/// drawn continuously as the viewport pans/zooms, filling the whole visible
/// area). Shares the same viewport-transform semantics as the content layer
/// and isn't constrained by content bounds — this avoids misalignment that
/// would result if "content self-drawn grid" and "render-layer background
/// grid" were two independent systems each computing their own coordinates.
void _paintGrid(
  Canvas canvas,
  double w,
  double h,
  GridSpec grid,
  Offset viewportOffset,
  double viewportScale,
  GridLayerCache? gridCache, {
  GridCellPaintCallback? onBeforePaintGridCell,
  GridCellPaintCallback? onAfterPaintGridCell,
}) {
  final cellSize = grid.cellSize;
  final stroke = grid.stroke ?? 0x14FFFFFF;
  final colSpan = grid.colSpan;
  final rowSpan = grid.rowSpan;
  final tileFill = grid.tileFill ?? 0x14FFFFFF;
  final tileRadiusRatio = grid.tileRadiusRatio;
  final tileInsetRatio = grid.tileInsetRatio;
  final hasCellHooks = onBeforePaintGridCell != null || onAfterPaintGridCell != null;

  final scale = viewportScale;
  final spanW = cellSize * colSpan * scale;
  final spanH = cellSize * rowSpan * scale;

  // Phase: X/Y are both computed dynamically from the current offset (kept in sync with content translation).
  final phaseX = ((viewportOffset.dx % spanW) + spanW) % spanW;
  final phaseY = ((viewportOffset.dy % spanH) + spanH) % spanH;

  // Cache path: the grid image is recorded once keyed on (grid, scale, size)
  // (origin-aligned, covering one extra period on each side), and each frame
  // only needs to translate to the current phase and replay — zero per-cell
  // drawing on pan frames. Skips the cache if a tile callback is set (the
  // cache records pure raster data and replay won't fire a Dart callback).
  if (gridCache != null && !hasCellHooks) {
    final picture = gridCache.resolve(grid, scale, w, h, (c) {
      _recordGrid(c, w, h, grid, spanW, spanH);
    });
    canvas.save();
    canvas.translate(phaseX - spanW, phaseY - spanH);
    canvas.drawPicture(picture);
    canvas.restore();
    return;
  }

  canvas.save();

  if (grid.style == GridStyle.tile) {
    final insetX = spanW * tileInsetRatio;
    final insetY = spanH * tileInsetRatio;
    final radius = math.min(spanW, spanH) * tileRadiusRatio;
    final color = colorFromArgb(tileFill);
    final paint = Paint()..color = color;
    // Start from phase-span so the partial tiles at the left/top edge also get painted, leaving no gaps.
    var row = 0;
    for (var y = phaseY - spanH; y <= h + spanH; y += spanH, row++) {
      var col = 0;
      for (var x = phaseX - spanW; x <= w + spanW; x += spanW, col++) {
        final rw = spanW - 2 * insetX;
        final rh = spanH - 2 * insetY;
        if (rw <= 0 || rh <= 0) continue;
        final rect = Rect.fromLTWH(x + insetX, y + insetY, rw, rh);
        final rrect = RRect.fromRectAndRadius(rect, Radius.circular(radius));
        if (hasCellHooks) {
          final info = GridCellPaintInfo(canvas: canvas, rect: rect, color: color, row: row, col: col);
          onBeforePaintGridCell?.call(info);
          canvas.drawRRect(rrect, paint);
          onAfterPaintGridCell?.call(info);
        } else {
          canvas.drawRRect(rrect, paint);
        }
      }
    }
  } else {
    final paint = Paint()
      ..color = colorFromArgb(stroke)
      ..strokeWidth = 0.5;
    for (var x = phaseX; x <= w + spanW; x += spanW) {
      canvas.drawLine(Offset(x, 0), Offset(x, h), paint);
    }
    for (var y = phaseY; y <= h + spanH; y += spanH) {
      canvas.drawLine(Offset(0, y), Offset(w, y), paint);
    }
  }

  canvas.restore();
}

/// Records the grid onto an origin-aligned canvas, covering
/// `[0, w+2·span] × [0, h+2·span]` — one extra period on each side beyond the
/// visible area, so that translating to any phase
/// (`phase - span ∈ [-span, 0)`) still fills the panel. Drawing parameters
/// match the direct-draw path in [_paintGrid] item for item.
void _recordGrid(Canvas canvas, double w, double h, GridSpec grid, double spanW, double spanH) {
  final totalW = w + 2 * spanW;
  final totalH = h + 2 * spanH;

  if (grid.style == GridStyle.tile) {
    final tileFill = grid.tileFill ?? 0x14FFFFFF;
    final insetX = spanW * grid.tileInsetRatio;
    final insetY = spanH * grid.tileInsetRatio;
    final radius = math.min(spanW, spanH) * grid.tileRadiusRatio;
    final rw = spanW - 2 * insetX;
    final rh = spanH - 2 * insetY;
    if (rw <= 0 || rh <= 0) return;
    final paint = Paint()..color = colorFromArgb(tileFill);
    for (var y = 0.0; y <= totalH; y += spanH) {
      for (var x = 0.0; x <= totalW; x += spanW) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTWH(x + insetX, y + insetY, rw, rh), Radius.circular(radius)),
          paint,
        );
      }
    }
  } else {
    final paint = Paint()
      ..color = colorFromArgb(grid.stroke ?? 0x14FFFFFF)
      ..strokeWidth = 0.5;
    for (var x = 0.0; x <= totalW; x += spanW) {
      canvas.drawLine(Offset(x, 0), Offset(x, totalH), paint);
    }
    for (var y = 0.0; y <= totalH; y += spanH) {
      canvas.drawLine(Offset(0, y), Offset(totalW, y), paint);
    }
  }
}

/// Visibility culling (drops commands that are clearly off-panel, improving performance).
bool _isOutside(DrawCommand cmd, double visL, double visR) => switch (cmd) {
  CircleCommand c => c.x < visL || c.x > visR,
  SlashCommand c => c.x < visL || c.x > visR,
  DotCommand c => c.x < visL || c.x > visR,
  BadgeCommand c => c.x < visL || c.x > visR,
  LineCommand c => (c.points.isNotEmpty ? c.points[0] : 0) < visL || (c.points.isNotEmpty ? c.points[0] : 0) > visR,
  RectCommand c => c.x + c.w < visL || c.x > visR,
};

/// Replays a single draw command, honoring [DrawCommand.alpha] opacity (used for animation interpolation).
void _paintCommand(Canvas canvas, DrawCommand cmd) {
  final alpha = cmd.alpha ?? 1;
  switch (cmd) {
    case CircleCommand c:
      if (c.fill != null) {
        canvas.drawCircle(Offset(c.x, c.y), c.r, _fillPaint..color = _withAlpha(c.fill!, alpha));
      }
      if (c.stroke != null) {
        canvas.drawCircle(
          Offset(c.x, c.y),
          c.r,
          _strokePaint
            ..color = _withAlpha(c.stroke!, alpha)
            ..strokeWidth = c.lineWidth ?? 2,
        );
      }
    case LineCommand c:
      final path = Path();
      for (var i = 0; i < c.points.length; i += 2) {
        final x = c.points[i];
        final y = i + 1 < c.points.length ? c.points[i + 1] : 0.0;
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(
        path,
        _strokePaint
          ..color = _withAlpha(c.stroke, alpha)
          ..strokeWidth = c.lineWidth ?? 2,
      );
    case SlashCommand c:
      canvas.drawLine(
        Offset(c.x - c.r, c.y + c.r),
        Offset(c.x + c.r, c.y - c.r),
        _strokePaint
          ..color = _withAlpha(c.stroke, alpha)
          ..strokeWidth = c.lineWidth ?? 2,
      );
    case DotCommand c:
      canvas.drawCircle(Offset(c.x, c.y), c.r, _fillPaint..color = _withAlpha(c.fill, alpha));
    case BadgeCommand c:
      final fs = c.fontSize ?? 12;
      final tp = TextPainter(
        text: TextSpan(
          text: c.text,
          style: TextStyle(color: _withAlpha(c.fill ?? 0xFFFFFFFF, alpha), fontSize: fs),
        ),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(c.x - tp.width / 2, c.y - tp.height / 2));
    case RectCommand c:
      final rect = Rect.fromLTWH(c.x, c.y, c.w, c.h);
      if (c.radius != null) {
        final rrect = RRect.fromRectAndRadius(rect, Radius.circular(c.radius!));
        if (c.fill != null) canvas.drawRRect(rrect, _fillPaint..color = _withAlpha(c.fill!, alpha));
        if (c.stroke != null) {
          canvas.drawRRect(
            rrect,
            _strokePaint
              ..color = _withAlpha(c.stroke!, alpha)
              ..strokeWidth = 0,
          );
        }
      } else {
        if (c.fill != null) canvas.drawRect(rect, _fillPaint..color = _withAlpha(c.fill!, alpha));
        if (c.stroke != null) {
          canvas.drawRect(
            rect,
            _strokePaint
              ..color = _withAlpha(c.stroke!, alpha)
              ..strokeWidth = 0,
          );
        }
      }
  }
}

/// Blends the animation opacity into a color.
Color _withAlpha(int argb, double alpha) => colorFromArgb(argb).withValues(alpha: alpha);
