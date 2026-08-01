import 'package:flutter/widgets.dart';

import '../../core/feed/feed_controller.dart';
import '../../core/model/feed_item.dart';
import '../components/douyin_gesture_layer.dart';
import '../components/feed_social.dart';
import '../slots/component.dart';
import '../slots/slot.dart';
import '../slots/tree.dart';
import 'skin.dart';

/// A fully custom (③-tier, see doc/DESIGN-0.3.0-plugin-skin.md §7.1) skin
/// for one page of a [VmFeedController]-driven vertical feed: no top bar, no
/// seek bar, full-bleed video, a right-side social rail, and bottom
/// author/music info — douyin-style.
///
/// Built fresh per page by `VmFeedPlayer`'s `itemBuilder`, so it carries the
/// page's own [item]/[index] as constructor fields rather than reading them
/// from [VmApi] (which only knows about the single shared engine, not which
/// feed index is currently showing).
///
/// 面向 [VmFeedController] 驱动的纵向 feed 中**单页**的完全自定义皮肤（③档，
/// 见 doc/DESIGN-0.3.0-plugin-skin.md §7.1）：无顶栏、无进度条、画面铺满全屏、
/// 右侧社交竖排、底部作者/音乐信息——抖音风格。
///
/// 由 `VmFeedPlayer` 的 `itemBuilder` 逐页新建，因此把本页的 [item]/[index]
/// 作为构造参数持有，而非从 [VmApi] 读取（后者只知道唯一共享的引擎，不知道
/// 当前展示的是 feed 里的哪一条）。
class VmDouyinSkin implements VmSkin {
  /// Creates the douyin-style skin for one feed page.
  ///
  /// 创建 feed 中某一页的抖音风格皮肤。
  ///
  /// - [item]: metadata + callbacks for this page / 本页的元数据与回调
  /// - [controller]: the feed controller owning local like state / 持有本地
  ///   点赞状态的 feed 控制器
  /// - [index]: this page's feed index / 本页在 feed 中的索引
  /// - [likeNotifier]: shared like-state notifier, created once by
  ///   `VmFeedPlayer` and reused across rebuilds of this page so double-tap
  ///   (gesture layer) and the rail's like button never drift out of sync /
  ///   共享的点赞状态 notifier，由 `VmFeedPlayer` 只创建一次并在本页历次重建
  ///   间复用，使双击（手势层）与竖排的点赞按钮永不失步
  const VmDouyinSkin({
    required this.item,
    required this.controller,
    required this.index,
    required this.likeNotifier,
  });

  /// Metadata + callbacks for this page.
  ///
  /// 本页的元数据与回调。
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
  List<VmComponent> components() => [
        DouyinGestureLayerComponent(controller: controller, index: index, likeNotifier: likeNotifier),
        SocialRailComponent(item: item, controller: controller, index: index, likeNotifier: likeNotifier),
        FeedInfoComponent(item: item),
      ];

  @override
  Widget assemble(BuildContext context, VmSlotBundle slots, Widget video) {
    return Stack(
      children: [
        Positioned.fill(child: video),
        Positioned.fill(child: Stack(children: slots[VmSlot.gesture])),
        Positioned.fill(child: Stack(children: slots[VmSlot.right])),
        Positioned.fill(child: Stack(children: slots[VmSlot.bottom])),
      ],
    );
  }
}
