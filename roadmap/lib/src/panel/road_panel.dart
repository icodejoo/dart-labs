/// 单路展示面板：`CustomPaint` + 手势 + 视口 + 逐格插入/移动/退出动画。
///
/// 对应 TS 版本 `panel/road-panel.ts` + `example/main.ts` 里 `renderRoad()` 手写的
/// diff 动画链路（TS 的动画不在渲染器里，是 demo 层用 `diffLayout`/`sampleEnter`/
/// `sampleMove`/`sampleExit` + `frameDriver` 手工采样出来的）。Flutter 版本把这条
/// 链路收进 `RoadPanel` 内部：用一个 `Ticker` 驱动视口物理状态机（拖拽惯性/回弹/
/// 自动滚动）和逐格动画采样，`CustomPaint`（[RoadPainter]）只管把当前帧的指令画
/// 出来，不关心指令是直达终态还是插值中间态。
///
/// 移植自 `src/panel/road-panel.ts` 与 `example/main.ts` 的 `renderRoad`。
library;

import 'package:flutter/material.dart' hide Theme;
import 'package:flutter/scheduler.dart';

import '../core/animation.dart' hide Easing;
import '../core/animation.dart' as anim show Easing;
import '../core/types.dart';
import '../core/viewport.dart';
import '../render/road_painter.dart';

/// 新数据到达后视口的跟随策略。
enum FollowTail {
  /// 不跟随（如切换游戏类型全量刷新时，用户可能正看着历史，不该被拽走）。
  none,

  /// 立即跳到尾部。
  hard,

  /// 缓动滚动到尾部。
  ease,
}

/// 本次数据更新的类型：对应 TS 版本 `store.ts` 的 `UpdateKind`，决定要不要播放
/// 插入动画——只有 [append] 会触发 enter/move/exit 采样，其余直达终态。
enum RoadUpdateKind { setResults, append, patch }

/// 单路展示面板。
///
/// 每次外部数据变化时重建这个 widget（换一份 [cells]/[decorations]），面板内部
/// 通过 `didUpdateWidget` 对比新旧布局，决定是直达终态还是播放插入/移动/退出动画。
class RoadPanel extends StatefulWidget {
  /// 本路当前布局的格子列表。
  final List<LayoutCell> cells;

  /// 不属于任何格子的装饰指令（如 streakHighlight 高亮矩形）。
  final List<DrawCommand> decorations;

  /// 内容总宽（逻辑像素）。
  final double contentWidth;

  /// 内容总高（逻辑像素）。
  final double contentHeight;

  /// 本路专属背景网格规格，null 用面板默认细线网格。
  final GridSpec? grid;

  /// 当前主题（提供画布背景色、默认网格样式）。
  final Theme theme;

  /// 面板宽度（逻辑像素）。
  final double panelWidth;

  /// 面板高度（逻辑像素）。
  final double panelHeight;

  /// 新格子到来后的视口跟随策略。
  final FollowTail followTail;

  /// 本次更新的类型，决定要不要播放插入动画。
  final RoadUpdateKind eventType;

  /// 格子动画时长（ms）；`prefers-reduced-motion`/无障碍场景可传 0 直达终态。
  final int animDurationMs;

  /// 双击面板时的回调（默认行为是回到尾部，调用方也可覆盖）。
  final VoidCallback? onDoubleTap;

  /// 单个格子被点击时的回调（联动高亮/tooltip 用）。
  final void Function(LayoutCell cell)? onCellTap;

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

