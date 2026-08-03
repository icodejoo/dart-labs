import 'package:flutter/widgets.dart';

import '../core/api.dart';
import '../core/feed/engine_pool.dart';
import '../core/feed/feed_controller.dart';
import '../core/feed/feed_prefetcher.dart';
import '../core/model/feed_item.dart';
import '../core/model/fit.dart';
import 'player.dart';
import 'skins/douyin_skin.dart';

/// Builds what a feed page shows while its video is not yet on screen — the
/// gap between the page mounting and its pooled engine finishing `open()`.
///
/// Return a cover image, a skeleton, a brand frame; videoman never loads
/// images itself, so what goes here is entirely the host's call. Returning a
/// plain black box is the default when no builder is given.
///
/// 构建一个 feed 页在其视频尚未上屏期间显示的内容——即该页挂载到其池引擎
/// `open()` 完成之间的空档。
///
/// 可以返回封面图、骨架屏、品牌占位；videoman 自身从不加载图片，放什么完全
/// 由宿主决定。未提供 builder 时默认是一块纯黑。
///
/// - [context]: the page's build context / 该页的 build 上下文
/// - [item]: the feed item this page shows / 该页展示的 feed 条目
///
/// Returns the placeholder widget to paint behind the page's chrome.
///
/// 返回要绘制在该页 chrome 之下的占位组件。
typedef VmFeedPlaceholderBuilder = Widget Function(BuildContext context, VmFeedItem item);

/// A vertical, douyin-style "swipe for next video" feed backed by a pool of
/// playback engines — one per warm page, rather than one shared by all.
///
/// Each page renders *its own* engine's surface, so a swipe crossfades
/// between two already-live surfaces. That is what removes the two artifacts
/// the earlier single-engine version had to paper over with a timed black
/// mask: a cold `open()` blanking the shared surface (black flash), and the
/// previous item's last decoded frame lingering on it until the new item's
/// frames arrived (stale frame). Neither can happen when the page being
/// swiped to was opened on its own engine while the viewer was still
/// watching the previous one.
///
/// Pages the pool has no engine for — a fast fling can outrun the warm
/// window — fall back to [placeholderBuilder] under their normal chrome, and
/// pick up the real surface as soon as their engine finishes opening.
///
/// 基于播放引擎池构建的纵向"上滑下一个视频"抖音风 feed——每个热页一个引擎，
/// 而非所有页共用一个。
///
/// 每一页渲染*自己*引擎的画面，因此一次上滑是在两个已经活着的画面之间交换。
/// 这正是消除早期单引擎版本只能靠定时黑遮罩掩盖的两个瑕疵的原因：冷 `open()`
/// 清空共享画面（黑屏一闪），以及上一条最后解码的那帧滞留其上直到新一条的帧
/// 到达（残留旧帧）。当观众还在看上一条时，即将滑到的那页就已经在自己的引擎上
/// 打开了，这两件事都无从发生。
///
/// 池中没有引擎可给的页——快速连划可能甩开热窗口——会在正常 chrome 之下退回
/// [placeholderBuilder]，并在其引擎打开完成的瞬间换上真实画面。
class VmFeedPlayer extends StatefulWidget {
  /// Creates a feed player.
  ///
  /// 创建一个 feed 播放器。
  ///
  /// - [engineFactory]: creates each pooled engine; hosts pass
  ///   `createVmEngine`. This widget owns and disposes every engine the
  ///   factory produces — unlike the earlier single-engine API, the host
  ///   does not construct one itself / 创建池中每个引擎，宿主传
  ///   `createVmEngine`。工厂产出的每个引擎都由本组件持有并释放——与早期的
  ///   单引擎 API 不同，宿主不再自行构造引擎
  /// - [loader]: resolves feed items by index / 按索引解析 feed 条目
  /// - [poolSize]: how many engines may exist at once; 3 (the default) covers
  ///   every page `PageView` mounts and both swipe directions. Lower it to 2
  ///   on memory-tight targets — forward swipes stay seamless, swiping back
  ///   falls to the placeholder / 同时最多存在多少个引擎；默认 3，刚好覆盖
  ///   `PageView` 会挂载的所有页与两个滑动方向。内存吃紧的目标机可降到 2——
  ///   向前滑仍然无缝，往回滑会落到占位
  /// - [prefetchDepth]: items ahead of the active one whose *network* path
  ///   gets warmed beyond what the pool already opens; defaults to 1 /
  ///   在池已打开的范围之外，再对往后多少条条目预热*网络*链路；默认 1
  /// - [prefetcher]: network warm-up strategy; defaults to
  ///   [NetworkWarmFeedPrefetcher] / 网络预热策略，默认
  ///   [NetworkWarmFeedPrefetcher]
  /// - [fit]: video fill mode, applied to each engine as the pool creates it;
  ///   defaults to [VmFit.cover] (full-bleed, no letterboxing) since a
  ///   douyin-style feed's whole point is edge-to-edge video — [VmFit.contain]
  ///   would letterbox by a different amount per item's aspect ratio, reading
  ///   as a size jump on every swipe / 视频填充模式，池创建每个引擎时对其应用；
  ///   默认 [VmFit.cover]（铺满不留黑边）——抖音风 feed 的卖点就是画面铺满全屏，
  ///   [VmFit.contain] 会按每条视频的宽高比留出不同大小的黑边，每次上滑都像
  ///   是尺寸跳了一下
  /// - [placeholderBuilder]: what a page shows before its engine is ready;
  ///   defaults to plain black / 某页在其引擎就绪前显示什么，默认纯黑
  const VmFeedPlayer({
    super.key,
    required this.engineFactory,
    required this.loader,
    this.poolSize = 3,
    this.prefetchDepth = 1,
    this.prefetcher,
    this.fit = VmFit.cover,
    this.placeholderBuilder,
  });

