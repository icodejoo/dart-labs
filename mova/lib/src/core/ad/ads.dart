import 'dart:async';

import 'package:meta/meta.dart' show visibleForTesting;

import '../api.dart';
import '../cutover/ctl.dart';
import '../model/ad.dart';
import '../model/source.dart';
import '../options/ad_config.dart';
import '../session/session.dart';
import '../session/timeline.dart';

/// Returns the first not-yet-played mid-roll break whose [MovaAdBreak.offset] has
/// been reached at [position]; null when none is due.
///
/// Pure so the mid-roll trigger rule is unit-testable in isolation. Earliest
/// due break wins; the caller marks it played so the next tick surfaces the
/// following one.
///
/// 返回首个尚未播放、且 [MovaAdBreak.offset] 在 [position] 处已到达的中插广告位；
/// 没有到期的则返回 null。
///
/// 纯函数，使中插触发规则可单独单测。最早到期者优先；调用方将其标记为已播，
/// 下一个 tick 便浮现下一条。
MovaAdBreak? dueMidRoll(
  List<MovaAdBreak> breaks,
  Duration position,
  Set<MovaAdBreak> played,
) {
  return movaDueMidRoll(breaks, position, played);
}

/// Orchestrates pre/mid/post-roll ads on top of a [MovaApi] by swapping the
/// playing source between the content and each ad break.
///
/// Pure Dart (no Flutter dependency) so it stays unit-testable and lives in the
/// core layer. Host-constructed and injected — call [load] instead of
/// [MovaApi.open] to start content with its ads. Mid-roll saves the content
/// position and resumes there after the ad (relying on the engine's parked-seek
/// so the resume lands even before the resumed source reports a duration).
/// Click-through is never navigated here — it is surfaced via
/// [MovaAdConfig.onAdEvent].
///
/// 在 [MovaApi] 之上编排前/中/后贴片广告：在正片与各广告位之间切换正在播放的源。
///
/// 纯 Dart（无 Flutter 依赖），可单测并归属核心层。由宿主构造并注入——用 [load]
/// 代替 [MovaApi.open] 来带广告地起播正片。中插会保存正片位置并在广告后从该处续播
/// （依赖 engine 的 seek 寄存，使续播位置在被续播源尚未报告时长前也能落地）。
/// 点击跳转不会在此处执行——经 [MovaAdConfig.onAdEvent] 暴露给宿主。
///
/// 与播放列表组合时使用 `MovaPlaylist(api, ads: ads)` 共享会话。
/// 新代码推荐直接使用 [MovaSession]；本类长期保留为薄适配器。
class MovaAds {
  /// Creates a controller bound to [api], seeded from [MovaOpts.ads].
  ///
  /// [cutover] enables seamless ad→content swaps: it should be the same
  /// [MovaCutoverEngine] passed as [api], so the controller can drive it to
  /// warm the content up before the ad ends. Omit it (or pass an [api] that
  /// is not a cutover engine) to keep today's plain `open()` behaviour.
  ///
  /// 创建绑定到 [api] 的控制器，初值取自 [MovaOpts.ads]。
  ///
  /// [cutover] 用于开启广告→正片的无缝切换：它应当就是同时作为 [api] 传入的那个
  /// `MovaCutoverEngine`，使控制器能驱动它在广告结束前预热正片。省略它（或传入
  /// 非切换引擎的 [api]）即保持今天的普通 `open()` 行为。
  ///
  /// - [api]: the player capability surface to drive / 要驱动的播放器能力面
  /// - [cutover]: optional seamless-cutover capability, same instance as [api] /
  ///   可选的无缝切换能力面，与 [api] 是同一实例
  ///
  /// Example / 示例:
  /// ```dart
  /// final api = MovaCutoverEngine(engineFactory: createMovaEngine);
  /// final ads = MovaAds(api, cutover: api);
  /// await ads.load(const MovaSource('https://host/movie.m3u8'));
  /// ```
  MovaAds(MovaApi api, {MovaCutover? cutover})
    : _session = movaSessionForAds(api, cutover);

  final MovaSession _session;

  /// 返回共享会话；新代码推荐直接使用 MovaSession。
  /// 经此入口 load/jumpTo 与广告入口等价，dispose 任一入口即销毁同一会话。
  /// 示例：`await ads.session.load(source);`。
  MovaSession get session => _session;

