import 'package:flutter/widgets.dart';
import 'package:countman/src/counter/plugin.dart';
import 'package:countman/src/counter/types.dart';

import 'animate_once.dart';
import 'providers.dart';
import 'reduce_motion.dart';

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
class CounterBuilder extends StatefulWidget {
  const CounterBuilder({
    super.key,
    this.from,
    required this.to,
    this.duration = const Duration(milliseconds: 1000),
    this.curve = Curves.easeOut,
    this.allowNegative = false,
    this.plugin,
    this.controller,
    required this.builder,
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
  });

  final double? from;
  final double to;
  final Duration duration;
  final Curve curve;

  /// When `false` (default) the animated value never goes below 0. Set `true`
  /// to count through / to negative numbers.
  final bool allowNegative;

  /// Optional [Counter] group for isolation/grouping. Defaults to the shared
  /// [defaultCounter] instance (equivalent to the top-level `counter()`).
  final Counter? plugin;

  /// Optional controller for imperative retarget/cancel and value read-out.
  final CounterValueController? controller;

  /// Called every frame with the current animated value and the cached [child].
  final Widget Function(BuildContext context, double value, Widget? child)
      builder;

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

/// 管理显示值、任务归属及显式重启动画。
class _CounterBuilderState extends State<CounterBuilder> {
  late final ValueNotifier<double> _value;
  CounterHandle? _handle;

  // ── animate-once resolved state (decided once in initState) ──────────────
  // Whether this instance participates in animate-once at all.
  //
  // 本实例是否参与 animate-once。
  bool _oncePart = false;
  // When participating, whether the entrance transition should be skipped.
  //
  // 参与时，是否应跳过入场过渡。
  bool _onceSkip = false;
  // Whether this instance is the animate-once "entry" (resolved its own
  // decision rather than inheriting), so build() should inject an
  // [AnimateOnceScope] for its descendants to inherit.
  //
  // 本实例是否为 animate-once「入口」（自行解析决策而非继承），因此 build()
  // 应注入 [AnimateOnceScope] 供其后代继承。
  bool _onceEntry = false;

  /// 初始化显示值，跳过入场动画时也保留控制器重启入口。
  @override
  void initState() {
    super.initState();
    _value = ValueNotifier(widget.from ?? 0);
    _resolveOnce();
    // Skip the entrance animation and show the final value immediately when
    // this id has already animated under the provider.
    //
    // 当该 id 已在 provider 下动画过时，跳过入场动画，立即显示终值。
    if (_oncePart && _onceSkip) {
      _value.value = widget.to;
      _attachController();
    } else {
      _addTask(from: widget.from);
    }
  }

  // The nearest counter scope, read WITHOUT registering a dependency so it is
  // safe to call from initState (we only need a one-time read at mount).
  //
  // 最近的 counter scope，读取时不注册依赖，因此可在 initState 中安全调用
  // （我们只需在挂载时一次性读取）。
  CountmanScope<Counter>? get _scope =>
      context.getInheritedWidgetOfExactType<CountmanScope<Counter>>();

  // Effective animate-once: widget override > provider default > false.
  //
  // 实际 animate-once：widget 覆盖 > provider 默认 > false。
  bool get _effAnimateOnce =>
      widget.animateOnce ?? _scope?.animateOnce ?? false;

  // Stable id: explicit onceId, else derived from a ValueKey on this widget.
  //
  // 稳定 id：显式 onceId，否则从本 widget 的 ValueKey 派生。
  String? get _onceId => widget.onceId ?? stableOnceIdFromKey(widget.key);

