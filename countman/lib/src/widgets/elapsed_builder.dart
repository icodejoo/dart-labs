import 'package:flutter/widgets.dart';
import 'package:countman/src/core/run_state.dart';
import 'package:countman/src/count_down/types.dart' show TimeParts;
import 'package:countman/src/elapsed/plugin.dart';
import 'package:countman/src/elapsed/types.dart';
import 'scope_resolution.dart';

/// Low-level open-ended elapsed-time (stopwatch) widget that exposes the
/// current [TimeParts] via a [builder] — the elapsed counterpart to
/// [CountdownBuilder]. Starts at zero on mount and counts up indefinitely until
/// removed or [ElapsedController.cancel]led.
///
/// ```dart
/// ElapsedBuilder(
///   builder: (context, parts, child) => Text(CountdownFormat.hms(parts)),
/// )
/// ```
///
/// 底层的开放式经过时间（秒表）组件，通过 [builder] 暴露当前 [TimeParts]——
/// [CountdownBuilder] 的经过时间对应物。挂载时从零开始，无限递增，直到被移除或
/// [ElapsedController.cancel]。
class ElapsedBuilder extends StatefulWidget {
  /// Creates an [ElapsedBuilder].
  ///
  /// 创建一个 [ElapsedBuilder]。
  const ElapsedBuilder({
    super.key,
    required this.builder,
    this.child,
    this.plugin,
    this.precise = false,
    this.since,
    this.initial,
    this.limit,
    this.onComplete,
    this.controller,
    this.onTick,
    this.threshold,
    this.onThreshold,
    this.onReady,
    this.onStart,
    this.onCancel,
    this.onPause,
    this.onResume,
  }) : assert(
         since == null || initial == null,
         'ElapsedBuilder: provide at most one of since or initial.',
       );

  /// Called each tick with the elapsed [TimeParts] and the pass-through [child].
  /// Update rate is set by [Elapsed.interval] on the [plugin].
  ///
  /// 每 tick 调用，携带经过时间 [TimeParts] 和透传的 [child]。更新频率由 [plugin]
  /// 上的 [Elapsed.interval] 决定。
  final Widget Function(BuildContext context, TimeParts parts, Widget? child)
      builder;

  /// Value-independent subtree passed through to [builder] unchanged each tick,
  /// so the per-tick rebuild can skip it (standard `AnimatedBuilder` child).
  ///
  /// 不依赖值的子树，每 tick 原样透传给 [builder]，使每 tick 重建跳过它。
  final Widget? child;

  /// Optional [Elapsed] group. Defaults to the nearest [ElapsedProvider]'s
  /// group, then [defaultElapsed].
  ///
  /// 可选的 [Elapsed] 分组。默认取最近 [ElapsedProvider] 的分组，再到
  /// [defaultElapsed]。
  final Elapsed? plugin;

  /// When true and no [plugin] is supplied, drives this stopwatch on the shared
  /// precise ([defaultElapsedMs], `interval: 0`) group so sub-second formatters
  /// update every frame. Ignored when [plugin] is set.
  ///
  /// 为 true 且未提供 [plugin] 时，用共享的精确组（[defaultElapsedMs]，
  /// `interval: 0`）驱动本秒表，使亚秒格式化器每帧更新。设置了 [plugin] 时忽略。
  final bool precise;

  /// 墙钟锚定的起点：已经过 = 当前墙钟 − [since]，例如“下单已 3 分钟”。
  /// 与 [initial] 互斥；详见 [ElapsedOptions.since]。改变后会重建任务。
  final DateTime? since;

  /// 单调钟锚定的起始偏移，例如恢复上次的秒表。与 [since] 互斥；详见
  /// [ElapsedOptions.initial]。改变后会重建任务。
  final Duration? initial;

  /// 上限：到达时发出值为 [limit] 的最后一次更新、触发 [onComplete] 并结束任务。
  /// 结束后 `controller.reset()` 会从零重新开始。修改它不会重建任务，已累计时间保留。
  final Duration? limit;

  /// 累计时间到达 [limit] 时调用一次。
  final void Function()? onComplete;

  /// Optional controller for pause / resume / reset.
  ///
  /// 可选的 pause / resume / reset 控制器。
  final ElapsedController? controller;

  /// Called on every tick with the current elapsed [TimeParts], for side
  /// effects that don't rebuild UI.
  ///
  /// 每 tick 以当前经过时间 [TimeParts] 回调，用于不重建 UI 的副作用。
  final void Function(TimeParts parts)? onTick;

  /// When elapsed time first reaches or exceeds this, [onThreshold] fires once.
  ///
  /// 当经过时间首次达到或超过此值时，[onThreshold] 触发一次。
  final Duration? threshold;

  /// Called once when elapsed time crosses [threshold].
  ///
  /// 当经过时间越过 [threshold] 时调用一次。
  final void Function()? onThreshold;

  /// Lifecycle callbacks: enqueued / first frame / cancelled / paused / resumed.
  ///
  /// 生命周期回调：入队 / 首帧 / 取消 / 暂停 / 恢复。
  final VoidCallback? onReady;
  final VoidCallback? onStart;
  final VoidCallback? onCancel;
  final VoidCallback? onPause;
  final VoidCallback? onResume;

  @override
  State<ElapsedBuilder> createState() => _ElapsedBuilderState();
}

