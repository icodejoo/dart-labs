/// What went wrong with a playback attempt.
///
/// 一次播放尝试出了什么问题。
enum MovaPlayFailKind {
  /// The kernel's `open()` threw. Only caught (instead of rethrown) when
  /// recovery is enabled.
  ///
  /// 内核 `open()` 抛出了异常。仅在 recovery 开启时才被捕获（否则照旧向外抛）。
  openThrew,

  /// No first frame within `MovaRecoveryConfig.startTimeout` of the attempt
  /// being armed while playback was intended.
  ///
  /// 播放意图为真时，尝试武装后 `MovaRecoveryConfig.startTimeout` 内没有首帧。
  startTimeout,

  /// Buffering continuously for `MovaRecoveryConfig.stallTimeout` after the
  /// first frame, while playing.
  ///
  /// 出首帧后、播放中连续缓冲达到 `MovaRecoveryConfig.stallTimeout`。
  stallTimeout,

  /// Native `END_FILE` with reason `error`; fails fast without waiting for a
  /// timeout.
  ///
  /// 原生 `END_FILE` 且原因为 `error`；无需等超时即可快速判失败。
  nativeEndError,

  /// A live source reached its end (the server closed the stream).
  ///
  /// 直播源走到了结尾（服务端断开了流）。
  liveEnded,
}

/// One playback failure, fed to a [MovaRecoveryPolicy].
///
/// A plain value so the recovery rule is unit-testable with no player, no
/// engine and no Flutter binding.
///
/// 一次播放失败，喂给 [MovaRecoveryPolicy]。
///
/// 纯值对象，使恢复规则无需播放器、引擎或 Flutter 绑定即可被测试。
class MovaPlayFail {
  /// What went wrong.
  ///
  /// 出了什么问题。
  final MovaPlayFailKind kind;

  /// Index into `MovaSource.uris` of the failing address.
  ///
  /// 失败地址在 `MovaSource.uris` 里的下标。
  final int sourceIndex;

  /// The failing address.
  ///
  /// 失败的地址。
  final String uri;

  /// How many addresses the source has (1 + alternatives).
  ///
  /// 源一共有几个地址（1 + 备选数）。
  final int sourceCount;

  /// Consecutive failures on this address since the last first frame, from 1.
  ///
  /// 自上次出首帧以来该地址的连续失败次数，从 1 起。
  final int attempt;

  /// Consecutive failures across all addresses since the last first frame.
  ///
  /// 自上次出首帧以来跨所有地址的连续失败次数。
  final int streak;

  /// Whether this source had shown a frame before failing (a mid-stream failure).
  ///
  /// 失败前本源是否出过画面（即播放中途失败）。
  final bool afterFirstFrame;

  /// How long the attempt or stall lasted before it was declared failed.
  ///
  /// 判定失败前这次尝试/卡顿持续了多久。
  final Duration waited;

  /// The underlying error object, when there was one.
  ///
  /// 底层错误对象（若有）。
  final Object? error;

  /// Whether an untried address remains after this one.
  ///
  /// 当前地址之后是否还有备选。
  bool get hasNextSource => sourceIndex + 1 < sourceCount;

  /// Creates a failure record.
  ///
  /// 创建一条失败记录。
  ///
  /// Example / 示例:
  /// ```dart
  /// const fail = MovaPlayFail(
  ///   kind: MovaPlayFailKind.startTimeout, sourceIndex: 0, uri: 'https://a',
  ///   sourceCount: 2, attempt: 1, streak: 1,
  /// );
  /// ```
  const MovaPlayFail({
    required this.kind,
    required this.sourceIndex,
    required this.uri,
    required this.sourceCount,
    required this.attempt,
    required this.streak,
    this.afterFirstFrame = false,
    this.waited = Duration.zero,
    this.error,
  });
}

/// What the engine does next.
///
/// 引擎接下来要做什么。
enum MovaRecoveryAction {
  /// Reload the same address.
  ///
  /// 重载同一个地址。
  retry,

  /// Move to the next alternative address.
  ///
  /// 切到下一个备选地址。
  failover,

  /// Stop trying and surface an error.
  ///
  /// 不再尝试，向外暴露错误。
  giveUp,
}

/// A policy's answer: an action plus how long to wait before acting.
///
/// 策略的答复：一个动作，加上执行前等多久。
class MovaRecoveryDecision {
  /// What to do.
  ///
  /// 要做什么。
  final MovaRecoveryAction action;

