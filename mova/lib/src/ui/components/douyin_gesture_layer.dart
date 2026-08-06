import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/feed/feed_controller.dart';
import '../slots/component.dart';
import '../slots/slot.dart';

/// Gesture layer for the douyin-style feed skin: single tap toggles
/// play/pause, double tap toggles the local like state and flashes a heart
/// burst — deliberately does **not** mount any drag-based
/// volume/brightness/seek gesture (see doc/SPEC.md's feed entry): the
/// vertical drag is owned by the feed's `PageView`, and simply never
/// registering a competing gesture recognizer here is how mova's
/// component architecture avoids the conflict without special-casing it.
///
/// douyin 风格 feed 皮肤的手势层：单击切换播放/暂停，双击切换本地点赞状态并
/// 闪一次心形动画——刻意**不**挂载任何基于拖动的音量/亮度/进度手势（见
/// doc/SPEC.md 的 feed 条目）：纵向拖动归 feed 的 `PageView` 所有，这里干脆
/// 不注册会竞争的手势识别器，就是 mova 组件化架构规避冲突的方式，
/// 无需任何特判。
class DouyinGestureLayerComponent extends MovaComp {
  /// Creates the douyin gesture-layer component.
  ///
  /// 创建抖音手势层组件。
  ///
  /// - [controller]: the feed controller owning local like state / 持有本地
  ///   点赞状态的 feed 控制器
  /// - [index]: this page's feed index / 本页在 feed 中的索引
  /// - [likeNotifier]: shared like-state notifier, kept in sync with the
  ///   social rail's like button / 共享的点赞状态 notifier，与社交竖排的点赞
  ///   按钮保持同步
  DouyinGestureLayerComponent({
    required this.controller,
    required this.index,
    required this.likeNotifier,
  });

  /// The feed controller owning local like state.
  ///
  /// 持有本地点赞状态的 feed 控制器。
  final MovaFeedCtrl controller;

  /// This page's feed index.
  ///
  /// 本页在 feed 中的索引。
  final int index;

  /// Shared like-state notifier for this page.
  ///
  /// 本页共享的点赞状态 notifier。
  final ValueNotifier<({bool liked, int count})> likeNotifier;

  @override
  String get name => 'douyinGestureLayer';

  @override
  MovaSlot get slot => MovaSlot.gesture;

  @override
  Widget build(BuildContext context, MovaApi api, List<Widget> children) {
    return _DouyinGestureLayer(api: api, controller: controller, index: index, likeNotifier: likeNotifier);
  }
}

/// Stateful gesture recognizer; owns only the transient heart-burst
/// animation trigger, all persistent state lives in [MovaFeedCtrl]/
/// [likeNotifier].
///
/// 有状态手势识别器；只持有瞬时的心形动画触发计数，持久状态都在
/// [MovaFeedCtrl]/[likeNotifier] 里。
class _DouyinGestureLayer extends StatefulWidget {
  /// Creates the internal douyin gesture widget.
  ///
  /// 创建内部抖音手势 widget。
  const _DouyinGestureLayer({
    required this.api,
    required this.controller,
    required this.index,
    required this.likeNotifier,
  });

  /// The capability surface this gesture layer drives.
  ///
  /// 该手势层驱动的能力面。
  final MovaApi api;

  /// The feed controller owning local like state.
  ///
  /// 持有本地点赞状态的 feed 控制器。
  final MovaFeedCtrl controller;

  /// This page's feed index.
  ///
  /// 本页在 feed 中的索引。
  final int index;

  /// Shared like-state notifier for this page.
  ///
  /// 本页共享的点赞状态 notifier。
  final ValueNotifier<({bool liked, int count})> likeNotifier;

  @override
  State<_DouyinGestureLayer> createState() => _DouyinGestureLayerState();
}

/// State for [_DouyinGestureLayer]; [_burstSeq] increments on every
/// double-tap-to-like so each burst gets a fresh [ValueKey], forcing a new
/// [_HeartBurst] instance (and thus a fresh animation) even for
/// back-to-back double-taps.
///
/// [_DouyinGestureLayer] 的状态；每次双击点赞都会递增 [_burstSeq]，使每次
/// 动画都拿到全新的 [ValueKey]，从而生成一个全新的 [_HeartBurst] 实例（也就是
/// 全新的动画）——即使连续双击也不例外。
class _DouyinGestureLayerState extends State<_DouyinGestureLayer> {
  /// Monotonically increasing counter keying the currently-shown burst.
  ///
  /// 单调递增的计数器，作为当前展示的心形动画的 key。
  int _burstSeq = 0;

  /// Toggles play/pause on a plain (non-double) tap.
  ///
  /// 单击（非双击）时切换播放/暂停。
  void _onTap() => widget.api.playOrPause();

  /// Toggles the local like state and triggers a fresh heart-burst.
  ///
  /// 切换本地点赞状态并触发一次全新的心形动画。
  void _onDoubleTap() {
    widget.likeNotifier.value = widget.controller.toggleLike(widget.index);
    setState(() => _burstSeq++);
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.api.options.theme;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _onTap,
      onDoubleTap: _onDoubleTap,
      child: Stack(
        children: [
          const SizedBox.expand(),
          if (_burstSeq > 0)
            Center(
              child: _HeartBurst(key: ValueKey(_burstSeq), color: theme.accentColor),
            ),
        ],
      ),
    );
  }
}

/// A single heart-burst: scales up while fading out, then leaves itself in
/// its fully-transparent end state — the next double-tap replaces it with a
/// fresh instance (see [_DouyinGestureLayerState._burstSeq]) rather than
/// this widget needing to remove itself from the tree.
///
/// 单次心形动画：放大的同时淡出，结束后停在完全透明的终态——下一次双击会用
/// 全新实例替换它（见 [_DouyinGestureLayerState._burstSeq]），本组件无需自行
/// 从树上移除。
class _HeartBurst extends StatelessWidget {
  /// Creates a heart-burst animation.
  ///
  /// 创建一次心形动画。
  const _HeartBurst({super.key, required this.color});

  /// ARGB heart color.
  ///
  /// 心形的 ARGB 颜色。
  final int color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.6, end: 1.6),
        duration: const Duration(milliseconds: 700),
        curve: Curves.easeOut,
        builder: (context, scale, child) {
          // Fades out over the same span the scale grows, so the burst
          // visibly pops then dissolves rather than just growing forever.
          //
          // 与放大同步淡出，使动画呈现"弹出后消散"而非一直放大。
          final progress = ((scale - 0.6) / 1.0).clamp(0.0, 1.0);
          return Opacity(
            opacity: 1 - progress,
            child: Transform.scale(scale: scale, child: child),
          );
        },
        child: Icon(Icons.favorite_rounded, color: Color(color), size: 80),
      ),
    );
  }
}
