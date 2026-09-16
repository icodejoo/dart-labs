import '../model/source.dart';
import 'trigger.dart';

/// Which stage of a swap the engine is in.
///
/// 引擎当前处于切换的哪个阶段。
enum MovaSwapPhase {
  /// One engine live, no shadow.
  ///
  /// 单引擎生效，无影子引擎。
  idle,

  /// A shadow engine exists and is warming up.
  ///
  /// 影子引擎已存在，正在预热。
  warming,

  /// The shadow engine is ready; a commit will be instant.
  ///
  /// 影子引擎已就绪；此时提交切换是瞬时的。
  ready,
}

/// The swap capability surface consumers drive, kept separate from [MovaApi]
/// so callers like `MovaAdCtrl` depend on the swap verbs alone and can be
/// tested against a tiny fake.
///
/// 调用方驱动的切换能力面，与 [MovaApi] 分开，使 `MovaAdCtrl` 这类调用方
/// 只依赖切换动词，并能对着一个极小的假对象做测试。
abstract class MovaSwapCtl {
  /// Whether seamless swapping is configured on.
  ///
  /// 是否已配置开启无缝切换。
  bool get swapEnabled;

  /// The current swap phase.
  ///
  /// 当前切换阶段。
  MovaSwapPhase get swapPhase;

  /// Emits every swap phase transition.
  ///
  /// 每次切换阶段迁移时推送。
  Stream<MovaSwapPhase> get swapPhases;

  /// Asks the configured trigger whether to start warming [source] at [at],
  /// and starts a shadow engine if it says yes.
  ///
  /// Safe to call on every progress tick: it is a no-op when swapping is
  /// disabled, when the trigger declines, or when a shadow for the same
  /// source is already warming.
  ///
  /// 询问已配置的触发策略是否应开始在 [at] 预热 [source]，若是则启动影子引擎。
  ///
  /// 可安全地在每个进度 tick 上调用：切换被禁用、触发策略拒绝、或同一源的
  /// 影子引擎已在预热时，均为空操作。
  ///
  /// - [source]: the media to warm up / 要预热的媒体
  /// - [at]: the position the swap should land on / 切换应落在的位置
  /// - [cue]: what is known about the switch point / 关于切换点的已知信息
  ///
  /// Example / 示例:
  /// ```dart
  /// await swap.prepare(content, at: resumeAt,
  ///     cue: MovaWarmCue(remaining: adLeft, total: adLength));
  /// ```
  Future<void> prepare(
    MovaSource source, {
    Duration at = Duration.zero,
    MovaWarmCue cue = const MovaWarmCue(),
  });

  /// Promotes a ready shadow engine to be the live one and disposes the old.
  ///
  /// 把已就绪的影子引擎转正为生效引擎，并释放旧引擎。
  ///
  /// - [waitForReady]: when true, waits out the readiness policy (bounded by
  ///   its own timeout) instead of refusing immediately /
  ///   为 true 时等待就绪判据出结果（受其自身超时约束），而不是立即拒绝
  ///
  /// Returns whether the swap happened; `false` means the caller must fall
  /// back to a plain `open()`.
  ///
  /// 返回切换是否发生；`false` 表示调用方须回落到普通 `open()`。
  Future<bool> commit({bool waitForReady = false});

  /// Tears down any shadow engine without swapping.
  ///
  /// 拆除影子引擎（若有），不执行切换。
  Future<void> abandon();

  /// Warms [source] and commits as soon as it is ready, falling back to a
  /// plain `open()` on the live engine when warming is declined or times out.
  ///
  /// The one-call form for unpredictable switch points (quality switching,
  /// playlist next-episode). [prepare] + [commit] is the two-phase form for
  /// predictable ones (ads).
  ///
  /// 预热 [source] 并在就绪后立即提交；预热被拒或超时时回落到在生效引擎上做
  /// 普通 `open()`。
  ///
  /// 这是面向不可预测切换点（清晰度切换、播放列表下一集）的一次性调用形式；
  /// 面向可预测切换点（广告）的两段式形式是 [prepare] + [commit]。
  ///
  /// - [source]: the media to switch to / 要切换到的媒体
  /// - [at]: the position to land on / 要落到的位置
  ///
  /// Returns whether the switch was seamless / 返回本次切换是否为无缝切换。
  Future<bool> swapTo(MovaSource source, {Duration at = Duration.zero});
}
