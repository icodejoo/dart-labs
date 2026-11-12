import 'package:countman/countman.dart';
import 'package:flutter/foundation.dart';

/// 番茄钟的一个阶段（例如“专注”或“休息”）。
@immutable
class PomodoroPhase {
  /// 创建阶段；[label] 用于展示，[duration] 为该阶段时长。
  const PomodoroPhase(this.label, this.duration);

  /// 阶段名称，例如“专注”。
  final String label;

  /// 阶段时长。
  final Duration duration;
}

/// 某一时刻的番茄钟快照，由插件在显示秒变化或阶段切换时推送。
@immutable
class PomodoroSnapshot {
  /// 创建快照。
  const PomodoroSnapshot({
    required this.phase,
    required this.phaseNumber,
    required this.phaseCount,
    required this.remainingSeconds,
    required this.finished,
    required this.updates,
  });

  /// 当前阶段。
  final PomodoroPhase phase;

  /// 当前是整个流程里的第几个阶段（从 1 起）。
  final int phaseNumber;

  /// 整个流程一共有多少个阶段。
  final int phaseCount;

  /// 当前阶段剩余整秒数（向上取整，与倒计时习惯一致）。
  final int remainingSeconds;

  /// 整个流程是否已经结束。
  final bool finished;

  /// 插件到目前为止推送的更新次数，用来直观看到“按需唤醒、不逐帧运行”。
  final int updates;
}

/// 番茄钟任务：保存阶段序列与当前阶段的单调钟锚点。
class PomodoroTask extends CountmanTask {
  /// 创建任务；[phases] 为一轮的阶段序列，[rounds] 为重复轮数。
  PomodoroTask(
    super.id, {
    required this.phases,
    required this.rounds,
    required this.onChange,
  });

  /// 一轮内的阶段序列。
  final List<PomodoroPhase> phases;

  /// 重复轮数。
  final int rounds;

  /// 快照回调。
  final void Function(PomodoroSnapshot snapshot) onChange;

  /// 当前阶段在整个流程中的下标（0 起，范围 0 到 phases.length * rounds）。
  int index = 0;

  /// 当前阶段起点的单调钟微秒。
  int phaseStartMicros = 0;

  /// 暂停时冻结的剩余微秒；null 表示正在运行。
  int? frozenRemainingMicros;

  /// 上次推送时的显示秒，用于判断是否需要再次推送。
  int lastShownSeconds = -1;

  /// 上次推送时的阶段下标。
  int lastShownIndex = -1;

  /// 累计推送次数。
  int updates = 0;

  /// 整个流程的阶段总数。
  int get total => phases.length * rounds;

  /// 流程是否已经走完。
  bool get finished => index >= total;

  /// 下标对应的阶段（超出范围时取最后一个阶段）。
  PomodoroPhase phaseAt(int i) => phases[(i < total ? i : total - 1) % phases.length];

  @override
  bool get isPaused => frozenRemainingMicros != null;
}

/// 控制一个番茄钟任务的句柄，由 [PomodoroPlugin.start] 返回。
class PomodoroHandle {
  PomodoroHandle._(this._plugin, this._task);

  final PomodoroPlugin _plugin;
  PomodoroTask _task;

  /// 暂停；已暂停或已结束时无操作。
  void pause() => _plugin._pause(_task);

  /// 继续；未暂停时无操作。
  void resume() => _plugin._resume(_task);

  /// 回到第一个阶段重新开始；流程已结束时会重新入队。
  void restart() => _task = _plugin._restart(_task);

  /// 当前是否处于暂停状态。
  bool get isPaused => _task.isPaused;
}

/// 自定义插件示例：用 [TaskQueuePlugin] 写一个番茄钟 / 间歇训练引擎。
///
/// 要点是 0.3.0 的 `tick` 新契约——每次只返回“距下次需要处理的微秒数”：
/// 一个 25 分钟的专注阶段，插件每秒只醒一次（甚至更久），其余时间调度器完全休眠，
/// 不再逐 vsync 出帧。基类 [TaskQueuePlugin] 负责任务表、并发安全和异常隔离，
/// 子类只实现 [renderInitial] / [step] / [nextWake] 三个钩子。
///
/// ```dart
/// final plugin = PomodoroPlugin();
/// Countman.use(plugin);
/// final handle = plugin.start(
///   phases: const [PomodoroPhase('专注', Duration(minutes: 25)), PomodoroPhase('休息', Duration(minutes: 5))],
///   rounds: 4,
///   onChange: (s) => debugPrint('${s.phase.label} ${s.remainingSeconds}s'),
/// );
/// ```
class PomodoroPlugin extends TaskQueuePlugin<PomodoroTask> {
  /// 创建插件；[name] 须唯一，[clockOverride] 为空时跟随 [CountmanClock.system]。
  PomodoroPlugin({String name = 'pomodoro', this.clockOverride}) : super(name);

