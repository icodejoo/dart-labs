import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import 'plugin_base.dart' show LazyDefault;
import 'start_scheduler.dart';
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
  // 唤醒请求与运行代次分开，防止回调新增任务或重启时丢帧。
  static bool _requested = false;
  static int _generation = 0;
  static bool _hasLast = false;
  static Duration _last = Duration.zero;
  // 按实例保存注册顺序，逐帧成员检查保持常数开销。
  static final _plugins = LinkedHashSet<CountmanPlugin>.identity();
  static final _installed = <String>{};

  // ── public API ────────────────────────────────────────────────────

  /// Register [plugin] by name. Duplicate names are silently ignored.
  /// Injects a [CountmanContext] so the plugin can request frames
  /// without depending on [Countman] directly.
  static void use(CountmanPlugin plugin) {
    if (_installed.contains(plugin.name)) return;
    _installed.add(plugin.name);
    _plugins.add(plugin);
    try {
      plugin.onAttach(_ctx);
    } catch (_) {
      // 挂载失败时撤销登记，避免已销毁实例占住名称。
      _plugins.remove(plugin);
      _installed.remove(plugin.name);
      rethrow;
    }
  }

  /// Request a frame loop. Plugins call this when they add a task.
  /// No-op if the loop is already running.
  static void start() {
    _requested = true;
    if (_running) return;
    _generation++;
    _running = true;
    _hasLast = false;
    _frameId = SchedulerBinding.instance.scheduleFrameCallback(_loop);
  }

  /// Stop the frame loop immediately.
  /// Plugins and their tasks are preserved — [start] resumes them.
  static void stop() {
    _generation++;
    _requested = false;
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
    // 先摘除旧注册表，销毁回调中新建的插件属于下一代。
    final plugins = List.of(_plugins);
    _plugins.clear();
    _installed.clear();
    // 先重置默认组，销毁回调内新建的默认组不会被误清除。
    LazyDefault.resetAll();
    // snapshot to allow dispose() to mutate _plugins if needed
    for (final p in plugins) {
      StartScheduler.instance.removeGroup(p);
      p.dispose();
    }
  }

  /// Unregister and dispose only this exact instance. Returns whether registered.
  /// 独立注销指定实例并释放批量配置；同名的其他实例不受影响。
  static bool unuse(CountmanPlugin plugin) {
    if (!_plugins.remove(plugin)) return false;
    _installed.remove(plugin.name);
    StartScheduler.instance.removeGroup(plugin);
    LazyDefault.resetInstance(plugin);
    plugin.dispose();
    if (_plugins.isEmpty) stop();
    return true;
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
    final generation = _generation;
    _requested = false;

    final dt = _hasLast ? timestamp - _last : Duration.zero;
    _last = timestamp;
    _hasLast = true;

    var busy = false;
    // 稳定快照保证帧中新建插件从下一帧开始处理。
    for (final plugin in List.of(_plugins)) {
      // 回调可能销毁、停止或注销插件，旧帧不得继续驱动旧列表。
      if (!_running || generation != _generation) return;
      if (!_plugins.contains(plugin)) continue;
      try {
        if (plugin.tick(timestamp, dt)) busy = true;
      } catch (e, st) {
        FlutterError.reportError(FlutterErrorDetails(
          exception: e,
          stack: st,
          library: 'countman',
          context: ErrorDescription('plugin "${plugin.name}" threw in tick()'),
        ));
      }
    }

    if (!_running || generation != _generation) return;
    if (busy || _requested) {
      _frameId = SchedulerBinding.instance.scheduleFrameCallback(_loop);
    } else {
      _running = false;
      _hasLast = false;
    }
  }
}
