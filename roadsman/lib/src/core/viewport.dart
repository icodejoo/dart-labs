/// 视口拖拽/惯性/回弹/缩放的纯状态机。
///
/// 不依赖任何手势库——上层（`panel/road_panel.dart`）用 `GestureDetector` 把
/// 拖拽增量/释放速度/缩放焦点喂给这里的纯函数，状态机本身不知道输入源。
/// 移植自 `src/core/viewport.ts`。
library;

import 'dart:math' as math;

import 'types.dart';

const double _minScale = 0.5;
const double _maxScale = 3;

/// 默认视口物理参数。
const ViewportConfig defaultViewportConfig = ViewportConfig(
  rubberBandFactor: 0.3,
  friction: 0.95,
  minVelocity: 0.02,
  reboundTau: 100,
  snapEpsilon: 0.5,
);

/// 创建初始视口状态（原点，scale=1，idle）。
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

/// 将值压入橡皮筋（超出边界的阻尼压缩）。
double _applyRubberBand(double value, double min, double max, double factor) {
  if (value > max) return max + (value - max) * factor;
  if (value < min) return min - (min - value) * factor;
  return value;
}

/// 反算橡皮筋压缩前的真实坐标，避免每次增量拖拽都在已压缩值上再次压缩导致抖动。
double _decompressRubberBand(double displayed, double min, double max, double factor) {
  if (displayed > max) return max + (displayed - max) / factor;
  if (displayed < min) return min - (min - displayed) / factor;
  return displayed;
}

double _clamp(double value, double min, double max) => math.max(min, math.min(max, value));

/// 处理拖拽增量，更新 offsetX/Y（Y 轴条件锁死：`bounds.minY == 0` 时锁死）。
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

/// 结束拖拽，根据速度决定进入惯性或回弹阶段。
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

/// 推进视口状态机一帧（[dt] ms）。处理 inertia / rebound / autoScroll 三个阶段；
/// idle 直接返回原状态。
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

/// 计算视口边界（根据面板尺寸、内容尺寸和缩放比例）。
///
/// ```dart
/// final bounds = computeBounds(400, 216, 800, 216, 1);
/// bounds.minX; // -400（内容比面板宽）
/// ```
ViewportBounds computeBounds(double panelW, double panelH, double contentW, double contentH, double scale) =>
    ViewportBounds(
      minX: math.min(0, panelW - contentW * scale),
      maxX: 0,
      minY: math.min(0, panelH - contentH * scale),
      maxY: 0,
    );

/// 围绕焦点缩放视口，保证焦点处内容的屏幕位置不变。
///
/// [nextScale] 超出 `[0.5, 3]` 会被 clamp；[bounds] 需按 clamp 后的缩放值重新计算。
///
/// ```dart
/// final bounds = computeBounds(panelW, panelH, contentW, contentH, nextScale);
/// final next = zoomAt(state, focalX, focalY, state.scale * 1.1, bounds);
/// ```
ViewportState zoomAt(ViewportState s, double focalX, double focalY, double nextScale, ViewportBounds bounds) {
  final clamped = _clamp(nextScale, _minScale, _maxScale);

  // 不变量：焦点处的内容点在缩放前后屏幕位置不变。
  // contentX = (focalX - offsetX) / scale
  // offsetX' = focalX - contentX * nextScale
  final contentX = (focalX - s.offsetX) / s.scale;
  final contentY = (focalY - s.offsetY) / s.scale;
  final newOffsetX = focalX - contentX * clamped;
  final newOffsetY = focalY - contentY * clamped;

  // 直接 clamp 到新边界（缩放不走橡皮筋）。
  return s.copyWith(
    scale: clamped,
    offsetX: _clamp(newOffsetX, bounds.minX, bounds.maxX),
    offsetY: _clamp(newOffsetY, bounds.minY, bounds.maxY),
    phase: ViewportPhase.idle,
  );
}

/// 触发自动滚动到尾部（新格子到来且之前处于尾部对齐时调用）。
///
/// 设置 autoScroll 阶段，指数趋近 [targetX]。
///
/// ```dart
/// final next = startAutoScroll(state, newBounds.minX);
/// ```
ViewportState startAutoScroll(ViewportState s, double targetX) =>
    s.copyWith(phase: ViewportPhase.autoScroll, autoScrollTargetX: targetX);
