import 'package:flutter/widgets.dart';

/// Registry of counter/countdown ids whose entrance transition has already
/// played once. Lives in the State of the nearest [CounterProvider] /
/// [CountdownProvider], so it survives while that provider (typically the
/// list's host page) is mounted and is released when the page is disposed —
/// giving "animate once per list lifetime" semantics.
///
/// 记录哪些 counter/countdown 的入场过渡已播放过一次的注册表。它存在于最近的
/// [CounterProvider] / [CountdownProvider] 的 State 中，因此在该 provider
/// （通常是列表的宿主页面）挂载期间存活，页面销毁时释放——从而实现「每个列表
/// 存活期内只滚一次」的语义。
class AnimateOnceRegistry {
  /// Ids that have already animated. A mutable set shared by identity — never
  /// diffed by value.
  ///
  /// 已经动画过的 id 集合。按 identity 共享的可变集合——从不按值比较。
  final Set<String> _seen = <String>{};

  /// Report a first-frame decision for [id] and record it.
  ///
  /// Returns `true` the first time [id] is seen (the caller SHOULD animate) and
  /// `false` on every later call (the caller should jump straight to the final
  /// value). Backed by [Set.add], which returns whether the element was newly
  /// added.
  ///
  /// 上报并记录 [id] 的首帧决策。
  ///
  /// 首次见到 [id] 时返回 `true`（调用方「应」播放动画），此后每次返回 `false`
  /// （调用方应直接跳到终值）。基于 [Set.add]，其返回值表示元素是否为新加入。
  ///
  /// @param id The stable id derived from the widget's key or an explicit value.
  ///
  ///   由 widget 的 key 或显式值派生出的稳定 id。
  ///
  /// @returns `true` if this is the first time [id] is seen, else `false`.
  ///
  ///   若为首次见到 [id] 返回 `true`，否则返回 `false`。
  bool shouldAnimate(String id) => _seen.add(id);

  /// Whether [id] has already animated (without recording anything).
  ///
  /// 查询 [id] 是否已经动画过（不记录任何内容）。
  ///
  /// @param id The stable id to query.
  ///
  ///   要查询的稳定 id。
  ///
  /// @returns `true` if [id] was already recorded as animated.
  ///
  ///   若 [id] 已被记录为已动画则返回 `true`。
  bool hasAnimated(String id) => _seen.contains(id);
}

/// Derive a stable, cross-rebuild id from a widget [key], for use as the
/// animate-once registry key.
///
/// Only [ValueKey] is accepted — its `value.toString()` is stable across
/// rebuilds when the value is (e.g. a data primary key). [UniqueKey],
/// [GlobalKey], and null keys are NOT stable across rebuilds and yield `null`,
/// which disables animate-once for that widget.
///
/// 从 widget 的 [key] 派生一个跨重建稳定的 id，用作 animate-once 注册表的键。
///
/// 只接受 [ValueKey]——当其 value 稳定（例如数据主键）时，`value.toString()`
/// 跨重建也稳定。[UniqueKey]、[GlobalKey] 和空 key 跨重建不稳定，返回 `null`，
/// 从而对该 widget 关闭 animate-once。
///
/// @param key The widget's key, or null.
///
///   widget 的 key，或为空。
///
/// @returns A stable string id, or `null` when [key] is not a [ValueKey].
///
///   稳定的字符串 id；当 [key] 不是 [ValueKey] 时返回 `null`。
String? stableOnceIdFromKey(Key? key) =>
    key is ValueKey ? '${key.value}' : null;

/// Carries an already-decided animate-once outcome down a subtree.
///
/// The FIRST widget that resolves an animate-once decision (the "entry" — the
/// outermost counter/countdown with a stable id, or an [AnimateOnce] wrapper)
/// records it in the [AnimateOnceRegistry] and inserts this scope. Every
/// descendant counter/countdown then simply obeys [skip] instead of resolving
/// (and recording) its own id — so multiple numbers inside one logical item
/// share a single decision and stay consistent.
///
/// 把已决定的 animate-once 结果沿子树向下传递。
///
/// 首个解析出 animate-once 决策的 widget（「入口」——最外层带稳定 id 的
/// counter/countdown，或 [AnimateOnce] 包装器）将其记录进 [AnimateOnceRegistry]
/// 并插入本 scope。之后每个后代 counter/countdown 只需遵从 [skip]，而不再各自
/// 解析（并记录）自己的 id——这样一个逻辑 item 内的多个数字共享同一个决策、保持
/// 一致。
class AnimateOnceScope extends InheritedWidget {
  const AnimateOnceScope({
    super.key,
    required this.skip,
    required super.child,
  });

  /// Whether descendants should skip their entrance transition (jump straight
  /// to the final value). Decided once by the entry widget.
  ///
  /// 后代是否应跳过入场过渡（直接到终值）。由入口 widget 决定一次。
  final bool skip;

