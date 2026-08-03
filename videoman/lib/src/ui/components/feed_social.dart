import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/feed/feed_controller.dart';
import '../../core/model/feed_item.dart';
import '../../core/options/theme.dart';
import '../slots/component.dart';
import '../slots/slot.dart';

/// Shared layout for the social rail's icon+count actions (like/comment/
/// share): an opaque-tap column of a themed [Icon] over its count text.
///
/// 社交竖排里"图标+计数"动作（点赞/评论/分享）的共享布局：一列可穿透点击的
/// 主题化 [Icon] 加下方计数文字。
///
/// - [icon]: the glyph / 图标
/// - [iconColor]: the icon's ARGB color / 图标的 ARGB 颜色
/// - [size]: icon size in logical pixels / 图标尺寸（逻辑像素）
/// - [count]: the count caption below the icon / 图标下方的计数文字
/// - [theme]: theme supplying the caption color/size / 提供计数文字颜色/字号的主题
/// - [onTap]: tap handler / 点击回调
Widget _railAction({
  required IconData icon,
  required int iconColor,
  required double size,
  required String count,
  required VmTheme theme,
  VoidCallback? onTap,
}) {
  return GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onTap,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: Color(iconColor), size: size),
        Text(count, style: TextStyle(color: Color(theme.textColor), fontSize: theme.captionFontSize)),
      ],
    ),
  );
}

/// Right-side social action rail (avatar/follow, like, comment, share),
/// bilibili/douyin-style. A pure grouping composite — every child renders
/// itself; this only lays them out in a column.
///
/// 右侧社交动作竖排（头像/关注、点赞、评论、分享），bilibili/douyin 风格。
/// 纯组合组件——每个子组件自行渲染，这里只负责把它们排成一列。
class SocialRailComponent extends VmComponent {
  /// Creates the social rail, wiring its children to [item]/[controller]/
  /// [index]/[likeNotifier].
  ///
  /// 创建社交竖排，把子组件接到 [item]/[controller]/[index]/[likeNotifier]。
  ///
  /// - [item]: metadata + callbacks for the current page / 当前页的元数据与回调
  /// - [controller]: the feed controller owning local like state / 持有本地
  ///   点赞状态的 feed 控制器
  /// - [index]: this page's feed index / 本页在 feed 中的索引
  /// - [likeNotifier]: shared like-state notifier for this page, kept in
  ///   sync with double-tap-to-like on the gesture layer / 本页共享的点赞状态
  ///   notifier，与手势层的双击点赞保持同步
  SocialRailComponent({
    required this.item,
    required this.controller,
    required this.index,
    required this.likeNotifier,
  });

  /// Metadata + callbacks for the current page.
  ///
  /// 当前页的元数据与回调。
  final VmFeedItem item;

  /// The feed controller owning local like state.
  ///
  /// 持有本地点赞状态的 feed 控制器。
  final VmFeedController controller;

  /// This page's feed index.
  ///
  /// 本页在 feed 中的索引。
  final int index;

  /// Shared like-state notifier for this page.
  ///
  /// 本页共享的点赞状态 notifier。
  final ValueNotifier<({bool liked, int count})> likeNotifier;

  @override
  String get name => 'socialRail';

  @override
  VmSlot get slot => VmSlot.right;

  @override
  List<VmComponent> get children => [
        AvatarComponent(item: item),
        LikeButtonComponent(controller: controller, index: index, likeNotifier: likeNotifier),
        CommentButtonComponent(item: item),
        ShareButtonComponent(item: item),
      ];

  @override
  Widget build(BuildContext context, VmApi api, List<Widget> children) {
    return Padding(
      padding: const EdgeInsets.only(right: 8, bottom: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [for (final c in children) Padding(padding: const EdgeInsets.only(top: 16), child: c)],
      ),
    );
  }
}

/// Author avatar; tapping the avatar fires [VmFeedItem.onAvatarTap], tapping
/// the small follow badge beneath it fires [VmFeedItem.onFollowTap].
/// videoman holds no follow state of its own (see [VmFeedItem]'s doc
/// comment) — the badge always renders, its actual meaning is the host's.
///
/// 作者头像；点头像触发 [VmFeedItem.onAvatarTap]，点下方小号关注角标触发
/// [VmFeedItem.onFollowTap]。videoman 不持有关注状态（见 [VmFeedItem] 文档
/// 注释）——角标恒定渲染，其实际含义由宿主决定。
class AvatarComponent extends VmComponent {
  /// Creates the avatar leaf component.
  ///
  /// 创建头像叶子组件。
  AvatarComponent({required this.item});

  /// Metadata + callbacks for the current page.
  ///
  /// 当前页的元数据与回调。
  final VmFeedItem item;

  @override
  String get name => 'avatar';

  @override
  VmSlot get slot => VmSlot.right;

  @override
  Widget build(BuildContext context, VmApi api, List<Widget> children) {
    final theme = api.options.theme;
    final avatarUrl = item.avatarUrl;
    return GestureDetector(
      onTap: item.onAvatarTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: Color(theme.iconColor).withValues(alpha: 0.2),
            backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl) : null,
            child: avatarUrl == null ? Icon(Icons.person_rounded, color: Color(theme.iconColor)) : null,
          ),
          GestureDetector(
            onTap: item.onFollowTap,
            behavior: HitTestBehavior.opaque,
            child: Icon(Icons.add_circle_rounded, color: Color(theme.accentColor), size: 20),
          ),
        ],
      ),
    );
  }
}

