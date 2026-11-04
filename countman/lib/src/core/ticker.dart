import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import 'plugin_base.dart' show LazyDefault;
import 'start_scheduler.dart';
import 'types.dart';

/// Shared vsync ticker — one `scheduleFrameCallback` drives all plugins.
///
/// Plugins call [start] when they enqueue a task.
/// 全部插件返回 idle 时停表；返回正数时共享一个休眠定时器。
/// and restarts on the next [start] call.
/// 共享帧驱动器，逐插件隔离 tick 与销毁异常。
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

  /// 全局唯一的休眠定时器。
  static Timer? _sleepTimer;

  /// 小于等于此窗口直接请求下一帧，避免短定时器抖动。
  static const int _frameWindowMicros = 20000;

  /// 结构变化时才重建的插件快照，稳态逐帧不分配列表。
  static final List<CountmanPlugin> _snapshot = [];

  /// 快照是否需要重建。
  static bool _snapshotDirty = true;

  /// 当前是否正在遍历快照。
  static bool _inLoop = false;

  // ── public API ────────────────────────────────────────────────────

  /// 按实例注册 [plugin]，重复注册相同实例无操作。
  /// 调试模式拒绝同名的另一实例；请复用实例或提供唯一 name。
  /// 例如 `Countman.use(Countdown(name: 'auction'))`。
  static void use(CountmanPlugin plugin) {
    if (_plugins.contains(plugin)) return;
    assert(
      !_plugins.any((p) => p.name == plugin.name),
      'countman: 插件 "${plugin.name}" 名称重复；复用同一个实例，或换一个唯一 name。',
    );
    _plugins.add(plugin);
    _snapshotDirty = true;
    try {
      plugin.onAttach(_ctx);
    } catch (_) {
      _plugins.remove(plugin);
      rethrow;
    }
  }

  /// 请求立即处理；取消休眠并确保只登记一个帧回调。
  /// 例如添加任务时调用 `Countman.start()`；无返回值。
  static void start() {
    _requested = true;
    if (_sleepTimer != null) {
      _sleepTimer!.cancel();
      _sleepTimer = null;
      _hasLast = false;
    }
    if (!_running) {
      _generation++;
      _running = true;
      _hasLast = false;
    }
    if (!_inLoop && _frameId == null) {
      _frameId = SchedulerBinding.instance.scheduleFrameCallback(_loop);
    }
  }

  /// 立即停表并取消休眠；保留任务，start 可恢复。
  /// Plugins and their tasks are preserved — [start] resumes them.
  static void stop() {
    _generation++;
    _requested = false;
    _sleepTimer?.cancel();
    _sleepTimer = null;
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
  /// 逐插件隔离销毁异常，使全部旧插件都得到释放。
  static void destroy() {
    stop();
    // 先摘除旧注册表，销毁回调中新建的插件属于下一代。
    final plugins = List.of(_plugins);
    _plugins.clear();
    _snapshotDirty = true;
    if (!_inLoop) _snapshot.clear();
    // 先重置默认组，销毁回调内新建的默认组不会被误清除。
    LazyDefault.resetAll();
    // snapshot to allow dispose() to mutate _plugins if needed
    for (final p in plugins) {
      StartScheduler.instance.removeGroup(p);
      try {
        try {
          p.onDetach();
        } finally {
          p.dispose();
        }
      } catch (error, stack) {
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stack,
            library: 'countman',
            context: ErrorDescription('插件 "${p.name}" 销毁异常'),
          ),
        );
      }
    }
  }

  /// 按实例注销 [plugin] 并调用 onDetach，返回是否曾注册。
  /// [dispose] 默认为 true；传 false 保留任务，下一次 add 可自注册。
  /// 例如 `Countman.unuse(group, dispose: false)`。
  static bool unuse(CountmanPlugin plugin, {bool dispose = true}) {
    if (!_plugins.remove(plugin)) return false;
    _snapshotDirty = true;
    if (!_inLoop) _snapshot.clear();
    StartScheduler.instance.removeGroup(plugin);
    LazyDefault.resetInstance(plugin);
    if (_plugins.isEmpty) stop();
    try {
      plugin.onDetach();
    } finally {
      if (dispose) plugin.dispose();
    }
    return true;
  }

  // ── test helpers ─────────────────────────────────────────────────

  /// 循环是否活跃；休眠期间仍为 true。
  @visibleForTesting
  static bool get isRunning => _running;

  /// 是否有挂起的全局休眠定时器。
  @visibleForTesting
  static bool get isSleeping => _sleepTimer != null;

  /// 当前按实例注册的插件数量。
  @visibleForTesting
  static int get pluginCount => _plugins.length;

  // ── frame loop ───────────────────────────────────────────────────

  /// 执行活动帧并汇总最早唤醒时间，休眠后重置 dt。
  static void _loop(Duration timestamp) {
    _frameId = null;
    // stop() may have been called from within a plugin tick
    if (!_running) return;
    final generation = _generation;
    _requested = false;

    final dt = _hasLast ? timestamp - _last : Duration.zero;
    _last = timestamp;
    _hasLast = true;

    var wake = CountmanPlugin.idle;
    if (_snapshotDirty) {
      _snapshot
        ..clear()
        ..addAll(_plugins);
      _snapshotDirty = false;
    }
    _inLoop = true;
    try {
      for (var index = 0; index < _snapshot.length; index++) {
        final plugin = _snapshot[index];
        // 回调可能销毁、停止或注销插件，旧帧不得继续驱动旧列表。
        if (!_running || generation != _generation) return;
        if (!_plugins.contains(plugin)) continue;
        try {
          final delay = plugin.tick(timestamp, dt);
          if (delay >= CountmanPlugin.nextFrame &&
              (wake == CountmanPlugin.idle || delay < wake))
            wake = delay;
        } catch (e, st) {
          FlutterError.reportError(
            FlutterErrorDetails(
              exception: e,
              stack: st,
              library: 'countman',
              context: ErrorDescription(
                'plugin "${plugin.name}" threw in tick()',
              ),
            ),
          );
        }
      }
    } finally {
      _inLoop = false;
      if (_snapshotDirty) _snapshot.clear();
      // stop 后同帧重启属于新一代；确保新一代首帧已登记。
      if (_running && generation != _generation && _frameId == null) {
        _frameId = SchedulerBinding.instance.scheduleFrameCallback(_loop);
      }
    }
    if (!_running || generation != _generation) return;
    if (_requested || (wake >= 0 && wake <= _frameWindowMicros)) {
      _frameId = SchedulerBinding.instance.scheduleFrameCallback(_loop);
    } else if (wake > _frameWindowMicros) {
      _hasLast = false;
      _sleepTimer = Timer(Duration(microseconds: wake), _wake);
    } else {
      _running = false;
      _hasLast = false;
    }
  }

  /// 定时器到期只请求一帧，实际处理仍统一由 vsync 驱动。
  static void _wake() {
    _sleepTimer = null;
    if (_running && _frameId == null) {
      _frameId = SchedulerBinding.instance.scheduleFrameCallback(_loop);
    }
  }
}
