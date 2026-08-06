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
    this.skippableAfter,
    this.clickThroughUrl,
  });
}

/// Lifecycle events reported to [MovaAdConfig.onAdEvent] as an ad plays.
///
/// 广告播放过程中上报给 [MovaAdConfig.onAdEvent] 的生命周期事件。
enum MovaAdEventType {
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

  /// Creates an ad event.
  ///
  /// 创建一个广告事件。
  ///
  /// - [type]: the event type / 事件类型
  /// - [adBreak]: the break it refers to / 对应的广告位
  const MovaAdEvent(this.type, this.adBreak);
}
