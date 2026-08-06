import 'source.dart';

/// Called after a like toggle commits locally, so the host can persist it
/// (e.g. call an API) — mova never calls a backend itself and never
/// rolls the local toggle back regardless of what the host does with it.
///
/// 点赞本地状态切换后的回调，供宿主自行持久化（例如调用 API）——mova
/// 自身从不调用后端，也不会因宿主后续行为回滚本地已切换的状态。
///
/// - [liked]: the new local liked flag / 切换后的本地点赞状态
/// - [likeCount]: the new local like count / 切换后的本地点赞数
typedef MovaFeedLikeChg = void Function(bool liked, int likeCount);

/// One playable entry in a [MovaFeedCtrl]-driven vertical feed
/// (bilibili/douyin-style "swipe for next video").
///
/// Carries the playable [source] plus the social-chrome metadata
/// [MovaDouyinSkin] renders (author/music/counts) and the callbacks fired for
/// actions mova does not own the business logic for (comment/share/
/// avatar/follow) — see doc/PRD.md ADR: mova owns like state locally
/// end-to-end (toggle + count + heart animation), everything else is a
/// passive callback.
///
/// [MovaFeedCtrl] 驱动的纵向 feed（bilibili/douyin 式"上滑下一个视频"）
/// 中的一条条目。
///
/// 除可播放的 [source] 外，还带 `MovaDouyinSkin` 渲染所需的社交 chrome 元数据
/// （作者/音乐/计数），以及 mova 不持有其业务逻辑的动作回调（评论/分享/
/// 头像/关注）——见 doc/PRD.md ADR：点赞状态由 mova 端到端本地持有
/// （切换 + 计数 + 心形动画），其余一律是被动回调。
class MovaFeedItem {
  /// The playable media source.
  ///
  /// 可播放的媒体源。
  final MovaSource source;

  /// Display name of the video's author.
  ///
  /// 视频作者的显示名。
  final String? authorName;

  /// URL of the author's avatar image.
  ///
  /// 作者头像图片地址。
  final String? avatarUrl;

  /// Display name of the background music/sound, if any.
  ///
  /// 背景音乐/声音的显示名（若有）。
  final String? musicName;

  /// Whether the current viewer has already liked this item; the seed value
  /// for mova's local like state (see [MovaFeedCtrl.toggleLike]).
  ///
  /// 当前观众是否已点赞该条目；作为 mova 本地点赞状态的初值（见
  /// [MovaFeedCtrl.toggleLike]）。
  final bool initialLiked;

  /// Seed value for the local like counter.
  ///
  /// 本地点赞计数的初值。
  final int initialLikeCount;

  /// Comment count shown on the social rail; display-only, mova never
  /// mutates it (tapping comment only fires [onComment]).
  ///
  /// 社交竖排展示的评论数；仅展示，mova 从不修改它（点击评论只触发
  /// [onComment]）。
  final int commentCount;

  /// Share count shown on the social rail; display-only.
  ///
  /// 社交竖排展示的分享数；仅展示。
  final int shareCount;

  /// Fired whenever the local like state changes (double-tap or the like
  /// button); mova calls this after already updating its own local state.
  ///
  /// 本地点赞状态变化时触发（双击或点赞按钮）；mova 会先更新自身本地
  /// 状态，再调用该回调。
  final MovaFeedLikeChg? onLikeChanged;

  /// Fired when the comment affordance is tapped; mova owns no comment UI.
  ///
  /// 点击评论入口时触发；mova 不持有任何评论 UI。
  final void Function()? onComment;

  /// Fired when the share affordance is tapped; mova owns no share UI.
  ///
  /// 点击分享入口时触发；mova 不持有任何分享 UI。
  final void Function()? onShare;

  /// Fired when the author avatar is tapped.
  ///
  /// 点击作者头像时触发。
  final void Function()? onAvatarTap;

  /// Fired when the follow affordance is tapped; mova owns no follow
  /// state (whether the viewer already follows the author is the host's).
  ///
  /// 点击关注入口时触发；mova 不持有关注状态（观众是否已关注作者由
  /// 宿主自行维护）。
  final void Function()? onFollowTap;

  /// Creates a feed item.
  ///
  /// 创建一个 feed 条目。
  ///
  /// - [source]: playable media source / 可播放的媒体源
  /// - [authorName]: author display name / 作者显示名
  /// - [avatarUrl]: author avatar URL / 作者头像地址
  /// - [musicName]: background music display name / 背景音乐显示名
  /// - [initialLiked]: seed liked flag / 点赞状态初值
  /// - [initialLikeCount]: seed like count / 点赞数初值
  /// - [commentCount]: display-only comment count / 仅展示的评论数
  /// - [shareCount]: display-only share count / 仅展示的分享数
  /// - [onLikeChanged]: local like-state change callback / 本地点赞状态变化回调
  /// - [onComment]: comment-tap callback / 评论点击回调
  /// - [onShare]: share-tap callback / 分享点击回调
  /// - [onAvatarTap]: avatar-tap callback / 头像点击回调
  /// - [onFollowTap]: follow-tap callback / 关注点击回调
  const MovaFeedItem({
    required this.source,
    this.authorName,
    this.avatarUrl,
    this.musicName,
    this.initialLiked = false,
    this.initialLikeCount = 0,
    this.commentCount = 0,
    this.shareCount = 0,
    this.onLikeChanged,
    this.onComment,
    this.onShare,
    this.onAvatarTap,
    this.onFollowTap,
  });

  /// Returns a copy with the given fields replaced; used internally by
  /// [MovaFeedCtrl] to persist a like toggle into its item cache.
  ///
  /// 返回一份替换了指定字段的拷贝；供 [MovaFeedCtrl] 内部把点赞切换结果
  /// 落回条目缓存。
  MovaFeedItem copyWith({bool? initialLiked, int? initialLikeCount}) {
    return MovaFeedItem(
      source: source,
      authorName: authorName,
      avatarUrl: avatarUrl,
      musicName: musicName,
      initialLiked: initialLiked ?? this.initialLiked,
      initialLikeCount: initialLikeCount ?? this.initialLikeCount,
      commentCount: commentCount,
      shareCount: shareCount,
      onLikeChanged: onLikeChanged,
      onComment: onComment,
      onShare: onShare,
      onAvatarTap: onAvatarTap,
      onFollowTap: onFollowTap,
    );
  }
}
