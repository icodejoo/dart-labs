import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/widgets.dart';
import 'package:countman/src/core/run_state.dart';
import 'package:countman/src/count_down/plugin.dart';
import 'package:countman/src/count_down/types.dart';

import 'scope_resolution.dart';

export 'package:countman/src/count_down/types.dart'
    show DurationFormatter, CountdownFormat, CountdownRounding, TimeParts;

/// A widget that drives a countdown timer on the shared ticker and
/// exposes the remaining [Duration] via a [builder] callback.
///
/// ## Basic usage
/// ```dart
/// CountdownBuilder(
///   duration: const Duration(minutes: 5),
///   builder: (context, remaining) => Text(CountdownFormat.ms(remaining)),
/// )
/// ```
///
/// ## Imperative control (pause / resume / reset)
/// Create a [CountdownController] and pass it via [controller]:
/// ```dart
/// final _ctrl = CountdownController();
///
/// CountdownBuilder(
///   duration: const Duration(minutes: 5),
///   controller: _ctrl,
///   builder: (context, remaining) => Text(CountdownFormat.ms(remaining)),
/// )
///
/// _ctrl.pause();
/// _ctrl.resume();
/// _ctrl.reset();
/// ```
///
/// ## Grouping
/// Pass a custom [Countdown] instance to isolate this widget's timer from the
/// default group:
/// ```dart
/// final _group = Countdown(name: 'auction');
/// Countman.use(_group);
///
/// CountdownBuilder(duration: ..., plugin: _group, builder: ...)
/// ```
///
/// 插件解析顺序：[plugin] > 最近 [CountdownProvider] 的 plugin > [precise] 默认组
/// > [defaultCountdown]。解析出的插件变化时，存活任务迁移到新插件并保留剩余时间、
/// 进度分母与暂停态。
class CountdownBuilder extends StatefulWidget {
  /// 创建倒计时构建器；[builder] 每次更新以当前剩余时间回调。
  const CountdownBuilder({
    super.key,
    this.duration,
    this.to,
    required Widget Function(BuildContext context, TimeParts parts, Widget? child)
        this.builder,
    this.child,
    this.controller,
    this.plugin,
    this.precise = false,
    this.total,
    this.rounding = CountdownRounding.floor,
    this.onComplete,
    this.onTick,
    this.threshold,
    this.onThreshold,
    this.onReady,
    this.onStart,
    this.onCancel,
    this.onPause,
    this.onResume,
  })  : listenableBuilder = null,
        assert(duration != null || to != null,
            'Provide either `duration` or `to`.');

  /// 创建“常驻子树”构建器：[listenableBuilder] 只在首次构建与配置变化时调用，
  /// 每次更新的剩余时间通过传入的 [ValueListenable] 推送，由子树里的 painter /
  /// Listenable 自行监听，不再逐 tick 重建。
  ///
  /// 适合 Ring/Bar 这类“painter 常驻 + repaint 原地更新”的展示组件。其余参数与默认
  /// 构造一致；监听到的 [TimeParts] 是任务内复用的实例，只能同步读取，不要保留。
  ///
  /// 示例：
  /// ```dart
  /// CountdownBuilder.listenable(
  ///   duration: const Duration(minutes: 1),
  ///   listenableBuilder: (context, parts, child) =>
  ///       MyProgress(listenable: parts),
  /// )
  /// ```
  const CountdownBuilder.listenable({
    super.key,
    this.duration,
    this.to,
    required Widget Function(BuildContext context,
            ValueListenable<TimeParts> parts, Widget? child)
        this.listenableBuilder,
    this.child,
    this.controller,
    this.plugin,
    this.precise = false,
    this.total,
    this.rounding = CountdownRounding.floor,
    this.onComplete,
    this.onTick,
    this.threshold,
    this.onThreshold,
    this.onReady,
    this.onStart,
    this.onCancel,
    this.onPause,
    this.onResume,
  })  : builder = null,
        assert(duration != null || to != null,
            'Provide either `duration` or `to`.');

