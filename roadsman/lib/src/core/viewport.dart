/// Pure state machine for viewport dragging/inertia/rebound/scaling.
///
/// Does not depend on any gesture library -- the upper layer (`panel/road_panel.dart`) uses `GestureDetector` to feed
/// drag deltas/release velocity/scale focus to the pure functions here, the state machine itself does not know the input source.
/// Ported from `src/core/viewport.ts`.
library;

import 'dart:math' as math;

import 'types.dart';

const double _minScale = 0.5;
const double _maxScale = 3;

/// Default viewport physics parameters.
const ViewportConfig defaultViewportConfig = ViewportConfig(
  rubberBandFactor: 0.3,
  friction: 0.95,
  minVelocity: 0.02,
  reboundTau: 100,
  snapEpsilon: 0.5,
);

/// Create initial viewport state (origin, scale=1, idle).
///
/// ```dart
/// final s = createViewport();
/// s.phase; // ViewportPhase.idle
/// ```
ViewportState createViewport() => const ViewportState(
  offsetX: 0,
  offsetY: 0,
  scale: 1,
  velocityX: 0,
  velocityY: 0,
  phase: ViewportPhase.idle,
);

/// Apply value to rubber band (damping compression beyond bounds).
double _applyRubberBand(double value, double min, double max, double factor) {
  if (value > max) return max + (value - max) * factor;
  if (value < min) return min - (min - value) * factor;
  return value;
}

/// Reverse-calculate the real coordinate before rubber band compression, avoiding jitter from repeated compression on already-compressed values during incremental dragging.
double _decompressRubberBand(double displayed, double min, double max, double factor) {
  if (displayed > max) return max + (displayed - max) / factor;
  if (displayed < min) return min - (min - displayed) / factor;
  return displayed;
}

double _clamp(double value, double min, double max) => math.max(min, math.min(max, value));

/// Handle drag delta, update offsetX/Y (Y axis conditionally locked: locked when `bounds.minY == 0`).
///
/// ```dart
/// final next = dragBy(state, -10, 0, bounds, defaultViewportConfig);
/// ```
ViewportState dragBy(ViewportState s, double dx, double dy, ViewportBounds bounds, ViewportConfig cfg) {
  final rawX = _decompressRubberBand(s.offsetX, bounds.minX, bounds.maxX, cfg.rubberBandFactor);
  final newOffsetX = _applyRubberBand(rawX + dx, bounds.minX, bounds.maxX, cfg.rubberBandFactor);

  final yLocked = bounds.minY == 0;
  var newOffsetY = s.offsetY;
  if (!yLocked) {
    final rawY = _decompressRubberBand(s.offsetY, bounds.minY, bounds.maxY, cfg.rubberBandFactor);
    newOffsetY = _applyRubberBand(rawY + dy, bounds.minY, bounds.maxY, cfg.rubberBandFactor);
  }

  return s.copyWith(
    phase: ViewportPhase.dragging,
    velocityX: 0,
    velocityY: 0,
    offsetX: newOffsetX,
    offsetY: yLocked ? 0 : newOffsetY,
  );
}

/// End drag, decide whether to enter inertia or rebound phase based on velocity.
///
/// ```dart
/// final next = endDrag(state, velocityX, velocityY, bounds, defaultViewportConfig);
/// ```
ViewportState endDrag(ViewportState s, double vx, double vy, ViewportBounds bounds, ViewportConfig cfg) {
  final speed = math.sqrt(vx * vx + vy * vy);
  final inBounds =
      s.offsetX >= bounds.minX &&
      s.offsetX <= bounds.maxX &&
      s.offsetY >= bounds.minY &&
      s.offsetY <= bounds.maxY;

  if (speed < cfg.minVelocity) {
    return s.copyWith(
      velocityX: 0,
      velocityY: 0,
      phase: inBounds ? ViewportPhase.idle : ViewportPhase.rebound,
    );
  }
  final yLocked = bounds.minY == 0;
  return s.copyWith(velocityX: vx, velocityY: yLocked ? 0 : vy, phase: ViewportPhase.inertia);
}

