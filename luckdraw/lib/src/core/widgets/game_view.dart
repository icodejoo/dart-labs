import 'package:flutter/widgets.dart';

import '../control/controller.dart';
import '../control/hooks.dart';
import '../foundation/image.dart';
import '../foundation/options.dart';
import '../game/frame.dart';
import '../game/game.dart';
import '../game/layout.dart';
import '../image/image_resolver.dart';
import '../motion/clock.dart';
import '../motion/motion.dart';
import '../motion/phase.dart';
import '../motion/result.dart';
import '../render/layer.dart';
import '../render/renderer.dart';
import '../text/text_measurer.dart';
import 'lifecycle.dart';

/// 通用玩法宿主；例如传入自定义 game、config 和可选 controller。
class LuckyGameView<
    C extends Object,
    L extends LuckyLayout,
    F extends LuckyFrame,
    R extends LuckyResult<Object?>> extends StatefulWidget {
  /// 创建宿主；未给宽高时要求父约束有界，外部控制器归调用者释放。
  const LuckyGameView(
      {super.key,
      required this.game,
      required this.config,
      this.controller,
      this.renderer,
      this.width,
      this.height,
      this.alignment = Alignment.topLeft,
      this.onStart,
      this.onButtonTap,
      this.onItemTap,
      this.onEnd,
      this.onPhaseChanged,
      this.onItemPassed,
      this.onImageError,
      this.onReady,
      this.hooks = const LuckyHooks(),
      this.layers = const [],
      this.performance = const LuckyPerformanceOptions(),
      this.textScaling = LuckyTextScaling.none,
      this.semanticsLabel,
      this.semanticsValueBuilder});

  /// 玩法策略。
  final LuckyGame<C, L, F, R> game;

  /// 不可变配置。
  final C config;

  /// 外部控制器，null 时由宿主创建。
  final LuckyController<C, L, F, R>? controller;

  /// 可替换的渲染后端。
  final LuckyRenderer<C, L, F, R>? renderer;

  /// 可选逻辑宽度。
  final double? width;

  /// 可选逻辑高度。
  final double? height;

  /// 非正方形容器的对齐。
  final AlignmentGeometry alignment;

  /// 命中按钮且当前允许开始时触发，不自动调用 play。
  final VoidCallback? onStart;

  /// 任意阶段的按钮点击。
  final LuckyButtonTapCallback? onButtonTap;

  /// 条目点击。
  final ValueChanged<int>? onItemTap;

  /// 一局正常或作废结束。
  final ValueChanged<R>? onEnd;

  /// 运动阶段变化。
  final ValueChanged<LuckyPhase>? onPhaseChanged;

  /// 越过条目的列和下标。
  final void Function(int reel, int index)? onItemPassed;

  /// 图片加载或转换失败。
  final ValueChanged<LuckyImageError>? onImageError;

  /// 全部请求均有结论。
  final VoidCallback? onReady;

  /// 生命周期与绘制钩子。
  final LuckyHooks hooks;

  /// 用户绘制层。
  final List<LuckyLayer<L, F>> layers;

  /// 缓存、采样及隐藏暂停策略。
  final LuckyPerformanceOptions performance;

  /// 系统文字缩放策略。
  final LuckyTextScaling textScaling;

  /// 无障碍标签，null 使用玩法默认。
  final String? semanticsLabel;

  /// 无障碍阶段与结果描述，null 时不提供 value。
  final String Function(LuckyPhase phase, R? result)? semanticsValueBuilder;

  /// 创建通用宿主状态。
  @override
  State<LuckyGameView<C, L, F, R>> createState() =>
      _LuckyGameViewState<C, L, F, R>();
}