  /// Fixed countdown length. Mutually exclusive with [to].
  final Duration? duration;

  /// Deadline target — [DateTime], [Duration], [int] (ms epoch), or ISO-8601
  /// [String]. Takes precedence over [duration].
  ///
  /// [Duration] 走相对时长（单调钟锚定，改系统时间不影响）；[DateTime]、[int]、
  /// [String] 解析为绝对截止（墙钟锚定，随系统时间变化）。
  final Object? to;

  /// Called on each interval tick with the shared per-task [TimeParts]
  /// (pre-decomposed remaining; `parts.total`/`parts.progress` give the
  /// denominator for progress rings/bars). Update rate is determined by
  /// [Countdown.interval] on the [plugin] (default: once per second).
  /// 经 [CountdownBuilder.listenable] 创建时为 null。
  final Widget Function(BuildContext context, TimeParts parts, Widget? child)?
      builder;

  /// 常驻子树的构建回调，只在首次构建与配置变化时调用；每次更新的剩余时间经
  /// [ValueListenable] 推送。仅 [CountdownBuilder.listenable] 创建时非空。
  final Widget Function(
          BuildContext context, ValueListenable<TimeParts> parts, Widget? child)?
      listenableBuilder;

  /// Value-independent subtree passed through to [builder] unchanged each tick,
  /// so the per-tick rebuild can skip it (standard `AnimatedBuilder` child).
  ///
  /// 不依赖值的子树，每 tick 原样透传给 [builder]，使每 tick 重建跳过它
  /// （标准 `AnimatedBuilder` 的 child 优化）。
  final Widget? child;

  /// Optional controller for pause / resume / reset / restart.
  final CountdownController? controller;

  /// Override the default [Countdown] group. Useful for isolating timer sets.
  /// 未设置时取最近 [CountdownProvider] 的分组。
  final Countdown? plugin;

  /// When true and no [plugin] is supplied, drives this countdown on the shared
  /// precise ([defaultCountdownMs], `interval: 0`) group so sub-second
  /// formatters update every frame. Ignored when [plugin] is set.
  ///
  /// 为 true 且未提供 [plugin] 时，用共享的精确组（[defaultCountdownMs]，
  /// `interval: 0`）驱动本倒计时，使亚秒格式化器每帧更新。设置了 [plugin] 时忽略。
  final bool precise;

  /// 进度分母（[TimeParts.total] / [TimeParts.progress] 的分母）。为空时沿用挂载
  /// 那一刻的剩余时间；例如拍卖整段时长：`to: end, total: end.difference(start)`。
  /// 改变后会重建倒计时任务（与修改 [duration] / [to] 一样）。
  final Duration? total;

  /// 显示取整方式，默认 [CountdownRounding.floor]；[CountdownRounding.ceil] 让
  /// 剩余 9.3 秒显示 10。改变后会重建倒计时任务。
  final CountdownRounding rounding;

  /// Called once when the countdown reaches [Duration.zero].
  final void Function()? onComplete;

  /// Called on every tick with the current remaining [TimeParts], for side
  /// effects that don't rebuild UI.
  ///
  /// 每 tick 以当前剩余 [TimeParts] 回调，用于不重建 UI 的副作用。
  final void Function(TimeParts parts)? onTick;

  /// When remaining first drops to or below this, [onThreshold] fires once.
  /// null (default) disables the check. Useful for e.g. turning the display
  /// red in the final minute.
  final Duration? threshold;

  /// Called once when remaining crosses [threshold].
  final void Function()? onThreshold;

  /// Lifecycle callbacks: enqueued / first frame / cancelled / paused / resumed.
  final VoidCallback? onReady;
  final VoidCallback? onStart;
  final VoidCallback? onCancel;
  final VoidCallback? onPause;
  final VoidCallback? onResume;

  @override
  State<CountdownBuilder> createState() => _CountdownBuilderState();
}

