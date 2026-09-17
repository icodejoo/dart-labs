import 'source.dart';

/// Where an ad break is inserted relative to the content.
///
/// 广告位相对正片的插入位置。
enum MovaAdBreakKind {
  /// Before the content starts (pre-roll).
  ///
  /// 正片开始前（前贴片）。
  pre,

  /// At a specific offset into the content (mid-roll).
  ///
  /// 正片播放到某个时间点（中插）。
  mid,

  /// After the content finishes (post-roll).
  ///
  /// 正片结束后（后贴片）。
  post,
}

/// One ad break: the ad media plus when and how it plays.
///
/// The library never navigates on click — [clickThroughUrl] is surfaced to the
/// host through [MovaAdConfig.onAdEvent] (a [MovaAdEventType.clicked] event) and the
/// host decides what to do with it. This keeps mova free of a URL-launcher
/// dependency.
///
/// 一个广告位：广告媒体，加上何时、如何播放。
///
/// 库本身从不在点击时跳转——[clickThroughUrl] 通过 [MovaAdConfig.onAdEvent]
/// （一个 [MovaAdEventType.clicked] 事件）暴露给宿主，由宿主决定如何处理。这样
/// mova 不必依赖任何打开 URL 的第三方库。
class MovaAdBreak {
  /// Where this break is inserted.
  ///
  /// 该广告位的插入位置。
  final MovaAdBreakKind kind;

  /// The ad media source.
  ///
  /// 广告媒体源。
  final MovaSource source;

  /// For [MovaAdBreakKind.mid], the content offset at which it plays; ignored
  /// for pre/post.
  ///
  /// 对 [MovaAdBreakKind.mid]，表示插播的正片时间点；对前/后贴片忽略。
  final Duration offset;

  /// How long the content keeps playing after this break becomes due, before
  /// the ad actually takes over — the window a "your video resumes after this
  /// ad" countdown badge is shown in.
  ///
  /// Deliberately *not* a blank-screen wait: the content plays on for the whole
  /// countdown, which is both a better experience and (when
  /// [MovaAdConfig.waitForAdReady] is on) exactly the window the ad is warmed
  /// up in. Only meaningful for [MovaAdBreakKind.mid] — a pre-roll has no
  /// content to play during the countdown and a post-roll has none left.
  /// Within an ad pod only the *first* break's delay is honoured; see
  /// `MovaAdCtrl`.
  ///
  /// 该广告位到期后、广告真正接管画面之前，正片继续播放的时长——也就是
  /// "N 秒后播放广告"角标显示的那段窗口。
  ///
  /// 刻意*不是*黑屏等待：整个倒计时期间正片照常播放，这既是更好的体验，也
  /// （在 [MovaAdConfig.waitForAdReady] 开启时）正好就是预热广告的那个窗口。
  /// 仅对 [MovaAdBreakKind.mid] 有意义——前贴片倒计时期间没有正片可播，后贴片
  /// 则已经播完了。一个广告 pod 里只有*第一条*的 delay 生效，见 `MovaAdCtrl`。
  final Duration delay;

  /// How long this ad slot runs before the content resumes, regardless of the
  /// ad media's own length; null means "play the media to its end".
  ///
  /// Decoupled from the media on purpose. The slot that was bought is 15
  /// seconds; the creative handed over may be longer, shorter, or a generic
  /// loop. Enforcement is a plain [Timer] started at the ad's first rendered
  /// frame and never touches the media timeline — the engine is not asked for
  /// a duration (which can take a long time to resolve over a real mobile
  /// network on a large file) and is never seeked near its real EOF (which
  /// reliably wedges the player on device). Expiry takes the exact same
  /// synchronous resume path `skip()` takes, which is the one path already
  /// proven on hardware.
  ///
  /// 该广告位运行多久后续播正片，与广告素材自身长度无关；null 表示"把素材播到
  /// 结束"。
  ///
  /// 刻意与素材解耦。买的广告位是 15 秒，交付的素材可能更长、更短、或是一段
  /// 通用循环片。到期判定是一个从广告首帧起算的普通 [Timer]，完全不碰媒体
  /// 时间轴——不向引擎要时长（大文件在真机移动网络下可能很久解析不出来），
  /// 也绝不 seek 到素材真实 EOF 附近（真机上会可靠地把播放器卡死）。到期后
  /// 走的是与 `skip()` 完全相同的同步续播路径，那是唯一已在真机上验证过的路径。
  final Duration? duration;

