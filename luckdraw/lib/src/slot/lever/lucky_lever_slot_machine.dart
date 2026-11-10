import 'package:flutter/widgets.dart';

import '../../core/control/controller.dart';
import '../../core/foundation/constants.dart';
import '../../core/motion/phase.dart';
import '../control/slot_controller.dart';
import '../layout/slot_layout.dart';
import '../model/slot_config.dart';
import '../model/slot_result.dart';
import '../motion/slot_motion.dart';
import '../render/payline_layer.dart';
import '../widgets/lucky_slot_machine.dart';
import 'lever_options.dart';
import 'lever_painter.dart';

/// 带拉杆、默认错峰停轮及赔付线高亮的老虎机。
///
/// 例如传入 config 和 SlotController，在 onPull 中异步决定 stopEach 的目标。
class LuckyLeverSlotMachine extends LuckySlotMachine {
  /// 创建拉霸机；宽高包含拉杆区，其余参数与 LuckySlotMachine 一致。
  const LuckyLeverSlotMachine(
      {super.key,
      required super.config,
      super.controller,
      this.lever = const LeverOptions(),
      this.onPull,
      super.renderer,
      super.width,
      super.height,
      super.alignment,
      super.onEnd,
      super.onPhaseChanged,
      super.onCellPassed,
      super.onImageError,
      super.onReady,
      super.hooks,
      super.layers,
      super.performance,
      super.textScaling,
      super.semanticsLabel,
      super.semanticsValueBuilder});

  /// 拉杆布局、阈值和自动开始策略。
  final LeverOptions lever;

  /// 每次有效拉杆调用；运动中也会调用，例如请求下一局的业务信息。
  final VoidCallback? onPull;

  /// 创建独立回弹及控制器所有者。
  @override
  State<LuckyLeverSlotMachine> createState() => _LuckyLeverSlotMachineState();
}

/// 管理拉杆回弹，老虎机时钟仍由内部宿主负责。
class _LuckyLeverSlotMachineState extends State<LuckyLeverSlotMachine>
    with SingleTickerProviderStateMixin {
  /// 与内部老虎机共享的控制器。
  late LuckyController<SlotConfig, SlotLayout, SlotFrame, SlotResult>
      _controller;

  /// 当前控制器是否由本组件创建。
  bool _ownsController = false;

  /// 独立短动画，回弹完成即停。
  late final AnimationController _progress;

  /// 已填充缺省错峰的配置，仅配置变更时重算。
  late SlotConfig _config;

  /// 最近结算，用于静态高亮。
  SlotResult? _result;

  /// 创建资源并计算内部配置。
  @override
  void initState() {
    super.initState();
    _attach();
    _progress =
        AnimationController(vsync: this, duration: widget.lever.springBack);
    _configure();
  }

  /// 接收或创建控制器，外部所有权保持不变。
  void _attach() {
    _ownsController = widget.controller == null;
    _controller = widget.controller ?? SlotController();
  }

  /// 对零延迟列填入列号乘错峰时间，显式非零延迟保留。
  void _configure() {
    _config = widget.config.copyWith(reels: [
      for (var r = 0; r < widget.config.reels.length; r++)
        widget.config.reels[r].stopDelay == Duration.zero
            ? widget.config.reels[r]
                .copyWith(stopDelay: widget.lever.staggerStop * r)
            : widget.config.reels[r]
    ]);
    _result = null;
  }

  /// 更新控制器所有权、动画时长和内部配置。
  @override
  void didUpdateWidget(covariant LuckyLeverSlotMachine oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      if (_ownsController) _controller.dispose();
      _attach();
      _result = null;
    }
    _progress.duration = widget.lever.springBack;
    if (oldWidget.config != widget.config || oldWidget.lever != widget.lever) {
      _configure();
    }
  }

  /// 有效拉杆总是通知业务，仅可开始阶段自动开始一局。
  void _pull() {
    if (widget.lever.autoPlay && _controller.phase.value.canPlay) {
      _controller.play();
    }
    widget.onPull?.call();
  }

  /// 松手后根据最终进度判断一次有效拉动，并启动回弹。
  void _release() {
    if (_progress.value >= widget.lever.pullThreshold) _pull();
    _progress.reverse();
  }

  /// 保存本局结果后通知调用者。
  void _ended(SlotResult result) {
    setState(() => _result = result);
    widget.onEnd?.call(result);
  }

  /// 新局开始时移除上局高亮，并转交阶段回调。
  void _phaseChanged(LuckyPhase phase) {
    if (phase == LuckyPhase.accelerating && _result != null) {
      setState(() => _result = null);
    }
    widget.onPhaseChanged?.call(phase);
  }

  /// 组合老虎机和独立拉杆，拉杆头提供可点按的无障碍按钮。
  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, constraints) {
        final height = widget.height ?? constraints.maxHeight;
        final width = widget.width ?? constraints.maxWidth;
        final leverWidth = height * widget.lever.widthFactor;
        final slot = Expanded(
            child: LuckySlotMachine(
                config: _config,
                controller: _controller,
                renderer: widget.renderer,
                alignment: widget.alignment,
                onEnd: _ended,
                onPhaseChanged: _phaseChanged,
                onCellPassed: widget.onItemPassed,
                onImageError: widget.onImageError,
                onReady: widget.onReady,
                hooks: widget.hooks,
                layers: [
                  ...widget.layers,
                  SlotPaylineLayer(
                      result: _result,
                      paylines: _config.paylines,
                      mode: _config.options.mode)
                ],
                performance: widget.performance,
                textScaling: widget.textScaling,
                semanticsLabel: widget.semanticsLabel,
                semanticsValueBuilder: widget.semanticsValueBuilder));
        final handle = SizedBox(
            width: leverWidth,
            height: height,
            child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                excludeFromSemantics: true,
                onVerticalDragStart: (_) => _progress.stop(),
                onVerticalDragUpdate: (details) => _progress.value =
                    (_progress.value +
                            details.delta.dy / (height * leverTravelFactor))
                        .clamp(0.0, 1.0),
                onVerticalDragEnd: (_) => _release(),
                onVerticalDragCancel: () => _progress.reverse(),
                child: Stack(children: [
                  Positioned.fill(
                      child: CustomPaint(
                          painter: LeverPainter(widget.lever, _progress))),
                  AnimatedBuilder(
                      animation: _progress,
                      builder: (context, child) {
                        final radius = leverWidth * leverKnobRadiusFactor;
                        return Positioned(
                            left: leverWidth / kLuckyHalfDivisor - radius,
                            top: height *
                                    (leverRestFactor +
                                        leverTravelFactor * _progress.value) -
                                radius,
                            width: radius * kLuckyHalfDivisor,
                            height: radius * kLuckyHalfDivisor,
                            child: Semantics(
                                button: true,
                                label: '拉杆',
                                child: GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTap: _pull)));
                      })
                ])));
        return SizedBox(
            width: width,
            height: height,
            child: Row(
                children: widget.lever.side == LeverSide.right
                    ? [slot, handle]
                    : [handle, slot]));
      });

  /// 停止回弹并释放仅由本组件拥有的控制器。
  @override
  void dispose() {
    _progress.dispose();
    if (_ownsController) _controller.dispose();
    super.dispose();
  }
}