/// Advance viewport state machine one frame ([dt] ms). Handle inertia / rebound / autoScroll three phases;
/// idle directly returns original state.
///
/// ```dart
/// final next = stepViewport(state, 16.7, bounds, defaultViewportConfig);
/// ```
ViewportState stepViewport(ViewportState s, double dt, ViewportBounds bounds, ViewportConfig cfg) {
  if (s.phase == ViewportPhase.idle) return s;

  var offsetX = s.offsetX;
  var offsetY = s.offsetY;
  var velocityX = s.velocityX;
  var velocityY = s.velocityY;
  var phase = s.phase;
  final yLocked = bounds.minY == 0;

  if (phase == ViewportPhase.inertia) {
    final decay = math.pow(cfg.friction, dt / 16.7).toDouble();
    velocityX *= decay;
    velocityY *= decay;
    offsetX += velocityX * dt;
    if (!yLocked) offsetY += velocityY * dt;

    final outOfBounds =
        offsetX < bounds.minX ||
        offsetX > bounds.maxX ||
        (!yLocked && (offsetY < bounds.minY || offsetY > bounds.maxY));

    if (outOfBounds) {
      phase = ViewportPhase.rebound;
    } else if (math.sqrt(velocityX * velocityX + velocityY * velocityY) < cfg.minVelocity) {
      phase = ViewportPhase.idle;
    }
  }

  if (phase == ViewportPhase.rebound) {
    final targetX = _clamp(offsetX, bounds.minX, bounds.maxX);
    final targetY = yLocked ? 0.0 : _clamp(offsetY, bounds.minY, bounds.maxY);
    final alpha = 1 - math.exp(-dt / cfg.reboundTau);
    offsetX += (targetX - offsetX) * alpha;
    if (!yLocked) offsetY += (targetY - offsetY) * alpha;
    velocityX = 0;
    velocityY = 0;

    final snapped =
        (targetX - offsetX).abs() < cfg.snapEpsilon &&
        (yLocked || (targetY - offsetY).abs() < cfg.snapEpsilon);
    if (snapped) {
      offsetX = targetX;
      offsetY = yLocked ? 0 : targetY;
      phase = ViewportPhase.idle;
    }
  }

  if (phase == ViewportPhase.autoScroll) {
    final targetX = s.autoScrollTargetX ?? bounds.minX;
    final alpha = 1 - math.exp(-dt / cfg.reboundTau);
    offsetX += (targetX - offsetX) * alpha;
    if ((targetX - offsetX).abs() < cfg.snapEpsilon) {
      offsetX = targetX;
      phase = ViewportPhase.idle;
    }
  }

  return s.copyWith(
    offsetX: offsetX,
    offsetY: yLocked ? 0 : offsetY,
    velocityX: velocityX,
    velocityY: yLocked ? 0 : velocityY,
    phase: phase,
  );
}

/// Compute viewport bounds (based on panel size, content size, and scale factor).
///
/// ```dart
/// final bounds = computeBounds(400, 216, 800, 216, 1);
/// bounds.minX; // -400 (content wider than panel)
/// ```
ViewportBounds computeBounds(double panelW, double panelH, double contentW, double contentH, double scale) =>
    ViewportBounds(
      minX: math.min(0, panelW - contentW * scale),
      maxX: 0,
      minY: math.min(0, panelH - contentH * scale),
      maxY: 0,
    );

/// Scale viewport around a focal point, ensuring the screen position of content at the focal point remains unchanged.
///
/// [nextScale] beyond `[0.5, 3]` will be clamped; [bounds] needs to be recomputed based on the clamped scale value.
///
/// ```dart
/// final bounds = computeBounds(panelW, panelH, contentW, contentH, nextScale);
/// final next = zoomAt(state, focalX, focalY, state.scale * 1.1, bounds);
/// ```
ViewportState zoomAt(ViewportState s, double focalX, double focalY, double nextScale, ViewportBounds bounds) {
  final clamped = _clamp(nextScale, _minScale, _maxScale);

  // Invariant: the content point at the focal point has the same screen position before and after scaling.
  // contentX = (focalX - offsetX) / scale
  // offsetX' = focalX - contentX * nextScale
  final contentX = (focalX - s.offsetX) / s.scale;
  final contentY = (focalY - s.offsetY) / s.scale;
  final newOffsetX = focalX - contentX * clamped;
  final newOffsetY = focalY - contentY * clamped;

  // Directly clamp to new bounds (scaling does not use rubber band).
  return s.copyWith(
    scale: clamped,
    offsetX: _clamp(newOffsetX, bounds.minX, bounds.maxX),
    offsetY: _clamp(newOffsetY, bounds.minY, bounds.maxY),
    phase: ViewportPhase.idle,
  );
}

/// Trigger automatic scroll to end (called when new cell arrives and was previously tail-aligned).
///
/// Set autoScroll phase, exponentially approach [targetX].
///
/// ```dart
/// final next = startAutoScroll(state, newBounds.minX);
/// ```
ViewportState startAutoScroll(ViewportState s, double targetX) =>
    s.copyWith(phase: ViewportPhase.autoScroll, autoScrollTargetX: targetX);