  /// How long to wait before doing it (backoff); always zero for [giveUp].
  ///
  /// 执行前等多久（退避）；[giveUp] 恒为零。
  final Duration delay;

  /// Reload the same address after [delay].
  ///
  /// 等 [delay] 后重载同一个地址。
  const MovaRecoveryDecision.retry({this.delay = Duration.zero}) : action = MovaRecoveryAction.retry;

  /// Move to the next alternative after [delay].
  ///
  /// 等 [delay] 后切到下一个备选。
  const MovaRecoveryDecision.failover({this.delay = Duration.zero}) : action = MovaRecoveryAction.failover;

  /// Stop trying.
  ///
  /// 不再尝试。
  const MovaRecoveryDecision.giveUp() : action = MovaRecoveryAction.giveUp, delay = Duration.zero;
}

/// Decides how to recover from a playback failure. The playback-side twin of
/// `MovaAdFailPolicy`: pure and injectable, so hosts with their own retry
/// budgets replace it wholesale.
///
/// 判定如何从一次播放失败中恢复。是播放侧的 `MovaAdFailPolicy`：纯粹、可注入，
/// 有自己重试预算的宿主可以整体替换。
///
/// Example / 示例:
/// ```dart
/// class GiveUpFast implements MovaRecoveryPolicy {
///   @override
///   MovaRecoveryDecision onFailure(MovaPlayFail fail) => const MovaRecoveryDecision.giveUp();
/// }
/// ```
abstract class MovaRecoveryPolicy {
  /// Answers what to do about [fail].
  ///
  /// 回答该如何处理 [fail]。
  ///
  /// - [fail]: the failure to judge / 要判定的失败
  ///
  /// Returns the decision; a thrown error is treated as give-up by the engine.
  ///
  /// 返回决策；抛出的异常会被引擎当作放弃。
  MovaRecoveryDecision onFailure(MovaPlayFail fail);
}

/// Retries each address [maxRetries] times after [retryDelay], then moves to
/// the next alternative, then gives up. The default policy.
///
/// 每个地址等 [retryDelay] 后重试 [maxRetries] 次，再切下一个备选，全部用完则放弃。
/// 默认策略。
///
/// Example / 示例:
/// ```dart
/// const MovaRecoveryConfig(enabled: true, policy: MovaRetryThenFailover(maxRetries: 2));
/// ```
class MovaRetryThenFailover implements MovaRecoveryPolicy {
  /// How many times one address is retried before moving on.
  ///
  /// 一个地址在换下一个前重试几次。
  final int maxRetries;

  /// Wait before each retry.
  ///
  /// 每次重试前的等待。
  final Duration retryDelay;

  /// Creates the policy.
  ///
  /// 创建策略。
  const MovaRetryThenFailover({this.maxRetries = 1, this.retryDelay = const Duration(seconds: 1)});

  @override
  MovaRecoveryDecision onFailure(MovaPlayFail fail) => fail.attempt <= maxRetries
      ? MovaRecoveryDecision.retry(delay: retryDelay)
      : fail.hasNextSource
          ? const MovaRecoveryDecision.failover()
          : const MovaRecoveryDecision.giveUp();
}

/// Never retries the same address: next alternative if any, else give up.
///
/// 从不重试同一地址：有备选就切，否则放弃。
///
/// Example / 示例:
/// ```dart
/// const MovaRecoveryConfig(enabled: true, policy: MovaFailoverOnly());
/// ```
class MovaFailoverOnly implements MovaRecoveryPolicy {
  /// Creates the policy.
  ///
  /// 创建策略。
  const MovaFailoverOnly();

  @override
  MovaRecoveryDecision onFailure(MovaPlayFail fail) =>
      fail.hasNextSource ? const MovaRecoveryDecision.failover() : const MovaRecoveryDecision.giveUp();
}

/// The error placed in `MovaState.error` once recovery gives up.
///
/// recovery 放弃后写入 `MovaState.error` 的错误。
class MovaGiveUpError implements Exception {
  /// The failure that exhausted recovery.
  ///
  /// 耗尽 recovery 的那次失败。
  final MovaPlayFail last;

  /// Creates the error.
  ///
  /// 创建错误。
  const MovaGiveUpError(this.last);

  @override
  String toString() => 'MovaGiveUpError(${last.kind.name}, ${last.uri})';
}
