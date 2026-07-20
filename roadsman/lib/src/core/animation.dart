/// 动画系统（纯函数）。
///
/// 提供 [diffLayout]（布局 diff）、缓动函数、插入/移动/退出动画采样、
/// [applyWindow]（窗口模式截取）等纯函数。渲染层保持无状态；动画层位于
/// compute 输出与渲染层之间。移植自 `src/core/animation.ts`。
library;

import 'dart:math' as math;

import 'types.dart';

/// 缓动函数类型。
typedef EasingFn = double Function(double t);

/// 缓动函数集合。任何 `double Function(double)` 均可自行传入。
///
/// ```dart
/// final v = Easing.easeOutCubic(0.5); // 约 0.875
/// ```
abstract final class Easing {
  /// 线性。
  static double linear(double t) => t;

  /// 缓出三次（轻柔落地）。
  static double easeOutCubic(double t) => 1 - math.pow(1 - t, 3).toDouble();

  /// 缓出回弹（带轻微弹性）。
  static double easeOutBack(double t) {
    const c = 1.70158;
    return 1 + (c + 1) * math.pow(t - 1, 3) + c * math.pow(t - 1, 2);
  }

  /// 弹簧（近似，过冲后回弹）。
  static double spring(double t) {
    const omega = 12.0;
    const zeta = 0.5;
    return 1 - math.exp(-zeta * omega * t) * math.cos(omega * math.sqrt(1 - zeta * zeta) * t);
  }
}

/// 插入动画预置名称（格子首次出现时）。
enum EnterAnimation {
  /// 无动画，直接呈现终态。
  none,

  /// 淡入（alpha 0→1）。
  fadeIn,

  /// 缩放插入（半径 0→r，配 [Easing.easeOutBack] 有回弹）。
  scaleIn,

  /// 下落插入（从上方落入 + 淡入）。
  dropIn,
}

/// 移动动画预置名称（格子位置变化，窗口左移时）。
enum MoveAnimation {
  /// 无动画。
  none,

  /// 线性位置 tween。
  tween,
}

/// 退出动画预置名称（窗口模式格子被挤出时）。
enum ExitAnimation {
  /// 无动画（直接消失）。
  none,

  /// 淡出 + 左移半格。
  fadeOut,
}

/// 路图显示模式：follow 视口缓动跟随（默认）/ window 固定 N 列，超出则挤出。
enum RoadDisplayMode { follow, window }

/// 单个格子的过渡描述（sealed class）。
sealed class Transition {
  const Transition();
}

/// 格子进入（新增）。
final class EnterTransition extends Transition {
  final LayoutCell cell;
  const EnterTransition(this.cell);
}

/// 格子移动（同 key，位置变化）。
final class MoveTransition extends Transition {
  final LayoutCell from;
  final LayoutCell to;
  const MoveTransition(this.from, this.to);
}

/// 格子退出（被挤出）。
final class ExitTransition extends Transition {
  final LayoutCell cell;
  const ExitTransition(this.cell);
}

/// 对比两个布局，输出过渡列表（仅基于 key 比较，不看内容）。
/// [prev] 为 null（首帧/全量刷新）时返回空列表（直接呈现终态）。
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

/// 插入动画采样函数类型。
typedef EnterSampleFn = List<DrawCommand> Function(LayoutCell cell, double progress);

/// 移动动画采样函数类型。
typedef MoveSampleFn = List<DrawCommand> Function(LayoutCell from, LayoutCell to, double progress);

/// 退出动画采样函数类型。
typedef ExitSampleFn = List<DrawCommand> Function(LayoutCell cell, double progress);

final _enterRegistry = <String, EnterSampleFn>{};
final _moveRegistry = <String, MoveSampleFn>{};
final _exitRegistry = <String, ExitSampleFn>{};

/// 注册自定义插入动画，可在 [sampleEnter] 里按 [name] 覆盖内置行为。
void registerEnterAnimation(String name, EnterSampleFn fn) => _enterRegistry[name] = fn;

/// 注册自定义移动动画。
void registerMoveAnimation(String name, MoveSampleFn fn) => _moveRegistry[name] = fn;

/// 注册自定义退出动画。
void registerExitAnimation(String name, ExitSampleFn fn) => _exitRegistry[name] = fn;

String _enterAnimName(EnterAnimation a) => switch (a) {
  EnterAnimation.none => 'none',
  EnterAnimation.fadeIn => 'fadeIn',
  EnterAnimation.scaleIn => 'scaleIn',
  EnterAnimation.dropIn => 'dropIn',
};

/// 采样插入动画，返回该 [progress] 下格子的绘制指令。
///
/// [name] 通常是 [EnterAnimation] 对应的名字（见 `_enterAnimName`），也可以是
/// 通过 [registerEnterAnimation] 注册的自定义名。[cellSize] 供 dropIn 计算起始
/// Y 偏移，默认 36。
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

/// 采样移动动画，返回该 [progress] 下格子的绘制指令。
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

/// 采样退出动画，返回该 [progress] 下格子的绘制指令（0 完全可见，1 完全消失）。
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

/// 把 [EnterAnimation]/[MoveAnimation]/[ExitAnimation] 枚举值转成 [sampleEnter] 等
/// 函数期望的字符串名，供不想手写字符串字面量的调用方使用。
extension EnterAnimationName on EnterAnimation {
  String get animName => _enterAnimName(this);
}

extension MoveAnimationName on MoveAnimation {
  String get animName => this == MoveAnimation.none ? 'none' : 'tween';
}

extension ExitAnimationName on ExitAnimation {
  String get animName => this == ExitAnimation.none ? 'none' : 'fadeOut';
}

/// 窗口模式：截取最近 [windowCols] 列，区间外的格子丢弃，区间内的格子整体左移。
/// key 不变，[diffLayout] 自然得出 enter/move/exit。
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

/// 等比缩放指令（以格子中心为原点，缩放所有坐标和尺寸）。
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

/// 对指令列表批量平移（返回新列表，不修改入参）。供动画插值与多路合并布局
/// （如 `roads/band_merge.dart` 把子路拼进同一画布）复用。
///
/// ```dart
/// final shifted = translateCommands(cell.commands, 0, 120);
/// ```
List<DrawCommand> translateCommands(List<DrawCommand> commands, double dx, double dy) {
  if (dx == 0 && dy == 0) return commands;
  return commands.map((cmd) => translateCommand(cmd, dx, dy)).toList();
}

/// 平移单条指令（返回新对象）。
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
