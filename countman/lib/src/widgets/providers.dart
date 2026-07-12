import 'package:flutter/widgets.dart';

import 'package:countman/src/core/ticker.dart';
import 'package:countman/src/counter/plugin.dart';
import 'package:countman/src/count_down/plugin.dart';
import 'package:countman/src/count_down/types.dart' show DurationFormatter;
import 'package:countman/src/elapsed/plugin.dart';

import 'animate_once.dart';
import 'text_counter.dart' show TextCounterStyle;
import 'text_countdown.dart' show TextCountdownStyle;
import 'text_elapsed.dart' show TextElapsedStyle;
import 'ring_style.dart' show RingCounterStyle, RingCountdownStyle;
import 'bar_style.dart' show BarCounterStyle, BarCountdownStyle;
import 'dial_countdown.dart' show DialCountdownStyle;
import 'card_countdown.dart' show CardCountdownStyle;
import 'odometer_counter.dart' show OdometerCounterStyle;

/// Shared inherited scope carrying the default configuration a
/// [CounterProvider] / [CountdownProvider] / [ElapsedProvider] hands down to
/// descendant countman display widgets.
///
/// Generic over the plugin type [P] ([Counter] / [Countdown] / [Elapsed]) so
/// each family looks up only its own scope. Every field is nullable: a widget
/// resolves each value in the order **widget property > provider > default**.
class CountmanScope<P> extends InheritedWidget {
  const CountmanScope({
    super.key,
    required this.plugin,
    required this.textStyle,
    required this.color,
    required this.trackColor,
    required this.duration,
    required this.curve,
    required this.allowNegative,
    required this.repaintBoundary,
    this.formatter,
    this.animateOnce,
    this.once,
    this.textCounterStyle,
    this.textCountdownStyle,
    this.textElapsedStyle,
    this.ringCounterStyle,
    this.ringCountdownStyle,
    this.barCounterStyle,
    this.barCountdownStyle,
    this.dialCountdownStyle,
    this.cardCountdownStyle,
    this.odometerCounterStyle,
    required super.child,
  });

  /// The group all descendants share when they don't name their own.
  final P? plugin;

  /// Default text style for text-based descendants.
  final TextStyle? textStyle;

  /// Default fill/arc color for ring/bar descendants.
  final Color? color;

  /// Default track color for ring/bar descendants.
  final Color? trackColor;

  /// Default animation duration (counter family).
  final Duration? duration;

  /// Default easing curve (counter family).
  final Curve? curve;

  /// Default `allowNegative` (counter family).
  final bool? allowNegative;

  /// Default `repaintBoundary` for descendants that support it.
  final bool? repaintBoundary;

  /// Default duration formatter for countdown/elapsed text descendants
  /// (null for the counter family).
  ///
  /// 倒计时/经过时间文本后代的默认时长格式化器（counter 家族为 null）。
  final DurationFormatter? formatter;

  /// Default `animateOnce` for descendants (see [CounterProvider.animateOnce]).
  ///
  /// 后代的 `animateOnce` 默认值（见 [CounterProvider.animateOnce]）。
  final bool? animateOnce;

  /// Shared animate-once registry; identity-stable, excluded from
  /// [updateShouldNotify].
  ///
  /// 共享的 animate-once 注册表；identity 稳定，排除在 [updateShouldNotify] 外。
  final AnimateOnceRegistry? once;

  /// Default per-component styles a descendant merges under its own `style`.
  ///
  /// 后代在自身 `style` 之下合并的各组件默认样式。
  final TextCounterStyle? textCounterStyle;
  final TextCountdownStyle? textCountdownStyle;
  final TextElapsedStyle? textElapsedStyle;
  final RingCounterStyle? ringCounterStyle;
  final RingCountdownStyle? ringCountdownStyle;
  final BarCounterStyle? barCounterStyle;
  final BarCountdownStyle? barCountdownStyle;
  final DialCountdownStyle? dialCountdownStyle;
  final CardCountdownStyle? cardCountdownStyle;
  final OdometerCounterStyle? odometerCounterStyle;

