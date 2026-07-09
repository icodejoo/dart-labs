import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import 'types.dart';

/// Shared vsync ticker — one `scheduleFrameCallback` drives all plugins.
///
/// Plugins call [start] when they enqueue a task.
/// The loop auto-stops when every plugin's [CountmanPlugin.tick] returns `false`,
/// and restarts on the next [start] call.
class Countman {
  Countman._();

  static final _ctx = CountmanContext(requestFrame: start);

  static int? _frameId;
  static bool _running = false;
  static bool _hasLast = false;
  static Duration _last = Duration.zero;
  static final _plugins = <CountmanPlugin>[];
  static final _installed = <String>{};

  // ── public API ────────────────────────────────────────────────────

  /// Register [plugin] by name. Duplicate names are silently ignored.
  /// Injects a [CountmanContext] so the plugin can request frames
  /// without depending on [Countman] directly.
  static void use(CountmanPlugin plugin) {
    if (_installed.contains(plugin.name)) return;
    _installed.add(plugin.name);
    _plugins.add(plugin);
    plugin.onAttach(_ctx);
  }

  /// Request a frame loop. Plugins call this when they add a task.
  /// No-op if the loop is already running.
  static void start() {
    if (_running) return;
    _running = true;
    _hasLast = false;
    _frameId = SchedulerBinding.instance.scheduleFrameCallback(_loop);
  }

  /// Stop the frame loop immediately.
  /// Plugins and their tasks are preserved — [start] resumes them.
  static void stop() {
    if (!_running) return;
    _running = false;
    _hasLast = false;
    final id = _frameId;
    _frameId = null;
    if (id != null) SchedulerBinding.instance.cancelFrameCallbackWithId(id);
  }

  /// Stop the loop and dispose every registered plugin.
  /// After destroy, the next [start] call (e.g. via a new task) rebuilds
  /// the plugin set from scratch via [use].
  static void destroy() {
    stop();
    // snapshot to allow dispose() to mutate _plugins if needed
    for (final p in List.of(_plugins)) {
      p.dispose();
    }
    _plugins.clear();
    _installed.clear();
  }

  // ── test helpers ─────────────────────────────────────────────────

  @visibleForTesting
  static bool get isRunning => _running;

  @visibleForTesting
  static int get pluginCount => _plugins.length;

  // ── frame loop ───────────────────────────────────────────────────

  static void _loop(Duration timestamp) {
    _frameId = null;
    // stop() may have been called from within a plugin tick
    if (!_running) return;

    final dt = _hasLast ? timestamp - _last : Duration.zero;
    _last = timestamp;
    _hasLast = true;

    var busy = false;
    // capture length so plugins added mid-tick start next frame
    final len = _plugins.length;
    for (var i = 0; i < len; i++) {
      try {
        if (_plugins[i].tick(timestamp, dt) != false) busy = true;
      } catch (e, st) {
        FlutterError.reportError(FlutterErrorDetails(
          exception: e,
          stack: st,
          library: 'countman',
          context: ErrorDescription('plugin "${_plugins[i].name}" threw in tick()'),
        ));
      }
    }

    if (busy && _running) {
      _frameId = SchedulerBinding.instance.scheduleFrameCallback(_loop);
    } else {
      _running = false;
      _hasLast = false;
    }
  }
}
