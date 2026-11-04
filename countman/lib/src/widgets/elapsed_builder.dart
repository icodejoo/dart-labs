import 'package:flutter/widgets.dart';
import 'package:countman/src/count_down/types.dart' show TimeParts;
import 'package:countman/src/elapsed/plugin.dart';
import 'package:countman/src/elapsed/types.dart';
import 'providers.dart';

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

/// 管理正计时任务及控制器归属。
class _ElapsedBuilderState extends State<ElapsedBuilder> {
  // Latest decomposed elapsed time (reused instance from the engine's onUpdate).
  TimeParts _parts = TimeParts.of(Duration.zero);
  // Bumped each tick to drive a rebuild (TimeParts is mutated in place).
  final ValueNotifier<int> _rev = ValueNotifier(0);
  ElapsedHandle? _handle;
  // Plugin inherited from the nearest ElapsedProvider (null if none).
  Elapsed? _scopePlugin;
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scopePlugin = CountmanScope.maybeOf<Elapsed>(context)?.plugin;
    // Start on first resolve, or re-anchor if the inherited group changed.
    if (!_initialized || scopePlugin != _scopePlugin) {
      _initialized = true;
      _scopePlugin = scopePlugin;
      _start();
    }
  }

  /// 当前生效的插件（显式传入 > provider 分组 > precise 默认组 > 默认组）。
  Elapsed get _plugin =>
      widget.plugin ??
      _scopePlugin ??
      (widget.precise ? defaultElapsedMs : defaultElapsed);

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

  /// 新建正计时任务，并恢复控制器的重启入口。[fromZero] 为 true（结束后重启）时
  /// 忽略 since / initial，从零开始，与存活任务 reset 清零的语义一致。
  void _start({bool fromZero = false}) {
    _handle?.cancel();
    final plugin = _plugin;
    _parts = fromZero
        ? TimeParts.of(Duration.zero)
        : TimeParts.of(_initialElapsed(plugin));
    _rev.value++;
    _handle = plugin.add(ElapsedOptions(
      since: fromZero ? null : widget.since,
      initial: fromZero ? null : widget.initial,
      limit: widget.limit,
      onComplete: () => widget.onComplete?.call(),
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
      onCancel: () => widget.onCancel?.call(),
      onPause: () => widget.onPause?.call(),
      onResume: () => widget.onResume?.call(),
    ));
    widget.controller?.attach(_handle!, relaunch: _relaunch);
  }

  /// 任务结束或取消后的重启入口：从零开始。
  void _relaunch() => _start(fromZero: true);

  /// 任务配置改变时重建，仅换控制器时保留时间、暂停状态和生命周期。
  @override
  void didUpdateWidget(ElapsedBuilder old) {
    super.didUpdateWidget(old);
    final controllerChanged = widget.controller != old.controller;
    if (controllerChanged) old.controller?.detach(_handle);
    // 动态阈值单独更新，避免为配置变化重建任务。
    _handle?.updateThreshold(widget.threshold);
    if (widget.plugin != old.plugin ||
        widget.precise != old.precise ||
        widget.since != old.since ||
        widget.initial != old.initial) {
      _start();
    } else {
      // 动态上限单独更新，保留已累计时间。
      if (widget.limit != old.limit) _handle?.updateLimit(widget.limit);
      if (controllerChanged && _handle != null) {
        widget.controller?.attach(_handle!, relaunch: _relaunch);
      }
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
