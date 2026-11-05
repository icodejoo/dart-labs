/// Pluggable adaptive-bitrate downshift policy.
///
/// Implementations decide, from a stream of buffering-state observations,
/// when the engine should downshift to a lower quality. This is the
/// injection point referenced in DESIGN §6.3: apps that want a custom ABR
/// heuristic (e.g. bandwidth-based instead of stall-count-based) implement
/// this interface and pass it via [MovaAbrConfig.policy].
///
/// 可插拔的自适应码率降档策略。
///
/// 实现类根据一连串缓冲状态观测，判断内核何时应降档到更低清晰度。这是
/// DESIGN §6.3 所指的注入点：想用自定义 ABR 策略（如基于带宽而非卡顿次数）的
/// 应用可实现此接口，并通过 [MovaAbrConfig.policy] 传入。
abstract class MovaAbrPolicy {
  /// Feeds the latest buffering flag; returns true exactly when a downshift
  /// should happen now.
  ///
  /// 输入最新的缓冲标志；恰在应立即降档时返回 true。
  ///
  /// - [buffering]: current buffering state / 当前是否在缓冲
  ///
  /// Returns whether to downshift now / 返回是否应立即降档。
  bool onBuffering(bool buffering);

  /// Resets any accumulated state (e.g. after a manual quality change).
  ///
  /// 重置任何已累积的状态（如手动切换清晰度后）。
  void reset();
}

/// Heuristic buffering monitor for adaptive downshifting.
///
/// Counts buffering *rising edges* (playback stalls). When stalls reach
/// [threshold], [onBuffering] returns true once as a "downshift now" signal
/// and the counter resets. In the engine's native "auto" mode this monitor
/// is typically disabled and libmpv handles ABR itself; it exists to
/// downshift when the user has *pinned* a quality that the network can't
/// sustain.
///
/// 用于自适应降档的启发式缓冲监测。
///
/// 统计缓冲*上升沿*（播放卡顿）。当卡顿次数达到 [threshold]，[onBuffering]
/// 会返回一次 true 作为"立即降档"信号并重置计数。内核原生"自动"模式下通常
/// 禁用本监测、由 libmpv 自行做 ABR；它的价值在于当用户*锁定*了网络扛不住的
/// 清晰度时触发降档。
class MovaBufferAbr implements MovaAbrPolicy {
  /// Number of stalls that triggers a downshift suggestion.
  ///
  /// 触发降档建议所需的卡顿次数。
  final int threshold;

  bool _last = false;
  int _stalls = 0;

  /// Creates a monitor that downshifts after [threshold] stalls (default 3).
  ///
  /// 创建一个在 [threshold] 次卡顿后建议降档的监测器（默认 3）。
  MovaBufferAbr({this.threshold = 3});

  /// Number of stalls counted since the last downshift signal.
  ///
  /// 距上次降档信号以来累计的卡顿次数。
  int get stalls => _stalls;

  @override
  bool onBuffering(bool buffering) {
    final risingEdge = buffering && !_last;
    _last = buffering;
    if (!risingEdge) return false;
    _stalls++;
    if (_stalls >= threshold) {
      _stalls = 0;
      return true;
    }
    return false;
  }

  @override
  void reset() {
    _last = false;
    _stalls = 0;
  }
}

/// Adaptive-bitrate configuration.
///
/// When [policy] is left null, the engine builds a default
/// [MovaBufferAbr] seeded with [stallThreshold]. Supplying [policy]
/// overrides that default with a custom [MovaAbrPolicy] implementation
/// (DESIGN §6.3 ABR injection point).
///
/// 自适应码率配置。
///
/// [policy] 留空时，engine 会用 [stallThreshold] 构造默认的
/// [MovaBufferAbr]。传入 [policy] 则用自定义 [MovaAbrPolicy] 实现覆盖默认
/// 行为（DESIGN §6.3 的 ABR 注入口）。
class MovaAbrConfig {
  /// Stall count that triggers a downshift when using the default policy.
  ///
  /// 使用默认策略时，触发降档所需的卡顿次数。
  final int stallThreshold;

  /// Whether ABR downshifting is active at all.
  ///
  /// 是否启用 ABR 降档。
  final bool enabled;

  /// 就绪后是否自动探测 HLS 档位；默认开启，不代表接管 auto ABR。
  /// false 关闭引擎及默认 UI 的全部自动探测；UI 自动入口还要求其
  /// `autoLoadQualities` 为 true，两者都为 true 才自动探测。
  /// 宿主显式调用 `api.loadQualities()` 不受这两个开关影响。
  /// 示例：`MovaAbrConfig(probeVariants: false)` 由宿主手动探测。
  final bool probeVariants;

  /// 是否由 mova 接管 auto 档降档；实验性，默认关。
  /// 开启后卡顿触发时从 auto 转到列表次高档，后续沿用既有降档策略。
  /// 不推断 mpv 当前实际选档；仍需 [enabled] 开启，且探测到至少两个具体档位。
  /// 示例：`MovaAbrConfig(manageAuto: true)`。
  /// CP0 真机实测（STG-AL00、默认配置、限速夹具、90 秒窗口）：mpv 的 auto 档停留最高档、
  /// 未自动降档，限速下反复缓冲；开启本开关由 mova 的 ABR 接管降档。仍为实验性，默认关。
  final bool manageAuto;

  /// Custom downshift policy; null selects the default [MovaBufferAbr].
  ///
  /// 自定义降档策略；为 null 时选用默认的 [MovaBufferAbr]。
  /// 此实例由宿主持有；下个版本弃用，推荐改用 [policyFactory] 避免跨引擎共享状态。
  final MovaAbrPolicy? policy;

  /// 每次创建引擎时调用一次，返回该引擎独享的 ABR 策略；优先于 [policy]。
  /// 不传时继续使用旧实例或默认策略，不会额外创建策略。
  /// 示例：`MovaAbrConfig(policyFactory: () => MovaBufferAbr(threshold: 2))`。
  final MovaAbrPolicy Function()? policyFactory;

  /// Creates an ABR config; enabled by default with a stall threshold of 3.
  ///
  /// 创建 ABR 配置；默认启用，卡顿阈值为 3。
  /// [manageAuto] 为实验性 auto 降档接管，默认关，返回配置实例。
  /// 示例：`const MovaAbrConfig(manageAuto: true, stallThreshold: 3)`。
  const MovaAbrConfig({
    this.stallThreshold = 3,
    this.enabled = true,
    this.probeVariants = true,
    this.manageAuto = false,
    this.policy,
    this.policyFactory,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MovaAbrConfig &&
          runtimeType == other.runtimeType &&
          stallThreshold == other.stallThreshold &&
          enabled == other.enabled &&
          probeVariants == other.probeVariants &&
          manageAuto == other.manageAuto &&
          policy == other.policy &&
          policyFactory == other.policyFactory;

  @override
  int get hashCode => Object.hash(stallThreshold, enabled, probeVariants, manageAuto, policy, policyFactory);
}