/// 持有布局、时间源、图片与宿主回调。
class _LuckyGameViewState<
        C extends Object,
        L extends LuckyLayout,
        F extends LuckyFrame,
        R extends LuckyResult<Object?>> extends State<LuckyGameView<C, L, F, R>>
    with TickerProviderStateMixin
    implements LuckyControllerHost<R> {
  /// 当前控制器。
  late LuckyController<C, L, F, R> _controller;

  /// 是否拥有当前控制器。
  bool _ownsController = false;

  /// 宿主时间源。
  late final TickerLuckyClock _clock;

  /// 图片解析器。
  late final LuckyImageResolver _resolver;

  /// 图片独立通知器。
  final LuckyFrameNotifier _images = LuckyFrameNotifier();

  /// 生命周期桥。
  late final LuckyLifecycle _lifecycle;

  /// 当前布局。
  L? _layout;

  /// 已应用的配置。
  C? _config;

  /// 是否需要重新布局。
  bool _dirty = true;

  /// 布局版本。
  int _generation = 0;

  /// 环境像素比。
  double _dpr = 1;

  /// 文字缩放。
  TextScaler _scaler = TextScaler.noScaling;

  /// 文字方向。
  TextDirection _direction = TextDirection.ltr;

  /// 待应用结构变化。
  bool _structural = false;

  /// 当前图片解析环境，与几何布局是否变化独立。
  ImageConfiguration? _imageConfiguration;

  /// 图片请求或其解析环境是否需要同步。
  bool _imagesDirty = true;

  /// 宿主当前是否隐藏或进入后台。
  bool _hidden = false;

  /// 图片变更是否发生在宿主 build 中。
  bool _building = false;

  /// 合并一次构建后的刷新。
  bool _refreshScheduled = false;

  /// 当前时钟。
  @override
  LuckyClock get clock => _clock;

  /// 初始化拥有资源并挂接外部控制器。
  @override
  void initState() {
    super.initState();
    widget.hooks.beforeInit?.call();
    _clock = TickerLuckyClock(this);
    final lifecycleState = WidgetsBinding.instance.lifecycleState;
    _hidden = lifecycleState == AppLifecycleState.hidden ||
        lifecycleState == AppLifecycleState.paused;
    _attachController();
    _resolver = LuckyImageResolver(
        onChanged: _imagesChanged, onError: _imageError, onReady: _ready);
    _lifecycle = LuckyLifecycle(onPause: _pause, onResume: _resume);
    PaintingBinding.instance.systemFonts.addListener(_fontsChanged);
  }

  /// 获取或创建控制器，宿主回调始终读取当前 widget。
  void _attachController() {
    _ownsController = widget.controller == null;
    _controller = widget.controller ?? widget.game.createController();
    if (_hidden && widget.performance.pauseWhenHidden) {
      _controller.pauseForLifecycle();
    }
    _controller.attach(this);
  }

  /// 跟随环境变化失效布局。
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final scaler = widget.textScaling == LuckyTextScaling.system
        ? MediaQuery.textScalerOf(context)
        : TextScaler.noScaling;
    final direction = Directionality.of(context);
    final imageConfiguration = createLocalImageConfiguration(context);
    if (_imageConfiguration != imageConfiguration) {
      _imageConfiguration = imageConfiguration;
      _imagesDirty = true;
    }
    if (_dpr != dpr || _scaler != scaler || _direction != direction) {
      _dirty = true;
    }
    _dpr = dpr;
    _scaler = scaler;
    _direction = direction;
  }

  /// 更新控制器、配置与布局选项。
  @override
  void didUpdateWidget(covariant LuckyGameView<C, L, F, R> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller ||
        oldWidget.game != widget.game) {
      _controller.detach();
      _controller.resumeForLifecycle();
      if (_ownsController) {
        _controller.dispose();
      }
      _attachController();
      _dirty = true;
    }
    if (oldWidget.config != widget.config) {
      _structural = _config != null &&
          widget.game.isStructuralChange(_config!, widget.config);
      _dirty = true;
    }
    if (_hidden &&
        oldWidget.performance.pauseWhenHidden !=
            widget.performance.pauseWhenHidden) {
      if (widget.performance.pauseWhenHidden) {
        _controller.pauseForLifecycle();
      } else {
        _controller.resumeForLifecycle();
      }
    }
    if (oldWidget.alignment != widget.alignment ||
        oldWidget.textScaling != widget.textScaling) {
      _dirty = true;
      _scaler = widget.textScaling == LuckyTextScaling.system
          ? MediaQuery.textScalerOf(context)
          : TextScaler.noScaling;
    }
  }

  /// 热重载重新计算布局并增加渲染版本。
  @override
  void reassemble() {
    super.reassemble();
    setState(() {
      _dirty = true;
    });
  }

  /// 系统字体变化只在低频路径触发布局。
  void _fontsChanged() {
    if (mounted) {
      setState(() {
        _dirty = true;
      });
    }
  }

  /// 隐藏时按策略暂停。
  void _pause() {
    _hidden = true;
    if (widget.performance.pauseWhenHidden) {
      _controller.pauseForLifecycle();
    }
  }

  /// 恢复应用时解除生命周期暂停。
  void _resume() {
    _hidden = false;
    _controller.resumeForLifecycle();
  }

  /// 图片变化独立通知渲染器，并低频更新 surface 输入。
  void _imagesChanged() {
    _images.notify();
    _refresh();
  }

  /// 转发给当前图片错误回调。
  void _imageError(LuckyImageError error) => widget.onImageError?.call(error);

  /// 全部图片有结论后触发就绪钩子。
  void _ready() {
    widget.hooks.afterInit?.call();
    widget.onReady?.call();
  }

  /// 安全合并 build 内的低频状态刷新。
  void _refresh() {
    if (!mounted) return;
    if (!_building) {
      setState(() {});
      return;
    }
    if (_refreshScheduled) return;
    _refreshScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshScheduled = false;
      if (mounted) {
        setState(() {});
      }
    });
  }

  /// 阶段变化更新语义与动画提示。
  @override
  void handlePhaseChanged(LuckyPhase phase) {
    if (!phase.isMoving && _structural) {
      _dirty = true;
    }
    widget.onPhaseChanged?.call(phase);
    _refresh();
  }

  /// 更新结果与无障碍值。
  @override
  void handleResult(R result) {
    widget.onEnd?.call(result);
    _refresh();
  }

  /// 转发跨条目事件。
  @override
  void handleItemPassed(int reel, int index) =>
      widget.onItemPassed?.call(reel, index);

  /// 转发开始钩子。
  @override
  void handleStarted() => widget.hooks.afterStart?.call();

  /// 点击命中全部按钮和条目，保留上游重叠触发行为。
  void _tap(Offset position) {
    final layout = _layout;
    if (layout == null || layout.isEmpty) return;
    for (final hit in widget.game
        .hitTestAll(_config!, layout, _controller.frame, position)) {
      if (hit.kind == LuckyHitKind.button) {
        widget.onButtonTap?.call(hit.index, _controller.phase.value);
        if (_controller.phase.value.acceptsStart) {
          widget.onStart?.call();
        }
      } else {
        widget.onItemTap?.call(hit.index);
      }
    }
  }

  /// 语义点击遵循与指针按钮点击相同的阶段限制。
  void _semanticTap() {
    if (_controller.phase.value.acceptsStart) {
      widget.onStart?.call();
    }
  }

  /// 转交按需启用的拖动。
  void _pan(LuckyPanPhase phase, Offset position) {
    final layout = _layout;
    if (layout != null && !layout.isEmpty) {
      widget.game
          .handlePan(_controller, layout, LuckyPanEvent(phase, position));
    }
  }

  /// 构建低频布局与渲染表面。
  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: _buildBox);

  /// 解析约束并只在输入变化时重新布局。
  Widget _buildBox(BuildContext context, BoxConstraints constraints) {
    final width = widget.width ?? constraints.maxWidth;
    final height = widget.height ?? constraints.maxHeight;
    if (!width.isFinite || !height.isFinite) {
      throw FlutterError('LuckyGameView 需要有界约束或显式 width/height');
    }
    final size = constraints.constrain(Size(width, height));
    final config = widget.game.resolveConfig(context, widget.config);
    if (_config != null && _config != config && !_structural) _dirty = true;
    _building = true;
    try {
      final previous = _layout;
      final defer =
          _structural && _controller.phase.value.isMoving && previous != null;
      if (!defer && (_dirty || previous?.size != size)) {
        final resized = previous?.size != size;
        if (resized) {
          widget.hooks.beforeResize?.call();
        }
        final measurer =
            TextPainterMeasurer(textScaler: _scaler, textDirection: _direction);
        try {
          _layout = widget.game.computeLayout(
              config,
              LuckyLayoutInput(
                  size: size,
                  devicePixelRatio: _dpr,
                  measurer: measurer,
                  textDirection: _direction,
                  alignment: widget.alignment));
        } finally {
          measurer.dispose();
        }
        _config = config;
        _generation++;
        _dirty = false;
        _structural = false;
        _controller.configure(config, _layout);
        if (resized) {
          widget.hooks.afterResize?.call();
        }
        _imagesDirty = true;
      }
      if (_imagesDirty) {
        _imagesDirty = false;
        _resolver.update(widget.game.collectImages(_config!, _layout!),
            _imageConfiguration!, _dpr);
      }
      final layout = _layout!;
      Widget surface = layout.isEmpty && !layout.paintsWhenEmpty
          ? const SizedBox.shrink()
          : (widget.renderer ?? widget.game.createDefaultRenderer())
              .buildSurface(
                  context,
                  LuckySurfaceData(
                      config: _config!,
                      layout: layout,
                      layoutGeneration: _generation,
                      frame: _controller.frame,
                      frameListenable: _controller.frameListenable,
                      images: _resolver.images,
                      imagesListenable: _images,
                      layers: widget.layers,
                      hooks: widget.hooks,
                      devicePixelRatio: _dpr,
                      textScale: _scaler,
                      textDirection: _direction,
                      performance: widget.performance,
                      isAnimating: _controller.phase.value.isMoving));
      final taps = widget.onStart != null ||
          widget.onButtonTap != null ||
          widget.onItemTap != null;
      final pans = widget.game.wantsPanGestures;
      if (taps || pans) {
        surface = GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: taps ? (details) => _tap(details.localPosition) : null,
            onPanStart: pans
                ? (details) => _pan(LuckyPanPhase.start, details.localPosition)
                : null,
            onPanUpdate: pans
                ? (details) => _pan(LuckyPanPhase.update, details.localPosition)
                : null,
            onPanEnd: pans ? (_) => _pan(LuckyPanPhase.end, Offset.zero) : null,
            child: surface);
      }
      return SizedBox(
          width: size.width,
          height: size.height,
          child: RepaintBoundary(
              child: Semantics(
                  label: widget.semanticsLabel ??
                      widget.game.semanticsLabel(_config!),
                  value: widget.semanticsValueBuilder
                      ?.call(_controller.phase.value, _controller.lastResult),
                  liveRegion: true,
                  button: widget.onStart != null,
                  onTap: widget.onStart == null ? null : _semanticTap,
                  child: surface)));
    } finally {
      _building = false;
    }
  }

  /// 按所有权顺序释放全部原生资源和监听。
  @override
  void dispose() {
    _lifecycle.dispose();
    PaintingBinding.instance.systemFonts.removeListener(_fontsChanged);
    _resolver.dispose();
    _images.dispose();
    _controller.detach();
    _controller.resumeForLifecycle();
    if (_ownsController) {
      _controller.dispose();
    }
    _clock.dispose();
    super.dispose();
  }
}