  /// The nearest scope, read WITHOUT registering a dependency so it is safe to
  /// call from `initState` (the decision is a one-time read at mount).
  ///
  /// 最近的 scope，读取时不注册依赖，因此可在 `initState` 中安全调用（决策是挂载
  /// 时的一次性读取）。
  ///
  /// @param context The calling widget's build context.
  ///
  ///   调用方 widget 的 build context。
  ///
  /// @returns The nearest [AnimateOnceScope], or `null` when none is present.
  ///
  ///   最近的 [AnimateOnceScope]，若不存在则为 `null`。
  static AnimateOnceScope? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<AnimateOnceScope>();

  @override
  bool updateShouldNotify(AnimateOnceScope old) => skip != old.skip;
}

/// 一次 animate-once 解析的结果：是否参与、是否跳过入场、是否为入口。
///
/// 由 [resolveAnimateOnce] 产出，组件在挂载时保存，build 时用 [wrap] 把入口决策
/// 发布给后代。
class AnimateOnceDecision {
  const AnimateOnceDecision._({
    required this.participates,
    required this.skip,
    required this.entry,
  });

  /// 不参与 animate-once：每次挂载都播放入场动画。
  static const AnimateOnceDecision none = AnimateOnceDecision._(
    participates: false,
    skip: false,
    entry: false,
  );

  /// 本实例是否参与 animate-once。
  final bool participates;

  /// 参与时，入场过渡是否应跳过（直接显示终值）。
  final bool skip;

  /// 本实例是否为入口（自行解析决策而非继承祖先 [AnimateOnceScope]）。
  final bool entry;

  /// 参与且需要跳过入场时为 true，等价于 `participates && skip`。
  bool get shouldSkip => participates && skip;

  /// 入口实例把决策包成 [AnimateOnceScope] 发布给后代；其余实例原样返回 [child]。
  ///
  /// 示例：`return _once.wrap(result);`
  Widget wrap(Widget child) =>
      entry ? AnimateOnceScope(skip: skip, child: child) : child;
}

/// 已经打印过的 animate-once 警告键，保证每种问题只在 debug 下提示一次。
final Set<String> _warnedAnimateOnce = <String>{};

/// 测试用：清空已打印的 animate-once 警告记录，便于重复断言。
@visibleForTesting
void debugResetAnimateOnceWarnings() => _warnedAnimateOnce.clear();

/// 仅 debug 下、同一 [key] 只打印一次 [message]；release 下什么也不做。
void _warnAnimateOnceOnce(String key, String message) {
  assert(() {
    if (_warnedAnimateOnce.add(key)) debugPrint(message);
    return true;
  }());
}

/// 在组件挂载时解析一次 animate-once 决策，供 CounterBuilder、AnimatedCounter 等共用。
///
/// 规则：祖先 [AnimateOnceScope] 已决策则遵从（不解析、不记录自己的 id，保证同一
/// 条目内多个数字一致）；否则有效开关为 [widgetAnimateOnce] ?? [scopeAnimateOnce]
/// ?? false，开启时用 [id] 与 [registry] 解析并记录，成为入口。
///
/// 没有稳定 id（[id] 为空）或没有 Provider（[registry] 为空）时**不断言**，debug 下
/// 用 `debugPrint` 对每种 [owner] 只警告一次，并退化为每次都动画（返回 [AnimateOnceDecision.none]）。
///
/// 参数：[context] 为组件上下文（不注册依赖，可在 initState 调用）；[owner] 用于
/// 警告文案，例如 `'CounterBuilder'`。返回解析结果。
///
/// 示例：
/// ```dart
/// _once = resolveAnimateOnce(context,
///     widgetAnimateOnce: widget.animateOnce,
///     scopeAnimateOnce: scope?.animateOnce,
///     registry: scope?.once,
///     id: widget.onceId ?? stableOnceIdFromKey(widget.key),
///     owner: 'CounterBuilder');
/// ```
AnimateOnceDecision resolveAnimateOnce(
  BuildContext context, {
  required bool? widgetAnimateOnce,
  required bool? scopeAnimateOnce,
  required AnimateOnceRegistry? registry,
  required String? id,
  required String owner,
}) {
  final inherited = AnimateOnceScope.maybeOf(context);
  if (inherited != null) {
    return AnimateOnceDecision._(
      participates: true,
      skip: inherited.skip,
      entry: false,
    );
  }
  if (!(widgetAnimateOnce ?? scopeAnimateOnce ?? false)) {
    return AnimateOnceDecision.none;
  }
  if (id == null) {
    _warnAnimateOnceOnce(
      '$owner:no-id',
      '$owner.animateOnce 已开启，但没有稳定 id：请给组件加 ValueKey（例如 '
      'ValueKey(row.id)）或传 onceId。本组件退化为每次都播放入场动画。',
    );
    return AnimateOnceDecision.none;
  }
  if (registry == null) {
    _warnAnimateOnceOnce(
      '$owner:no-provider',
      '$owner.animateOnce 已开启，但上层没有 CounterProvider：animate-once 的登记表'
      '存在于 Provider 中。本组件退化为每次都播放入场动画。',
    );
    return AnimateOnceDecision.none;
  }
  // shouldAnimate 首次见到 id 时返回 true（应动画，不跳过）。
  return AnimateOnceDecision._(
    participates: true,
    skip: !registry.shouldAnimate(id),
    entry: true,
  );
}
