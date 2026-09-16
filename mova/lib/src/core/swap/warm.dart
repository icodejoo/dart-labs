/// One observation of a warming shadow engine, fed to a [MovaWarmPolicy].
///
/// A plain value object so the readiness rule can be exercised without any
/// engine, kernel or Flutter binding.
///
/// 对预热中影子引擎的一次观测，喂给 [MovaWarmPolicy]。
///
/// 纯值对象，使就绪规则无需任何引擎、内核或 Flutter 绑定即可被测试。
class MovaWarmSignal {
  /// The shadow engine's current playhead.
  ///
  /// 影子引擎的当前播放位置。
  final Duration position;

  /// How far the shadow engine has buffered ahead.
  ///
  /// 影子引擎已缓冲到的位置。
  final Duration buffer;

  /// The position the swap should land on.
  ///
  /// 切换应当落在的位置。
  final Duration target;

  /// Whether the shadow engine is currently stalled.
  ///
  /// 影子引擎当前是否正在缓冲。
  final bool buffering;

  /// How long this warm-up has been running.
  ///
  /// 本次预热已进行的时长。
  final Duration elapsed;

  /// Creates an observation.
  ///
  /// 创建一次观测。
  ///
  /// - [position], [buffer], [target]: positions in media time / 媒体时间轴上的位置
  /// - [buffering]: current stall flag / 当前是否卡顿
  /// - [elapsed]: time since warm-up started / 自预热开始的耗时
  const MovaWarmSignal({
    required this.position,
    required this.buffer,
    required this.target,
    required this.buffering,
    required this.elapsed,
  });
}

/// The verdict a [MovaWarmPolicy] returns for one [MovaWarmSignal].
///
/// [MovaWarmPolicy] 针对一次 [MovaWarmSignal] 给出的裁决。
enum MovaWarmVerdict {
  /// Not ready yet; keep warming.
  ///
  /// 尚未就绪，继续预热。
  waiting,

  /// Ready — the swap may commit now.
  ///
  /// 已就绪——现在可以提交切换。
  ready,

  /// Give up; the caller must tear the shadow down and fall back to a plain
  /// `open()` rather than stall the user waiting for a swap that isn't coming.
  ///
  /// 放弃；调用方须拆掉影子引擎并回落到普通 `open()`，而不是让用户干等一个
  /// 永远不会到来的切换。
  giveUp,
}

/// Decides when a warming shadow engine is ready to become the live one.
///
/// The exact counterpart of [MovaAbrPolicy]: that one watches for "too
/// rough, step down", this one watches for "smooth enough, swap now".
///
/// 判定预热中的影子引擎何时可以转正为生效引擎。
///
/// 与 [MovaAbrPolicy] 恰好互为镜像：后者盯"太卡了，降档"，本者盯"够顺了，
/// 现在切"。
abstract class MovaWarmPolicy {
  /// Feeds one observation and returns the verdict.
  ///
  /// 输入一次观测并返回裁决。
  ///
  /// - [signal]: the latest shadow-engine observation / 最新一次影子引擎观测
  ///
  /// Returns the verdict for this tick / 返回本 tick 的裁决。
  MovaWarmVerdict onSignal(MovaWarmSignal signal);

  /// Resets accumulated state so the instance can drive another warm-up.
  ///
  /// 重置累积状态，使该实例可驱动下一次预热。
  void reset();
}

/// Buffer-based readiness: ready once the shadow has reached the target
/// position, is not stalled, and holds [lookahead] of buffered data — for
/// [stableTicks] consecutive observations.
///
/// The consecutive-tick requirement is what keeps a single lucky tick from
/// committing a swap that immediately re-buffers on screen; the lookahead is
/// what makes the first frames after the swap play through instead of
/// stalling at the moment the user is watching.
///
/// 基于缓冲的就绪判据：影子引擎已到达目标位置、未在卡顿、且已缓冲
/// [lookahead] 的数据——并连续满足 [stableTicks] 次观测。
///
/// 要求连续多 tick，是为了避免某一次侥幸的观测把切换提交出去、切完立刻在
/// 用户眼前重新缓冲；要求提前量，是为了让切换后的头几帧能连贯播下去，而不是
/// 恰好卡在用户注视的那一刻。
class MovaBufferWarm implements MovaWarmPolicy {
  /// How much buffered-ahead data counts as enough.
  ///
  /// 多少提前缓冲量算够。
  final Duration lookahead;

  /// How close to [MovaWarmSignal.target] counts as arrived.
  ///
  /// 距 [MovaWarmSignal.target] 多近算已到达。
  final Duration tolerance;

  /// Consecutive satisfying observations required.
  ///
  /// 需要连续满足的观测次数。
  final int stableTicks;

  /// Deadline after which [MovaWarmVerdict.giveUp] is returned.
  ///
  /// 超过该期限即返回 [MovaWarmVerdict.giveUp]。
  final Duration timeout;

  /// Creates a buffer-based readiness policy.
  ///
  /// 创建一个基于缓冲的就绪判据。
  ///
  /// - [lookahead]: buffered-ahead requirement, default 1s / 提前缓冲量要求，默认 1 秒
  /// - [tolerance]: arrival tolerance, default 800ms / 到达容差，默认 800 毫秒
  /// - [stableTicks]: consecutive satisfying ticks, default 2 / 连续满足次数，默认 2
  /// - [timeout]: give-up deadline, default 8s / 放弃期限，默认 8 秒
  ///
  /// Example / 示例:
  /// ```dart
  /// final policy = MovaBufferWarm(lookahead: const Duration(seconds: 2));
  /// ```
  MovaBufferWarm({
    this.lookahead = const Duration(seconds: 1),
    this.tolerance = const Duration(milliseconds: 800),
    this.stableTicks = 2,
    this.timeout = const Duration(seconds: 8),
  });

  int _stable = 0;
  bool _ready = false;

  /// Consecutive satisfying observations seen so far; for tests and
  /// diagnostics.
  ///
  /// 至今连续满足的观测次数；供测试与诊断使用。
  int get stable => _stable;

  @override
  MovaWarmVerdict onSignal(MovaWarmSignal signal) {
    if (_ready) return MovaWarmVerdict.ready;
    if (signal.elapsed >= timeout) return MovaWarmVerdict.giveUp;

    final arrived = signal.position >= signal.target - tolerance;
    final buffered = signal.buffer - signal.position >= lookahead;
    final satisfied = arrived && buffered && !signal.buffering;

    if (!satisfied) {
      _stable = 0;
      return MovaWarmVerdict.waiting;
    }
    _stable++;
    if (_stable >= stableTicks) {
      _ready = true;
      return MovaWarmVerdict.ready;
    }
    return MovaWarmVerdict.waiting;
  }

  @override
  void reset() {
    _stable = 0;
    _ready = false;
  }
}
