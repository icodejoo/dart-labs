import 'dart:async';

import 'package:flutter/material.dart';
import 'package:luckdraw/grid.dart';
import 'package:luckdraw/slot.dart';
import 'package:luckdraw/wheel.dart';

/// 示例下方的外部控制区构建器；对应官方示例里写在 canvas 之外的 DOM 按钮。
///
/// [start] 等价于官方的 `play()` 后延时 `stop(n)`；需要更细的控制时直接用 [controller]。
typedef OfficialControlsBuilder<T> = Widget Function(
    BuildContext context, T controller, VoidCallback start);

/// 叠在画布上方的组件构建器；对应官方示例里绝对定位在 canvas 上的 DOM 元素。
typedef OfficialOverlayBuilder<T> = Widget Function(
    BuildContext context, T controller, VoidCallback start);

/// 常用的“开始 / 停止”外部按钮行；例如 `officialButtons([('开始', start)])`。
Widget officialButtons(List<(String, VoidCallback)> buttons) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Wrap(spacing: 8, runSpacing: 4, children: [
      for (final (label, onTap) in buttons)
        FilledButton.tonal(onPressed: onTap, child: Text(label)),
    ]));

/// 三种舞台共用的外框：画布（可带叠层）、结果文字和控制区。
class _StageFrame extends StatelessWidget {
  /// 创建外框；[width]、[height] 是官方示例的 CSS 像素尺寸。
  const _StageFrame(
      {required this.width,
      required this.height,
      required this.canvas,
      required this.result,
      this.overlay,
      this.controls});

  /// 画布宽度。
  final double width;

  /// 画布高度。
  final double height;

  /// 玩法组件。
  final Widget canvas;

  /// 最近一次结果文字，空串不显示。
  final String result;

  /// 叠在画布上的组件，可为空。
  final Widget? overlay;

  /// 画布下方的控制区，可为空。
  final Widget? controls;

  /// 超出卡片宽度时整体等比缩小，保持官方像素布局不变形。
  @override
  Widget build(BuildContext context) =>
      Column(mainAxisSize: MainAxisSize.min, children: [
        FittedBox(
            fit: BoxFit.scaleDown,
            child: SizedBox(
                width: width,
                height: height,
                child: Stack(children: [
                  Positioned.fill(child: canvas),
                  if (overlay != null) Positioned.fill(child: overlay!),
                ]))),
        if (result.isNotEmpty)
          Padding(
              padding: const EdgeInsets.only(top: 6),
              child:
                  Text(result, style: Theme.of(context).textTheme.bodySmall)),
        if (controls != null) controls!,
      ]);
}

/// 可运行的转盘示例舞台，持有控制器并实现官方“开始后延时停止”的惯用流程。
///
/// 例如 `OfficialWheel(config: cfg, stopIndex: () => 0)`。
class OfficialWheel extends StatefulWidget {
  /// 创建舞台；[stopIndex] 为空表示不自动停止。
  const OfficialWheel(
      {super.key,
      required this.config,
      this.width = 200,
      this.height = 200,
      this.autoPlay = false,
      this.stopIndex,
      this.stopDelay = const Duration(seconds: 3),
      this.overlay,
      this.controls});

  /// 转盘配置。
  final WheelConfig config;

  /// 画布宽度（官方 CSS 像素）。
  final double width;

  /// 画布高度（官方 CSS 像素）。
  final double height;

  /// 挂载后立即开始旋转，对应官方示例里直接写的 `myLucky.play()`。
  final bool autoPlay;

  /// 开始后返回要停下的奖品下标；为空则只转不停。
  final int Function()? stopIndex;

  /// 开始到调用停止之间的延时，对应官方用 `setTimeout` 模拟接口。
  final Duration stopDelay;

  /// 叠在画布上的组件。
  final OfficialOverlayBuilder<WheelController>? overlay;

  /// 画布下方的控制区。
  final OfficialControlsBuilder<WheelController>? controls;

  /// 创建状态。
  @override
  State<OfficialWheel> createState() => _OfficialWheelState();
}

/// [OfficialWheel] 的状态：控制器、延时停止计时器和结果文字。
class _OfficialWheelState extends State<OfficialWheel> {
  /// 本舞台独占的控制器。
  final WheelController _controller = WheelController();

  /// 延时停止计时器。
  Timer? _timer;

  /// 最近一次结果文字。
  String _result = '';

  /// 需要时在首帧后自动开始。
  @override
  void initState() {
    super.initState();
    if (widget.autoPlay) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _controller.play());
    }
  }

  /// 开始并按配置延时停止。
  void _start() {
    if (!_controller.play()) return;
    final stop = widget.stopIndex;
    if (stop == null) return;
    _timer?.cancel();
    _timer = Timer(widget.stopDelay, () => _controller.stop(stop()));
  }

  /// 构建画布、叠层与控制区。
  @override
  Widget build(BuildContext context) => _StageFrame(
      width: widget.width,
      height: widget.height,
      result: _result,
      canvas: LuckyWheel(
          config: widget.config,
          controller: _controller,
          width: widget.width,
          height: widget.height,
          onStart: _start,
          onEnd: (r) => setState(() => _result = r.cancelled
              ? ''
              : '中奖：${r.index}'
                  '${_firstText(r.prize)}')),
      overlay: widget.overlay?.call(context, _controller, _start),
      controls: widget.controls?.call(context, _controller, _start));

  /// 取奖品第一行文字作为结果补充，没有文字返回空串。
  static String _firstText(WheelPrize? prize) =>
      prize == null || prize.texts.isEmpty ? '' : '（${prize.texts.first.text}）';

  /// 释放计时器与控制器。
  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }
}

