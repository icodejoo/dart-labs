import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/widgets.dart';
import 'package:countman/src/core/run_state.dart';
import 'package:countman/src/counter/plugin.dart';
import 'package:countman/src/counter/types.dart';

import 'animate_once.dart';
import 'providers.dart';
import 'scope_resolution.dart';
import 'hidden_task_state.dart';

/// A widget that drives a counter animation on the shared ticker and
/// exposes the current value via a [builder] callback.
///
/// ```dart
/// CounterBuilder(
///   to: 9999,
///   builder: (context, value, child) => Text(value.toInt().toString()),
/// )
/// ```
///
/// The [child] passed to [builder] is built once and reused across every
/// frame — put any subtree that does not depend on the animated value there
/// to skip rebuilding it (the standard `AnimatedBuilder` optimization).
///
/// 插件解析顺序：[plugin] > 最近 [CounterProvider] 的 plugin > [defaultCounter]。
/// Provider 切换分组时，存活任务迁移到新分组并从当前显示值继续（暂停态保留）。
class CounterBuilder extends StatefulWidget {
  /// 创建计数构建器；[builder] 每帧以当前值回调。
  const CounterBuilder({
    super.key,
    this.from,
    required this.to,
    this.duration = const Duration(milliseconds: 1000),
    this.curve = Curves.easeOut,
    this.allowNegative = false,
    this.plugin,
    this.fps,
    this.controller,
    required Widget Function(BuildContext context, double value, Widget? child)
        this.builder,
    this.child,
    this.valueTransform,
    this.onUpdate,
    this.onComplete,
    this.onReady,
    this.onStart,
    this.onCancel,
    this.repaintBoundary = true,
    this.animateOnce,
    this.onceId,
  }) : assert(
         fps == null || (fps > 0 && fps < double.infinity),
         'fps 必须为有限正数',
       ),
       listenableBuilder = null;

  /// 创建“常驻子树”构建器：[listenableBuilder] 只在首次构建与配置变化时调用，
  /// 逐帧数值通过传入的 [ValueListenable] 推送，由子树里的 painter / Listenable
  /// 自行监听，不再逐帧重建。
  ///
  /// 适合 Ring/Bar 这类“painter 常驻 + repaint 原地更新”的展示组件；不支持
  /// [valueTransform]。其余参数与默认构造一致。
  ///
  /// 示例：
  /// ```dart
  /// CounterBuilder.listenable(
  ///   to: 100,
  ///   listenableBuilder: (context, value, child) =>
  ///       MyProgress(listenable: value),
  /// )
  /// ```
  const CounterBuilder.listenable({
    super.key,
    this.from,
    required this.to,
    this.duration = const Duration(milliseconds: 1000),
    this.curve = Curves.easeOut,
    this.allowNegative = false,
    this.plugin,
    this.fps,
    this.controller,
    required Widget Function(
            BuildContext context, ValueListenable<double> value, Widget? child)
        this.listenableBuilder,
    this.child,
    this.onUpdate,
    this.onComplete,
    this.onReady,
    this.onStart,
    this.onCancel,
    this.repaintBoundary = true,
    this.animateOnce,
    this.onceId,
  }) : assert(
         fps == null || (fps > 0 && fps < double.infinity),
         'fps 必须为有限正数',
       ),
       builder = null,
        valueTransform = null;

  final double? from;
  final double to;
  final Duration duration;
  final Curve curve;

  /// When `false` (default) the animated value never goes below 0. Set `true`
  /// to count through / to negative numbers.
  final bool allowNegative;

  /// Optional [Counter] group for isolation/grouping. Defaults to the nearest
  /// [CounterProvider]'s group, then the shared [defaultCounter] instance
  /// (equivalent to the top-level `counter()`).
  final Counter? plugin;

  /// 实例显示刷新上限（帧/秒），返回可空配置；null 继承插件再到全局。
  /// 示例：`fps: 30`；只限制显示更新，完成与阈值不延迟。
  final double? fps;

  /// Optional controller for imperative retarget/cancel and value read-out.
  final CounterValueController? controller;