  /// 广告时钟取时；测试注入随 fakeAsync 推进的函数，返回当前时刻。
  /// 示例：`ads.debugClock = () => origin.add(async.elapsed)`。
  @visibleForTesting
  // ignore: invalid_use_of_visible_for_testing_member
  DateTime Function() get debugClock => _session.debugClock;
  @visibleForTesting
  // ignore: invalid_use_of_visible_for_testing_member
  set debugClock(DateTime Function() value) => _session.debugClock = value;

  /// Whether an ad is currently on screen.
  ///
  /// 当前是否正在播放广告。
  bool get isShowingAd => _session.isShowingAd;

  /// The ad break currently playing, or null when none is.
  ///
  /// 当前正在播放的广告位；无则为 null。
  MovaAdBreak? get currentBreak => _session.currentBreak;

  /// Whether an ad is counting down to take over while the content still
  /// plays.
  ///
  /// 是否有一条广告正在倒计时、即将接管，而正片仍在播放。
  bool get isAdPending => _session.isAdPending;

  /// The break that is counting down, or null when none is.
  ///
  /// 正在倒计时的广告位；没有则为 null。
  MovaAdBreak? get pendingBreak => _session.pendingBreak;

  /// Time left before the pending ad takes over, or null when none is pending
  /// or the pending break has no visible countdown.
  ///
  /// Null for the default mid-roll shape (`delay == 0`, waiting silently for
  /// readiness): that wait is meant to be invisible, so there is nothing to
  /// render.
  ///
  /// 距待播广告接管还剩的时长；没有待播广告、或待播广告位没有可见倒计时时为 null。
  ///
  /// 中插的默认形态（`delay == 0`、静默等待就绪）下返回 null：那段等待本就该是
  /// 用户无感的，没有任何东西需要渲染。
  Duration? get delayRemaining => _session.delayRemaining;

  /// Elapsed time into the current ad (from zero).
  ///
  /// 当前广告已播放的时长（从零开始）。
  Duration get adPosition => _session.adPosition;

  /// Whether the current ad may be skipped right now.
  ///
  /// 当前广告此刻是否可跳过。
  bool get canSkip => _session.canSkip;

  /// Time remaining until the current ad becomes skippable, or null when the
  /// ad is not skippable at all.
  ///
  /// 距当前广告可跳过还剩的时长；广告完全不可跳过时为 null。
  Duration? get skipIn => _session.skipIn;

  /// Fires whenever the ad phase or current break changes (start/end/skip);
  /// UI can rebuild off this in addition to the progress stream.
  ///
  /// 每当广告阶段或当前广告位变化（开始/结束/跳过）时发出；UI 可据此（外加进度流）
  /// 重建。
  Stream<void> get changes => _session.changes;

  /// 正片及全部后贴片结束时发出一次通知；返回广播流。
  /// `MovaPlaylist(api, ads: ads)` 使用此信号自动连播。
  /// 示例：`ads.contentEnded.listen((_) => showFinished());`。
  Stream<void> get contentEnded => _session.contentEnded;

  /// Reports resolver, content-open and terminal content failures.
  ///
  /// 返回正片源解析、打开/切换失败与正片终结错误的异常流；回 idle，由宿主决定重试。
  /// recovery 开启时等待引擎 giveUp，非终结诊断不触发本流。
  /// 宿主钩子拒绝 open、或已过期加载的迟到异常不触发本流；不代表所有播放错误。
  ///
  /// 示例：`ads.contentError.listen((error) => showRetry(error));`
  Stream<Object> get contentError => _session.contentError;

  /// Loads [content] with its scheduled ads: plays a pre-roll first when one is
  /// configured, otherwise starts the content directly.
  ///
  /// 带排期广告地加载 [content]：配置了前贴片则先播它，否则直接起播正片。
  ///
  /// - [content]: the main content source / 正片源
  ///
  /// 返回是否被接受为当前内容；接受不等于出首帧，正片异常通过 [contentError] 通知。
  /// 示例：`await ads.load(const MovaSource('https://host/movie.mp4'));`
  Future<bool> load(MovaSource content) => movaAdsLoad(_session, content);