/// 可运行的九宫格示例舞台；流程与 [OfficialWheel] 一致。
///
/// 例如 `OfficialGrid(config: cfg, stopIndex: () => 0)`。
class OfficialGrid extends StatefulWidget {
  /// 创建舞台；[stopIndex] 为空表示不自动停止。
  const OfficialGrid(
      {super.key,
      required this.config,
      this.width = 300,
      this.height = 300,
      this.autoPlay = false,
      this.stopIndex,
      this.stopDelay = const Duration(seconds: 3),
      this.overlay,
      this.controls});

  /// 九宫格配置。
  final GridConfig config;

  /// 画布宽度（官方 CSS 像素）。
  final double width;

  /// 画布高度（官方 CSS 像素）。
  final double height;

  /// 挂载后立即开始旋转。
  final bool autoPlay;

  /// 开始后返回要停下的奖品下标；为空则只转不停。
  final int Function()? stopIndex;

  /// 开始到调用停止之间的延时。
  final Duration stopDelay;

  /// 叠在画布上的组件。
  final OfficialOverlayBuilder<GridController>? overlay;

  /// 画布下方的控制区。
  final OfficialControlsBuilder<GridController>? controls;

  /// 创建状态。
  @override
  State<OfficialGrid> createState() => _OfficialGridState();
}

/// [OfficialGrid] 的状态。
class _OfficialGridState extends State<OfficialGrid> {
  /// 本舞台独占的控制器。
  final GridController _controller = GridController();

  /// 延时停止计时器。
  Timer? _timer;

  /// 最近一次结果文字。
  String _result = '';

  /// 需要时在首帧后自动开始。
  @override
  void initState() {
    super.initState();
    if (widget.autoPlay) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _controller.play());
    }
  }

  /// 开始并按配置延时停止。
  void _start() {
    if (!_controller.play()) return;
    final stop = widget.stopIndex;
    if (stop == null) return;
    _timer?.cancel();
    _timer = Timer(widget.stopDelay, () => _controller.stop(stop()));
  }

  /// 构建画布、叠层与控制区。
  @override
  Widget build(BuildContext context) => _StageFrame(
      width: widget.width,
      height: widget.height,
      result: _result,
      canvas: LuckyGrid(
          config: widget.config,
          controller: _controller,
          width: widget.width,
          height: widget.height,
          onStart: _start,
          onEnd: (r) =>
              setState(() => _result = r.cancelled ? '' : '中奖：${r.index}')),
      overlay: widget.overlay?.call(context, _controller, _start),
      controls: widget.controls?.call(context, _controller, _start));

  /// 释放计时器与控制器。
  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }
}

/// 可运行的老虎机示例舞台；老虎机没有画布内按钮，需通过叠层或控制区触发 `start`。
///
/// 例如 `OfficialSlot(config: cfg, stopIndex: () => 0, controls: ...)`。
class OfficialSlot extends StatefulWidget {
  /// 创建舞台；[stopIndex] 为空表示不自动停止。
  const OfficialSlot(
      {super.key,
      required this.config,
      this.width = 300,
      this.height = 200,
      this.autoPlay = false,
      this.stopIndex,
      this.stopDelay = const Duration(seconds: 2),
      this.overlay,
      this.controls});

  /// 老虎机配置。
  final SlotConfig config;

  /// 画布宽度（官方 CSS 像素）。
  final double width;

  /// 画布高度（官方 CSS 像素）。
  final double height;

  /// 挂载后立即开始旋转。
  final bool autoPlay;

  /// 开始后返回全部列要停下的奖品下标；为空则只转不停。
  final int Function()? stopIndex;

  /// 开始到调用停止之间的延时。
  final Duration stopDelay;

  /// 叠在画布上的组件。
  final OfficialOverlayBuilder<SlotController>? overlay;

  /// 画布下方的控制区。
  final OfficialControlsBuilder<SlotController>? controls;

  /// 创建状态。
  @override
  State<OfficialSlot> createState() => _OfficialSlotState();
}

/// [OfficialSlot] 的状态。
class _OfficialSlotState extends State<OfficialSlot> {
  /// 本舞台独占的控制器。
  final SlotController _controller = SlotController();

  /// 延时停止计时器。
  Timer? _timer;

  /// 最近一次结果文字。
  String _result = '';

  /// 需要时在首帧后自动开始。
  @override
  void initState() {
    super.initState();
    if (widget.autoPlay) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _controller.play());
    }
  }

  /// 开始并按配置延时停止。
  void _start() {
    if (!_controller.play()) return;
    final stop = widget.stopIndex;
    if (stop == null) return;
    _timer?.cancel();
    _timer = Timer(widget.stopDelay, () => _controller.stop(stop()));
  }

  /// 构建画布、叠层与控制区。
  @override
  Widget build(BuildContext context) => _StageFrame(
      width: widget.width,
      height: widget.height,
      result: _result,
      canvas: LuckySlotMachine(
          config: widget.config,
          controller: _controller,
          width: widget.width,
          height: widget.height,
          onEnd: (r) => setState(
              () => _result = r.cancelled ? '' : '结果：${r.indices.join(', ')}')),
      overlay: widget.overlay?.call(context, _controller, _start),
      controls: widget.controls?.call(context, _controller, _start));

  /// 释放计时器与控制器。
  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }
}
