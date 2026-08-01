import 'package:flutter/widgets.dart';

import '../core/api.dart';
import '../core/feed/feed_controller.dart';
import '../core/feed/feed_prefetcher.dart';
import 'player.dart';
import 'scope/scope.dart';
import 'skins/douyin_skin.dart';
import 'slots/tree.dart';

/// A vertical, douyin-style "swipe for next video" feed built on a single
/// shared [VmApi] — see doc/SPEC.md's feed-prefetch entry for why this is
/// one engine switched via repeated [VmApi.open] rather than a pool of
/// parallel engines.
///
/// Only the page the user has actually settled on ([VmFeedController.
/// activeIndex]) renders the real video surface; neighbouring pages built by
/// [PageView] for scroll physics render their chrome (social rail, author/
/// music info) over a plain black surface instead of the single shared
/// video texture — otherwise every mounted neighbour would show whichever
/// video happens to be currently playing, not its own content, since there
/// is only one decoder. This means the just-settled page briefly shows black
/// until its `open()` resolves; see doc/SPEC.md for the accepted trade-off
/// this follows from.
///
/// 基于单一共享 [VmApi] 构建的纵向"上滑下一个视频"抖音风 feed——为什么是一个
/// 引擎反复 [VmApi.open] 切换而非并行引擎池，见 doc/SPEC.md 的 feed 预取条目。
///
/// 只有用户真正定格停留的那一页（[VmFeedController.activeIndex]）渲染真实
/// 视频画面；[PageView] 为滚动物理效果额外构建的相邻页只在纯黑底上渲染自己的
/// chrome（社交竖排、作者/音乐信息）——否则每个已挂载的相邻页都会显示当前
/// 正在播放的那条视频（而非它自己的内容），因为只有一个解码器。这意味着刚
/// 定格的页面在其 `open()` 完成前会短暂显示黑屏；这背后的取舍见 doc/SPEC.md。
class VmFeedPlayer extends StatefulWidget {
  /// Creates a feed player.
  ///
  /// 创建一个 feed 播放器。
  ///
  /// - [api]: the single engine every page shares / 每页共享的唯一引擎
  /// - [loader]: resolves feed items by index / 按索引解析 feed 条目
  /// - [prefetchDepth]: items ahead of the active one to warm; defaults
  ///   conservatively to 1 (see doc/SPEC.md's device-tiering conclusion) /
  ///   提前预热多少条；默认取保守值 1（见 doc/SPEC.md 的设备分档结论）
  /// - [prefetcher]: warm-up strategy; defaults to
  ///   [NetworkWarmFeedPrefetcher] / 预热策略，默认
  ///   [NetworkWarmFeedPrefetcher]
  const VmFeedPlayer({
    super.key,
    required this.api,
    required this.loader,
    this.prefetchDepth = 1,
    this.prefetcher,
  });

  /// The single engine every page shares.
  ///
  /// 每页共享的唯一引擎。
  final VmApi api;

  /// Resolves feed items by index.
  ///
  /// 按索引解析 feed 条目。
  final VmFeedLoader loader;

  /// Items ahead of the active one to warm.
  ///
  /// 提前预热多少条。
  final int prefetchDepth;

  /// Warm-up strategy; null uses [VmFeedController]'s own default.
  ///
  /// 预热策略；为 null 时使用 [VmFeedController] 自身的默认值。
  final VmFeedPrefetcher? prefetcher;

  @override
  State<VmFeedPlayer> createState() => _VmFeedPlayerState();
}

/// State for [VmFeedPlayer]; owns the [VmFeedController], the [PageController],
/// and the per-page like-state notifiers that must outlive individual page
/// rebuilds (see [VmDouyinSkin]'s doc comment on why identity matters here).
///
/// [VmFeedPlayer] 的状态；持有 [VmFeedController]、[PageController]，以及
/// 必须在单页历次重建间存活的逐页点赞状态 notifier（为什么这里的身份很重要，
/// 见 [VmDouyinSkin] 的文档注释）。
class _VmFeedPlayerState extends State<VmFeedPlayer> {
  /// Drives the single shared engine through the feed.
  ///
  /// 驱动唯一共享引擎在 feed 中前进的控制器。
  late final VmFeedController _controller;

  /// Backs the vertical swipe-for-next-video paging.
  ///
  /// 支撑纵向"上滑下一个视频"翻页的控制器。
  final PageController _pageController = PageController();

  /// Like-state notifiers, keyed by feed index, kept alive for this
  /// [State]'s whole lifetime so double-tap (gesture layer) and the social
  /// rail's like button never drift out of sync across page rebuilds.
  ///
  /// 按 feed 索引存放的点赞状态 notifier，在本 [State] 整个生命周期内存活，
  /// 使双击（手势层）与社交竖排的点赞按钮在历次页面重建间永不失步。
  final Map<int, ValueNotifier<({bool liked, int count})>> _likeNotifiers =
      <int, ValueNotifier<({bool liked, int count})>>{};

  @override
  void initState() {
    super.initState();
    _controller = VmFeedController(
      api: widget.api,
      loader: widget.loader,
      prefetchDepth: widget.prefetchDepth,
      prefetcher: widget.prefetcher,
    );
    _activate(0);
  }

  /// Switches the shared engine to [index] and rebuilds once it settles, so
  /// that page's placeholder swaps for the real video surface.
  ///
  /// 把共享引擎切换到 [index] 并在其完成后重建一次，使该页从占位切换为真实
  /// 视频画面。
  Future<void> _activate(int index) async {
    await _controller.activate(index);
    if (mounted) setState(() {});
  }

  /// Returns the stable like-state notifier for [index], creating it (seeded
  /// from [VmFeedController.likeStateOf]) the first time it's needed.
  ///
  /// 返回 [index] 对应的稳定点赞状态 notifier；首次需要时才创建（用
  /// [VmFeedController.likeStateOf] 播种初值）。
  ValueNotifier<({bool liked, int count})> _likeNotifierFor(int index) {
    return _likeNotifiers.putIfAbsent(index, () => ValueNotifier(_controller.likeStateOf(index)));
  }

  /// Builds one feed page: the real video surface if [index] is the
  /// currently-active page, otherwise the page's chrome over a plain black
  /// surface (see this class's own doc comment for why).
  ///
  /// 构建一页 feed：若 [index] 是当前活跃页则渲染真实视频画面，否则只在纯黑
  /// 底上渲染该页的 chrome（原因见本类文档注释）。
  Widget _buildPage(BuildContext context, int index) {
    final item = _controller.peek(index);
    if (item == null) {
      _controller.ensure(index).then((_) {
        if (mounted) setState(() {});
      });
      return const ColoredBox(color: Color(0xFF000000));
    }

    final skin = VmDouyinSkin(
      item: item,
      controller: _controller,
      index: index,
      likeNotifier: _likeNotifierFor(index),
    );

    if (index == _controller.activeIndex) {
      return VmPlayer(api: widget.api, skin: skin, autoLoadQualities: false);
    }

    return VmScope(
      api: widget.api,
      child: Builder(builder: (context) {
        final bundle = buildSlots(context, widget.api, skin.components());
        return skin.assemble(context, bundle, const ColoredBox(color: Color(0xFF000000)));
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PageView.builder(
      controller: _pageController,
      scrollDirection: Axis.vertical,
      onPageChanged: _activate,
      itemBuilder: _buildPage,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _pageController.dispose();
    for (final notifier in _likeNotifiers.values) {
      notifier.dispose();
    }
    super.dispose();
  }
}
