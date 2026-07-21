/// Single-road display panel: `CustomPaint` + gestures + viewport + per-cell
/// insert/move/exit animations.
///
/// Corresponds to the TS version's `panel/road-panel.ts` combined with the
/// hand-rolled diff-animation pipeline in `renderRoad()` from `example/main.ts`
/// (in TS, the animation doesn't live in the renderer — it's the demo layer
/// manually sampling frames via `diffLayout`/`sampleEnter`/`sampleMove`/
/// `sampleExit` + `frameDriver`). The Flutter version folds that pipeline into
/// `RoadPanel` itself: a `Ticker` drives the viewport's physical state machine
/// (drag inertia/rebound/auto-scroll) and per-cell animation sampling, while
/// `CustomPaint` ([RoadPainter]) just paints whatever commands the current
/// frame hands it, indifferent to whether those commands are final states or
/// interpolated in-between states.
///
/// Ported from `src/panel/road-panel.ts` and `example/main.ts`'s `renderRoad`.
library;

import 'package:flutter/material.dart' hide Theme;
import 'package:flutter/scheduler.dart';

import '../core/animation.dart' hide Easing;
import '../core/animation.dart' as anim show Easing;
import '../core/types.dart';
import '../core/viewport.dart';
import '../render/road_painter.dart';
import 'ux/pulse.dart';

/// Viewport follow strategy applied when new data arrives.
enum FollowTail {
  /// Don't follow (e.g. a full refresh when switching game type — the user
  /// might be looking at history and shouldn't get yanked away).
  none,

  /// Jump to the tail immediately.
  hard,

  /// Ease-scroll to the tail.
  ease,
}

/// The kind of this data update: corresponds to the TS version's
/// `UpdateKind` in `store.ts`, and decides whether to play the insert
/// animation — only [append] triggers enter/move/exit sampling; everything
/// else goes straight to its final state.
enum RoadUpdateKind { setResults, append, patch }

/// Single-road display panel.
///
/// Rebuilt whenever external data changes (a new [cells]/[decorations] is
/// passed in); internally the panel diffs the old and new layout in
/// `didUpdateWidget` to decide whether to jump straight to the final state or
/// play insert/move/exit animations.
class RoadPanel extends StatefulWidget {
  /// This road's current layout cell list.
  final List<LayoutCell> cells;

  /// Decoration commands that don't belong to any cell (e.g. the
  /// streakHighlight highlight rectangle).
  final List<DrawCommand> decorations;

  /// Total content width (logical pixels).
  final double contentWidth;

  /// Total content height (logical pixels).
  final double contentHeight;

  /// This road's dedicated background grid spec; null uses the panel's
  /// default thin-line grid.
  final GridSpec? grid;

  /// Current theme (supplies canvas background color, default grid style).
  final Theme theme;

  /// Panel width (logical pixels).
  final double panelWidth;

  /// Panel height (logical pixels).
  final double panelHeight;

  /// Viewport follow strategy once new cells arrive.
  final FollowTail followTail;

  /// The kind of this update, deciding whether to play the insert animation.
  final RoadUpdateKind eventType;

  /// Cell animation duration (ms); pass 0 to jump straight to the final
  /// state for `prefers-reduced-motion`/accessibility scenarios.
  final int animDurationMs;

  /// Callback for double-tapping the panel (default behavior returns to the
  /// tail; callers may override it).
  final VoidCallback? onDoubleTap;

  /// Callback fired when a single cell is tapped (used for linked
  /// highlight/tooltip).
  final void Function(LayoutCell cell)? onCellTap;

  /// Whether to play a pulsing halo after a new cell is inserted
  /// (corresponds to the TS version's `ux/pulse.ts` effect, built directly
  /// into the panel here — the pulse needs to know "which cell, and when it
  /// was added," information only `RoadPanel` itself has while diffing; an
  /// external controller can only pass a plain on/off switch).
  final bool pulseEnabled;

  /// Fired **before** the grid tile's built-in fill (only takes effect when
  /// `grid.style == GridStyle.tile`), useful for custom-drawing background
  /// elements underneath; see [RoadPainter.onBeforePaintGridCell].
  final GridCellPaintCallback? onBeforePaintGridCell;

  /// Fired **after** the grid tile's built-in fill; see
  /// [RoadPainter.onAfterPaintGridCell].
  final GridCellPaintCallback? onAfterPaintGridCell;