/// 把“当前 [TimeParts] + 更新通知”包成 [ValueListenable]，供常驻子树监听。
class _PartsListenable implements ValueListenable<TimeParts> {
  /// [notifier] 在每次更新时通知，[read] 读取最新的 [TimeParts]。
  _PartsListenable(this._notifier, this._read);

  /// 更新通知源。
  final Listenable _notifier;

  /// 读取当前 [TimeParts] 的函数。
  final TimeParts Function() _read;

  @override
  void addListener(VoidCallback listener) => _notifier.addListener(listener);

  @override
  void removeListener(VoidCallback listener) =>
      _notifier.removeListener(listener);

  @override
  TimeParts get value => _read();
}

/// 管理倒计时任务、插件迁移、运行状态及控制器归属。
class _CountdownBuilderState extends State<CountdownBuilder> {
  // Reused instance from the engine's onUpdate (per-task, mutated in place).
  late TimeParts _parts;
  // Bumped each tick to drive a rebuild (TimeParts is reused, so identity
  // can't signal change on its own).
  final ValueNotifier<int> _rev = ValueNotifier(0);

  /// 给常驻子树的监听视图，与 [_rev] 同步通知。
  late final _PartsListenable _partsListenable =
      _PartsListenable(_rev, () => _parts);

  /// 当前任务句柄。
  CountdownHandle? _handle;

  /// 当前生效的插件（显式 > Provider > precise 默认组 > 默认组）。
  late Countdown _plugin;

  /// 首次 didChangeDependencies 才创建任务，保证能读到作用域。
  bool _started = false;

  /// 无存活任务时的终态：完成为 completed，其余为 idle。
  CountmanRunState _doneState = CountmanRunState.idle;

  /// 为 true 时旧任务被取消不把 runState 写成 idle（紧接着会有新任务）。
  bool _keepRunState = false;

  /// 为 true 时旧任务被取消不触发用户的 onCancel（插件迁移，不是真的取消）。
  bool _quietCancel = false;

  /// 为 true 时不转发用户的 onPause（迁移时为还原暂停态而暂停新任务）。
  bool _quietPause = false;

  /// 解析当前应使用的插件，并向作用域注册依赖。
  Countdown _resolvePlugin() => resolvePluginDependent<Countdown>(context,
      widgetPlugin: widget.plugin,
      fallback: () => widget.precise ? defaultCountdownMs : defaultCountdown);

  /// 组件配置对应的初始剩余时间，用于首个 tick 之前的显示。
  Duration get _initialRemaining => widget.to != null
      ? remainingUntil(widget.to!, clock: _plugin.clock)
      : widget.duration!;

