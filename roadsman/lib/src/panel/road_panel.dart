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
import 'ux/pulse.dart';

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

  /// 新格子插入后是否播放呼吸光圈（对应 TS 版本 `ux/pulse.ts` 的效果，这里直接
  /// 内建在面板里——呼吸光圈需要知道"哪个格子、什么时候新增"，这个信息只有
  /// `RoadPanel` 自己在 diff 时才拿得到，外部控制器只能传一个开关）。
  final bool pulseEnabled;

  /// 网格瓷砖内置填充**之前**触发，方便自定义绘制底部背景元素（仅
  /// `grid.style == GridStyle.tile` 时生效）；参见 [RoadPainter.onBeforePaintGridCell]。
  final GridCellPaintCallback? onBeforePaintGridCell;

  /// 网格瓷砖内置填充**之后**触发；参见 [RoadPainter.onAfterPaintGridCell]。
  final GridCellPaintCallback? onAfterPaintGridCell;

  /// 每条绘制指令（圆/线/斜线/点/文字标记/矩形）内置绘制**之前**触发；
  /// 参见 [RoadPainter.onBeforePaintCommand]。
  final CommandPaintCallback? onBeforePaintCommand;

  /// 每条绘制指令内置绘制**之后**触发；参见 [RoadPainter.onAfterPaintCommand]。
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

  /// 呼吸光圈：独立于插入动画（280ms）另开一条更长的采样时间线（2000ms，对齐
  /// TS 版本 `ux/pulse.ts` 的默认时长），只在 [RoadPanel.pulseEnabled] 时对最新
  /// 插入的格子生效。
  LayoutCell? _pulseCell;
  int _pulseStartMs = 0;

  /// 呼吸光圈的时长/颜色来源：与 `ux/pulse.dart` 的 [PulseOptions] 默认值同源，
  /// 避免面板内再复制一份字面量。
  static const _pulseOptions = PulseOptions();

  /// 插入动画期间的过渡索引（在 didUpdateWidget 里算一次，整个 280ms 复用，
  /// 不在每帧重建 map）。
  Map<String, LayoutCell> _enters = const {};
  Map<String, MoveTransition> _moves = const {};
  List<LayoutCell> _exitCells = const [];

  /// 静止帧（无过渡）的指令列表缓存：数据没变时复用同一个 List 实例，
  /// 让内容层 Picture 缓存的 identical 判断能真正生效。
  List<DrawCommand>? _staticCommands;

  /// 动画期间的"底图"指令：不在动的格子 + decorations，整个动画期恒定，
  /// 走独立的 Picture 缓存；正在 enter/move/exit 的格子每帧采样后走叠加层。
  /// 动画帧的直绘量从 O(全部指令) 降到 O(动的格子)。
  List<DrawCommand>? _animBaseCommands;

  /// 兜底网格规格缓存（widget.grid 为 null 时用），避免每次 build 新建对象
  /// 导致 shouldRepaint 恒为 true。
  GridSpec? _fallbackGrid;

  /// 内容层 Picture 缓存：静止帧的指令列表只录制一次，拖拽/惯性/自动滚动等
  /// 纯视口帧直接重放，不再逐条指令走 Paint/TextPainter 构造。
  final CommandLayerCache _layerCache = CommandLayerCache();

  /// 动画底图专用的 Picture 缓存（与静止帧缓存分开，动画结束回到静止列表时
  /// 不互相挤掉对方的录制结果）。
  final CommandLayerCache _animBaseCache = CommandLayerCache();

  /// 背景网格 Picture 缓存：网格在内容坐标系里静止，平移类帧只重放不重录。
  final GridLayerCache _gridCache = GridLayerCache();

  /// 活帧状态：每帧变化的数据写这里并 markFrame()，经 repaint Listenable 直达
  /// markNeedsPaint——动画/拖拽帧零 widget 重建、零 element diff。
  final RoadFrameState _frame = RoadFrameState();

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    _prevLayout = _currentLayout();
    _syncFrame();
  }

  /// 把当前帧数据写入 [_frame] 并触发重绘（替代 setState：不重建 widget 子树）。
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

  /// 有活跃工作（视口物理/格子动画/呼吸光圈）时确保 Ticker 在跑；
  /// [_onTick] 发现无事可做时会自行停掉，面板静止时不再空转 vsync 回调。
  void _wake() {
    if (!_ticker.isActive) {
      // Ticker 重启后 elapsed 从零计，同步归零 _lastTick，消除首帧 dt<=0 的死帧。
      _lastTick = Duration.zero;
      _ticker.start();
    }
  }

  @override
  void didUpdateWidget(covariant RoadPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.theme != oldWidget.theme) _fallbackGrid = null;

    // 数据没变（父级因无关 UI 状态重建）时不做 diff、不失效指令/Picture 缓存、
    // 不动视口——否则每次开关切换都会让所有面板重录 Picture 并重跑 diff。
    // 布局对象来自引擎 compute 输出，数据未变时引用稳定。
    final dataChanged =
        !identical(widget.cells, oldWidget.cells) ||
        !identical(widget.decorations, oldWidget.decorations);
    if (!dataChanged) {
      // 面板几何变了（如窗口缩放）时边界会收紧，把静止的视口重新夹回新边界，
      // 避免停在界外且 Ticker 已停、永远不回弹。
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
    // -1 哨兵：Ticker 可能已停止（elapsed 会在重启后清零），真正的起点在下一帧
    // _onTick 里用当帧 elapsed 补上。
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
      // 动画底图：不在动的格子在整个动画期恒定，录一次 Picture 反复重放。
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

    // dragging 阶段由指针事件驱动（stepViewport 对它是恒等变换），不算活跃工作，
    // 否则拖拽途中数据到达会让 Ticker 以 60fps 空转到手指抬起。
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

    // dragging 不进步进：stepViewport 对该阶段是恒等变换，帧由指针事件驱动；
    // 若算作 changed 会让 Ticker 在拖拽期间永远停不下来。
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
      // 视口 idle、动画播完、光圈结束：停掉 Ticker，静止面板不再空转。
      _ticker.stop();
    }
  }

  /// 清空过渡索引与动画底图（动画结束/无动画更新时调用）。
  void _clearTransitionState() {
    _enters = const {};
    _moves = const {};
    _exitCells = const [];
    _animBaseCommands = null;
  }

  /// 呼吸光圈当前帧的绘制指令：半径随时间增大、透明度随时间衰减的描边圆，
  /// 叠在格子圆圈之上（对应 TS 版本 `drawPulseRing` 的采样逻辑）。
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

  /// 本帧内容层"底图"：无过渡时是全量静止列表（Picture 缓存），动画期间是
  /// "不在动的格子"底图（另一份 Picture 缓存）——两者在各自生命周期内引用恒定。
  List<DrawCommand> _baseCommands() {
    if (_transitions.isEmpty) {
      return _staticCommands ??= [
        ...widget.decorations,
        for (final cell in widget.cells) ...cell.commands,
      ];
    }
    return _animBaseCommands!;
  }

  /// 本帧叠加层：正在 enter/move/exit 的格子按进度采样 + 呼吸光圈。
  /// 只有动的格子逐帧直绘（通常 1-2 个），文字重排版从每帧全部 badge 降到
  /// 只有动画格子自己的 badge。
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

  // `GestureDetector` 不允许同时挂 pan 与 scale 识别器（scale 是 pan 的超集，
  // 官方断言会直接报错）——单指拖拽和双指缩放统一走 onScale* 三个回调，靠
  // ScaleUpdateDetails.pointerCount 区分：1 指按拖拽处理（走 dragBy 的阻尼语义），
  // ≥2 指才走缩放（走 zoomAt 的焦点不变量）。

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
    // 手势系统自带最小二乘速度估计（px/s），视口状态机要 px/ms，除以 1000
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
    // 每帧变化的数据都在 _frame 里由 repaint Listenable 驱动，这里只组装
    // 低频变化的静态配置；面板内部不再有任何 setState——动画/拖拽帧零重建。
    return GestureDetector(
      onScaleStart: _onScaleStart,
      onScaleUpdate: _onScaleUpdate,
      onScaleEnd: _onScaleEnd,
      onDoubleTap: _handleDoubleTap,
      child: SizedBox(
        width: widget.panelWidth,
        height: widget.panelHeight,
        // RepaintBoundary：把本面板隔离成独立绘制层——否则一个面板动画时
        // markNeedsPaint 会传播到共同祖先，同屏的所有兄弟面板每帧全部重画。
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