  /// Fired **before** each draw command's (circle/line/slash/dot/text
  /// marker/rectangle) built-in drawing; see
  /// [RoadPainter.onBeforePaintCommand].
  final CommandPaintCallback? onBeforePaintCommand;

  /// Fired **after** each draw command's built-in drawing; see
  /// [RoadPainter.onAfterPaintCommand].
  final CommandPaintCallback? onAfterPaintCommand;

  const RoadPanel({
    super.key,
    required this.cells,
    this.decorations = const [],
    required this.contentWidth,
    required this.contentHeight,
    this.grid,
    required this.theme,
    required this.panelWidth,
    required this.panelHeight,
    this.followTail = FollowTail.none,
    this.eventType = RoadUpdateKind.setResults,
    this.animDurationMs = 280,
    this.onDoubleTap,
    this.onCellTap,
    this.pulseEnabled = false,
    this.onBeforePaintGridCell,
    this.onAfterPaintGridCell,
    this.onBeforePaintCommand,
    this.onAfterPaintCommand,
  });

  @override
  State<RoadPanel> createState() => _RoadPanelState();
}

class _RoadPanelState extends State<RoadPanel> with SingleTickerProviderStateMixin {
  late ViewportState _viewport = createViewport();
  late Ticker _ticker;
  Duration _lastTick = Duration.zero;

  RoadLayout? _prevLayout;
  List<Transition> _transitions = const [];
  double _animProgress = 1;
  int _animStartMs = 0;

  /// Pulsing halo: runs on its own, longer sampling timeline (2000ms,
  /// matching the TS version's `ux/pulse.ts` default duration) independent
  /// of the insert animation (280ms); only applies to the most recently
  /// inserted cell when [RoadPanel.pulseEnabled] is set.
  LayoutCell? _pulseCell;
  int _pulseStartMs = 0;

  /// Source of the pulse halo's duration/color: shares the same defaults as
  /// [PulseOptions] in `ux/pulse.dart`, so the panel doesn't duplicate the
  /// literal values.
  static const _pulseOptions = PulseOptions();

  /// Transition index for the insert animation (computed once in
  /// didUpdateWidget, reused for the whole 280ms — not rebuilt as a map
  /// every frame).
  Map<String, LayoutCell> _enters = const {};
  Map<String, MoveTransition> _moves = const {};
  List<LayoutCell> _exitCells = const [];

  /// Cache of the static-frame (no transition) command list: reuses the
  /// same List instance when data hasn't changed, so the content layer's
  /// Picture cache identical-check actually works.
  List<DrawCommand>? _staticCommands;

  /// "Base image" commands during animation: cells not currently animating
  /// plus decorations, constant for the whole animation, kept in a separate
  /// Picture cache; cells currently entering/moving/exiting are sampled
  /// every frame and drawn as an overlay layer. This drops the animation
  /// frame's direct-draw workload from O(all commands) to O(animating cells).
  List<DrawCommand>? _animBaseCommands;

  /// Fallback grid spec cache (used when widget.grid is null), avoiding a
  /// new object on every build which would make shouldRepaint always true.
  GridSpec? _fallbackGrid;

  /// Content layer Picture cache: the static-frame command list is recorded
  /// only once; pure viewport frames (drag/inertia/auto-scroll) just replay
  /// it instead of walking every command through Paint/TextPainter again.
  final CommandLayerCache _layerCache = CommandLayerCache();

  /// Picture cache dedicated to the animation base image (kept separate
  /// from the static-frame cache so that once the animation ends and it
  /// falls back to the static list, neither cache evicts the other's
  /// recording).
  final CommandLayerCache _animBaseCache = CommandLayerCache();

  /// Background grid Picture cache: the grid is static in content
  /// coordinates, so pan-only frames just replay it without re-recording.
  final GridLayerCache _gridCache = GridLayerCache();

