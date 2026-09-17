import '../ad/fail.dart';
import '../model/ad.dart';
import '../swap/plan.dart';
import '../swap/trigger.dart';
import '../swap/warm.dart';

/// Decides whether a given ad break should be warmed up and cut to only once
/// it is actually ready to play.
///
/// Injectable so hosts can base the answer on anything they know and mova does
/// not — current network class, whether the creative is a high-value takeover,
/// a server-side flag, an A/B bucket. The built-in [MovaAdWaitByKind] answers
/// it from the break's [MovaAdBreakKind] alone.
///
/// 判定某一条广告位是否应当先预热、待其真正可播后才切入。
///
/// 可注入，使宿主能依据任何 mova 不知道的信息作答——当前网络等级、这条素材
/// 是不是高价值大包段、服务端下发的开关、A/B 分桶。内置的
/// [MovaAdWaitByKind] 仅依据广告位的 [MovaAdBreakKind] 作答。
abstract class MovaAdWaitPolicy {
  /// Returns whether [adBreak] should wait for readiness before cutting in.
  ///
  /// 返回 [adBreak] 是否应等待就绪后再切入。
  ///
  /// - [adBreak]: the break about to play / 即将播放的广告位
  ///
  /// Returns whether to wait / 返回是否等待。
  bool waitFor(MovaAdBreak adBreak);
}

/// Answers "wait for readiness?" per [MovaAdBreakKind], defaulting to the one
/// rule that follows from what is on screen during the wait.
///
/// The value of waiting equals the value of the picture the viewer is looking
/// at while you wait. During a **mid-roll** that picture is the content they
/// are actively watching, and cutting it to a loading spinner both ruins the
/// moment and spends an impression on a black rectangle — so [mid] defaults to
/// true. During a **pre-roll** there is no picture at all: the ad's own
/// loading state *is* the first screen the viewer expects, nothing is being
/// interrupted, and waiting would only push that first screen further out — so
/// [pre] defaults to false. A **post-roll** follows the same logic as a
/// pre-roll: the content is over, there is no ongoing experience to protect —
/// so [post] defaults to false.
///
/// 依 [MovaAdBreakKind] 回答"是否等待就绪"，默认值由"等待期间屏幕上是什么"
/// 这一条判据推出。
///
/// 等待的价值，等于等待期间用户正看着的那张画面的价值。**中插**期间那张画面
/// 是用户正在观看的正片，把它切成一个转圈既毁掉了当下的观看体验，又把一次
/// 曝光花在了黑矩形上——所以 [mid] 默认 true。**前贴片**期间压根没有画面：
/// 广告自身的加载态*就是*用户预期看到的第一屏，没有任何东西被打断，等待只会
/// 把这第一屏更加推后——所以 [pre] 默认 false。**后贴片**与前贴片同理：
/// 正片已经结束，没有正在进行的体验需要保护——所以 [post] 默认 false。
class MovaAdWaitByKind implements MovaAdWaitPolicy {
  /// Whether pre-rolls wait; false by default.
  ///
  /// 前贴片是否等待；默认 false。
  final bool pre;

  /// Whether mid-rolls wait; true by default.
  ///
  /// 中插是否等待；默认 true。
  final bool mid;

  /// Whether post-rolls wait; false by default.
  ///
  /// 后贴片是否等待；默认 false。
  final bool post;

  /// Creates a per-kind wait rule.
  ///
  /// 创建一份按类型区分的等待规则。
  ///
  /// - [pre]: wait before pre-rolls / 前贴片前是否等待
  /// - [mid]: wait before mid-rolls / 中插前是否等待
  /// - [post]: wait before post-rolls / 后贴片前是否等待
  ///
  /// Example / 示例:
  /// ```dart
  /// // Also wait for post-rolls (a high-value next-episode teaser).
  /// // 后贴片也等待（一条高价值的下集预告）。
  /// const MovaAdConfig(waitForAdReady: MovaAdWaitByKind(post: true));
  ///
  /// // Never wait, anywhere — back to 0.4.0 behaviour.
  /// // 任何位置都不等待——回到 0.4.0 行为。
  /// const MovaAdConfig(waitForAdReady: MovaAdWaitByKind(mid: false));
  /// ```
  const MovaAdWaitByKind({this.pre = false, this.mid = true, this.post = false});

  @override
  bool waitFor(MovaAdBreak adBreak) => switch (adBreak.kind) {
        MovaAdBreakKind.pre => pre,
        MovaAdBreakKind.mid => mid,
        MovaAdBreakKind.post => post,
      };
}

/// What to do when an ad was supposed to be warmed up before cutting in, but
/// was not ready in time.
///
/// 当广告本该预热就绪后再切入、却没能及时就绪时该怎么办。
enum MovaAdNotReady {
  /// Cut to the ad anyway, accepting whatever blank/loading the player shows.
  /// Preserves ad inventory at the cost of the viewer's experience.
  ///
  /// 照切不误，接受播放器呈现的黑屏/loading。以观众体验为代价保住广告库存。
  hardCut,

