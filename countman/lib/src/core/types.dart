/// Capabilities injected into a plugin when it is registered.
/// Plugins hold a reference and call [requestFrame] whenever they
/// enqueue a new task and need the ticker to (re-)start.
class CountmanContext {
  const CountmanContext({required this.requestFrame});

  /// Ask the ticker to schedule the next frame.
  /// Idempotent — safe to call even when the ticker is already running.
  final void Function() requestFrame;
}

/// Plugin interface. Each instance owns its own task queue and is
/// registered once on the shared [Countman] ticker.
///
/// Lifecycle:
///   1. [onAttach] — called once by [Countman.use]; store [ctx] for later.
///   2. [tick]     — called every frame; return `false` when idle.
///   3. [dispose]  — called by [Countman.destroy].
abstract interface class CountmanPlugin {
  String get name;

  /// Called once when the plugin is registered. Store [ctx.requestFrame]
  /// and call it whenever a new task is added and the ticker may be idle.
  void onAttach(CountmanContext ctx);

  /// Drive the plugin's task queue for this frame.
  /// Return `false` when there is nothing left to do —
  /// the ticker auto-stops when every plugin is idle.
  bool tick(Duration elapsed, Duration dt);

  void dispose();
}
