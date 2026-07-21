/// Animation system (pure functions).
///
/// Provides [diffLayout] (layout diff), easing functions, enter/move/exit animation sampling,
/// [applyWindow] (window mode cropping) etc pure functions. Rendering layer remains stateless; animation layer is between
/// compute output and rendering layer. Ported from `src/core/animation.ts`.
library;

import 'dart:math' as math;

import 'types.dart';

/// Easing function type.
typedef EasingFn = double Function(double t);

/// Collection of easing functions. Any `double Function(double)` can be passed in directly.
///
/// ```dart
/// final v = Easing.easeOutCubic(0.5); // about 0.875
/// ```
abstract final class Easing {
  /// Linear.
  static double linear(double t) => t;

  /// Ease out cubic (gentle landing).
  static double easeOutCubic(double t) => 1 - math.pow(1 - t, 3).toDouble();

  /// Ease out back (with slight elasticity).
  static double easeOutBack(double t) {
    const c = 1.70158;
    return 1 + (c + 1) * math.pow(t - 1, 3) + c * math.pow(t - 1, 2);
  }

  /// Spring (approximation, overshoot then rebound).
  static double spring(double t) {
    const omega = 12.0;
    const zeta = 0.5;
    return 1 - math.exp(-zeta * omega * t) * math.cos(omega * math.sqrt(1 - zeta * zeta) * t);
  }
}

/// Enter animation preset names (when cell first appears).
enum EnterAnimation {
  /// No animation, directly present final state.
  none,

  /// Fade in (alpha 0→1).
  fadeIn,

  /// Scale enter (radius 0→r, with [Easing.easeOutBack] has rebound).
  scaleIn,

  /// Drop in (fall from above + fade in).
  dropIn,
}

/// Move animation preset names (cell position change, when window shifts left).
enum MoveAnimation {
  /// No animation.
  none,

  /// Linear position tween.
  tween,
}

/// Exit animation preset names (when cell is pushed out in window mode).
enum ExitAnimation {
  /// No animation (disappear directly).
  none,

  /// Fade out + shift left half cell.
  fadeOut,
}

/// Road display mode: follow viewport easing follow (default) / window fixed N columns, push out when exceeded.
enum RoadDisplayMode { follow, window }

/// Transition description for a single cell (sealed class).
sealed class Transition {
  const Transition();
}

/// Cell enter (newly added).
final class EnterTransition extends Transition {
  final LayoutCell cell;
  const EnterTransition(this.cell);
}

/// Cell move (same key, position change).
final class MoveTransition extends Transition {
  final LayoutCell from;
  final LayoutCell to;
  const MoveTransition(this.from, this.to);
}

/// Cell exit (pushed out).
final class ExitTransition extends Transition {
  final LayoutCell cell;
  const ExitTransition(this.cell);
}

/// Compare two layouts, output transition list (based only on key comparison, not content).
/// When [prev] is null (first frame/full refresh), returns empty list (directly present final state).
///
/// ```dart
/// final transitions = diffLayout(prev, next);
/// ```
List<Transition> diffLayout(RoadLayout? prev, RoadLayout next) {
  if (prev == null) return const [];

  final prevMap = {for (final c in prev.cells) c.key: c};
  final nextMap = {for (final c in next.cells) c.key: c};
  final transitions = <Transition>[];

  for (final entry in nextMap.entries) {
    if (!prevMap.containsKey(entry.key)) {
      transitions.add(EnterTransition(entry.value));
    }
  }

  for (final entry in nextMap.entries) {
    final prevCell = prevMap[entry.key];
    if (prevCell != null && (prevCell.x != entry.value.x || prevCell.y != entry.value.y)) {
      transitions.add(MoveTransition(prevCell, entry.value));
    }
  }

  for (final entry in prevMap.entries) {
    if (!nextMap.containsKey(entry.key)) {
      transitions.add(ExitTransition(entry.value));
    }
  }

  return transitions;
}

/// Enter animation sampling function type.
typedef EnterSampleFn = List<DrawCommand> Function(LayoutCell cell, double progress);

/// Move animation sampling function type.
typedef MoveSampleFn = List<DrawCommand> Function(LayoutCell from, LayoutCell to, double progress);

/// Exit animation sampling function type.
typedef ExitSampleFn = List<DrawCommand> Function(LayoutCell cell, double progress);

final _enterRegistry = <String, EnterSampleFn>{};
final _moveRegistry = <String, MoveSampleFn>{};
final _exitRegistry = <String, ExitSampleFn>{};

/// Register custom enter animation, can override built-in behavior by [name] in [sampleEnter].
void registerEnterAnimation(String name, EnterSampleFn fn) => _enterRegistry[name] = fn;

/// Register custom move animation.
void registerMoveAnimation(String name, MoveSampleFn fn) => _moveRegistry[name] = fn;

/// Register custom exit animation.
void registerExitAnimation(String name, ExitSampleFn fn) => _exitRegistry[name] = fn;