  final List<_VelocitySample> _velocitySamples = [];

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
    _prevLayout = _currentLayout();
  }

  @override
  void didUpdateWidget(covariant RoadPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = _currentLayout();
    final animate = widget.eventType == RoadUpdateKind.append && widget.animDurationMs > 0;

    _transitions = animate ? diffLayout(_prevLayout, next) : const [];
    _animProgress = _transitions.isEmpty ? 1 : 0;
    _animStartMs = _lastTick.inMilliseconds;
    _prevLayout = next;

    final bounds = _bounds();
    switch (widget.followTail) {
      case FollowTail.hard:
        _viewport = _viewport.copyWith(offsetX: bounds.minX, phase: ViewportPhase.idle);
      case FollowTail.ease:
        _viewport = startAutoScroll(_viewport, bounds.minX);
      case FollowTail.none:
        break;
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
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

    if (_viewport.phase != ViewportPhase.idle) {
      _viewport = stepViewport(_viewport, dt, _bounds(), defaultViewportConfig);
      changed = true;
    }

    if (_animProgress < 1) {
      final t = ((elapsed.inMilliseconds - _animStartMs) / widget.animDurationMs).clamp(0.0, 1.0);
      _animProgress = anim.Easing.easeOutCubic(t);
      changed = true;
      if (t >= 1) _transitions = const [];
    }

    if (changed) setState(() {});
  }

  /// 按当前动画进度采样出这一帧应绘制的指令：进入格子播放 scaleIn，移动格子播放
  /// tween，其余格子直达终态；退出格子（窗口模式挤出）额外叠加淡出采样。
  List<DrawCommand> _sampleCommands() {
    if (_transitions.isEmpty) {
      return [...widget.decorations, for (final cell in widget.cells) ...cell.commands];
    }

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

    final cellCmds = widget.cells.expand((cell) {
      if (enters.containsKey(cell.key)) {
        return sampleEnter(EnterAnimation.scaleIn.animName, cell, _animProgress);
      }
      final move = moves[cell.key];
      if (move != null) {
        return sampleMove(MoveAnimation.tween.animName, move.from, move.to, _animProgress);
      }
      return cell.commands;
    });

    final exitCmds = _animProgress < 1
        ? exitCells.expand((cell) => sampleExit(ExitAnimation.fadeOut.animName, cell, _animProgress))
        : const <DrawCommand>[];

    return [...widget.decorations, ...cellCmds, ...exitCmds];
  }

  Offset? _lastFocalPoint;
  double _lastGestureScale = 1;

  // `GestureDetector` 不允许同时挂 pan 与 scale 识别器（scale 是 pan 的超集，
  // 官方断言会直接报错）——单指拖拽和双指缩放统一走 onScale* 三个回调，靠
  // ScaleUpdateDetails.pointerCount 区分：1 指按拖拽处理（走 dragBy 的阻尼语义），
  // ≥2 指才走缩放（走 zoomAt 的焦点不变量）。

  void _onScaleStart(ScaleStartDetails details) {
    _lastFocalPoint = details.localFocalPoint;
    _lastGestureScale = 1;
    _velocitySamples.clear();
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    _velocitySamples.add(_VelocitySample(details.focalPoint, DateTime.now()));
    if (_velocitySamples.length > 5) _velocitySamples.removeAt(0);

    if (details.pointerCount <= 1) {
      final last = _lastFocalPoint ?? details.localFocalPoint;
      final dx = details.localFocalPoint.dx - last.dx;
      final dy = details.localFocalPoint.dy - last.dy;
      setState(() {
        _viewport = dragBy(_viewport, dx, dy, _bounds(), defaultViewportConfig);
      });
    } else {
      final scaleDelta = details.scale / _lastGestureScale;
      _lastGestureScale = details.scale;
      if (scaleDelta != 1.0) {
        final nextScale = _viewport.scale * scaleDelta;
        setState(() {
          _viewport = zoomAt(
            _viewport,
            details.localFocalPoint.dx,
            details.localFocalPoint.dy,
            nextScale,
            computeBounds(widget.panelWidth, widget.panelHeight, widget.contentWidth, widget.contentHeight, nextScale),
          );
        });
      }
    }
    _lastFocalPoint = details.localFocalPoint;
  }

  void _onScaleEnd(ScaleEndDetails details) {
    double vx = 0, vy = 0;
    if (_velocitySamples.length >= 2) {
      final first = _velocitySamples.first;
      final last = _velocitySamples.last;
      final dtMs = last.time.difference(first.time).inMicroseconds / 1000.0;
      if (dtMs > 0) {
        vx = (last.position.dx - first.position.dx) / dtMs;
        vy = (last.position.dy - first.position.dy) / dtMs;
      }
    }
    setState(() {
      _viewport = endDrag(_viewport, vx, vy, _bounds(), defaultViewportConfig);
    });
  }

  void _handleDoubleTap() {
    if (widget.onDoubleTap != null) {
      widget.onDoubleTap!();
      return;
    }
    setState(() => _viewport = startAutoScroll(_viewport, _bounds().minX));
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onScaleStart: _onScaleStart,
      onScaleUpdate: _onScaleUpdate,
      onScaleEnd: _onScaleEnd,
      onDoubleTap: _handleDoubleTap,
      child: SizedBox(
        width: widget.panelWidth,
        height: widget.panelHeight,
        child: ClipRect(
          child: CustomPaint(
            painter: RoadPainter(
              commands: _sampleCommands(),
              contentWidth: widget.contentWidth,
              viewportOffset: Offset(_viewport.offsetX, _viewport.offsetY),
              viewportScale: _viewport.scale,
              grid: widget.grid ?? GridSpec(cellSize: 18, stroke: widget.theme.grid.stroke),
              background: widget.theme.canvas.background,
            ),
          ),
        ),
      ),
    );
  }
}

class _VelocitySample {
  final Offset position;
  final DateTime time;
  const _VelocitySample(this.position, this.time);
}
