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
    this.controller,
    this.onTick,
    this.threshold,
    this.onThreshold,
    this.onReady,
    this.onStart,
    this.onCancel,
    this.onPause,
    this.onResume,
  });

  /// Called each tick with the elapsed [TimeParts] and the pass-through [child].
  /// Update rate is set by [Elapsed.interval] on the [plugin].
  ///
  /// 每 tick 调用，携带经过时间 [TimeParts] 和透传的 [child]。更新频率由 [plugin]
  /// 上的 [Elapsed.interval] 决定。
  final Widget Function(BuildContext context, TimeParts parts, Widget? child) builder;

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

  void _start() {
    _handle?.cancel();
    _handle = (widget.plugin ??
            _scopePlugin ??
            (widget.precise ? defaultElapsedMs : defaultElapsed))
        .add(ElapsedOptions(
      onUpdate: (p) {
        _parts = p;
        _rev.value++;
        widget.onTick?.call(p);
      },
      threshold: widget.threshold,
      onThreshold: widget.onThreshold,
      onReady: widget.onReady,
      onStart: widget.onStart,
      onCancel: widget.onCancel,
      onPause: widget.onPause,
      onResume: widget.onResume,
    ));
    widget.controller?.attach(_handle!);
  }

  @override
  void didUpdateWidget(ElapsedBuilder old) {
    super.didUpdateWidget(old);
    if (widget.plugin != old.plugin ||
        widget.precise != old.precise ||
        widget.controller != old.controller) {
      old.controller?.detach();
      _start();
    }
  }

  @override
  void dispose() {
    widget.controller?.detach();
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