  /// 显式指定的时钟（测试可注入 [ManualCountmanClock]）。
  final CountmanClock? clockOverride;

  /// 当前单调钟微秒；用单调钟，改系统时间不影响番茄钟。
  int get _now => (clockOverride ?? CountmanClock.system).monotonicMicros();

  /// 开始一个番茄钟并返回控制句柄。
  PomodoroHandle start({
    required List<PomodoroPhase> phases,
    int rounds = 1,
    required void Function(PomodoroSnapshot snapshot) onChange,
  }) {
    final task = PomodoroTask(nextId(), phases: phases, rounds: rounds, onChange: onChange)
      ..phaseStartMicros = _now;
    enqueue(task);
    return PomodoroHandle._(this, task);
  }

  /// 当前阶段剩余微秒。
  int _remainingOf(PomodoroTask task) {
    final frozen = task.frozenRemainingMicros;
    if (frozen != null) return frozen;
    return task.phaseAt(task.index).duration.inMicroseconds - (_now - task.phaseStartMicros);
  }

  void _pause(PomodoroTask task) {
    if (task.done || task.isPaused) return;
    task.frozenRemainingMicros = _remainingOf(task);
  }

  void _resume(PomodoroTask task) {
    final frozen = task.frozenRemainingMicros;
    if (task.done || frozen == null) return;
    final duration = task.phaseAt(task.index).duration.inMicroseconds;
    task.phaseStartMicros = _now - (duration - frozen);
    task.frozenRemainingMicros = null;
    task.reanchor();
    ctx.requestFrame();
  }

  PomodoroTask _restart(PomodoroTask task) {
    if (task.done) {
      // 已结束的任务已被移出队列，重新建一个。
      final fresh = PomodoroTask(nextId(), phases: task.phases, rounds: task.rounds, onChange: task.onChange)
        ..phaseStartMicros = _now;
      enqueue(fresh);
      return fresh;
    }
    task
      ..index = 0
      ..phaseStartMicros = _now
      ..frozenRemainingMicros = null
      ..lastShownSeconds = -1
      ..lastShownIndex = -1
      ..reanchor();
    ctx.requestFrame();
    return task;
  }

  /// 推送快照；剩余秒向上取整。
  void _emit(PomodoroTask task) {
    final remaining = task.finished ? 0 : _remainingOf(task);
    final seconds = remaining <= 0 ? 0 : (remaining + 999999) ~/ 1000000;
    task.lastShownSeconds = seconds;
    task.lastShownIndex = task.index;
    task.updates++;
    task.onChange(PomodoroSnapshot(
      phase: task.phaseAt(task.index),
      phaseNumber: task.index < task.total ? task.index + 1 : task.total,
      phaseCount: task.total,
      remainingSeconds: seconds,
      finished: task.finished,
      updates: task.updates,
    ));
  }

  @override
  void renderInitial(PomodoroTask task) => _emit(task);

  @override
  void step(PomodoroTask task, double dtMs) {
    // 阶段到点就顺延到下一个；起点按阶段时长累加，不累积误差。
    while (!task.finished && _remainingOf(task) <= 0) {
      task.phaseStartMicros += task.phaseAt(task.index).duration.inMicroseconds;
      task.index++;
    }
    if (task.finished) {
      _emit(task);
      task.done = true;
      return;
    }
    final seconds = (_remainingOf(task) + 999999) ~/ 1000000;
    if (task.index != task.lastShownIndex || seconds != task.lastShownSeconds) _emit(task);
  }

  /// 新契约的核心：告诉调度器“多久之后再叫我”。
  /// 显示秒只在剩余降到整秒边界时才变，所以睡到下一个整秒边界即可。
  @override
  int nextWake(PomodoroTask task) {
    final remaining = _remainingOf(task);
    if (remaining <= 0) return CountmanPlugin.nextFrame;
    final untilNextSecond = remaining - ((remaining - 1) ~/ 1000000) * 1000000;
    // 距离更近的是“阶段结束”还是“下一个整秒”，两者都不会超过剩余时间。
    return untilNextSecond < 1 ? 1 : untilNextSecond;
  }
}
