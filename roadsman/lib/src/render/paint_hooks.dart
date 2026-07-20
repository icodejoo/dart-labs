/// 绘制回调类型：让调用方在内置绘制前/后插入自定义 Canvas 绘制，控制图层顺序
/// （before = 画在内置内容之下，after = 画在内置内容之上），且内置绘制永远照常
/// 执行——这些回调是纯增量挂钩，不会替换/跳过任何内置绘制。
///
/// 两组挂钩：
/// - 网格瓷砖（[GridCellPaintCallback]）：只在 `GridStyle.tile` 下、每个瓷砖单元
///   格触发，用于自定义底部背景元素（棋盘配色、贴图等）。
/// - 绘制指令（[CommandPaintCallback]）：[RoadPainter]/[RoadFramePainter] 绘制
///   的每一条 [DrawCommand]（圆/线/斜线/点/文字标记/矩形，含叠加层）触发一次，
///   携带原始指令对象，可 switch 拿到该指令的全部坐标/尺寸/颜色字段。
///
/// 未设置回调（默认）时零开销——网格/内容层的 Picture 缓存快速路径完全不受
/// 影响；一旦设置了对应回调，该层当帧会退回逐条直绘（缓存录制的是纯栅格数据，
/// 没法在重放时触发 Dart 回调），仅牺牲拖拽/惯性帧的部分性能换取正确性。
library;

import 'dart:ui';

import '../core/types.dart';

/// 网格瓷砖绘制信息：内置填充执行前后都会带上这份信息回调一次。
///
/// [canvas] 已经处于当前 viewport 变换之下（内容坐标系），直接用 [rect] 的坐标
/// 作画即可，无需自己再处理平移/缩放。
class GridCellPaintInfo {
  /// 当前画布，已应用 viewport 变换（内容坐标系）。
  final Canvas canvas;

  /// 瓷砖的位置与大小（内容坐标系，已按 [GridSpec.tileInsetRatio] 收缩）。
  final Rect rect;

  /// 内置填充色（[GridSpec.tileFill]，缺省时的兜底色）。
  final Color color;

  /// 瓷砖在本次绘制循环里的行号（从 0 起，仅为遍历顺序，不是逻辑网格行号——
  /// 网格随 viewport 相位滚动，同一行号在不同帧可能对应不同的实际内容位置；
  /// 常见用法是按奇偶行/列做棋盘配色）。
  final int row;

  /// 瓷砖在本次绘制循环里的列号（含义同 [row]）。
  final int col;

  const GridCellPaintInfo({
    required this.canvas,
    required this.rect,
    required this.color,
    required this.row,
    required this.col,
  });
}

/// 网格瓷砖绘制前/后回调；参见 [GridCellPaintInfo]。
typedef GridCellPaintCallback = void Function(GridCellPaintInfo info);

/// 单条绘制指令的信息：内置绘制执行前后都会带上这份信息回调一次。
///
/// [canvas] 已经处于当前 viewport 变换之下（内容坐标系）。[command] 是原始
/// [DrawCommand]，switch 其运行时类型（[CircleCommand]/[LineCommand]/
/// [SlashCommand]/[DotCommand]/[BadgeCommand]/[RectCommand]）可取到该指令的
/// 全部坐标/尺寸/颜色字段。
class CommandPaintInfo {
  /// 当前画布，已应用 viewport 变换（内容坐标系）。
  final Canvas canvas;

  /// 即将/刚刚被内置绘制的指令。
  final DrawCommand command;

  const CommandPaintInfo({required this.canvas, required this.command});
}

/// 绘制指令前/后回调；参见 [CommandPaintInfo]。
typedef CommandPaintCallback = void Function(CommandPaintInfo info);