  /// Live frame state: data that changes every frame is written here and
  /// markFrame() is called, going straight to markNeedsPaint through the
  /// repaint Listenable — zero widget rebuild, zero element diff for
  /// animation/drag frames.
  final RoadFrameState _frame = RoadFrameState();

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    _prevLayout = _currentLayout();
    _syncFrame();
  }

  /// Writes the current frame's data into [_frame] and triggers a repaint
  /// (replaces setState: doesn't rebuild the widget subtree).
  void _syncFrame() {
    final base = _baseCommands();
    _frame
      ..commands = base
      ..overlayCommands = _overlayCommands()
      ..viewportOffset = Offset(_viewport.offsetX, _viewport.offsetY)
      ..viewportScale = _viewport.scale
      ..layerCache = identical(base, _staticCommands)
          ? _layerCache
          : identical(base, _animBaseCommands)
          ? _animBaseCache
          : null;
    _frame.markFrame();
  }

  /// Makes sure the Ticker is running whenever there's active work
  /// (viewport physics/cell animation/pulse halo); [_onTick] stops it on
  /// its own once there's nothing left to do, so an idle panel no longer
  /// spins on vsync callbacks.
  void _wake() {
    if (!_ticker.isActive) {
      // After the Ticker restarts, elapsed counts from zero again, so reset
      // _lastTick to zero in step, eliminating a dead first frame with dt<=0.
      _lastTick = Duration.zero;
      _ticker.start();
    }
  }

  @override
  void didUpdateWidget(covariant RoadPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.theme != oldWidget.theme) _fallbackGrid = null;

    // Skip diffing, invalidating command/Picture caches, and touching the
    // viewport when the data hasn't changed (parent rebuilt over unrelated
    // UI state) — otherwise every toggle switch would re-record Pictures
    // and rerun the diff on every panel. Layout objects come from the
    // engine's compute output, so references stay stable when data hasn't
    // changed.
    final dataChanged =
        !identical(widget.cells, oldWidget.cells) ||
        !identical(widget.decorations, oldWidget.decorations);
    if (!dataChanged) {
      // When panel geometry changes (e.g. window resize) bounds tighten, so
      // re-clamp the idle viewport into the new bounds — otherwise it could
      // sit outside the bounds with the Ticker already stopped and never
      // rebound.
      if (widget.panelWidth != oldWidget.panelWidth ||
          widget.panelHeight != oldWidget.panelHeight ||
          widget.contentWidth != oldWidget.contentWidth ||
          widget.contentHeight != oldWidget.contentHeight) {
        final b = _bounds();
        final cx = _viewport.offsetX.clamp(b.minX, b.maxX).toDouble();
        final cy = _viewport.offsetY.clamp(b.minY, b.maxY).toDouble();
        if (cx != _viewport.offsetX || cy != _viewport.offsetY) {
          _viewport = _viewport.copyWith(offsetX: cx, offsetY: cy);
          _syncFrame();
        }
      }
      return;
    }

    final next = _currentLayout();
    final animate = widget.eventType == RoadUpdateKind.append && widget.animDurationMs > 0;

    _transitions = animate ? diffLayout(_prevLayout, next) : const [];
    _animProgress = _transitions.isEmpty ? 1 : 0;
    // -1 sentinel: the Ticker may have stopped (elapsed resets to zero on
    // restart), so the real start time is filled in from that frame's
    // elapsed value the next time [_onTick] runs.
    _animStartMs = -1;
    _prevLayout = next;
    _staticCommands = null;

    if (_transitions.isEmpty) {
      _clearTransitionState();
    } else {
      final enters = <String, LayoutCell>{};
      final moves = <String, MoveTransition>{};
      final exitCells = <LayoutCell>[];
      for (final t in _transitions) {
        switch (t) {
          case EnterTransition(:final cell):
            enters[cell.key] = cell;
          case MoveTransition(:final to):
            moves[to.key] = t;
          case ExitTransition(:final cell):
            exitCells.add(cell);
        }
      }
      _enters = enters;
      _moves = moves;
      _exitCells = exitCells;
      // Animation base image: non-animating cells stay constant for the
      // whole animation, so record the Picture once and replay it repeatedly.
      _animBaseCommands = [
        ...widget.decorations,
        for (final cell in widget.cells)
          if (!enters.containsKey(cell.key) && !moves.containsKey(cell.key)) ...cell.commands,
      ];
    }

    if (widget.pulseEnabled && animate) {
      final entered = _transitions.whereType<EnterTransition>();
      if (entered.isNotEmpty) {
        _pulseCell = entered.last.cell;
        _pulseStartMs = -1;
      }
    }

    final bounds = _bounds();
    switch (widget.followTail) {
      case FollowTail.hard:
        _viewport = _viewport.copyWith(offsetX: bounds.minX, phase: ViewportPhase.idle);
      case FollowTail.ease:
        _viewport = startAutoScroll(_viewport, bounds.minX);
      case FollowTail.none:
        break;
    }

    _syncFrame();

    // The dragging phase is driven by pointer events (stepViewport is an
    // identity transform for it), so it doesn't count as active work —
    // otherwise data arriving mid-drag would keep the Ticker spinning at
    // 60fps until the finger lifts.
    if (_animProgress < 1 ||
        _pulseCell != null ||
        (_viewport.phase != ViewportPhase.idle && _viewport.phase != ViewportPhase.dragging)) {
      _wake();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _layerCache.dispose();
    _animBaseCache.dispose();
    _gridCache.dispose();
    _frame.dispose();
    super.dispose();
  }

  RoadLayout _currentLayout() => RoadLayout(
    cells: widget.cells,
    decorations: widget.decorations,
    contentWidth: widget.contentWidth,
    contentHeight: widget.contentHeight,
    grid: widget.grid,
  );

  ViewportBounds _bounds() => computeBounds(
    widget.panelWidth,
    widget.panelHeight,
    widget.contentWidth,
    widget.contentHeight,
    _viewport.scale,
  );

  void _onTick(Duration elapsed) {
    final dt = (elapsed - _lastTick).inMicroseconds / 1000.0;
    _lastTick = elapsed;
    if (dt <= 0) return;

    var changed = false;

    // Don't step during dragging: stepViewport is an identity transform for
    // that phase, and frames are driven by pointer events; counting it as
    // changed would keep the Ticker running forever during a drag.
    if (_viewport.phase != ViewportPhase.idle && _viewport.phase != ViewportPhase.dragging) {
      _viewport = stepViewport(_viewport, dt, _bounds(), defaultViewportConfig);
      changed = true;
    }

    if (_animProgress < 1) {
      if (_animStartMs < 0) _animStartMs = elapsed.inMilliseconds;
      final t = ((elapsed.inMilliseconds - _animStartMs) / widget.animDurationMs).clamp(0.0, 1.0);
      _animProgress = anim.Easing.easeOutCubic(t);
      changed = true;
      if (t >= 1) {
        _transitions = const [];
        _clearTransitionState();
      }
    }

    if (_pulseCell != null) {
      if (_pulseStartMs < 0) _pulseStartMs = elapsed.inMilliseconds;
      final t = (elapsed.inMilliseconds - _pulseStartMs) / _pulseOptions.duration;
      changed = true;
      if (t >= 1) _pulseCell = null;
    }

    if (changed) {
      _syncFrame();
    } else {
      // Viewport idle, animation finished, pulse ended: stop the Ticker so
      // an idle panel stops spinning.
      _ticker.stop();
    }
  }

  /// Clears the transition index and animation base image (called when the
  /// animation ends / on a non-animated update).
  void _clearTransitionState() {
    _enters = const {};
    _moves = const {};
    _exitCells = const [];
    _animBaseCommands = null;
  }

  /// The pulse halo's draw commands for the current frame: a stroked circle
  /// whose radius grows and opacity fades over time, layered on top of the
  /// cell's circle (corresponds to the TS version's `drawPulseRing`
  /// sampling logic).
  List<DrawCommand> _samplePulseRing() {
    final cell = _pulseCell;
    if (cell == null) return const [];
    final t = _pulseStartMs < 0
        ? 0.0
        : ((_lastTick.inMilliseconds - _pulseStartMs) / _pulseOptions.duration).clamp(0.0, 1.0);
    final cx = cell.x + cell.w / 2;
    final cy = cell.y + cell.h / 2;
    final r = cell.w * 0.42 * (1 + 0.3 * t);
    return [
      CircleCommand(
        x: cx,
        y: cy,
        r: r,
        stroke: _pulseOptions.color,
        lineWidth: 2,
        alpha: 0.6 * (1 - t),
      ),
    ];
  }

  /// This frame's content-layer "base image": the full static list (Picture
  /// cache) when there's no transition, or the "non-animating cells" base
  /// image (a separate Picture cache) during animation — both keep a
  /// constant reference throughout their own lifecycle.
  List<DrawCommand> _baseCommands() {
    if (_transitions.isEmpty) {
      return _staticCommands ??= [
        ...widget.decorations,
        for (final cell in widget.cells) ...cell.commands,
      ];
    }
    return _animBaseCommands!;
  }

  /// This frame's overlay layer: cells currently entering/moving/exiting
  /// sampled by progress, plus the pulse halo. Only animating cells are
  /// directly drawn every frame (usually 1-2), so text re-layout drops from
  /// every badge every frame to just the animating cell's own badge.
  List<DrawCommand> _overlayCommands() {
    final pulse = _samplePulseRing();
    if (_transitions.isEmpty) return pulse;

    final sampled = <DrawCommand>[];
    for (final cell in _enters.values) {
      sampled.addAll(sampleEnter(EnterAnimation.scaleIn.animName, cell, _animProgress));
    }
    for (final move in _moves.values) {
      sampled.addAll(sampleMove(MoveAnimation.tween.animName, move.from, move.to, _animProgress));
    }
    if (_animProgress < 1) {
      for (final cell in _exitCells) {
        sampled.addAll(sampleExit(ExitAnimation.fadeOut.animName, cell, _animProgress));
      }
    }
    sampled.addAll(pulse);
    return sampled;
  }

  Offset? _lastFocalPoint;
  double _lastGestureScale = 1;

  // `GestureDetector` doesn't allow attaching both pan and scale recognizers
  // at once (scale is a superset of pan, and the framework's own assertion
  // would throw) — so single-finger drag and two-finger zoom both go
  // through the three onScale* callbacks, distinguished by
  // ScaleUpdateDetails.pointerCount: 1 finger is treated as a drag (dragBy's
  // damping semantics), and only ≥2 fingers go through zoom (zoomAt's
  // focal-point invariant).

  void _onScaleStart(ScaleStartDetails details) {
    _lastFocalPoint = details.localFocalPoint;
    _lastGestureScale = 1;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    if (details.pointerCount <= 1) {
      final last = _lastFocalPoint ?? details.localFocalPoint;
      final dx = details.localFocalPoint.dx - last.dx;
      final dy = details.localFocalPoint.dy - last.dy;
      _viewport = dragBy(_viewport, dx, dy, _bounds(), defaultViewportConfig);
      _syncFrame();
    } else {
      final scaleDelta = details.scale / _lastGestureScale;
      _lastGestureScale = details.scale;
      if (scaleDelta != 1.0) {
        final nextScale = _viewport.scale * scaleDelta;
        _viewport = zoomAt(
          _viewport,
          details.localFocalPoint.dx,
          details.localFocalPoint.dy,
          nextScale,
          computeBounds(widget.panelWidth, widget.panelHeight, widget.contentWidth, widget.contentHeight, nextScale),
        );
        _syncFrame();
      }
    }
    _lastFocalPoint = details.localFocalPoint;
  }

  void _onScaleEnd(ScaleEndDetails details) {
    // The gesture system's built-in least-squares velocity estimate is in
    // px/s, but the viewport state machine wants px/ms, hence the /1000.
    final v = details.velocity.pixelsPerSecond;
    _viewport = endDrag(_viewport, v.dx / 1000, v.dy / 1000, _bounds(), defaultViewportConfig);
    _syncFrame();
    _wake();
  }

  void _handleDoubleTap() {
    if (widget.onDoubleTap != null) {
      widget.onDoubleTap!();
      return;
    }
    _viewport = startAutoScroll(_viewport, _bounds().minX);
    _syncFrame();
    _wake();
  }

  @override
  Widget build(BuildContext context) {
    // Data that changes every frame lives in _frame and is driven by the
    // repaint Listenable; here we only assemble the low-frequency static
    // config — the panel no longer calls setState anywhere, so
    // animation/drag frames trigger zero rebuilds.
    return GestureDetector(
      onScaleStart: _onScaleStart,
      onScaleUpdate: _onScaleUpdate,
      onScaleEnd: _onScaleEnd,
      onDoubleTap: _handleDoubleTap,
      child: SizedBox(
        width: widget.panelWidth,
        height: widget.panelHeight,
        // RepaintBoundary: isolates this panel into its own paint layer —
        // otherwise markNeedsPaint from one animating panel would propagate
        // to the shared ancestor, repainting every sibling panel on screen
        // every frame.
        child: RepaintBoundary(
          child: ClipRect(
            child: CustomPaint(
              painter: RoadFramePainter(
                frame: _frame,
                gridCache: _gridCache,
                contentWidth: widget.contentWidth,
                grid:
                    widget.grid ??
                    (_fallbackGrid ??= GridSpec(cellSize: 18, stroke: widget.theme.grid.stroke)),
                background: widget.theme.canvas.background,
                onBeforePaintGridCell: widget.onBeforePaintGridCell,
                onAfterPaintGridCell: widget.onAfterPaintGridCell,
                onBeforePaintCommand: widget.onBeforePaintCommand,
                onAfterPaintCommand: widget.onAfterPaintCommand,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