  /// Creates each pooled engine.
  ///
  /// 创建池中每个引擎。
  final VmEngineFactory engineFactory;

  /// Resolves feed items by index.
  ///
  /// 按索引解析 feed 条目。
  final VmFeedLoader loader;

  /// How many engines may exist at once.
  ///
  /// 同时最多存在多少个引擎。
  final int poolSize;

  /// Items ahead of the active one whose network path gets warmed.
  ///
  /// 往后多少条条目会被预热网络链路。
  final int prefetchDepth;

  /// Network warm-up strategy; null uses [VmFeedController]'s own default.
  ///
  /// 网络预热策略；为 null 时使用 [VmFeedController] 自身的默认值。
  final VmFeedPrefetcher? prefetcher;

  /// Video fill mode, applied to each engine as the pool creates it.
  ///
  /// 视频填充模式，池创建每个引擎时对其应用。
  final VmFit fit;

  /// What a page shows before its engine is ready.
  ///
  /// 某页在其引擎就绪前显示什么。
  final VmFeedPlaceholderBuilder? placeholderBuilder;

  @override
  State<VmFeedPlayer> createState() => _VmFeedPlayerState();
}

/// State for [VmFeedPlayer]; owns the [VmFeedEnginePool], the
/// [VmFeedController], the [PageController], and the per-page like-state
/// notifiers that must outlive individual page rebuilds (see [VmDouyinSkin]'s
/// doc comment on why identity matters here).
///
/// [VmFeedPlayer] 的状态；持有 [VmFeedEnginePool]、[VmFeedController]、
/// [PageController]，以及必须在单页历次重建间存活的逐页点赞状态 notifier
/// （为什么这里的身份很重要，见 [VmDouyinSkin] 的文档注释）。
class _VmFeedPlayerState extends State<VmFeedPlayer> {
  /// Holds the live engines, at most [VmFeedPlayer.poolSize] of them.
  ///
  /// 持有存活的引擎，最多 [VmFeedPlayer.poolSize] 个。
  late final VmFeedEnginePool _pool;

  /// Drives the pool through the feed.
  ///
  /// 驱动引擎池在 feed 中前进的控制器。
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

  /// Indices [_buildPage] has already asked [VmFeedController.ensure] for.
  ///
  /// Without this, a page whose loader resolves `null` (the feed ended) spins
  /// forever: `build` requests it, the request completes with nothing to
  /// cache, `setState` rebuilds, and `build` requests it again. Failed loads
  /// drop back out of the set so a later rebuild does retry them.
  ///
  /// [_buildPage] 已经向 [VmFeedController.ensure] 请求过的索引。
  ///
  /// 没有这层记录，loader 解析出 `null`（feed 已到尽头）的页面会永远空转：
  /// `build` 发起请求，请求完成但没有任何东西可缓存，`setState` 触发重建，
  /// `build` 又发起同一个请求。加载失败的索引会被移出集合，使后续重建仍会
  /// 重试它们。
  final Set<int> _requested = <int>{};

  @override
  void initState() {
    super.initState();
    _pool = VmFeedEnginePool(
      engineFactory: widget.engineFactory,
      size: widget.poolSize,
      fit: widget.fit,
      onChanged: _onPoolChanged,
    );
    _controller = VmFeedController(
      pool: _pool,
      loader: widget.loader,
      prefetchDepth: widget.prefetchDepth,
      prefetcher: widget.prefetcher,
    );
    _controller.activate(0);
  }

  /// Rebuilds when a pool slot binds, unbinds, or becomes ready — that is
  /// what swaps a page from its placeholder to its real video surface.
  ///
  /// 池中某个 slot 绑定、解绑或变为就绪时重建——这正是让某页从占位换成真实
  /// 视频画面的时机。
  void _onPoolChanged() {
    if (!mounted) return;
    setState(() {});
  }

