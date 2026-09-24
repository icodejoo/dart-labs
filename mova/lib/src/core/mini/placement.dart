import '../options/mini_config.dart';

/// An axis-aligned rectangle in logical pixels, in the host window's
/// coordinate space. A tiny stand-in for `Rect`: `core/` must not import
/// `dart:ui`.
///
/// 宿主窗口坐标系下的轴对齐矩形（逻辑像素）。`Rect` 的极简替身：`core/`
/// 不许 import `dart:ui`。
class MovaMiniRect {
  /// Creates the rectangle from its left/top corner and size.
  ///
  /// 由左上角与尺寸创建矩形。
  const MovaMiniRect({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  /// Left edge / 左边界
  final double left;

  /// Top edge / 上边界
  final double top;

  /// Width / 宽度
  final double width;

  /// Height / 高度
  final double height;

  /// Right edge / 右边界
  double get right => left + width;

  /// Bottom edge / 下边界
  double get bottom => top + height;

  /// Returns a copy translated by ([dx], [dy]).
  ///
  /// 返回平移 ([dx], [dy]) 后的拷贝。
  MovaMiniRect shift(double dx, double dy) =>
      MovaMiniRect(left: left + dx, top: top + dy, width: width, height: height);

  /// Returns a copy with the given fields replaced.
  ///
  /// 返回一份替换了指定字段的拷贝。
  MovaMiniRect copyWith({double? left, double? top, double? width, double? height}) =>
      MovaMiniRect(
        left: left ?? this.left,
        top: top ?? this.top,
        width: width ?? this.width,
        height: height ?? this.height,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MovaMiniRect &&
          left == other.left &&
          top == other.top &&
          width == other.width &&
          height == other.height;

  @override
  int get hashCode => Object.hash(left, top, width, height);

  @override
  String toString() => 'MovaMiniRect(left: $left, top: $top, width: $width, height: $height)';
}

/// The edge insets kept clear of system chrome (status bar, home indicator).
///
/// 需要避开系统 chrome（状态栏、Home 指示条）的内边距。
class MovaMiniInsets {
  /// Creates a set of edge insets; all zero by default.
  ///
  /// 创建一组边缘内边距；默认全为 0。
  const MovaMiniInsets({this.left = 0, this.top = 0, this.right = 0, this.bottom = 0});

  /// Left inset / 左边距
  final double left;

  /// Top inset / 上边距
  final double top;

  /// Right inset / 右边距
  final double right;

  /// Bottom inset / 下边距
  final double bottom;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MovaMiniInsets &&
          left == other.left &&
          top == other.top &&
          right == other.right &&
          bottom == other.bottom;

  @override
  int get hashCode => Object.hash(left, top, right, bottom);

  @override
  String toString() => 'MovaMiniInsets(left: $left, top: $top, right: $right, bottom: $bottom)';
}

/// Decides where the mini window lands after a drag ends.
///
/// Pure logic, injected via [MovaMiniConfig.placement] so a host can replace
/// the built-in corner snapping with its own (free positioning, magnetic
/// grid, single-edge dock, …) without forking the widget.
///
/// 决定小窗在一次拖动结束后落在哪里。
///
/// 纯逻辑，经 [MovaMiniConfig.placement] 注入，宿主可以在不 fork widget 的
/// 前提下把内置的吸角换成自己的（自由摆放、磁吸网格、单边停靠……）。
abstract class MovaMiniPlacement {
  /// Returns the resting rectangle for [current] inside [bounds].
  ///
  /// - [current]: where the finger released it / 手指松开时的位置
  /// - [bounds]: the host window rect / 宿主窗口矩形
  /// - [insets]: system-chrome insets to avoid / 要避开的系统内边距
  /// - [velocityX]/[velocityY]: release velocity in px/s / 松手速度
  ///
  /// 返回 [current] 在 [bounds] 内的最终停靠矩形。
  MovaMiniRect settle(
    MovaMiniRect current, {
    required MovaMiniRect bounds,
    required MovaMiniInsets insets,
    double velocityX = 0,
    double velocityY = 0,
  });
}

/// Clamps [r] so it lies fully inside [bounds] minus [insets] and [margin].
/// Exposed separately because the drag itself needs it every frame, while
/// snapping only happens on release.
///
/// 钳制 [r] 使其完全落在 [bounds] 去掉 [insets] 与 [margin] 后的区域内。
/// 单独暴露是因为拖动过程每帧都要用它，而吸边只在松手时发生。
MovaMiniRect clampToBounds(
  MovaMiniRect r, {
  required MovaMiniRect bounds,
  required MovaMiniInsets insets,
  double margin = 0,
}) {
  final minLeft = bounds.left + insets.left + margin;
  final maxRight = bounds.right - insets.right - margin;
  final minTop = bounds.top + insets.top + margin;
  final maxBottom = bounds.bottom - insets.bottom - margin;

  final availableWidth = maxRight - minLeft;
  final availableHeight = maxBottom - minTop;

  // Degenerate case: the window is wider/taller than the available area.
  // Fall back to top-left alignment instead of producing a negative width.
  //
  // 退化情形：窗口比可用区还大。退回左上对齐，而不是产生负宽/负高。
  final width = r.width > availableWidth ? availableWidth : r.width;
  final height = r.height > availableHeight ? availableHeight : r.height;

  var left = r.left;
  var top = r.top;

  if (left < minLeft) left = minLeft;
  final maxLeft = minLeft + (availableWidth - width);
  if (left > maxLeft) left = maxLeft;

  if (top < minTop) top = minTop;
  final maxTop = minTop + (availableHeight - height);
  if (top > maxTop) top = maxTop;

  return MovaMiniRect(left: left, top: top, width: width, height: height);
}

/// Remaps [r] from [oldBounds] to [newBounds] by preserving its *relative*
/// position (e.g. "near the bottom-right corner") instead of its raw pixel
/// coordinates. Needed because a bare [clampToBounds] only guarantees
/// validity, not intent: after a bounds shape change (rotation swaps width
/// and height), reusing the old absolute `left`/`top` can leave the window
/// stranded far from where it visually was — real-device verification
/// (2026-09-24) found the window "走位" toward an edge across repeated
/// rotations. Callers should still run the result through [clampToBounds]
/// as a safety net (this function does not itself guarantee validity when
/// [oldBounds] is degenerate, e.g. zero-sized).
///
/// 把 [r] 从 [oldBounds] 映射到 [newBounds]，保持的是**相对位置**（如"贴在
/// 右下角"）而不是绝对像素坐标。必要性：单纯 [clampToBounds] 只保证"合法"
/// 而不保证"符合直觉"——bounds 形状变化（转屏导致宽高互换）后直接沿用旧的
/// 绝对 `left`/`top`，可能让小窗停在离原视觉位置很远的地方——真机验证
/// （2026-09-24）实测到连续转屏会"走位"往某个方向跑。调用方仍应把结果过一遍
/// [clampToBounds] 兜底（[oldBounds] 退化为零尺寸等情形本函数本身不保证
/// 合法性）。
MovaMiniRect remapProportionally(
  MovaMiniRect r, {
  required MovaMiniRect oldBounds,
  required MovaMiniRect newBounds,
}) {
  final oldAvailW = oldBounds.width - r.width;
  final oldAvailH = oldBounds.height - r.height;
  final fracX = oldAvailW > 0 ? ((r.left - oldBounds.left) / oldAvailW).clamp(0.0, 1.0) : 0.0;
  final fracY = oldAvailH > 0 ? ((r.top - oldBounds.top) / oldAvailH).clamp(0.0, 1.0) : 0.0;

  final newAvailW = newBounds.width - r.width;
  final newAvailH = newBounds.height - r.height;
  return r.copyWith(
    left: newBounds.left + fracX * newAvailW,
    top: newBounds.top + fracY * newAvailH,
  );
}

/// Returns the rect for [corner] — the window's first appearance.
///
/// 返回 [corner] 对应的矩形——小窗首次出现的位置。
MovaMiniRect rectForCorner(
  MovaMiniCorner corner, {
  required double width,
  required double height,
  required MovaMiniRect bounds,
  required MovaMiniInsets insets,
  double margin = 0,
}) {
  final minLeft = bounds.left + insets.left + margin;
  final maxLeft = bounds.right - insets.right - margin - width;
  final minTop = bounds.top + insets.top + margin;
  final maxTop = bounds.bottom - insets.bottom - margin - height;

  switch (corner) {
    case MovaMiniCorner.topLeft:
      return MovaMiniRect(left: minLeft, top: minTop, width: width, height: height);
    case MovaMiniCorner.topRight:
      return MovaMiniRect(left: maxLeft, top: minTop, width: width, height: height);
    case MovaMiniCorner.bottomLeft:
      return MovaMiniRect(left: minLeft, top: maxTop, width: width, height: height);
    case MovaMiniCorner.bottomRight:
      return MovaMiniRect(left: maxLeft, top: maxTop, width: width, height: height);
  }
}

/// Built-in placement: clamps into bounds, then (when [snap]) slides
/// horizontally to whichever side the window's center is nearer, honouring
/// [margin] and the safe-area [MovaMiniInsets].
///
/// 内置落点策略：先钳进边界，再（[snap] 为真时）沿水平方向滑到窗口中心更靠近
/// 的那一侧，并遵守 [margin] 与安全区 [MovaMiniInsets]。
class MovaCornerSnap implements MovaMiniPlacement {
  /// Creates the built-in corner-snapping placement policy.
  ///
  /// 创建内置的吸角落点策略。
  ///
  /// - [snap]: whether release slides to the nearer horizontal edge /
  ///   松手是否滑向更近的水平边缘
  /// - [margin]: edge inset kept clear / 保留的边距
  const MovaCornerSnap({this.snap = true, this.margin = 0});

  /// Whether release slides to the nearer horizontal edge.
  ///
  /// 松手是否滑向更近的水平边缘。
  final bool snap;

  /// Edge inset kept clear.
  ///
  /// 保留的边距。
  final double margin;

  @override
  MovaMiniRect settle(
    MovaMiniRect current, {
    required MovaMiniRect bounds,
    required MovaMiniInsets insets,
    double velocityX = 0,
    double velocityY = 0,
  }) {
    // Vertical direction is always clamp-only — snapping is a horizontal
    // (left/right edge) concept only, by deliberate product decision.
    //
    // 垂直方向永远只钳制不吸边——吸边只是水平（左右边缘）概念，是明确的
    // 产品决策。
    final clamped = clampToBounds(current, bounds: bounds, insets: insets, margin: margin);
    if (!snap) return clamped;

    final minLeft = bounds.left + insets.left + margin;
    final maxLeft = bounds.right - insets.right - margin - clamped.width;

    // Fast, decisive horizontal fling wins over the window's current center
    // position — inertia takes priority.
    //
    // 明确的高速水平甩动优先于窗口当前中心位置——惯性优先。
    const flingThreshold = 800.0;
    bool goLeft;
    if (velocityX.abs() >= flingThreshold) {
      goLeft = velocityX < 0;
    } else {
      final center = clamped.left + clamped.width / 2;
      final boundsCenter = bounds.left + bounds.width / 2;
      goLeft = center < boundsCenter;
    }

    return clamped.copyWith(left: goLeft ? minLeft : maxLeft);
  }
}