  /// The nearest scope of plugin type [P], or null when there is none.
  static CountmanScope<P>? maybeOf<P>(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<CountmanScope<P>>();

  @override
  bool updateShouldNotify(CountmanScope<P> old) =>
      plugin != old.plugin ||
      textStyle != old.textStyle ||
      color != old.color ||
      trackColor != old.trackColor ||
      duration != old.duration ||
      curve != old.curve ||
      allowNegative != old.allowNegative ||
      repaintBoundary != old.repaintBoundary ||
      formatter != old.formatter ||
      animateOnce != old.animateOnce ||
      textCounterStyle != old.textCounterStyle ||
      textCountdownStyle != old.textCountdownStyle ||
      textElapsedStyle != old.textElapsedStyle ||
      ringCounterStyle != old.ringCounterStyle ||
      ringCountdownStyle != old.ringCountdownStyle ||
      barCounterStyle != old.barCounterStyle ||
      barCountdownStyle != old.barCountdownStyle ||
      dialCountdownStyle != old.dialCountdownStyle ||
      cardCountdownStyle != old.cardCountdownStyle ||
      odometerCounterStyle != old.odometerCounterStyle;
  // `once` intentionally excluded: mutable identity-stable registry.
}

/// Base state that owns (or borrows) a plugin and wires the group-level
/// [onGroupReady] / [onAllComplete] callbacks onto it. Concrete providers
/// implement [createPlugin] and [buildScope].
abstract class _ProviderStateBase<W extends StatefulWidget, P> extends State<W> {
  // Lazily created when this provider must own a plugin (group callbacks set
  // but no external plugin supplied). Cached for the provider's lifetime.
  P? _owned;

  // animate-once registry, created once and living for this provider's
  // (= host page's) lifetime, so scrolled-out/in descendants share it.
  //
  // animate-once 注册表，只创建一次并存活于本 provider（= 宿主页面）的生命周期，
  // 使滚出/滚入的后代共享它。
  final AnimateOnceRegistry once = AnimateOnceRegistry();

  /// The external plugin the widget was given, if any.
  P? get widgetPlugin;

  /// Whether the widget wants group-level callbacks (forces plugin ownership).
  bool get wantsGroupCallbacks;

  /// Creates and registers a fresh owned plugin.
  P createPlugin();

  /// Attaches/clears the group callbacks on [plugin].
  void wire(P? plugin, {required bool clear});

  /// The effective plugin: the external one, else the owned one (may be null).
  P? get effectivePlugin => widgetPlugin ?? _owned;

  @override
  void initState() {
    super.initState();
    if (widgetPlugin == null && wantsGroupCallbacks) {
      _owned = createPlugin();
    }
    wire(effectivePlugin, clear: false);
  }

  @override
  void dispose() {
    wire(effectivePlugin, clear: true);
    super.dispose();
  }
}

// ── Counter ─────────────────────────────────────────────────────────

/// Supplies default configuration and an optional shared [Counter] group to
/// every counter display widget below it.
///
/// ```dart
/// CounterProvider(
///   duration: const Duration(milliseconds: 800),
///   textStyle: const TextStyle(fontSize: 28),
///   child: Column(children: [TextCounter(to: 100), RingCounter(to: 50)]),
/// )
/// ```
class CounterProvider extends StatefulWidget {
  const CounterProvider({
    super.key,
    this.plugin,
    this.textStyle,
    this.color,
    this.trackColor,
    this.duration,
    this.curve,
    this.allowNegative,
    this.repaintBoundary,
    this.animateOnce,
    this.textCounterStyle,
    this.ringCounterStyle,
    this.barCounterStyle,
    this.odometerCounterStyle,
    this.onGroupReady,
    this.onAllComplete,
    required this.child,
  });

  final Counter? plugin;
  final TextStyle? textStyle;
  final Color? color;
  final Color? trackColor;
  final Duration? duration;
  final Curve? curve;
  final bool? allowNegative;
  final bool? repaintBoundary;

  /// When `true`, descendant counter widgets carrying a stable [ValueKey]
  /// play their entrance animation only the first time that key is seen; on
  /// later rebuilds (e.g. scrolled back into a lazy list) they jump straight
  /// to the final value. A widget's own `animateOnce` overrides this.
  ///
  /// 为 `true` 时，携带稳定 [ValueKey] 的后代 counter widget 只在该 key 首次
  /// 出现时播放入场动画；之后重建（例如滚回懒加载列表）直接跳到终值。widget
  /// 自身的 `animateOnce` 会覆盖此值。
  final bool? animateOnce;