  /// Returns the stable like-state notifier for [index], creating it (seeded
  /// from [VmFeedController.likeStateOf]) the first time it's needed.
  ///
  /// 返回 [index] 对应的稳定点赞状态 notifier；首次需要时才创建（用
  /// [VmFeedController.likeStateOf] 播种初值）。
  ///
  /// - [index]: the feed index the notifier belongs to / 该 notifier 所属的
  ///   feed 索引
  ValueNotifier<({bool liked, int count})> _likeNotifierFor(int index) {
    return _likeNotifiers.putIfAbsent(index, () => ValueNotifier(_controller.likeStateOf(index)));
  }

  /// Builds one feed page: its own pooled engine's video surface once that
  /// engine is ready, otherwise the page's chrome over
  /// [VmFeedPlayer.placeholderBuilder].
  ///
  /// 构建一页 feed：其自身池引擎就绪后渲染该引擎的视频画面，否则在
  /// [VmFeedPlayer.placeholderBuilder] 之上渲染该页的 chrome。
  ///
  /// - [context]: the page's build context / 该页的 build 上下文
  /// - [index]: the feed index being built / 正在构建的 feed 索引
  Widget _buildPage(BuildContext context, int index) {
    final item = _controller.peek(index);
    if (item == null) {
      if (_requested.add(index)) {
        _controller.ensure(index).then(
          (_) {
            if (mounted) setState(() {});
          },
          onError: (Object _) => _requested.remove(index),
        );
      }
      return const ColoredBox(color: Color(0xFF000000));
    }

    final skin = VmDouyinSkin(
      item: item,
      controller: _controller,
      index: index,
      likeNotifier: _likeNotifierFor(index),
    );

    final slot = _controller.slotFor(index);
    if (slot != null && slot.ready) {
      return VmPlayer(api: slot.api, skin: skin, autoLoadQualities: false);
    }

    // No engine of its own yet, so the chrome needs *some* api to scope
    // against. The active page's engine stands in: every component in a
    // douyin page's chrome (social rail, author/music info) reads the feed
    // item, not playback state, so which engine backs the scope changes
    // nothing on screen — it only has to be non-null.
    //
    // 该页还没有自己的引擎，而 chrome 需要*某个* api 才能建立 scope。用活跃页
    // 的引擎顶上：抖音页 chrome 里的每个组件（社交竖排、作者/音乐信息）读的都是
    // feed 条目而非播放状态，因此由哪个引擎撑起 scope 对画面毫无影响——它只需要
    // 非空即可。
    final scopeApi = slot?.api ?? _fallbackScopeApi(index);
    final placeholder =
        widget.placeholderBuilder?.call(context, item) ?? const ColoredBox(color: Color(0xFF000000));
    if (scopeApi == null) return placeholder;

    // Route through VmPlayer with the placeholder as its surface rather than
    // hand-rebuilding VmScope + buildSlots + assemble here: VmPlayer keys the
    // tree by api identity, so when this page's own engine finishes opening
    // and scopeApi flips from the borrowed fallback to its own, the chrome
    // remounts cleanly instead of silently reusing State bound to the old api.
    //
    // 走 VmPlayer、把占位当它的 surface 传入，而非在此手工重装
    // VmScope + buildSlots + assemble：VmPlayer 按 api 身份给组件树做 key，
    // 于是当本页自己的引擎打开完成、scopeApi 从借来的 fallback 切成自己的引擎时，
    // chrome 会干净地重新挂载，而不是悄悄复用绑在旧 api 上的 State。
    return VmPlayer(api: scopeApi, skin: skin, autoLoadQualities: false, surface: placeholder);
  }

  /// Returns any live engine to scope a not-yet-bound page's chrome against:
  /// the active page's, or failing that whichever one the pool holds.
  ///
  /// `null` only before the very first bind, when the pool is still empty.
  ///
  /// 返回任意一个存活引擎，用于为尚未绑定的页面 chrome 建立 scope：优先取活跃
  /// 页的，取不到就取池中任意一个。
  ///
  /// 仅在首次绑定之前（池仍为空时）才为 `null`。
  ///
  /// - [index]: the page needing a scope, used only to skip its own empty
  ///   slot / 需要 scope 的那一页，仅用于跳过它自己的空 slot
  VmApi? _fallbackScopeApi(int index) {
    final active = _controller.activeIndex;
    if (active != null && active != index) {
      final slot = _controller.slotFor(active);
      if (slot != null) return slot.api;
    }
    for (final bound in _pool.boundIndices) {
      final slot = _pool.slotFor(bound);
      if (slot != null) return slot.api;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return PageView.builder(
      controller: _pageController,
      scrollDirection: Axis.vertical,
      onPageChanged: _controller.activate,
      itemBuilder: _buildPage,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _pool.dispose();
    _pageController.dispose();
    for (final notifier in _likeNotifiers.values) {
      notifier.dispose();
    }
    super.dispose();
  }
}