  /// Drop this break entirely; the content is never interrupted. Protects the
  /// viewer — and arguably the advertiser too, since an impression rendered as
  /// a black rectangle is an impression wasted.
  ///
  /// 完全丢弃这条广告位，正片不被打断。保护观众——某种意义上也保护了广告主，
  /// 因为呈现为一块黑矩形的曝光就是被浪费掉的曝光。
  dropBreak,
}

/// Configuration for pre/mid/post-roll ads.
///
/// Disabled and empty by default so enabling it is an explicit host decision.
/// The controller (`MovaAdCtrl`) is host-constructed and orchestrates the
/// content↔ad source swaps; this bundle only carries the schedule and the
/// [onAdEvent] hook (the sole way click-through is surfaced — mova never
/// opens a URL itself).
///
/// 前/中/后贴片广告的配置。
///
/// 默认关闭且列表为空，是否启用由宿主显式决定。控制器（`MovaAdCtrl`）由宿主
/// 构造并编排正片↔广告的源切换；本配置只承载排期与 [onAdEvent] 钩子（点击跳转的
/// 唯一暴露途径——mova 从不自行打开 URL）。
class MovaAdConfig {
  /// Master switch; no ads play when `false`.
  ///
  /// 总开关；为 `false` 时不播放任何广告。
  final bool enabled;

  /// The ad breaks to schedule.
  ///
  /// 要排期的广告位列表。
  final List<MovaAdBreak> breaks;

  /// Host hook notified of every ad lifecycle event, including
  /// [MovaAdEventType.clicked] (which carries the click-through URL to act on).
  ///
  /// 宿主钩子，接收每个广告生命周期事件，包括 [MovaAdEventType.clicked]
  /// （携带可供处理的点击跳转地址）。
  final void Function(MovaAdEvent event)? onAdEvent;

  /// Whether an ad is warmed up and cut to only once ready; consulted only
  /// when [MovaAdBreak.waitForReady] leaves the question open.
  ///
  /// 是否先预热广告、待其就绪后才切入；仅在 [MovaAdBreak.waitForReady]
  /// 未表态时才被咨询。
  final MovaAdWaitPolicy waitForAdReady;

  /// Upper bound on how long an ad may be waited for before
  /// [notReadyAction] decides what to do instead.
  ///
  /// 等待广告就绪的上限；超过后由 [notReadyAction] 裁决改做什么。
  final Duration adReadyTimeout;

  /// What to do when the wait ran out; [MovaAdNotReady.hardCut] by default,
  /// because the fallback must be exactly today's behaviour.
  ///
  /// 等不到时怎么办；默认 [MovaAdNotReady.hardCut]，因为降级路径必须恰好等于
  /// 今天的行为。
  final MovaAdNotReady notReadyAction;

  /// Injectable recovery rule for ads that will not play; null uses
  /// [MovaAdRetrySkip].
  ///
  /// 播不出来的广告的可注入兜底规则；null 表示使用 [MovaAdRetrySkip]。
  final MovaAdFailPolicy? failPolicy;

  /// How long after `open()` an ad with no first frame counts as failed.
  ///
  /// `open()` 之后多久仍无首帧即算作加载失败。
  final Duration loadTimeout;

  /// Whether [MovaAdBreak.duration] is counted from the ad's first rendered
  /// frame rather than from `open()`.
  ///
  /// Defaults to true: the slot the advertiser bought is *visible* seconds, so
  /// a slow load must not eat into it.
  ///
  /// [MovaAdBreak.duration] 是否从广告首帧起算（而非从 `open()` 起算）。
  ///
  /// 默认 true：广告主买的是*可见*秒数，加载慢不应该吃掉这段时长。
  final bool durationFromFirstFrame;

  /// Injectable warm-up plan for the content→ad direction; null uses
  /// [effectiveWarmPlan]'s default.
  ///
  /// content→ad 方向的可注入预热计划；null 表示使用 [effectiveWarmPlan] 的默认值。
  final MovaWarmPlan? adWarmPlan;

  /// Creates an ad configuration; disabled and empty by default.
  ///
  /// 创建广告配置；默认关闭且列表为空。
  ///
  /// - [enabled]: master switch / 总开关
  /// - [breaks]: ad break schedule / 广告位排期
  /// - [onAdEvent]: lifecycle hook / 生命周期钩子
  /// - [waitForAdReady]: per-kind readiness-wait rule / 按类型的就绪等待规则
  /// - [adReadyTimeout]: readiness-wait ceiling / 就绪等待上限
  /// - [notReadyAction]: what to do when the wait ran out / 等不到时怎么办
  /// - [failPolicy]: ad failure recovery rule / 广告失败兜底规则
  /// - [loadTimeout]: no-first-frame deadline / 无首帧的判定期限
  /// - [durationFromFirstFrame]: count the slot from the first frame / 广告位时长从首帧起算
  /// - [adWarmPlan]: content→ad warm-up plan / content→ad 方向的预热计划
  const MovaAdConfig({
    this.enabled = false,
    this.breaks = const <MovaAdBreak>[],
    this.onAdEvent,
    this.waitForAdReady = const MovaAdWaitByKind(),
    this.adReadyTimeout = const Duration(seconds: 5),
    this.notReadyAction = MovaAdNotReady.hardCut,
    this.failPolicy,
    this.loadTimeout = const Duration(seconds: 8),
    this.durationFromFirstFrame = true,
    this.adWarmPlan,
  });