  /// Whether the player waits for this ad to actually be ready before cutting
  /// to it, overriding [MovaAdConfig.waitForAdReady] for this one break; null
  /// defers to the config.
  ///
  /// The per-break escape hatch on top of the per-kind default. Set it when
  /// one particular creative deserves different treatment from the rest of its
  /// kind — a mid-roll from a CDN known to be slow that you would rather cut
  /// to immediately than delay, or a post-roll carrying a high-value
  /// next-episode teaser that is worth waiting for.
  ///
  /// Only has any effect when the host wired a `MovaSwapCtl` and
  /// [MovaSwapConfig.enabled] is true; with no swap engine there is nothing to
  /// warm up in and the field is ignored.
  ///
  /// 播放器是否等这条广告真的就绪后才切过去；为该条广告位覆盖
  /// [MovaAdConfig.waitForAdReady]，null 表示沿用配置。
  ///
  /// 这是架在"按 kind 取默认值"之上的单条逃生口。当某一条素材值得与同类其他
  /// 广告位区别对待时使用——比如一条来自已知较慢 CDN 的中插，你宁可立刻硬切
  /// 也不愿推迟；又比如一条承载高价值"下集预告"的后贴片，值得为它等一等。
  ///
  /// 仅在宿主接了 `MovaSwapCtl` 且 [MovaSwapConfig.enabled] 为 true 时才有
  /// 效果；没有切换引擎就没有可预热之处，该字段被忽略。
  final bool? waitForReady;

  /// How long into the ad the viewer may skip; null means not skippable.
  ///
  /// 广告播放多久后可跳过；null 表示不可跳过。
  final Duration? skippableAfter;

  /// Optional click-through URL; the library only reports it via
  /// [MovaAdConfig.onAdEvent] and never opens it.
  ///
  /// 可选的点击跳转地址；库仅经 [MovaAdConfig.onAdEvent] 上报，绝不主动打开。
  final String? clickThroughUrl;

  /// Creates an ad break.
  ///
  /// 创建一个广告位。
  ///
  /// - [kind]: insertion position / 插入位置
  /// - [source]: ad media / 广告媒体
  /// - [offset]: mid-roll content offset / 中插的正片时间点
  /// - [delay]: countdown before the ad takes over / 广告接管前的倒计时
  /// - [duration]: fixed slot length / 固定的广告位时长
  /// - [waitForReady]: per-break readiness override / 单条广告位的就绪等待覆盖
  /// - [skippableAfter]: skip-allowed threshold / 允许跳过的阈值
  /// - [clickThroughUrl]: reported-only click URL / 仅上报的点击地址
  ///
  /// Example / 示例:
  /// ```dart
  /// const MovaAdBreak(
  ///   kind: MovaAdBreakKind.pre,
  ///   source: MovaSource('https://host/preroll.mp4'),
  ///   skippableAfter: Duration(seconds: 5),
  /// );
  /// ```
  const MovaAdBreak({
    required this.kind,
    required this.source,
    this.offset = Duration.zero,
    this.delay = Duration.zero,
    this.duration,
    this.waitForReady,
    this.skippableAfter,
    this.clickThroughUrl,
  });