/// Like button; toggles [VmFeedController]'s local like state end to end
/// (icon + count + heart-fill) and stays in sync with double-tap-to-like on
/// the gesture layer via the shared [likeNotifier].
///
/// 点赞按钮；端到端切换 [VmFeedController] 的本地点赞状态（图标 + 计数 +
/// 实心样式），并通过共享的 [likeNotifier] 与手势层的双击点赞保持同步。
class LikeButtonComponent extends VmComponent {
  /// Creates the like-button leaf component.
  ///
  /// 创建点赞按钮叶子组件。
  LikeButtonComponent({required this.controller, required this.index, required this.likeNotifier});

  /// The feed controller owning local like state.
  ///
  /// 持有本地点赞状态的 feed 控制器。
  final VmFeedController controller;

  /// This page's feed index.
  ///
  /// 本页在 feed 中的索引。
  final int index;

  /// Shared like-state notifier for this page.
  ///
  /// 本页共享的点赞状态 notifier。
  final ValueNotifier<({bool liked, int count})> likeNotifier;

  @override
  String get name => 'likeButton';

  @override
  VmSlot get slot => VmSlot.right;

  @override
  Widget build(BuildContext context, VmApi api, List<Widget> children) {
    final theme = api.options.theme;
    return ValueListenableBuilder<({bool liked, int count})>(
      valueListenable: likeNotifier,
      builder: (context, value, _) {
        return _railAction(
          icon: value.liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
          iconColor: value.liked ? theme.accentColor : theme.iconColor,
          size: 32,
          count: '${value.count}',
          theme: theme,
          onTap: () => likeNotifier.value = controller.toggleLike(index),
        );
      },
    );
  }
}

/// Comment entry; display-only count from [VmFeedItem.commentCount], tap
/// fires [VmFeedItem.onComment] — videoman owns no comment UI.
///
/// 评论入口；计数来自 [VmFeedItem.commentCount] 仅供展示，点击触发
/// [VmFeedItem.onComment]——videoman 不持有任何评论 UI。
class CommentButtonComponent extends VmComponent {
  /// Creates the comment-button leaf component.
  ///
  /// 创建评论按钮叶子组件。
  CommentButtonComponent({required this.item});

  /// Metadata + callbacks for the current page.
  ///
  /// 当前页的元数据与回调。
  final VmFeedItem item;

  @override
  String get name => 'commentButton';

  @override
  VmSlot get slot => VmSlot.right;

  @override
  Widget build(BuildContext context, VmApi api, List<Widget> children) {
    final theme = api.options.theme;
    return _railAction(
      icon: Icons.chat_bubble_rounded,
      iconColor: theme.iconColor,
      size: 30,
      count: '${item.commentCount}',
      theme: theme,
      onTap: item.onComment,
    );
  }
}

/// Share entry; display-only count from [VmFeedItem.shareCount], tap fires
/// [VmFeedItem.onShare] — videoman owns no share sheet.
///
/// 分享入口；计数来自 [VmFeedItem.shareCount] 仅供展示，点击触发
/// [VmFeedItem.onShare]——videoman 不持有任何分享面板。
class ShareButtonComponent extends VmComponent {
  /// Creates the share-button leaf component.
  ///
  /// 创建分享按钮叶子组件。
  ShareButtonComponent({required this.item});

  /// Metadata + callbacks for the current page.
  ///
  /// 当前页的元数据与回调。
  final VmFeedItem item;

  @override
  String get name => 'shareButton';

  @override
  VmSlot get slot => VmSlot.right;

  @override
  Widget build(BuildContext context, VmApi api, List<Widget> children) {
    final theme = api.options.theme;
    return _railAction(
      icon: Icons.reply_rounded,
      iconColor: theme.iconColor,
      size: 30,
      count: '${item.shareCount}',
      theme: theme,
      onTap: item.onShare,
    );
  }
}

/// Bottom info block: author name and music/sound name, douyin-style.
///
/// 底部信息块：作者名与音乐/声音名，douyin 风格。
class FeedInfoComponent extends VmComponent {
  /// Creates the feed-info leaf component.
  ///
  /// 创建 feed 信息叶子组件。
  FeedInfoComponent({required this.item});

  /// Metadata for the current page.
  ///
  /// 当前页的元数据。
  final VmFeedItem item;

  @override
  String get name => 'feedInfo';

  @override
  VmSlot get slot => VmSlot.bottom;

  @override
  Widget build(BuildContext context, VmApi api, List<Widget> children) {
    final theme = api.options.theme;
    final author = item.authorName;
    final music = item.musicName;
    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 72, bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (author != null)
            Text(
              '@$author',
              style: TextStyle(
                color: Color(theme.textColor),
                fontSize: theme.titleFontSize,
                fontWeight: FontWeight.bold,
              ),
            ),
          if (music != null) ...[
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.music_note_rounded, color: Color(theme.textColor), size: 14),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    music,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Color(theme.textColor), fontSize: theme.captionFontSize),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