String _enterAnimName(EnterAnimation a) => switch (a) {
  EnterAnimation.none => 'none',
  EnterAnimation.fadeIn => 'fadeIn',
  EnterAnimation.scaleIn => 'scaleIn',
  EnterAnimation.dropIn => 'dropIn',
};

/// Sample enter animation, return the cell's draw commands at [progress].
///
/// [name] is usually the name corresponding to [EnterAnimation] (see `_enterAnimName`), or can be
/// a custom name registered via [registerEnterAnimation]. [cellSize] used for dropIn to compute starting
/// Y offset, defaults to 36.
///
/// ```dart
/// final cmds = sampleEnter('scaleIn', cell, 0.5);
/// ```
List<DrawCommand> sampleEnter(String name, LayoutCell cell, double progress, [double cellSize = 36]) {
  final custom = _enterRegistry[name];
  if (custom != null) return custom(cell, progress);

  switch (name) {
    case 'none':
      return _applyAlpha(cell.commands, 1);
    case 'fadeIn':
      return _applyAlpha(cell.commands, progress);
    case 'scaleIn':
      return _scaleCommands(cell.commands, cell, progress);
    case 'dropIn':
      final offsetY = (1 - progress) * -cellSize;
      return translateCommands(_applyAlpha(cell.commands, progress), 0, offsetY);
    default:
      return _applyAlpha(cell.commands, 1);
  }
}

/// Sample move animation, return the cell's draw commands at [progress].
///
/// ```dart
/// final cmds = sampleMove('tween', from, to, 0.5);
/// ```
List<DrawCommand> sampleMove(String name, LayoutCell from, LayoutCell to, double progress) {
  final custom = _moveRegistry[name];
  if (custom != null) return custom(from, to, progress);

  switch (name) {
    case 'none':
      return to.commands;
    case 'tween':
    default:
      final dx = (to.x - from.x) * progress;
      final dy = (to.y - from.y) * progress;
      return translateCommands(from.commands, dx, dy);
  }
}

/// Sample exit animation, return the cell's draw commands at [progress] (0 fully visible, 1 fully disappeared).
///
/// ```dart
/// final cmds = sampleExit('fadeOut', cell, 0.5);
/// ```
List<DrawCommand> sampleExit(String name, LayoutCell cell, double progress, [double cellSize = 36]) {
  final custom = _exitRegistry[name];
  if (custom != null) return custom(cell, progress);

  switch (name) {
    case 'none':
      return progress < 1 ? cell.commands : const [];
    case 'fadeOut':
    default:
      final alpha = 1 - progress;
      final offsetX = -(progress * cellSize * 0.5);
      return translateCommands(_applyAlpha(cell.commands, alpha), offsetX, 0);
  }
}

/// Convert [EnterAnimation]/[MoveAnimation]/[ExitAnimation] enum values to the string names expected by
/// [sampleEnter] etc functions, for callers who don't want to hand-write string literals.
extension EnterAnimationName on EnterAnimation {
  String get animName => _enterAnimName(this);
}

extension MoveAnimationName on MoveAnimation {
  String get animName => this == MoveAnimation.none ? 'none' : 'tween';
}

extension ExitAnimationName on ExitAnimation {
  String get animName => this == ExitAnimation.none ? 'none' : 'fadeOut';
}

/// Window mode: crop the most recent [windowCols] columns, cells outside the range are discarded, cells inside the range shift left as a whole.
/// key remains unchanged, [diffLayout] naturally derives enter/move/exit.
///
/// ```dart
/// final windowed = applyWindow(layout, 8, 36);
/// ```
RoadLayout applyWindow(RoadLayout layout, int windowCols, double cellSize) {
  if (layout.cells.isEmpty) return layout;

  final maxPhysCol = layout.cells.map((c) => (c.x / cellSize).floor()).reduce(math.max);
  final minKeepCol = math.max(0, maxPhysCol - windowCols + 1);
  final shiftX = minKeepCol * cellSize;

  final filtered = layout.cells
      .where((c) => (c.x / cellSize).floor() >= minKeepCol)
      .map(
        (c) => LayoutCell(
          key: c.key,
          x: c.x - shiftX,
          y: c.y,
          w: c.w,
          h: c.h,
          resultNo: c.resultNo,
          commands: c.commands.map((cmd) => translateCommand(cmd, -shiftX, 0)).toList(),
        ),
      )
      .toList();

  return RoadLayout(
    cells: filtered,
    decorations: layout.decorations?.map((cmd) => translateCommand(cmd, -shiftX, 0)).toList(),
    contentWidth: windowCols * cellSize,
    contentHeight: layout.contentHeight,
  );
}

List<DrawCommand> _applyAlpha(List<DrawCommand> commands, double alpha) =>
    commands.map((cmd) => _withAlpha(cmd, alpha)).toList();