  /// Asserts this break's construction-time invariants; a no-op in release.
  ///
  /// Called by `MovaAdCtrl` for every break it is handed, so a misconfigured
  /// schedule fails loudly on the developer's machine and costs nothing in
  /// production. It is a method rather than an `assert` in the constructor
  /// initialiser list because [MovaAdBreak] is `const` and Dart's constant
  /// evaluator cannot compare [Duration]s — neither `>` nor `==` nor
  /// `inMicroseconds` is available to it — so such an assert would make
  /// *every* `const MovaAdBreak(...)` a compile error, valid ones included.
  ///
  /// The two invariants:
  /// - [duration] must outlast [skippableAfter], otherwise the slot is
  ///   force-resumed before the skip control ever appears and the ad is, in
  ///   practice, unskippable — an error that on device looks like "this
  ///   player's skip button is broken" and is extremely hard to attribute.
  /// - [delay] is only meaningful for [MovaAdBreakKind.mid].
  ///
  /// 断言该广告位的构造期不变量；release 下为空操作。
  ///
  /// `MovaAdCtrl` 对拿到的每一条广告位都会调用它，使配错的排期在开发者机器上
  /// 大声失败、在生产环境零成本。之所以做成方法而不是构造器初始化列表里的
  /// `assert`：[MovaAdBreak] 是 `const` 的，而 Dart 的常量求值器无法比较
  /// [Duration]——`>`、`==`、`inMicroseconds` 它都不支持——那样的 assert 会让
  /// *每一处* `const MovaAdBreak(...)` 都变成编译错误，合法的也不例外。
  ///
  /// 两条不变量：
  /// - [duration] 必须长于 [skippableAfter]，否则广告位会在跳过控件出现之前就被
  ///   强制续播，这条广告实际上不可跳过——这个错误在真机上的表现是"这个播放器的
  ///   跳过按钮是坏的"，极难归因。
  /// - [delay] 只对 [MovaAdBreakKind.mid] 有意义。
  ///
  /// Example / 示例:
  /// ```dart
  /// for (final b in breaks) {
  ///   b.assertValid();
  /// }
  /// ```
  void assertValid() {
    final d = duration;
    final s = skippableAfter;
    assert(
      d == null || s == null || d > s,
      'duration must outlast skippableAfter, otherwise the slot is force-'
      'resumed before the skip control ever appears and the ad is, in '
      'practice, unskippable. / duration 必须长于 skippableAfter，否则广告位'
      '会在跳过控件出现之前就被强制续播，这条广告实际上不可跳过。',
    );
    assert(
      kind == MovaAdBreakKind.mid || delay == Duration.zero,
      'delay is only meaningful for mid-roll breaks: a pre-roll has no '
      'content to play during the countdown, a post-roll has none left. / '
      'delay 只对中插有意义：前贴片倒计时期间没有正片可播，后贴片已经播完了。',
    );
  }
}

/// Lifecycle events reported to [MovaAdConfig.onAdEvent] as an ad plays.
///
/// 广告播放过程中上报给 [MovaAdConfig.onAdEvent] 的生命周期事件。
enum MovaAdEventType {
  /// The break became due but has not taken over yet: its [MovaAdBreak.delay]
  /// countdown is running, or it is being warmed up in the background, while
  /// the content deliberately keeps playing.
  ///
  /// 广告位已到期但尚未接管：其 [MovaAdBreak.delay] 倒计时正在走，或正在后台
  /// 预热，而正片刻意继续播放。
  pending,

  /// The ad began playing.
  ///
  /// 广告开始播放。
  started,

  /// The ad played to the end.
  ///
  /// 广告播放到结束。
  completed,

  /// The viewer skipped the ad.
  ///
  /// 观众跳过了广告。
  skipped,

  /// The viewer tapped the ad (host handles [MovaAdBreak.clickThroughUrl]).
  ///
  /// 观众点击了广告（由宿主处理 [MovaAdBreak.clickThroughUrl]）。
  clicked,

  /// The ad could not be played: it failed to open, errored out, never
  /// produced a first frame, or was dropped for not warming up in time.
  ///
  /// 广告无法播放：打开失败、播放报错、始终没有首帧，或因未能及时预热就绪而
  /// 被丢弃。
  failed,
}

/// An ad lifecycle notification: what happened, and to which break.
///
/// 一条广告生命周期通知：发生了什么、发生在哪个广告位。
class MovaAdEvent {
  /// What happened.
  ///
  /// 发生的事件类型。
  final MovaAdEventType type;

  /// The break the event refers to.
  ///
  /// 该事件对应的广告位。
  final MovaAdBreak adBreak;

  /// The underlying error for a [MovaAdEventType.failed] event; null for every
  /// other type.
  ///
  /// [MovaAdEventType.failed] 事件的底层错误；其他类型一律为 null。
  final Object? error;

  /// Creates an ad event.
  ///
  /// 创建一个广告事件。
  ///
  /// - [type]: the event type / 事件类型
  /// - [adBreak]: the break it refers to / 对应的广告位
  /// - [error]: underlying error, for failures only / 底层错误，仅失败时有值
  const MovaAdEvent(this.type, this.adBreak, {this.error});
}