  /// Called every frame with the current animated value and the cached [child].
  /// 经 [CounterBuilder.listenable] 创建时为 null。
  final Widget Function(BuildContext context, double value, Widget? child)?
      builder;

  /// 常驻子树的构建回调，只在首次构建与配置变化时调用；逐帧数值经
  /// [ValueListenable] 推送。仅 [CounterBuilder.listenable] 创建时非空。
  final Widget Function(
          BuildContext context, ValueListenable<double> value, Widget? child)?
      listenableBuilder;

  /// Optional value-independent subtree, passed through to [builder] unchanged
  /// every frame so it is not rebuilt.
  final Widget? child;

  /// Optional mapping applied to the raw animated value before it reaches
  /// [builder] (e.g. rounding, scaling). [onUpdate] still receives the raw value.
  final double Function(double value)? valueTransform;

  /// Called every frame with the raw animated value (before [valueTransform]).
  final void Function(double value)? onUpdate;

  /// Called once when the animation reaches [to].
  final void Function(double value)? onComplete;

  /// Fired when the task is enqueued (synchronous at start).
  final VoidCallback? onReady;

  /// Fired on the animation's first rendered frame (timing begins).
  final VoidCallback? onStart;

  /// Fired if the task is cancelled before completing (retarget / dispose).
  final VoidCallback? onCancel;

  /// Wraps the builder output in a [RepaintBoundary].
  /// Default: true. Set to false when many instances share one layer
  /// (e.g. a dense grid) — too many boundaries increase GPU compositing cost.
  final bool repaintBoundary;

  /// Animate-once opt-in. `null` (default) inherits the nearest
  /// [CounterProvider]'s `animateOnce`; `true`/`false` overrides it. When
  /// effectively `true` AND a stable id is available (see [onceId]), the
  /// entrance animation plays only the first time that id is seen under the
  /// provider — later rebuilds jump straight to [to].
  ///
  /// 没有稳定 id 或上层没有 [CounterProvider] 时不会断言：debug 下打印一次警告，
  /// 并退化为每次都播放入场动画。
  ///
  /// animate-once 开关。`null`（默认）继承最近 [CounterProvider] 的
  /// `animateOnce`；`true`/`false` 覆盖之。当实际为 `true` 且存在稳定 id
  /// （见 [onceId]）时，入场动画只在该 id 于 provider 下首次出现时播放——之后
  /// 重建直接跳到 [to]。
  final bool? animateOnce;

  /// Explicit stable id for animate-once. When null, the id is derived from a
  /// [ValueKey] on this widget's [key]. Provided so wrapper widgets
  /// ([TextCounter] etc.) can forward the id extracted from their own key.
  ///
  /// animate-once 的显式稳定 id。为空时从本 widget 的 [key]（[ValueKey]）派生。
  /// 提供此参数以便包装 widget（[TextCounter] 等）转发从自身 key 提取的 id。
  final String? onceId;

  @override
  State<CounterBuilder> createState() => _CounterBuilderState();
}

