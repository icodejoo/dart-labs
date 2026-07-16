/// `CustomPainter` 渲染层：把核心层产出的 [DrawCommand] 列表画到 Flutter Canvas 上。
///
/// 对应 TS 版本的 `renderer-canvas/canvas-renderer.ts`：每帧对指令列表全量重绘，
/// 不做增量 diff（diff 发生在更上层的 `panel/road_panel.dart`，只决定当前帧要画
/// 哪些插值后的指令，画布本身永远是"整份重画"）。这个模型天然贴合 Flutter 的
/// `CustomPainter`：`shouldRepaint` 对应 TS 里"要不要在下一帧调 `render()`"。
///
/// 两个 painter 入口共享同一套绘制实现（[_paintRoad]）：
/// - [RoadPainter]：无状态快照式，字段即当帧数据，适合外部直接使用；
/// - [RoadFramePainter] + [RoadFrameState]：面板内部的"活帧"路径——painter 从
///   状态对象实时读取，`repaint` Listenable 驱动重绘，动画/拖拽帧零 widget 重建。
///
/// 移植自 `src/renderer-canvas/canvas-renderer.ts`。
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../core/types.dart';

/// 把核心层的 ARGB 整数颜色转成 Flutter [Color]。
Color colorFromArgb(int argb) => Color(argb);

/// 内容层的 [ui.Picture] 缓存：同一份指令列表只录制一次（含 TextPainter 布局、
/// Paint 构造这些开销最大的部分），后续帧无论视口怎么平移/缩放都只是
/// `canvas.drawPicture` 重放——纯视口帧（拖拽/惯性/自动滚动）不再逐条指令
/// 走 Dart 绘制代码。
///
/// 选 Picture 而不是栅格化成 [ui.Image]：Picture 是矢量重放，缩放不糊、不用
/// 关心 DPR、录制同步完成；Image 栅格化是异步的且要按最大缩放倍率×DPR 备图，
/// 复杂度不成比例。
///
/// 由面板层（`RoadPanel`）持有并跨 painter 实例复用（painter 每次 build 都会
/// 重建，缓存放在 painter 里会随之丢失）；面板销毁时调用 [dispose]。
/// 一个面板一份，勿跨面板共享（跨面板共享会让旧 Picture 在另一面板的在途帧里
/// 被 dispose）。
class CommandLayerCache {
  /// 已录制的内容层。
  ui.Picture? _picture;

  /// 录制时对应的指令列表（按引用判断是否命中）。
  List<DrawCommand>? _forCommands;

  /// 命中缓存则直接返回，否则用 [record] 录一份新的并替换旧缓存。
  ui.Picture resolve(List<DrawCommand> commands, void Function(Canvas canvas) record) {
    if (identical(_forCommands, commands) && _picture != null) return _picture!;
    final recorder = ui.PictureRecorder();
    record(Canvas(recorder));
    _picture?.dispose();
    _picture = recorder.endRecording();
    _forCommands = commands;
    return _picture!;
  }

  /// 释放底层 Picture 资源。
  void dispose() {
    _picture?.dispose();
    _picture = null;
    _forCommands = null;
  }
}

/// 背景网格的 [ui.Picture] 缓存。网格在内容坐标系里是静止的（相位滚动只是
/// 整体平移），所以按 (grid 实例, scale, 面板尺寸) 录制一张覆盖
/// `[-span, w+span] × [-span, h+span]` 的网格图，之后每帧只需
/// `translate(phase - span) + drawPicture`——拖拽/惯性期间不再逐格
/// drawRRect/drawLine（tile 模式一帧约几百次调用，是拖拽帧的主要 Dart 开销）。
///
/// 缩放手势期间 scale 逐事件变化会逐次重录，成本与原直绘持平；平移类帧
/// （最常见）全部命中。同 [CommandLayerCache]，一个面板一份，勿跨面板共享。
class GridLayerCache {
  ui.Picture? _picture;
  GridSpec? _grid;
  double _scale = 0;
  double _w = 0;
  double _h = 0;

  /// 命中（grid 引用、scale、尺寸均一致）则复用，否则重录。
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

  /// 释放底层 Picture 资源。
  void dispose() {
    _picture?.dispose();
    _picture = null;
    _grid = null;
  }
}

/// 单个路面板的 `CustomPainter`：消费 [commands]，按 [viewport] 做变换绘制，
/// 可选绘制背景网格 [grid]。字段是当帧快照，数据变化时重建 painter 实例。
class RoadPainter extends CustomPainter {
  /// 待绘制的指令列表（已按当前帧插值完毕，全量重绘）。
  final List<DrawCommand> commands;