  /// Resolves whether [adBreak] waits for readiness: the break's own
  /// [MovaAdBreak.waitForReady] wins when set, otherwise [waitForAdReady]
  /// decides.
  ///
  /// This is the single place the three-layer override happens, so callers —
  /// `MovaAdCtrl` above all — never inspect [MovaAdBreakKind] themselves; a
  /// `kind == mid` branch anywhere else would make the host's override
  /// unreachable.
  ///
  /// 解析 [adBreak] 是否等待就绪：广告位自身的 [MovaAdBreak.waitForReady]
  /// 设了就以它为准，否则交由 [waitForAdReady] 裁决。
  ///
  /// 三层覆盖只在这一处发生，因此调用方——尤其是 `MovaAdCtrl`——绝不自行检查
  /// [MovaAdBreakKind]；别处出现 `kind == mid` 这类分支会让宿主的覆盖绕不过去。
  ///
  /// - [adBreak]: the break about to play / 即将播放的广告位
  ///
  /// Returns whether to wait / 返回是否等待。
  bool waitsFor(MovaAdBreak adBreak) =>
      adBreak.waitForReady ?? waitForAdReady.waitFor(adBreak);

  /// The warm-up plan used for the content→ad direction.
  ///
  /// Defaults to eager (the whole point of [MovaAdBreak.delay] is to spend
  /// that window warming up, so there is nothing to wait for), buffer-based
  /// readiness bounded by [adReadyTimeout], and `pauseWhenReady: true` so the
  /// ad is shown from its first frame.
  ///
  /// 用于 content→ad 方向的预热计划。
  ///
  /// 默认立即触发（[MovaAdBreak.delay] 窗口存在的全部意义就是拿来预热，没有
  /// 再等的道理）、以 [adReadyTimeout] 为界的缓冲判据、以及 `pauseWhenReady:
  /// true` 使广告从第一帧开始展示。
  MovaWarmPlan get effectiveWarmPlan =>
      adWarmPlan ??
      MovaWarmPlan(
        trigger: const MovaEagerWarm(),
        policy: MovaBufferWarm(timeout: adReadyTimeout),
        pauseWhenReady: true,
      );

  /// The failure policy actually in effect.
  ///
  /// 实际生效的失败兜底策略。
  MovaAdFailPolicy get effectiveFailPolicy => failPolicy ?? const MovaAdRetrySkip();

  /// Returns a copy with the given fields replaced; omitted fields keep their
  /// current value.
  ///
  /// 返回一份替换了指定字段的拷贝；未指定的字段保持当前值。
  MovaAdConfig copyWith({
    bool? enabled,
    List<MovaAdBreak>? breaks,
    void Function(MovaAdEvent event)? onAdEvent,
    MovaAdWaitPolicy? waitForAdReady,
    Duration? adReadyTimeout,
    MovaAdNotReady? notReadyAction,
    MovaAdFailPolicy? failPolicy,
    Duration? loadTimeout,
    bool? durationFromFirstFrame,
    MovaWarmPlan? adWarmPlan,
  }) {
    return MovaAdConfig(
      enabled: enabled ?? this.enabled,
      breaks: breaks ?? this.breaks,
      onAdEvent: onAdEvent ?? this.onAdEvent,
      waitForAdReady: waitForAdReady ?? this.waitForAdReady,
      adReadyTimeout: adReadyTimeout ?? this.adReadyTimeout,
      notReadyAction: notReadyAction ?? this.notReadyAction,
      failPolicy: failPolicy ?? this.failPolicy,
      loadTimeout: loadTimeout ?? this.loadTimeout,
      durationFromFirstFrame: durationFromFirstFrame ?? this.durationFromFirstFrame,
      adWarmPlan: adWarmPlan ?? this.adWarmPlan,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MovaAdConfig &&
          runtimeType == other.runtimeType &&
          enabled == other.enabled &&
          identical(breaks, other.breaks) &&
          onAdEvent == other.onAdEvent &&
          waitForAdReady == other.waitForAdReady &&
          adReadyTimeout == other.adReadyTimeout &&
          notReadyAction == other.notReadyAction &&
          failPolicy == other.failPolicy &&
          loadTimeout == other.loadTimeout &&
          durationFromFirstFrame == other.durationFromFirstFrame &&
          adWarmPlan == other.adWarmPlan;

  @override
  int get hashCode => Object.hash(
        enabled,
        breaks,
        onAdEvent,
        waitForAdReady,
        adReadyTimeout,
        notReadyAction,
        failPolicy,
        loadTimeout,
        durationFromFirstFrame,
        adWarmPlan,
      );
}