/// 管理正计时任务、插件迁移、运行状态及控制器归属。
class _ElapsedBuilderState extends State<ElapsedBuilder> {
  // Latest decomposed elapsed time (reused instance from the engine's onUpdate).
  TimeParts _parts = TimeParts.of(Duration.zero);
  // Bumped each tick to drive a rebuild (TimeParts is mutated in place).
  final ValueNotifier<int> _rev = ValueNotifier(0);

  /// 当前任务句柄。
  ElapsedHandle? _handle;

  /// 当前生效的插件（显式 > Provider > precise 默认组 > 默认组）。
  late Elapsed _plugin;

  /// 首次 didChangeDependencies 才创建任务，保证能读到作用域。
  bool _started = false;

  /// 无存活任务时的终态：到达 limit 为 completed，其余为 idle。
  CountmanRunState _doneState = CountmanRunState.idle;

  /// 为 true 时旧任务被取消不把 runState 写成 idle（紧接着会有新任务）。
  bool _keepRunState = false;

  /// 为 true 时旧任务被取消不触发用户的 onCancel（插件迁移，不是真的取消）。
  bool _quietCancel = false;

  /// 为 true 时不转发用户的 onPause（迁移时为还原暂停态而暂停新任务）。
  bool _quietPause = false;

  /// 解析当前应使用的插件，并向作用域注册依赖。
  Elapsed _resolvePlugin() => resolvePluginDependent<Elapsed>(context,
      widgetPlugin: widget.plugin,
      fallback: () => widget.precise ? defaultElapsedMs : defaultElapsed);

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

  /// 任务创建时的累计时间（钳到 limit），用于首个 tick 之前的显示。
  Duration _initialElapsed(Elapsed plugin) {
    final since = widget.since;
    var micros = since != null
        ? plugin.clock.wallMicros() - since.microsecondsSinceEpoch
        : widget.initial?.inMicroseconds ?? 0;
    final limit = Elapsed.limitMicrosOf(widget.limit);
    if (limit != null && micros > limit) micros = limit;
    return Duration(microseconds: micros < 0 ? 0 : micros);
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

  /// 到达上限的回调：先更新 runState 为 completed，再转发用户 onComplete。
  void _onTaskComplete() {
    _doneState = CountmanRunState.completed;
    widget.controller?.setRunState(CountmanRunState.completed);
    widget.onComplete?.call();
  }

  /// 新建正计时任务，并恢复控制器的重启入口。[fromZero] 为 true（结束后重启）时
  /// 忽略 since / initial，从零开始，与存活任务 reset 清零的语义一致。
  /// 迁移时传入 [resumeAt]（接着已经过的时长走）、[adoptLapsFrom]（接管圈速）、
  /// [paused]（保持暂停）与 [silent]（旧任务静默取消）。
  void _start({
    bool fromZero = false,
    Duration? resumeAt,
    ElapsedHandle? adoptLapsFrom,
    bool paused = false,
    bool silent = false,
  }) {
    _cancelCurrent(silent: silent);
    _doneState = CountmanRunState.idle;
    final plugin = _plugin;
    final Duration shown;
    if (fromZero) {
      shown = Duration.zero;
    } else if (resumeAt != null) {
      shown = resumeAt;
    } else {
      shown = _initialElapsed(plugin);
    }
    _parts = TimeParts.of(shown);
    _rev.value++;
    final useConfigStart = !fromZero && resumeAt == null;
    _handle = plugin.add(ElapsedOptions(
      since: useConfigStart ? widget.since : null,
      initial: fromZero
          ? null
          : (resumeAt ?? widget.initial),
      limit: widget.limit,
      onComplete: _onTaskComplete,
      onUpdate: (p) {
        _parts = p;
        _rev.value++;
        widget.onTick?.call(p);
      },
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
    if (adoptLapsFrom != null) _handle!.adoptLaps(adoptLapsFrom);
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

  /// 插件变化：存活任务迁移到新插件，保留已经过时长、圈速与暂停态；
  /// 没有存活任务（到达上限或已取消）时只换插件，保留终态与圈速。
  void _migrate(Elapsed next) {
    final old = _handle;
    _plugin = next;
    if (old == null || old.isDone) return;
    _start(
      resumeAt: old.elapsed,
      adoptLapsFrom: old,
      paused: old.isPaused,
      silent: true,
    );
  }

  /// 任务结束或取消后的重启入口：从零开始。
  void _relaunch() => _start(fromZero: true);

  /// 按组件当前配置（`since` / `initial` 起点、`limit`）从头开始。
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
  void didUpdateWidget(ElapsedBuilder old) {
    super.didUpdateWidget(old);
    final controllerChanged = widget.controller != old.controller;
    if (controllerChanged) old.controller?.detach(_handle);
    // 动态阈值单独更新，避免为配置变化重建任务。
    _handle?.updateThreshold(widget.threshold);
    final plugin = _resolvePlugin();
    if (widget.since != old.since || widget.initial != old.initial) {
      _plugin = plugin;
      _start();
      return;
    }
    // 动态上限单独更新，保留已累计时间。
    if (widget.limit != old.limit) _handle?.updateLimit(widget.limit);
    if (!identical(plugin, _plugin)) {
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
    return ValueListenableBuilder<int>(
      valueListenable: _rev,
      child: widget.child,
      builder: (ctx, _, child) => widget.builder(ctx, _parts, child),
    );
  }
}