  /// Loads content whose source is resolved lazily, with its scheduled ads.
  ///
  /// Behaves exactly like [load] except that [resolve] is not called until the
  /// content is actually about to be opened — after every pre-roll has
  /// finished, or (when seamless swapping is on) a couple of seconds before
  /// the last pre-roll ends, when the content starts warming up. The result is
  /// memoised: [resolve] is called at most once per [loadDeferred].
  ///
  /// If [resolve] throws or rejects, the controller goes idle and the error is
  /// reported on [contentError]; the host decides whether to call
  /// [loadDeferred] again.
  ///
  /// 带排期广告地加载一段"源需要惰性解析"的正片。
  ///
  /// 与 [load] 完全相同，区别只在于 [resolve] 直到正片真的要被打开时才调用——
  /// 即所有前贴片播完之后，或（开启无缝切换时）最后一条前贴片结束前一两秒、
  /// 正片开始预热之时。结果会被记忆化：每次 [loadDeferred] 最多调用一次
  /// [resolve]。
  ///
  /// [resolve] 抛出或 reject 时，控制器转入空闲，错误经 [contentError] 上报；
  /// 是否重新调用 [loadDeferred] 由宿主决定。
  ///
  /// - [resolve]: resolves the content source on demand / 按需解析正片源
  ///
  /// 返回是否被接受为当前内容；接受不等于出首帧，解析与正片打开异常通过 [contentError] 通知。
  ///
  /// Example / 示例:
  /// ```dart
  /// await ads.loadDeferred(() async {
  ///   final play = await api.requestPlayback(videoId);  // DRM / signed URL
  ///   return MovaSource(play.url, title: play.title);
  /// });
  /// ```
  Future<bool> loadDeferred(MovaSourceResolver resolve) =>
      movaAdsLoadDeferred(_session, resolve);

  /// Immediately interrupts the content to play [ad] at an arbitrary point,
  /// then resumes the content where it was interrupted. For ads scheduled at
  /// runtime rather than pre-configured in [MovaAdConfig.breaks]; only fires
  /// while content is actually playing. [ad] should be a
  /// [MovaAdBreakKind.mid] break — its own [MovaAdBreak.offset] is ignored, "now"
  /// is the current content position.
  ///
  /// 立即打断正片，在任意时点插播 [ad]，播完回到打断处续播。用于运行时（而非
  /// 在 [MovaAdConfig.breaks] 预配置）插播的广告；仅在正片确实在播放时生效。[ad]
  /// 应为 [MovaAdBreakKind.mid]——其自身的 [MovaAdBreak.offset] 被忽略，"当下"即当前
  /// 正片位置。
  ///
  /// - [ad]: the ad break to insert now / 要即时插入的广告位
  ///
  /// Example / 示例:
  /// ```dart
  /// ads.playAdNow(const MovaAdBreak(
  ///   kind: MovaAdBreakKind.mid,
  ///   source: MovaSource('https://host/flash-sale.mp4'),
  ///   skippableAfter: Duration(seconds: 5),
  /// ));
  /// ```
  Future<void> playAdNow(MovaAdBreak ad) => _session.playAdNow(ad);

  /// Skips the current ad if it is skippable right now; no-op otherwise.
  ///
  /// Also a no-op in [_Phase.pending]: there is no ad on screen to skip yet,
  /// and cancelling an ad that is about to play is a host product decision.
  ///
  /// 若当前广告此刻可跳过则跳过；否则为空操作。
  ///
  /// 在 [_Phase.pending] 阶段同样是空操作：屏幕上还没有广告可跳，而"取消一条
  /// 即将播放的广告"是宿主的产品决策。
  void skip() => _session.skip();

  /// Reports a click on the current ad; the host acts on
  /// [MovaAdBreak.clickThroughUrl], the library does not navigate.
  ///
  /// 上报一次对当前广告的点击；由宿主处理 [MovaAdBreak.clickThroughUrl]，库不跳转。
  void notifyClicked() => _session.notifyClicked();

  /// Releases subscriptions and closes the change stream; call once on
  /// teardown.
  ///
  /// 释放订阅并关闭变更流；销毁时调用一次。
  Future<void> dispose() => _session.dispose();
}