  /// Fired when the group goes idle → active (its first task is enqueued).
  final VoidCallback? onGroupReady;

  /// Fired when the group goes active → idle (its last task leaves).
  final VoidCallback? onAllComplete;

  /// Default per-component styles handed down to counter descendants.
  ///
  /// 下发给向上计数后代的各组件默认样式。
  final TextCounterStyle? textCounterStyle;
  final RingCounterStyle? ringCounterStyle;
  final BarCounterStyle? barCounterStyle;
  final OdometerCounterStyle? odometerCounterStyle;

  final Widget child;

  @override
  State<CounterProvider> createState() => _CounterProviderState();
}

class _CounterProviderState extends _ProviderStateBase<CounterProvider, Counter> {
  @override
  Counter? get widgetPlugin => widget.plugin;

  @override
  bool get wantsGroupCallbacks =>
      widget.onGroupReady != null || widget.onAllComplete != null;

  @override
  Counter createPlugin() {
    final p = Counter();
    Countman.use(p);
    return p;
  }

  @override
  void wire(Counter? plugin, {required bool clear}) {
    if (plugin == null) return;
    plugin.onFirstEnqueued = clear ? null : widget.onGroupReady;
    plugin.onQueueDrained = clear ? null : widget.onAllComplete;
  }

  @override
  Widget build(BuildContext context) => CountmanScope<Counter>(
        plugin: effectivePlugin,
        textStyle: widget.textStyle,
        color: widget.color,
        trackColor: widget.trackColor,
        duration: widget.duration,
        curve: widget.curve,
        allowNegative: widget.allowNegative,
        repaintBoundary: widget.repaintBoundary,
        animateOnce: widget.animateOnce,
        once: once,
        textCounterStyle: widget.textCounterStyle,
        ringCounterStyle: widget.ringCounterStyle,
        barCounterStyle: widget.barCounterStyle,
        odometerCounterStyle: widget.odometerCounterStyle,
        child: widget.child,
      );
}

// ── Countdown ───────────────────────────────────────────────────────

/// Supplies default configuration and an optional shared [Countdown] group to
/// every countdown display widget below it.
class CountdownProvider extends StatefulWidget {
  const CountdownProvider({
    super.key,
    this.plugin,
    this.textStyle,
    this.color,
    this.trackColor,
    this.repaintBoundary,
    this.formatter,
    this.animateOnce,
    this.textCountdownStyle,
    this.ringCountdownStyle,
    this.barCountdownStyle,
    this.dialCountdownStyle,
    this.cardCountdownStyle,
    this.onGroupReady,
    this.onAllComplete,
    required this.child,
  });

  final Countdown? plugin;
  final TextStyle? textStyle;
  final Color? color;
  final Color? trackColor;
  final bool? repaintBoundary;

  /// Default duration formatter handed down to [TextCountdown] descendants
  /// (each may still override with its own `formatter`).
  ///
  /// 下发给 [TextCountdown] 后代的默认时长格式化器（每个仍可用自身 `formatter`
  /// 覆盖）。
  final DurationFormatter? formatter;

  /// When `true`, descendant countdown widgets carrying a stable [ValueKey]
  /// play their entrance transition only the first time that key is seen; on
  /// later rebuilds they show the current remaining value with no entrance
  /// transition. A widget's own `animateOnce` overrides this.
  ///
  /// 为 `true` 时，携带稳定 [ValueKey] 的后代 countdown widget 只在该 key 首次
  /// 出现时播放入场过渡；之后重建直接显示当前剩余值、无入场过渡。widget 自身的
  /// `animateOnce` 会覆盖此值。
  final bool? animateOnce;

  /// Fired when the group goes idle → active (its first task is enqueued).
  final VoidCallback? onGroupReady;

  /// Fired when the group goes active → idle (its last task leaves).
  final VoidCallback? onAllComplete;

  /// Default per-component styles handed down to countdown descendants.
  ///
  /// 下发给倒计时后代的各组件默认样式。
  final TextCountdownStyle? textCountdownStyle;
  final RingCountdownStyle? ringCountdownStyle;
  final BarCountdownStyle? barCountdownStyle;
  final DialCountdownStyle? dialCountdownStyle;
  final CardCountdownStyle? cardCountdownStyle;