DrawCommand _withAlpha(DrawCommand cmd, double alpha) => switch (cmd) {
  CircleCommand c => CircleCommand(x: c.x, y: c.y, r: c.r, fill: c.fill, stroke: c.stroke, lineWidth: c.lineWidth, alpha: alpha),
  LineCommand c => LineCommand(points: c.points, stroke: c.stroke, lineWidth: c.lineWidth, alpha: alpha),
  SlashCommand c => SlashCommand(x: c.x, y: c.y, r: c.r, stroke: c.stroke, lineWidth: c.lineWidth, alpha: alpha),
  DotCommand c => DotCommand(x: c.x, y: c.y, r: c.r, fill: c.fill, alpha: alpha),
  BadgeCommand c => BadgeCommand(x: c.x, y: c.y, text: c.text, fill: c.fill, fontSize: c.fontSize, alpha: alpha),
  RectCommand c => RectCommand(x: c.x, y: c.y, w: c.w, h: c.h, fill: c.fill, stroke: c.stroke, radius: c.radius, alpha: alpha),
};

/// Uniformly scale commands (with cell center as origin, scale all coordinates and dimensions).
List<DrawCommand> _scaleCommands(List<DrawCommand> commands, LayoutCell cell, double scale) {
  final cx = cell.x + cell.w / 2;
  final cy = cell.y + cell.h / 2;
  return commands.map((cmd) {
    return switch (cmd) {
      CircleCommand c => CircleCommand(
        x: cx + (c.x - cx) * scale,
        y: cy + (c.y - cy) * scale,
        r: c.r * scale,
        fill: c.fill,
        stroke: c.stroke,
        lineWidth: c.lineWidth,
        alpha: c.alpha,
      ),
      DotCommand c => DotCommand(
        x: cx + (c.x - cx) * scale,
        y: cy + (c.y - cy) * scale,
        r: c.r * scale,
        fill: c.fill,
        alpha: c.alpha,
      ),
      SlashCommand c => SlashCommand(
        x: cx + (c.x - cx) * scale,
        y: cy + (c.y - cy) * scale,
        r: c.r * scale,
        stroke: c.stroke,
        lineWidth: c.lineWidth,
        alpha: c.alpha,
      ),
      BadgeCommand c => BadgeCommand(
        x: cx + (c.x - cx) * scale,
        y: cy + (c.y - cy) * scale,
        text: c.text,
        fill: c.fill,
        fontSize: (c.fontSize ?? 12) * scale,
        alpha: c.alpha,
      ),
      RectCommand c => RectCommand(
        x: cx + (c.x - cx) * scale,
        y: cy + (c.y - cy) * scale,
        w: c.w * scale,
        h: c.h * scale,
        fill: c.fill,
        stroke: c.stroke,
        radius: c.radius,
        alpha: c.alpha,
      ),
      LineCommand c => LineCommand(
        points: [
          for (var i = 0; i < c.points.length; i++)
            i.isEven
                ? cx + (c.points[i] - cx) * scale
                : cy + (c.points[i] - cy) * scale,
        ],
        stroke: c.stroke,
        lineWidth: c.lineWidth,
        alpha: c.alpha,
      ),
    };
  }).toList();
}

/// Batch translate a list of commands (returns new list, does not modify input). Reused by animation interpolation and multi-road merge layout
/// (e.g. `roads/band_merge.dart` combining sub-roads into the same canvas).
///
/// ```dart
/// final shifted = translateCommands(cell.commands, 0, 120);
/// ```
List<DrawCommand> translateCommands(List<DrawCommand> commands, double dx, double dy) {
  if (dx == 0 && dy == 0) return commands;
  return commands.map((cmd) => translateCommand(cmd, dx, dy)).toList();
}

/// Translate a single command (returns new object).
DrawCommand translateCommand(DrawCommand cmd, double dx, double dy) => switch (cmd) {
  CircleCommand c => CircleCommand(
    x: c.x + dx,
    y: c.y + dy,
    r: c.r,
    fill: c.fill,
    stroke: c.stroke,
    lineWidth: c.lineWidth,
    alpha: c.alpha,
  ),
  DotCommand c => DotCommand(x: c.x + dx, y: c.y + dy, r: c.r, fill: c.fill, alpha: c.alpha),
  SlashCommand c => SlashCommand(
    x: c.x + dx,
    y: c.y + dy,
    r: c.r,
    stroke: c.stroke,
    lineWidth: c.lineWidth,
    alpha: c.alpha,
  ),
  BadgeCommand c => BadgeCommand(
    x: c.x + dx,
    y: c.y + dy,
    text: c.text,
    fill: c.fill,
    fontSize: c.fontSize,
    alpha: c.alpha,
  ),
  RectCommand c => RectCommand(
    x: c.x + dx,
    y: c.y + dy,
    w: c.w,
    h: c.h,
    fill: c.fill,
    stroke: c.stroke,
    radius: c.radius,
    alpha: c.alpha,
  ),
  LineCommand c => LineCommand(
    points: [for (var i = 0; i < c.points.length; i++) i.isEven ? c.points[i] + dx : c.points[i] + dy],
    stroke: c.stroke,
    lineWidth: c.lineWidth,
    alpha: c.alpha,
  ),
};