/// 管理显示值、任务归属、插件迁移、运行状态及显式重启动画。
class _CounterBuilderState extends State<CounterBuilder>
    with HiddenTaskState<CounterBuilder> {
  /// 同步组件可见性；静音不会改变控制器运行状态。
  @override
  void onTaskMuteChanged(bool muted) => _handle?.muted = muted;

  /// 当前显示值，Builder 与监听者都读取它。
  late final ValueNotifier<double> _value;

  /// 当前任务句柄；animate-once 跳过入场时为空句柄或 null。
  CounterHandle? _handle;

  /// 当前生效的插件（组件显式 > Provider > 默认）。
  late Counter _plugin;

  /// 是否应减弱动画（MediaQuery 优先，没有则读平台标志）。
  bool _reduceMotion = false;

  /// 首次 didChangeDependencies 才创建任务，保证能读到作用域与 MediaQuery。
  bool _started = false;

  /// 挂载时解析的 animate-once 决策。
  AnimateOnceDecision _once = AnimateOnceDecision.none;

  /// 无存活任务时的终态：完成为 completed，其余为 idle。
  CountmanRunState _doneState = CountmanRunState.idle;

  /// 为 true 时旧任务被取消不把 runState 写成 idle（紧接着会有新任务或终态）。
  bool _keepRunState = false;

  /// 为 true 时旧任务被取消不触发用户的 onCancel（插件迁移，不是真的取消）。
  bool _quietCancel = false;

  /// 最近的 counter 作用域；不注册依赖，可在 initState 之外随时读取。
  CountmanScope<Counter>? get _scope =>
      context.getInheritedWidgetOfExactType<CountmanScope<Counter>>();

  /// 按减弱动画开关折算时长，减弱时直接跳到终值。
  Duration _motion(Duration d) => _reduceMotion ? Duration.zero : d;

  /// 初始化显示值；任务在首次 didChangeDependencies 里创建。
  @override
  void initState() {
    super.initState();
    _value = ValueNotifier(widget.from ?? 0);
  }

  /// 解析插件与减弱动画；首次创建任务，之后插件变化时迁移任务并保留状态。
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = reduceMotionOf(context);
    final plugin = resolvePluginDependent<Counter>(context,
        widgetPlugin: widget.plugin, fallback: () => defaultCounter);
    if (!_started) {
      _started = true;
      _plugin = plugin;
      _resolveOnce();
      _begin();
    } else if (!identical(plugin, _plugin)) {
      _migrate(plugin);
    }
  }

  /// 挂载时解析一次 animate-once 决策，规则见 [resolveAnimateOnce]。
  void _resolveOnce() {
    final scope = _scope;
    _once = resolveAnimateOnce(
      context,
      widgetAnimateOnce: widget.animateOnce,
      scopeAnimateOnce: scope?.animateOnce,
      registry: scope?.once,
      id: widget.onceId ?? stableOnceIdFromKey(widget.key),
      owner: 'CounterBuilder',
    );
  }

  /// 首次启动：该 id 已动画过则直接显示终值，否则创建入场任务。
  void _begin() {
    if (_once.shouldSkip) {
      _value.value = widget.to;
      _doneState = CountmanRunState.completed;
      _attachController();
    } else {
      _addTask(from: widget.from);
    }
  }

  /// 取消当前任务；[silent] 为 true 时不触发用户 onCancel。
  /// 取消期间不把 runState 写成 idle，由调用方随后写入新状态。
  void _cancelCurrent({bool silent = false}) {
    final handle = _handle;
    if (handle == null) return;
    _keepRunState = true;
    _quietCancel = silent;
    try {
      handle.cancel();
    } finally {
      _keepRunState = false;
      _quietCancel = false;
    }
  }

  /// 任务被取消的回调：转发用户 onCancel，并把 runState 回到 idle。
  void _onTaskCancel() {
    if (!_quietCancel) widget.onCancel?.call();
    if (_keepRunState) return;
    _doneState = CountmanRunState.idle;
    widget.controller?.setRunState(CountmanRunState.idle);
  }

  /// 任务完成的回调：先更新 runState 为 completed，再转发用户 onComplete。
  void _onTaskComplete(double v) {
    // 静音终点不投递 onUpdate，但保留终态显示与控制器值。
    _value.value = v;
    widget.controller?.latestValue = v;
    _doneState = CountmanRunState.completed;
    widget.controller?.setRunState(CountmanRunState.completed);
    widget.onComplete?.call(v);
  }

  /// 从 [from] 新建任务；可覆盖目标、时长与曲线，省略时使用当前组件配置。
  /// [silent] 表示这是插件迁移（旧任务静默取消），[paused] 让新任务保持暂停。
  void _addTask({
    required double? from,
    double? to,
    Duration? duration,
    Curve? curve,
    bool silent = false,
    bool paused = false,
  }) {
    _cancelCurrent(silent: silent);
    _doneState = CountmanRunState.idle;
    _handle = _plugin.addMuted(CounterOptions(
      fps: widget.fps,
      from: from,
      to: to ?? widget.to,
      duration: _motion(duration ?? widget.duration),
      curve: curve ?? widget.curve,
      allowNegative: widget.allowNegative,
      onUpdate: (v) {
        _value.value = v;
        widget.controller?.latestValue = v;
        widget.onUpdate?.call(v);
      },
      onComplete: _onTaskComplete,
      onReady: () => widget.onReady?.call(),
      onStart: () => widget.onStart?.call(),
      onCancel: _onTaskCancel,
    ), muted: taskMuted);
    if (paused) _handle!.pause();
    _attachController();
  }

  /// 插件变化：存活任务迁移到新插件，从当前显示值继续并保留暂停态；
  /// 没有存活任务（已完成、已取消、跳过入场）时只换插件，保留显示值与终态。
  void _migrate(Counter next) {
    final old = _handle;
    _plugin = next;
    if (old == null || old.isDone) return;
    _handle = old.migrateTo(next);
    _attachController();
  }

  /// 从当前显示值执行显式更新，绕过仅入场一次的限制。
  void _relaunch({required double to, Duration? duration, Curve? curve}) {
    _addTask(from: _value.value, to: to, duration: duration, curve: curve);
  }

  /// 按组件当前配置从头播放（起点取 [CounterBuilder.from]），绕过仅入场一次的限制。
  void _restart() => _addTask(from: widget.from);

  /// 由任务句柄状态推导当前 runState：存活为 running / paused，否则取终态。
  CountmanRunState _runStateNow() {
    final handle = _handle;
    if (handle != null && !handle.isDone) {
      return handle.isPaused
          ? CountmanRunState.paused
          : CountmanRunState.running;
    }
    return _doneState;
  }

  /// 绑定任务、重启动作及 runState，并立即同步当前显示值。
  void _attachController() {
    final controller = widget.controller;
    if (controller == null) return;
    // 跳过入场时没有任务：用不入队的空句柄作归属凭据，避免误触发分组回调和多余帧。
    _handle ??= _plugin.detachedHandle();
    controller.attach(_handle!, relaunch: _relaunch, restart: _restart);
    controller.latestValue = _value.value;
    controller.setRunState(_runStateNow());
  }

  /// 配置变化按原策略更新任务；仅换插件时迁移，仅替换控制器时保留任务与生命周期。
  @override
  void didUpdateWidget(CounterBuilder old) {
    super.didUpdateWidget(old);
    if (widget.fps != old.fps) _handle?.fps = widget.fps;
    final controllerChanged = widget.controller != old.controller;
    if (controllerChanged) old.controller?.detach(_handle);
    final plugin = resolvePluginDependent<Counter>(context,
        widgetPlugin: widget.plugin, fallback: () => defaultCounter);
    final configChanged = widget.to != old.to ||
        widget.duration != old.duration ||
        widget.curve != old.curve ||
        widget.allowNegative != old.allowNegative;
    if (configChanged) {
      _plugin = plugin;
      if (_once.participates) {
        // 已参与 animate-once → 之后任何值变直接跳到新值，不播动画（入场只播一次）。
        _cancelCurrent();
        _value.value = widget.to;
        _doneState = CountmanRunState.completed;
        _attachController();
      } else {
        // 总是从当前显示值新建任务，使任务结束后重定目标也能生效。
        _addTask(from: _value.value);
      }
    } else if (!identical(plugin, _plugin)) {
      _migrate(plugin);
    } else if (controllerChanged) {
      _attachController();
    }
  }

  /// 仅解绑当前 State 的任务，再释放显示值。
  @override
  void dispose() {
    widget.controller?.detach(_handle);
    _handle?.cancel();
    _value.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // RepaintBoundary 隔离本组件的重绘，否则一个脏计数器会重绘整个祖先层。
    final listenableBuilder = widget.listenableBuilder;
    final Widget inner = listenableBuilder != null
        ? listenableBuilder(context, _value, widget.child)
        : ValueListenableBuilder<double>(
            valueListenable: _value,
            child: widget.child,
            builder: (ctx, value, child) => widget.builder!(
              ctx,
              widget.valueTransform != null
                  ? widget.valueTransform!(value)
                  : value,
              child,
            ),
          );
    final result =
        widget.repaintBoundary ? RepaintBoundary(child: inner) : inner;
    // 作为 animate-once 入口，发布决策供后代 counter/countdown 继承。
    return _once.wrap(result);
  }
}