  final Widget child;

  @override
  State<CountdownProvider> createState() => _CountdownProviderState();
}

class _CountdownProviderState extends _ProviderStateBase<CountdownProvider, Countdown> {
  @override
  Countdown? get widgetPlugin => widget.plugin;

  @override
  bool get wantsGroupCallbacks =>
      widget.onGroupReady != null || widget.onAllComplete != null;

  @override
  Countdown createPlugin() {
    final p = Countdown();
    Countman.use(p);
    return p;
  }

  @override
  void wire(Countdown? plugin, {required bool clear}) {
    if (plugin == null) return;
    plugin.onFirstEnqueued = clear ? null : widget.onGroupReady;
    plugin.onQueueDrained = clear ? null : widget.onAllComplete;
  }

  @override
  Widget build(BuildContext context) => CountmanScope<Countdown>(
        plugin: effectivePlugin,
        textStyle: widget.textStyle,
        color: widget.color,
        trackColor: widget.trackColor,
        duration: null,
        curve: null,
        allowNegative: null,
        repaintBoundary: widget.repaintBoundary,
        formatter: widget.formatter,
        animateOnce: widget.animateOnce,
        once: once,
        textCountdownStyle: widget.textCountdownStyle,
        ringCountdownStyle: widget.ringCountdownStyle,
        barCountdownStyle: widget.barCountdownStyle,
        dialCountdownStyle: widget.dialCountdownStyle,
        cardCountdownStyle: widget.cardCountdownStyle,
        child: widget.child,
      );
}

// ── Elapsed ─────────────────────────────────────────────────────────

/// Supplies default configuration and an optional shared [Elapsed] group to
/// every elapsed-time display widget below it.
class ElapsedProvider extends StatefulWidget {
  const ElapsedProvider({
    super.key,
    this.plugin,
    this.textStyle,
    this.textElapsedStyle,
    this.formatter,
    this.onGroupReady,
    this.onAllComplete,
    required this.child,
  });

  final Elapsed? plugin;
  final TextStyle? textStyle;

  /// Default [TextElapsed] style handed down to elapsed descendants.
  ///
  /// 下发给经过时间后代的默认 [TextElapsed] 样式。
  final TextElapsedStyle? textElapsedStyle;

  /// Default duration formatter handed down to [TextElapsed] descendants
  /// (each may still override with its own `formatter`).
  ///
  /// 下发给 [TextElapsed] 后代的默认时长格式化器（每个仍可用自身 `formatter` 覆盖）。
  final DurationFormatter? formatter;

  /// Fired when the group goes idle → active (its first task is enqueued).
  final VoidCallback? onGroupReady;

  /// Fired when the group goes active → idle (its last task leaves).
  final VoidCallback? onAllComplete;

  final Widget child;

  @override
  State<ElapsedProvider> createState() => _ElapsedProviderState();
}

class _ElapsedProviderState extends _ProviderStateBase<ElapsedProvider, Elapsed> {
  @override
  Elapsed? get widgetPlugin => widget.plugin;

  @override
  bool get wantsGroupCallbacks =>
      widget.onGroupReady != null || widget.onAllComplete != null;

  @override
  Elapsed createPlugin() {
    final p = Elapsed();
    Countman.use(p);
    return p;
  }

  @override
  void wire(Elapsed? plugin, {required bool clear}) {
    if (plugin == null) return;
    plugin.onFirstEnqueued = clear ? null : widget.onGroupReady;
    plugin.onQueueDrained = clear ? null : widget.onAllComplete;
  }