  /// 内容总宽（逻辑像素），用于可视裁剪。
  final double contentWidth;

  /// 当前视口偏移/缩放。
  final Offset viewportOffset;

  /// 当前视口缩放倍率。
  final double viewportScale;

  /// 背景网格配置，null 表示不绘制网格。
  final GridSpec? grid;

  /// 画布背景色。
  final int background;

  /// 内容层 Picture 缓存（可选，由面板层持有跨帧复用）。传入后同一份 [commands]
  /// 只录制一次，纯视口帧直接重放；不传则退回逐条指令直绘（带可视裁剪）。
  final CommandLayerCache? layerCache;

  /// 背景网格 Picture 缓存（可选，由面板层持有跨帧复用）。
  final GridLayerCache? gridCache;

  /// 叠加层指令（呼吸光圈、动画中的格子等每帧变化的少量指令），画在内容层
  /// 之上、同一视口变换内。与 [commands] 分离是为了让底层的 Picture 缓存不被
  /// 逐帧动画击穿。
  final List<DrawCommand> overlayCommands;

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
  );

  @override
  bool shouldRepaint(covariant RoadPainter oldDelegate) =>
      !identical(oldDelegate.commands, commands) ||
      !identical(oldDelegate.overlayCommands, overlayCommands) ||
      oldDelegate.contentWidth != contentWidth ||
      oldDelegate.viewportOffset != viewportOffset ||
      oldDelegate.viewportScale != viewportScale ||
      oldDelegate.grid != grid ||
      oldDelegate.background != background;
}

/// "活帧"状态：面板每帧要变的数据（指令、视口、缓存选择）都写进这里，
/// [markFrame] 触发 [RoadFramePainter] 经 `repaint` Listenable 直达
/// `markNeedsPaint`——动画/拖拽帧完全绕开 setState/build/element diff。
class RoadFrameState extends ChangeNotifier {
  /// 内容层指令（静止或动画底图，配合 [layerCache] 走 Picture 重放）。
  List<DrawCommand> commands = const [];

  /// 叠加层指令（呼吸光圈、动画中的格子），每帧直绘。
  List<DrawCommand> overlayCommands = const [];

  /// 当前视口偏移。
  Offset viewportOffset = Offset.zero;

  /// 当前视口缩放。
  double viewportScale = 1;

  /// 本帧内容层适用的 Picture 缓存（静止帧/动画底图各有一份），null 走直绘。
  CommandLayerCache? layerCache;

  /// 通知 painter 重绘当前帧。
  void markFrame() => notifyListeners();
}

/// 从 [RoadFrameState] 实时取帧数据的 `CustomPainter`。
///
/// 构造时把 frame 作为 `repaint` Listenable 传给基类：帧状态变化只触发
/// `markNeedsPaint`，不重建任何 widget。painter 自己的字段只剩数据变化频率低的
/// 静态配置（尺寸/网格/背景），它们变化时由 build 重建 painter，走 shouldRepaint。
class RoadFramePainter extends CustomPainter {
  /// 帧状态（同时作为 repaint Listenable）。
  final RoadFrameState frame;

  /// 内容总宽（逻辑像素），用于直绘路径的可视裁剪。
  final double contentWidth;

  /// 背景网格配置，null 不绘制。
  final GridSpec? grid;

  /// 画布背景色。
  final int background;

  /// 背景网格 Picture 缓存。
  final GridLayerCache? gridCache;