  /// 首次解析插件并创建任务；之后插件变化时迁移任务并保留状态。
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final plugin = _resolvePlugin();
    if (!_started) {
      _started = true;
      _plugin = plugin;
      _start();
    } else if (!identical(plugin, _plugin)) {
      _migrate(plugin);
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
  void _onTaskComplete() {
    _doneState = CountmanRunState.completed;
    widget.controller?.setRunState(CountmanRunState.completed);
    widget.onComplete?.call();
  }

  /// 新建倒计时，省略 remaining 时使用组件的初始时长。
  /// 迁移时额外传入 [total]（保持进度分母）、[deadline]（保持绝对截止语义）、
  /// [paused]（保持暂停）与 [silent]（旧任务静默取消）。
  void _start({
    Duration? remaining,
    Duration? total,
    DateTime? deadline,
    bool paused = false,
    bool silent = false,
  }) {
    _cancelCurrent(silent: silent);
    _doneState = CountmanRunState.idle;
    final plugin = _plugin;
    // 显式剩余时间（重启/迁移）按相对时长；否则沿用组件配置的锚点类型。
    final anchor = deadline != null
        ? (duration: null, deadline: deadline)
        : remaining != null
            ? (duration: remaining, deadline: null)
            : widget.to != null
                ? countdownAnchorOf(widget.to!, clock: plugin.clock)
                : (duration: widget.duration, deadline: null);
    final r = remaining ?? _initialRemaining;
    // 首个 tick 之前的初值：与引擎一致地取整并使用显式分母。
    _parts = TimeParts.of(
      Duration(
        microseconds: widget.rounding.apply(r.inMicroseconds, plugin.interval),
      ),
      total ?? widget.total ?? r,
    );
    _rev.value++;
    _handle = plugin.add(CountdownOptions(
      duration: anchor.duration,
      deadline: anchor.deadline,
      total: total ?? widget.total,
      rounding: widget.rounding,
      onUpdate: (p) {
        _parts = p;
        _rev.value++;
        widget.onTick?.call(p);
      },
      onComplete: _onTaskComplete,
      // 事件转发到当前配置，替换回调不重置已有时间。
      threshold: widget.threshold,
      onThreshold: () => widget.onThreshold?.call(),
      onReady: () => widget.onReady?.call(),
      onStart: () => widget.onStart?.call(),
      onCancel: _onTaskCancel,
      onPause: () {
        if (!_quietPause) widget.onPause?.call();
      },
      onResume: () => widget.onResume?.call(),
    ));
    if (paused) {
      _quietPause = true;
      try {
        _handle!.pause();
      } finally {
        _quietPause = false;
      }
    }
    _attachController();
  }

  /// 插件变化：存活任务迁移到新插件，保留剩余时间、进度分母、暂停态与绝对截止；
  /// 没有存活任务（已完成或已取消）时只换插件，保留终态。
  void _migrate(Countdown next) {
    final old = _handle;
    _plugin = next;
    if (old == null || old.isDone) return;
    final paused = old.isPaused;
    _start(
      remaining: old.remaining,
      total: _parts.total,
      deadline: paused ? null : old.absoluteDeadline,
      paused: paused,
      silent: true,
    );
  }

  /// 结束后按显式时长、组件时长、当前截止时间的顺序重启。
  void _relaunch({Duration? duration}) {
    _start(remaining: duration ?? widget.duration);
  }

  /// 按组件当前配置（`to` / `duration`、`total`、取整方式）从头开始。
  void _restart() => _start();

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

  /// 绑定任务、重启动作及 runState。
  void _attachController() {
    final controller = widget.controller;
    if (controller == null || _handle == null) return;
    controller.attach(_handle!, relaunch: _relaunch, restart: _restart);
    controller.setRunState(_runStateNow());
  }

  /// 任务配置改变时重建；仅换插件时迁移；仅换控制器时保留时间、暂停状态和生命周期。
  @override
  void didUpdateWidget(CountdownBuilder old) {
    super.didUpdateWidget(old);
    final controllerChanged = widget.controller != old.controller;
    if (controllerChanged) old.controller?.detach(_handle);
    // 动态阈值单独更新，避免为配置变化重建任务。
    _handle?.updateThreshold(widget.threshold);
    final plugin = _resolvePlugin();
    if (widget.duration != old.duration ||
        widget.to != old.to ||
        widget.total != old.total ||
        widget.rounding != old.rounding) {
      _plugin = plugin;
      _start();
    } else if (!identical(plugin, _plugin)) {
      _migrate(plugin);
    } else if (controllerChanged) {
      _attachController();
    }
  }

  /// 仅解绑当前 State 的任务，再释放更新通知器。
  @override
  void dispose() {
    widget.controller?.detach(_handle);
    _handle?.cancel();
    _rev.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final listenableBuilder = widget.listenableBuilder;
    if (listenableBuilder != null) {
      return listenableBuilder(context, _partsListenable, widget.child);
    }
    return ValueListenableBuilder<int>(
      valueListenable: _rev,
      child: widget.child,
      builder: (ctx, _, child) => widget.builder!(ctx, _parts, child),
    );
  }
}

// CountdownController 定义在 controllers/countdown_controller.dart，经 plugin.dart 与 countman.dart 导出。