  @override
  Widget build(BuildContext context) => CountmanScope<Elapsed>(
        plugin: effectivePlugin,
        textStyle: widget.textStyle,
        color: null,
        trackColor: null,
        duration: null,
        curve: null,
        allowNegative: null,
        repaintBoundary: null,
        formatter: widget.formatter,
        textElapsedStyle: widget.textElapsedStyle,
        child: widget.child,
      );
}

// ── Aggregate ───────────────────────────────────────────────────────

/// One-stop provider that configures all three families at once, so a page
/// using counters, countdowns AND stopwatches doesn't need to hand-nest
/// [CounterProvider] / [CountdownProvider] / [ElapsedProvider].
///
/// Shared visual defaults ([textStyle] / [color] / [trackColor] /
/// [repaintBoundary] / [animateOnce]) apply to whichever families they're
/// relevant to; counter-only ([duration] / [curve] / [allowNegative]),
/// countdown+elapsed ([formatter]), and each per-component `*Style` route to
/// their respective family. Internally just nests the three providers.
///
/// 一站式 provider，一次配置全部三个家族，使同时用到计数、倒计时、秒表的页面无需
/// 手动嵌套 [CounterProvider] / [CountdownProvider] / [ElapsedProvider]。
///
/// 共享视觉默认值（[textStyle] / [color] / [trackColor] / [repaintBoundary] /
/// [animateOnce]）应用到相关的家族；仅 counter 的（[duration] / [curve] /
/// [allowNegative]）、countdown+elapsed 的（[formatter]）以及各组件 `*Style`
/// 分别下发到对应家族。内部只是嵌套三个 provider。
///
/// ```dart
/// CountmanProvider(
///   textStyle: const TextStyle(fontSize: 24),
///   color: Colors.teal,
///   formatter: CountdownFormat.hms,
///   child: MyPage(),
/// )
/// ```
class CountmanProvider extends StatelessWidget {
  const CountmanProvider({
    super.key,
    this.counter,
    this.countdown,
    this.elapsed,
    this.textStyle,
    this.color,
    this.trackColor,
    this.duration,
    this.curve,
    this.allowNegative,
    this.repaintBoundary,
    this.animateOnce,
    this.formatter,
    this.textCounterStyle,
    this.textCountdownStyle,
    this.textElapsedStyle,
    this.ringCounterStyle,
    this.ringCountdownStyle,
    this.barCounterStyle,
    this.barCountdownStyle,
    this.dialCountdownStyle,
    this.cardCountdownStyle,
    this.odometerCounterStyle,
    required this.child,
  });

  /// Optional shared groups, one per family.
  final Counter? counter;
  final Countdown? countdown;
  final Elapsed? elapsed;

  /// Shared visual defaults (applied to every family that supports them).
  final TextStyle? textStyle;
  final Color? color;
  final Color? trackColor;
  final bool? repaintBoundary;
  final bool? animateOnce;

  /// Counter-family-only defaults.
  final Duration? duration;
  final Curve? curve;
  final bool? allowNegative;

  /// Countdown + elapsed default formatter.
  final DurationFormatter? formatter;

  /// Per-component default styles, routed to their family's provider.
  final TextCounterStyle? textCounterStyle;
  final TextCountdownStyle? textCountdownStyle;
  final TextElapsedStyle? textElapsedStyle;
  final RingCounterStyle? ringCounterStyle;
  final RingCountdownStyle? ringCountdownStyle;
  final BarCounterStyle? barCounterStyle;
  final BarCountdownStyle? barCountdownStyle;
  final DialCountdownStyle? dialCountdownStyle;
  final CardCountdownStyle? cardCountdownStyle;
  final OdometerCounterStyle? odometerCounterStyle;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return CounterProvider(
      plugin: counter,
      textStyle: textStyle,
      color: color,
      trackColor: trackColor,
      duration: duration,
      curve: curve,
      allowNegative: allowNegative,
      repaintBoundary: repaintBoundary,
      animateOnce: animateOnce,
      textCounterStyle: textCounterStyle,
      ringCounterStyle: ringCounterStyle,
      barCounterStyle: barCounterStyle,
      odometerCounterStyle: odometerCounterStyle,
      child: CountdownProvider(
        plugin: countdown,
        textStyle: textStyle,
        color: color,
        trackColor: trackColor,
        repaintBoundary: repaintBoundary,
        animateOnce: animateOnce,
        formatter: formatter,
        textCountdownStyle: textCountdownStyle,
        ringCountdownStyle: ringCountdownStyle,
        barCountdownStyle: barCountdownStyle,
        dialCountdownStyle: dialCountdownStyle,
        cardCountdownStyle: cardCountdownStyle,
        child: ElapsedProvider(
          plugin: elapsed,
          textStyle: textStyle,
          formatter: formatter,
          textElapsedStyle: textElapsedStyle,
          child: child,
        ),
      ),
    );
  }
}