  // Resolve the animate-once decision exactly once at mount. Inheritance wins:
  // if an ancestor [AnimateOnceScope] already decided, obey it (do NOT resolve
  // or record our own id — keeps multiple numbers in one item consistent).
  // Otherwise become the entry: resolve from our id + registry and record it.
  //
  // 在挂载时解析一次 animate-once 决策。继承优先：若祖先 [AnimateOnceScope] 已
  // 决策，则遵从（不解析、不记录自己的 id——保证一个 item 内多个数字一致）。
  // 否则成为入口：用自身 id + 注册表解析并记录。
  void _resolveOnce() {
    final inherited = AnimateOnceScope.maybeOf(context);
    if (inherited != null) {
      _oncePart = true;
      _onceSkip = inherited.skip;
      _onceEntry = false;
      return;
    }
    if (!_effAnimateOnce) return;
    final id = _onceId;
    assert(
      id != null,
      'CounterBuilder.animateOnce is enabled but no stable id is available. '
      'Provide a ValueKey (e.g. ValueKey(row.id)) or onceId; animate-once is '
      'disabled for this widget.',
    );
    if (id == null) return;
    final reg = _scope?.once;
    if (reg == null) return; // no provider → degrade to always-animate
    _oncePart = true;
    _onceEntry = true;
    // shouldAnimate returns true on first sight (→ animate, don't skip).
    _onceSkip = !reg.shouldAnimate(id);
  }

  /// 从 [from] 新建任务；可覆盖目标、时长与曲线，省略时使用当前组件配置。
  void _addTask({
    required double? from,
    double? to,
    Duration? duration,
    Curve? curve,
  }) {
    _handle?.cancel();
    _handle = (widget.plugin ?? defaultCounter).add(CounterOptions(
      from: from,
      to: to ?? widget.to,
      duration: motionDuration(duration ?? widget.duration),
      curve: curve ?? widget.curve,
      allowNegative: widget.allowNegative,
      onUpdate: (v) {
        _value.value = v;
        widget.controller?.latestValue = v;
        widget.onUpdate?.call(v);
      },
      onComplete: (v) => widget.onComplete?.call(v),
      onReady: () => widget.onReady?.call(),
      onStart: () => widget.onStart?.call(),
      onCancel: () => widget.onCancel?.call(),
    ));
    _attachController();
  }

  /// 从当前显示值执行显式更新，绕过仅入场一次的限制。
  void _relaunch({required double to, Duration? duration, Curve? curve}) {
    _addTask(from: _value.value, to: to, duration: duration, curve: curve);
  }

  /// 绑定任务及重启动作，并立即同步当前显示值。
  void _attachController() {
    final controller = widget.controller;
    if (controller == null) return;
    // 跳过入场时使用已取消的无回调任务作为归属凭据，不触发组件生命周期。
    _handle ??= (widget.plugin ?? defaultCounter).add(CounterOptions(
      from: _value.value,
      to: _value.value,
      duration: Duration.zero,
    ))
      ..cancel();
    controller.attach(_handle!, relaunch: _relaunch);
    controller.latestValue = _value.value;
  }

  /// 配置变化按原策略更新任务，仅替换控制器时保留任务与生命周期。
  @override
  void didUpdateWidget(CounterBuilder old) {
    super.didUpdateWidget(old);
    final controllerChanged = widget.controller != old.controller;
    if (controllerChanged) old.controller?.detach(_handle);
    if (widget.to != old.to ||
        widget.duration != old.duration ||
        widget.curve != old.curve ||
        widget.plugin != old.plugin ||
        widget.allowNegative != old.allowNegative) {
      if (_oncePart) {
        // Already participating in animate-once → any later value change jumps
        // straight to the new value, no animation (entrance plays only once).
        //
        // 已参与 animate-once → 之后任何值变直接跳到新值，不播动画（入场只播一次）。
        _handle?.cancel();
        _value.value = widget.to;
        _attachController();
      } else {
        // Always create a fresh task from the current displayed value so
        // retargeting works even after the previous animation finished.
        _addTask(from: _value.value);
      }
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
    // RepaintBoundary isolates this widget's repaint from its siblings.
    // Without it a single dirty counter repaints the whole ancestor layer.
    final inner = ValueListenableBuilder<double>(
      valueListenable: _value,
      child: widget.child,
      builder: (ctx, value, child) => widget.builder(
        ctx,
        widget.valueTransform != null ? widget.valueTransform!(value) : value,
        child,
      ),
    );
    Widget result =
        widget.repaintBoundary ? RepaintBoundary(child: inner) : inner;
    // As the animate-once entry, publish the decision so descendant
    // counters/countdowns inherit it instead of resolving their own id.
    //
    // 作为 animate-once 入口，发布决策，供后代 counter/countdown 继承，
    // 而不再解析各自的 id。
    if (_onceEntry) {
      result = AnimateOnceScope(skip: _onceSkip, child: result);
    }
    return result;
  }
}