  RoadFramePainter({
    required this.frame,
    required this.contentWidth,
    this.grid,
    required this.background,
    this.gridCache,
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
  );

  @override
  bool shouldRepaint(covariant RoadFramePainter oldDelegate) =>
      !identical(oldDelegate.frame, frame) ||
      oldDelegate.contentWidth != contentWidth ||
      oldDelegate.grid != grid ||
      oldDelegate.background != background;
}

// ─── 共享绘制实现（RoadPainter 与 RoadFramePainter 共用） ───────────────────

/// 直绘路径复用的填充/描边 Paint。单 UI 线程且 `Canvas.draw*` 在调用时即拷贝
/// Paint 状态，调用返回后立刻改字段复用是安全的——避免动画帧每条指令 1-2 次
/// Paint 分配（含 native finalizer 注册）。每次使用必须重置用到的全部字段。
final Paint _fillPaint = Paint();
final Paint _strokePaint = Paint()..style = PaintingStyle.stroke;

/// 完整画一帧：背景 → 网格 → 内容层（Picture 缓存或直绘+裁剪）→ 叠加层。
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
}) {
  final w = size.width;
  final h = size.height;

  canvas.drawRect(Rect.fromLTWH(0, 0, w, h), _fillPaint..color = colorFromArgb(background));

  // 1. 背景网格：不参与 scroll 变换，始终铺满面板。
  if (grid != null) {
    _paintGrid(canvas, w, h, grid, viewportOffset, viewportScale, gridCache);
  }

  // 2. 内容层：应用 viewport 变换。
  canvas.save();
  canvas.translate(viewportOffset.dx, viewportOffset.dy);
  canvas.scale(viewportScale);

  if (layerCache != null) {
    // 缓存路径：整层录成 Picture 重放。录制时不做可视裁剪（Picture 与视口
    // 无关，才能跨平移/缩放复用），裁剪交给画布 clip——重放开销远低于逐条
    // 指令的 Paint/TextPainter 构造。
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
      _paintCommand(canvas, cmd);
    }
  }

  // 3. 叠加层（呼吸光圈、动画中的格子），数量极少，直绘。
  for (final cmd in overlayCommands) {
    _paintCommand(canvas, cmd);
  }

  canvas.restore();
}

/// 渲染背景网格（相位与内容坐标同步对齐，随 viewport 平移/缩放连续绘制，铺满
/// 整个可视区域）。与内容层共用同一份 viewport 变换语义，不受内容边界限制——
/// 避免"内容自绘网格"与"渲染层背景网格"两套独立系统各自计算坐标导致的错位。
void _paintGrid(
  Canvas canvas,
  double w,
  double h,
  GridSpec grid,
  Offset viewportOffset,
  double viewportScale,
  GridLayerCache? gridCache,
) {
  final cellSize = grid.cellSize;
  final stroke = grid.stroke ?? 0x14FFFFFF;
  final colSpan = grid.colSpan;
  final rowSpan = grid.rowSpan;
  final tileFill = grid.tileFill ?? 0x14FFFFFF;
  final tileRadiusRatio = grid.tileRadiusRatio;
  final tileInsetRatio = grid.tileInsetRatio;

  final scale = viewportScale;
  final spanW = cellSize * colSpan * scale;
  final spanH = cellSize * rowSpan * scale;

  // 相位：X/Y 均按当前 offset 动态计算（同步内容平移）。
  final phaseX = ((viewportOffset.dx % spanW) + spanW) % spanW;
  final phaseY = ((viewportOffset.dy % spanH) + spanH) % spanH;

  // 缓存路径：网格图按 (grid, scale, 尺寸) 录制一次（原点对齐、覆盖四周各多
  // 一个周期），每帧只平移到当前相位再重放——平移类帧零逐格绘制。
  if (gridCache != null) {
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
    final paint = Paint()..color = colorFromArgb(tileFill);
    // 从 phase-span 起步，保证左/上边缘的半截瓷砖也能画出来，不留空隙。
    for (var y = phaseY - spanH; y <= h + spanH; y += spanH) {
      for (var x = phaseX - spanW; x <= w + spanW; x += spanW) {
        final rw = spanW - 2 * insetX;
        final rh = spanH - 2 * insetY;
        if (rw <= 0 || rh <= 0) continue;
        canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTWH(x + insetX, y + insetY, rw, rh), Radius.circular(radius)),
          paint,
        );
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

/// 把网格录制到原点对齐的画布上，覆盖 `[0, w+2·span] × [0, h+2·span]`——
/// 比可视区四周各多一个周期，平移到任意相位（`phase - span ∈ [-span, 0)`）
/// 后都能铺满面板。绘制参数与 [_paintGrid] 的直绘路径逐项一致。
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

/// 可视范围裁剪（剔除明显在面板外的指令，提升性能）。
bool _isOutside(DrawCommand cmd, double visL, double visR) => switch (cmd) {
  CircleCommand c => c.x < visL || c.x > visR,
  SlashCommand c => c.x < visL || c.x > visR,
  DotCommand c => c.x < visL || c.x > visR,
  BadgeCommand c => c.x < visL || c.x > visR,
  LineCommand c => (c.points.isNotEmpty ? c.points[0] : 0) < visL || (c.points.isNotEmpty ? c.points[0] : 0) > visR,
  RectCommand c => c.x + c.w < visL || c.x > visR,
};

/// 回放单条绘制指令，支持 [DrawCommand.alpha] 透明度（动画插值用）。
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

/// 颜色叠加动画透明度。
Color _withAlpha(int argb, double alpha) => colorFromArgb(argb).withValues(alpha: alpha);
