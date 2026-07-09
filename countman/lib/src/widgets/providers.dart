import 'package:flutter/widgets.dart';

import 'package:countman/src/core/ticker.dart';
import 'package:countman/src/counter/plugin.dart';
import 'package:countman/src/count_down/plugin.dart';
import 'package:countman/src/elapsed/plugin.dart';

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

  /// Default animation duration (count-up family).
  final Duration? duration;

  /// Default easing curve (count-up family).
  final Curve? curve;

  /// Default `allowNegative` (count-up family).
  final bool? allowNegative;

  /// Default `repaintBoundary` for descendants that support it.
  final bool? repaintBoundary;

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
      repaintBoundary != old.repaintBoundary;
}

/// Base state that owns (or borrows) a plugin and wires the group-level
/// [onGroupReady] / [onAllComplete] callbacks onto it. Concrete providers
/// implement [createPlugin] and [buildScope].
abstract class _ProviderStateBase<W extends StatefulWidget, P> extends State<W> {
  // Lazily created when this provider must own a plugin (group callbacks set
  // but no external plugin supplied). Cached for the provider's lifetime.
  P? _owned;

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
/// every count-up display widget below it.
///
/// ```dart
/// CounterProvider(
///   duration: const Duration(milliseconds: 800),
///   textStyle: const TextStyle(fontSize: 28),
///   child: Column(children: [CounterText(to: 100), CounterRing(to: 50)]),
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

  /// Fired when the group goes idle → active (its first task is enqueued).
  final VoidCallback? onGroupReady;

  /// Fired when the group goes active → idle (its last task leaves).
  final VoidCallback? onAllComplete;

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
    this.onGroupReady,
    this.onAllComplete,
    required this.child,
  });

  final Countdown? plugin;
  final TextStyle? textStyle;
  final Color? color;
  final Color? trackColor;
  final bool? repaintBoundary;

  /// Fired when the group goes idle → active (its first task is enqueued).
  final VoidCallback? onGroupReady;

  /// Fired when the group goes active → idle (its last task leaves).
  final VoidCallback? onAllComplete;

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
    this.onGroupReady,
    this.onAllComplete,
    required this.child,
  });

  final Elapsed? plugin;
  final TextStyle? textStyle;

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
        child: widget.child,
      );
}
