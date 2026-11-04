part of 'animated_counter.dart';

// ── 作用域接入 ────────────────────────────────────────────────────────────────

/// 与上层 [CounterProvider] 的协作：解析动画任务所在的 [Counter] 插件、
/// animate-once 决策，以及感知 MediaQuery 的减弱动画设置。
mixin _CounterScope<W extends _BaseAnimatedCounter> on State<W> {
  /// 本实例是否参与 animate-once。
  bool _oncePart = false;

  /// 参与时，入场过渡是否应跳过（直接显示终值）。
  bool _onceSkip = false;

  /// 本实例是否为 animate-once 的“入口”（自己解析决策而非继承），入口会在 build
  /// 里注入 [AnimateOnceScope]，让后代计数器共享同一决策。
  bool _onceEntry = false;

  /// 最近一次读到的 `MediaQuery.disableAnimations`；没有 MediaQuery 时为 null。
  bool? _mediaReduceMotion;

  /// 最近的 counter 作用域；不注册依赖，可在 initState 与异步回调里读取。
  CountmanScope<Counter>? get _counterScope =>
      context.getInheritedWidgetOfExactType<CountmanScope<Counter>>();

  /// 动画任务使用的插件：组件显式 plugin > 最近 CounterProvider 的 plugin > defaultCounter。
  ///
  /// 每次创建任务时现读，Provider 的 onGroupReady / onAllComplete 因而对本组件生效。
  Counter get _counterPlugin => resolvePlugin<Counter>(context,
      widgetPlugin: widget.plugin, fallback: () => defaultCounter);

  /// 当前是否应减弱动画：MediaQuery 优先，没有 MediaQuery 时读平台标志，
  /// 语义与 [reduceMotionOf] 一致，但可在 build 之外调用。
  bool get _reduceMotion => _mediaReduceMotion ?? reduceMotion;

  /// 在挂载时解析一次 animate-once 决策；继承优先。
  ///
  /// 规则见 [resolveAnimateOnce]：祖先 [AnimateOnceScope] 已决策则遵从，否则用自身
  /// ValueKey 派生的 id 与 Provider 的注册表解析并记录。没有稳定 id 或没有 Provider
  /// 时退化为每次都动画，debug 下只警告一次，不断言。
  void _resolveOnce() {
    final decision = resolveAnimateOnce(
      context,
      widgetAnimateOnce: widget.animateOnce,
      scopeAnimateOnce: _counterScope?.animateOnce,
      registry: _counterScope?.once,
      id: stableOnceIdFromKey(widget.key),
      owner: 'AnimatedCounter',
    );
    _oncePart = decision.participates;
    _onceSkip = decision.skip;
    _onceEntry = decision.entry;
  }

  /// 入口实例把决策发布给后代；其余实例原样返回。
  Widget _wrapOnce(Widget child) =>
      _onceEntry ? AnimateOnceScope(skip: _onceSkip, child: child) : child;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 注册对 MediaQuery 的依赖，系统减弱动画设置变化时随之更新。
    _mediaReduceMotion = MediaQuery.maybeDisableAnimationsOf(context);
  }
}
