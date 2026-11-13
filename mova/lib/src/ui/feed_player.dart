import 'dart:async';
import 'package:flutter/material.dart';

import '../core/guard/auto_pause.dart';
import '../core/state/state.dart';
import 'guard/auto_pause.dart';
import 'style/style.dart';

import '../core/api.dart';
import '../core/feed/feed_pool.dart';
import '../core/feed/feed.dart';
import '../core/feed/feed_prefetcher.dart';
import '../core/model/feed_item.dart';
import '../core/model/fit.dart';
import 'player.dart';
import 'ui_kits/douyin_ui_kit.dart';

/// Default feed backdrop and unloaded-page surface.
///
/// Feed 默认背景与未加载页面的画面。
const _feedBackground = Colors.black;
const _feedPlaceholder = ColoredBox(color: _feedBackground);

/// Builds what a feed page shows while its video is not yet on screen — the
/// gap between the page mounting and its pooled player finishing `open()`.
///
/// Return a cover image, a skeleton, a brand frame; mova never loads
/// images itself, so what goes here is entirely the host's call. Returning a
/// plain black box is the default when no builder is given.
///
/// 构建一个 feed 页在其视频尚未上屏期间显示的内容——即该页挂载到其池播放器
/// `open()` 完成之间的空档。
///
/// 可以返回封面图、骨架屏、品牌占位；mova 自身从不加载图片，放什么完全
/// 由宿主决定。未提供 builder 时默认是一块纯黑。
///
/// - [context]: the page's build context / 该页的 build 上下文
/// - [item]: the feed item this page shows / 该页展示的 feed 条目
///
/// Returns the placeholder widget to paint behind the page's chrome.
///
/// 返回要绘制在该页 chrome 之下的占位组件。
typedef MovaFeedHolderBuilder =
    Widget Function(BuildContext context, MovaFeedItem item);

/// 构建单页失败界面；[retry] 仅重试该页，不影响相邻条目。
typedef MovaFeedErrorBuilder =
    Widget Function(
      BuildContext context,
      int index,
      Object error,
      VoidCallback retry,
    );

/// Host controls for one feed player; the widget owns its players while the
/// host owns this controller. Queries return null and commands do nothing
/// while detached. Example: `await ctrl.pause()`.
///
/// Feed 的宿主控制入口；组件持有播放器生命周期，宿主持有本控制器。
/// 同时仅可挂载到一个 MovaFeedPlayer，卸载后查询返回 null、命令为空操作。
/// 示例：`await ctrl.pause()`。
class MovaFeedPlayerCtrl extends ChangeNotifier {
  /// 创建未绑定的控制器；交给 MovaFeedPlayer.ctrl 后生效。
  MovaFeedPlayerCtrl();

  _MovaFeedPlayerState? _owner;

  /// Generation of host pause commands; play and detach invalidate pending reconciliation.
  ///
  /// 宿主暂停命令的代际；play 与解绑会使待补暂停失效。
  int _pauseGeneration = 0;

  /// 当前 feed，可查询缓存、条目和点赞状态；不要自行 dispose。
  MovaFeed? get feed => _owner?._feed;

  /// 最近开始绑定的条目索引，首次绑定前为 null。
  int? get activeIndex => feed?.activeIndex;

  /// 当前页播放器；没有绑定时为 null，打开在途时也可控制；宿主不要自行 dispose。
  IMovaApi? get activeApi => _owner?._activeApi;

  /// 跳至 [index]；负索引不执行，当前页重复调用会重试加载。
  void jumpToPage(int index) {
    final owner = _owner;
    if (owner == null || index < 0 || !owner._pageController.hasClients) return;
    if ((owner._pageController.page?.round() ?? 0) == index) {
      owner._retry(index);
    } else {
      owner._pageController.jumpToPage(index);
    }
  }

  /// Pauses the current page without waiting for activation. A pending
  /// activation reapplies the pause after focus; unbound calls do nothing.
  ///
  /// 暂停当前页，不等待激活；在途激活聚焦后会补暂停，未绑定时为空操作。
  ///
  /// Returns when the current player's pause completes.
  ///
  /// 当前播放器的暂停完成时返回。
  Future<void> pause() async {
    // 即使意图已被守卫置为暂停，也要撤销它记住的恢复欠账。
    final owner = _owner;
    final generation = owner?._activationGeneration;
    final pauseGeneration = ++_pauseGeneration;
    owner?._guardKey.currentState?.cancelResume();
    await activeApi?.pause();
    if (owner != null) {
      unawaited(
        _pauseAfterActivation(
          owner,
          generation!,
          pauseGeneration,
        ).catchError((Object _) {}),
      );
    }
  }

  /// Reapplies pause after focus, isolating activation failures already shown
  /// by the owner and skipping detached controllers, newer pages or commands.
  ///
  /// 聚焦后补暂停，隔离 owner 已展示的激活错误，并跳过解绑、更新的页面或命令。
  Future<void> _pauseAfterActivation(
    _MovaFeedPlayerState owner,
    int generation,
    int pauseGeneration,
  ) async {
    try {
      await owner._activationSettled;
    } on Object {
      // Activation reports its own failure UI; pause remains best-effort.
      //
      // 激活自行展示失败 UI；此处仍尽力落实暂停。
    }
    if (identical(_owner, owner) &&
        pauseGeneration == _pauseGeneration &&
        generation == owner._activationGeneration) {
      owner._guardKey.currentState?.cancelResume();
      await activeApi?.pause();
    }
  }

  /// Plays the current page and cancels a pending pause reconciliation.
  /// Visibility guards may still pause it while hidden.
  ///
  /// 播放当前页并取消待补暂停；内置可见性守卫仍可在隐藏时暂停它。
  ///
  /// Returns when the current player's play completes; unbound calls do nothing.
  ///
  /// 当前播放器的播放命令完成时返回；未绑定时为空操作。
  Future<void> play() async {
    ++_pauseGeneration;
    await activeApi?.play();
  }

  void _attach(_MovaFeedPlayerState owner) {
    assert(_owner == null || identical(_owner, owner), '控制器不能同时挂载多个 feed');
    _owner = owner;
  }

  /// Detaches [owner] and invalidates its pending pause reconciliation.
  ///
  /// 解绑 [owner]，使其待补暂停失效。
  void _detach(_MovaFeedPlayerState owner) {
    if (identical(_owner, owner)) {
      ++_pauseGeneration;
      _owner = null;
    }
  }

  void _changed() => notifyListeners();
}

/// A vertical, douyin-style "swipe for next video" feed backed by a pool of
/// players — one per warm page, rather than one shared by all.
///
/// Each page renders *its own* player's surface, so a swipe crossfades
/// between two already-live surfaces. That is what removes the two artifacts
/// the earlier single-player version had to paper over with a timed black
/// mask: a cold `open()` blanking the shared surface (black flash), and the
/// previous item's last decoded frame lingering on it until the new item's
/// frames arrived (stale frame). Neither can happen when the page being
/// swiped to was opened on its own player while the viewer was still
/// watching the previous one.
///
/// Pages the pool has no player for — a fast fling can outrun the warm
/// window — fall back to [placeholderBuilder] under their normal chrome, and
/// pick up the real surface as soon as their player finishes opening.
///
/// 基于播放器池构建的纵向"上滑下一个视频"抖音风 feed——每个热页一个播放器，
/// 而非所有页共用一个。
///
/// 每一页渲染*自己*播放器的画面，因此一次上滑是在两个已经活着的画面之间交换。
/// 这正是消除早期单播放器版本只能靠定时黑遮罩掩盖的两个瑕疵的原因：冷 `open()`
/// 清空共享画面（黑屏一闪），以及上一条最后解码的那帧滞留其上直到新一条的帧
/// 到达（残留旧帧）。当观众还在看上一条时，即将滑到的那页就已经在自己的播放器上
/// 打开了，这两件事都无从发生。
///
/// 池中没有播放器可给的页——快速连划可能甩开热窗口——会在正常 chrome 之下退回
/// [placeholderBuilder]，并在其播放器打开完成的瞬间换上真实画面。
class MovaFeedPlayer extends StatefulWidget {
  /// Creates a feed player.
  ///
  /// 创建一个 feed 播放器。
  ///
  /// - [movaFactory]: creates each pooled player; hosts pass
  ///   `createMova`. This widget owns and disposes every player the
  ///   factory produces — unlike the earlier single-player API, the host
  ///   does not construct one itself / 创建池中每个播放器，宿主传
  ///   `createMova`。工厂产出的每个播放器都由本组件持有并释放——与早期的
  ///   单播放器 API 不同，宿主不再自行构造播放器
  /// - [ctrl]: 宿主控制器，组件卸载时解绑，播放器仍归组件持有
  /// - [autoPause]: 整条 feed 的可见性守卫配置，null 禁用内置守卫
  /// - [routeObservers]: 已挂到外层 Navigator 的观察器
  /// - [errorBuilder]: 单页失败界面及显式重试入口
  /// - [loader]: resolves feed items by index / 按索引解析 feed 条目
  /// - [poolSize]: how many players may exist at once; 3 (the default) covers
  ///   every page `PageView` mounts and both swipe directions. Lower it to 2
  ///   on memory-tight targets — forward swipes stay seamless, swiping back
  ///   falls to the placeholder / 同时最多存在多少个播放器；默认 3，刚好覆盖
  ///   `PageView` 会挂载的所有页与两个滑动方向。内存吃紧的目标机可降到 2——
  ///   向前滑仍然无缝，往回滑会落到占位
  /// - [prefetchDepth]: items ahead of the active one whose *network* path
  ///   gets warmed beyond what the pool already opens; defaults to 1 /
  ///   在池已打开的范围之外，再对往后多少条条目预热*网络*链路；默认 1
  /// - [prefetcher]: network warm-up strategy; defaults to
  ///   [MovaNetworkWarmFeedPrefetcher] / 网络预热策略，默认
  ///   [MovaNetworkWarmFeedPrefetcher]
  /// - [fit]: video fill mode, applied to each player as the pool creates it;
  ///   defaults to [MovaFit.cover] (full-bleed, no letterboxing) since a
  ///   douyin-style feed's whole point is edge-to-edge video — [MovaFit.contain]
  ///   would letterbox by a different amount per item's aspect ratio, reading
  ///   as a size jump on every swipe / 视频填充模式，池创建每个播放器时对其应用；
  ///   默认 [MovaFit.cover]（铺满不留黑边）——抖音风 feed 的卖点就是画面铺满全屏，
  ///   [MovaFit.contain] 会按每条视频的宽高比留出不同大小的黑边，每次上滑都像
  ///   是尺寸跳了一下
  /// - [placeholderBuilder]: what a page shows before its player is ready;
  ///   defaults to plain black / 某页在其播放器就绪前显示什么，默认纯黑
  /// - [posterUntilFirstFrame]: keep the placeholder as a poster over a ready
  ///   page until its player reports a first frame; defaults to `false` /
  ///   页面就绪后仍把占位当封面盖着，直到其播放器报告首帧；默认 `false`
  const MovaFeedPlayer({
    super.key,
    required this.movaFactory,
    required this.loader,
    this.poolSize = 3,
    this.prefetchDepth = 1,
    this.prefetcher,
    this.fit = MovaFit.cover,
    this.placeholderBuilder,
    this.posterUntilFirstFrame = false,
    this.ctrl,
    this.autoPause = const MovaAutoPauseOpts(),
    this.routeObservers = const [],
    this.errorBuilder,
  });

  /// Creates each pooled player.
  ///
  /// 创建池中每个播放器。
  final MovaFactory movaFactory;

  /// 宿主控制入口；更换或卸载时解除绑定，不负责 dispose 控制器。
  final MovaFeedPlayerCtrl? ctrl;

  /// 整个 feed 的可见性暂停策略；默认隐藏时暂停，重新可见按原意图恢复。
  /// 为 null 时禁用内置守卫，翻页的单页互斥仍由播放器池管理。
  final MovaAutoPauseOpts? autoPause;

  /// 已挂到外层 Navigator 的观察器，用于感知半透明路由覆盖。
  final List<RouteObserver<ModalRoute<dynamic>>> routeObservers;

  /// 单页加载或播放失败时的界面；默认显示主题文案和重试按钮。
  final MovaFeedErrorBuilder? errorBuilder;

  /// Resolves feed items by index.
  /// Replacing the loader restarts at page zero with a fresh cache and pool.
  ///
  /// 按索引解析 feed 条目。
  /// 更换加载器会重建缓存与播放器池，并从第零页重新开始。
  final MovaFeedLoader loader;

  /// How many players may exist at once.
  ///
  /// 同时最多存在多少个播放器。
  final int poolSize;

  /// Items ahead of the active one whose network path gets warmed.
  ///
  /// 往后多少条条目会被预热网络链路。
  final int prefetchDepth;

  /// Network warm-up strategy; null uses [MovaFeed]'s own default.
  ///
  /// 网络预热策略；为 null 时使用 [MovaFeed] 自身的默认值。
  final IMovaFeedPrefetcher? prefetcher;

  /// Video fill mode, applied to each player as the pool creates it.
  ///
  /// 视频填充模式，池创建每个播放器时对其应用。
  final MovaFit fit;

  /// What a page shows before its player is ready.
  ///
  /// 某页在其播放器就绪前显示什么。
  final MovaFeedHolderBuilder? placeholderBuilder;

  /// When true, a ready page keeps showing [placeholderBuilder] as a poster
  /// over the live surface until that player reports its first frame
  /// (`MovaState.rendered`). Default `false`: the placeholder disappears the
  /// moment `open()` resolves, exactly as before.
  ///
  /// 为 true 时，已就绪的页面会把 [placeholderBuilder] 作为封面继续盖在真实画面上，
  /// 直到该播放器报告首帧（`MovaState.rendered`）。默认 `false`：`open()` 一完成占位就
  /// 消失，与之前完全相同。
  final bool posterUntilFirstFrame;

  @override
  State<MovaFeedPlayer> createState() => _MovaFeedPlayerState();
}

/// State for [MovaFeedPlayer]; owns the [MovaFeedPool], the
/// [MovaFeed], the [PageController], and the per-page like-state
/// notifiers that must outlive individual page rebuilds (see [MovaDouyinUiKit]'s
/// doc comment on why identity matters here).
///
/// [MovaFeedPlayer] 的状态；持有 [MovaFeedPool]、[MovaFeed]、
/// [PageController]，以及必须在单页历次重建间存活的逐页点赞状态 notifier
/// （为什么这里的身份很重要，见 [MovaDouyinUiKit] 的文档注释）。
class _MovaFeedPlayerState extends State<MovaFeedPlayer> {
  /// Holds the live players, at most [MovaFeedPlayer.poolSize] of them.
  ///
  /// 持有存活的播放器，最多 [MovaFeedPlayer.poolSize] 个。
  late MovaFeedPool _pool;

  /// Drives the pool through the feed.
  ///
  /// 驱动播放器池在 feed 中前进的 [MovaFeed]。
  late MovaFeed _feed;

  /// Backs the vertical swipe-for-next-video paging.
  ///
  /// 支撑纵向"上滑下一个视频"翻页的控制器。
  PageController _pageController = PageController();

  // 守卫在播放器解绑期间保持挂载，宿主暂停可同步撤销恢复。
  final _guardKey = GlobalKey<MovaAutoPauseState>();

  /// Like-state notifiers, keyed by feed index, kept alive within the current
  /// retained window so double-tap (gesture layer) and the social
  /// rail's like button never drift out of sync across page rebuilds.
  ///
  /// 按 feed 索引存放的点赞状态 notifier，在当前滑窗内跨重建存活，
  /// 使双击（手势层）与社交竖排的点赞按钮在历次页面重建间永不失步。
  final Map<int, ValueNotifier<({bool liked, int count})>> _likeNotifiers =
      <int, ValueNotifier<({bool liked, int count})>>{};

  /// Indices [_buildPage] has already asked [MovaFeed.ensure] for.
  ///
  /// Without this, a page whose loader resolves `null` (the feed ended) spins
  /// forever: `build` requests it, the request completes with nothing to
  /// cache, `setState` rebuilds, and `build` requests it again. Failed loads
  /// keep their ticket until the viewer explicitly retries.
  ///
  /// [_buildPage] 已经向 [MovaFeed.ensure] 请求过的索引。
  ///
  /// 没有这层记录，loader 解析出 `null`（feed 已到尽头）的页面会永远空转：
  /// `build` 发起请求，请求完成但没有任何东西可缓存，`setState` 触发重建，
  /// `build` 又发起同一个请求。加载失败保留票据并展示错误，只在显式重试时移除。
  final Map<int, Object> _requested = <int, Object>{};
  final Map<int, Object> _errors = {};
  int _activationGeneration = 0;
  int? _endIndex;
  int _loaderGeneration = 0;

  /// Records the first unavailable page and returns the loader result.
  ///
  /// 记录首个不可用页面并返回加载结果。
  Future<MovaFeedItem?> _load(int index) async {
    if (_endIndex != null && index >= _endIndex!) return null;
    final generation = _loaderGeneration;
    final item = await widget.loader(index);
    if (!mounted || generation != _loaderGeneration) return null;
    if (item == null && (_endIndex == null || index < _endIndex!)) {
      setState(() => _endIndex = index);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted ||
            generation != _loaderGeneration ||
            !_pageController.hasClients ||
            index == 0) {
          return;
        }
        if ((_pageController.page ?? 0) >= index) {
          _pageController.jumpToPage(index - 1);
        }
      });
    }
    return item;
  }

  IMovaApi? get _activeApi {
    final index = _feed.activeIndex;
    return index == null ? null : _feed.slotFor(index)?.api;
  }

  /// 当前缓存的逐页请求和点赞状态总数，供回归检查。
  int get debugPageStateCount => _requested.length + _likeNotifiers.length;

  // 当前翻页的打开、聚焦和互斥暂停全部完成后才落定。
  Future<void>? _activationSettled;

  /// Activates a valid page and pauses playback beyond the known end.
  ///
  /// 激活有效页面；进入已知终点以外时暂停播放。
  Future<void> _activate(int index) async {
    if (_endIndex != null && index >= _endIndex!) {
      await _activeApi?.pause();
      return;
    }
    final generation = ++_activationGeneration;
    try {
      final result = _feed.activate(index);
      _activationSettled = result;
      _prunePageState();
      await result;
      if (!mounted || generation != _activationGeneration) return;
      if (_feed.peek(index) == null) {
        for (final bound in _pool.boundIndices) {
          await _pool.slotFor(bound)?.api.pause();
        }
        return;
      }
      if (_feed.peek(index) != null &&
          _feed.slotFor(index)?.ready != true) {
        _recordFailure(index, StateError('媒体打开未被接受'));
      } else {
        setState(() => _errors.remove(index));
        widget.ctrl?._changed();
      }
    } on Object catch (error) {
      if (generation == _activationGeneration) _recordFailure(index, error);
    }
  }

  void _recordFailure(int index, Object error) {
    if (!mounted || !_feed.retains(index)) return;
    setState(() => _errors[index] = error);
    // 当前页加载失败时停止上一页，避免失败界面下仍有旧页声音。
    if (_pageController.hasClients && _pageController.page?.round() == index) {
      unawaited(_activeApi?.pause().catchError((Object _) {}));
    }
  }

  void _retry(int index) {
    setState(() {
      _errors.remove(index);
      _requested.remove(index);
    });
    final slot = _feed.slotFor(index);
    if (slot != null && slot.ready && slot.api.state.error != null) {
      unawaited(
        slot.api.reload().catchError((Object e) => _recordFailure(index, e)),
      );
    } else {
      unawaited(_activate(index));
    }
  }

  /// Builds host-provided or default failure content with an explicit retry.
  ///
  /// 构建宿主提供或默认的失败内容，并提供显式重试。
  Widget _failure(
    BuildContext context,
    int index,
    Object error, {
    IMovaApi? api,
  }) {
    void retry() {
      if (api == null) {
        _retry(index);
      } else {
        unawaited(
          api.reload().catchError((Object e) => _recordFailure(index, e)),
        );
      }
    }

    final custom = widget.errorBuilder;
    if (custom != null) return custom(context, index, error, retry);
    final strings = MovaPlayerStyle.stringsOf(context);
    return ColoredBox(
      color: _feedBackground,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              strings.playbackError,
              style: const TextStyle(color: Colors.white),
            ),
            TextButton(onPressed: retry, child: Text(strings.retry)),
          ],
        ),
      ),
    );
  }

  /// 回收窗口外的页面状态，等子树在本帧卸载后再释放 notifier。
  void _prunePageState() {
    _requested.removeWhere((index, _) => !_feed.retains(index));
    _errors.removeWhere((index, _) => !_feed.retains(index));
    final expired = _likeNotifiers.keys
        .where((index) => !_feed.retains(index))
        .toList();
    for (final index in expired) {
      final notifier = _likeNotifiers.remove(index)!;
      WidgetsBinding.instance.addPostFrameCallback((_) => notifier.dispose());
    }
  }

  @override
  /// Connects the loader through the page-end tracker.
  ///
  /// 将加载器接入分页终点追踪。
  void initState() {
    super.initState();
    _createFeed();
    widget.ctrl?._attach(this);
    unawaited(_activate(0));
  }

  /// Creates a fresh cache and player pool for the current loader.
  ///
  /// 为当前加载器创建新的缓存和播放器池。
  void _createFeed() {
    _pool = MovaFeedPool(
      movaFactory: widget.movaFactory,
      size: widget.poolSize,
      fit: widget.fit,
      onChanged: _onPoolChanged,
    );
    _feed = MovaFeed(
      pool: _pool,
      loader: _load,
      prefetchDepth: widget.prefetchDepth,
      prefetcher: widget.prefetcher,
    );
  }

  @override
  void didUpdateWidget(MovaFeedPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.loader != widget.loader) {
      _loaderGeneration++;
      _activationGeneration++;
      _guardKey.currentState?.cancelResume();
      _feed.dispose();
      unawaited(_pool.dispose());
      final oldPages = _pageController;
      final oldLikes = _likeNotifiers.values.toList();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        oldPages.dispose();
        for (final notifier in oldLikes) {
          notifier.dispose();
        }
      });
      _pageController = PageController();
      _likeNotifiers.clear();
      _requested.clear();
      _errors.clear();
      _endIndex = null;
      _activationSettled = null;
      _createFeed();
      unawaited(_activate(0));
    }
    if (!identical(oldWidget.ctrl, widget.ctrl)) {
      oldWidget.ctrl?._detach(this);
      widget.ctrl?._attach(this);
    }
  }

  /// Rebuilds when a pool slot binds, unbinds, or becomes ready — that is
  /// what swaps a page from its placeholder to its real video surface.
  ///
  /// 池中某个 slot 绑定、解绑或变为就绪时重建——这正是让某页从占位换成真实
  /// 视频画面的时机。
  void _onPoolChanged() {
    if (!mounted) return;
    _prunePageState();
    widget.ctrl?._changed();
    setState(() {});
  }

  /// Returns the stable like-state notifier for [index], creating it (seeded
  /// from [MovaFeed.likeStateOf]) the first time it's needed.
  ///
  /// 返回 [index] 对应的稳定点赞状态 notifier；首次需要时才创建（用
  /// [MovaFeed.likeStateOf] 播种初值）。
  ///
  /// - [index]: the feed index the notifier belongs to / 该 notifier 所属的
  ///   feed 索引
  ValueNotifier<({bool liked, int count})> _likeNotifierFor(int index) {
    return _likeNotifiers.putIfAbsent(
      index,
      () => ValueNotifier(_feed.likeStateOf(index)),
    );
  }

  /// Builds one feed page: its own pooled player's video surface once that
  /// player is ready, otherwise the page's chrome over
  /// [MovaFeedPlayer.placeholderBuilder].
  ///
  /// 构建一页 feed：其自身池播放器就绪后渲染该播放器的视频画面，否则在
  /// [MovaFeedPlayer.placeholderBuilder] 之上渲染该页的 chrome。
  ///
  /// - [context]: the page's build context / 该页的 build 上下文
  /// - [index]: the feed index being built / 正在构建的 feed 索引
  Widget _buildPage(BuildContext context, int index) {
    final failure = _errors[index];
    if (failure != null) return _failure(context, index, failure);
    final item = _feed.peek(index);
    if (item == null) {
      if (!_requested.containsKey(index) && _feed.retains(index)) {
        final ticket = Object();
        _requested[index] = ticket;
        _feed
            .ensure(index)
            .then(
              (_) {
                if (mounted &&
                    _feed.retains(index) &&
                    identical(_requested[index], ticket)) {
                  setState(() {});
                }
              },
              onError: (Object error) {
                if (identical(_requested[index], ticket)) {
                  _recordFailure(index, error);
                }
              },
            );
      }
      return _feedPlaceholder;
    }

    final uiKit = MovaDouyinUiKit(
      item: item,
      feed: _feed,
      index: index,
      likeNotifier: _likeNotifierFor(index),
    );

    final slot = _feed.slotFor(index);
    if (slot != null && slot.ready) {
      return StreamBuilder<MovaState>(
        stream: slot.api.states,
        initialData: slot.api.state,
        builder: (context, snapshot) {
          final error = snapshot.data?.error;
          if (error != null) {
            return _failure(context, index, error, api: slot.api);
          }
          return MovaPlayer(
            api: slot.api,
            uiKit: uiKit,
            autoLoadQualities: false,
            poster: widget.posterUntilFirstFrame
                ? _placeholder(context, item)
                : null,
          );
        },
      );
    }

    // No player of its own yet, so the chrome needs *some* api to scope
    // against. The active page's player stands in: every component in a
    // douyin page's chrome (social rail, author/music info) reads the feed
    // item, not playback state, so which player backs the scope changes
    // nothing on screen — it only has to be non-null.
    //
    // 该页还没有自己的播放器，而 chrome 需要*某个* api 才能建立 scope。用活跃页
    // 的播放器顶上：抖音页 chrome 里的每个组件（社交竖排、作者/音乐信息）读的都是
    // feed 条目而非播放状态，因此由哪个播放器撑起 scope 对画面毫无影响——它只需要
    // 非空即可。
    final scopeApi = slot?.api ?? _fallbackScopeApi(index);
    final placeholder = _placeholder(context, item);
    if (scopeApi == null) return placeholder;

    // Route through MovaPlayer with the placeholder as its surface rather than
    // hand-rebuilding MovaScope + buildSlots + assemble here: MovaPlayer keys the
    // tree by api identity, so when this page's own player finishes opening
    // and scopeApi flips from the borrowed fallback to its own, the chrome
    // remounts cleanly instead of silently reusing State bound to the old api.
    //
    // 走 MovaPlayer、把占位当它的 surface 传入，而非在此手工重装
    // MovaScope + buildSlots + assemble：MovaPlayer 按 api 身份给组件树做 key，
    // 于是当本页自己的播放器打开完成、scopeApi 从借来的 fallback 切成自己的播放器时，
    // chrome 会干净地重新挂载，而不是悄悄复用绑在旧 api 上的 State。
    return MovaPlayer(
      api: scopeApi,
      uiKit: uiKit,
      autoLoadQualities: false,
      surface: placeholder,
    );
  }

  /// Builds the host placeholder with the same fallback for every page phase.
  ///
  /// 为页面各阶段构建宿主占位，并共用同一默认画面。
  Widget _placeholder(BuildContext context, MovaFeedItem item) =>
      widget.placeholderBuilder?.call(context, item) ?? _feedPlaceholder;

  /// Returns any live player to scope a not-yet-bound page's chrome against:
  /// the active page's, or failing that whichever one the pool holds.
  ///
  /// `null` only before the very first bind, when the pool is still empty.
  ///
  /// 返回任意一个存活播放器，用于为尚未绑定的页面 chrome 建立 scope：优先取活跃
  /// 页的，取不到就取池中任意一个。
  ///
  /// 仅在首次绑定之前（池仍为空时）才为 `null`。
  ///
  /// - [index]: the page needing a scope, used only to skip its own empty
  ///   slot / 需要 scope 的那一页，仅用于跳过它自己的空 slot
  IMovaApi? _fallbackScopeApi(int index) {
    final active = _feed.activeIndex;
    if (active != null && active != index) {
      final slot = _feed.slotFor(active);
      if (slot != null) return slot.api;
    }
    for (final bound in _pool.boundIndices) {
      final slot = _pool.slotFor(bound);
      if (slot != null) return slot.api;
    }
    return null;
  }

  @override
  /// Limits paging to the first confirmed loader end.
  ///
  /// 将分页限制在加载器首次确认的终点之前。
  Widget build(BuildContext context) {
    final pages = PageView.builder(
      itemCount: _endIndex,
      controller: _pageController,
      scrollDirection: Axis.vertical,
      onPageChanged: _activate,
      itemBuilder: _buildPage,
    );
    final api = _activeApi;
    final opts = widget.autoPause;
    // 打开失败导致 api 为空时仍保留包装，避免 PageView 重挂丢失页码。
    if (opts == null) return pages;
    return MovaAutoPause(
      key: _guardKey,
      api: api,
      opts: opts,
      routeObservers: widget.routeObservers,
      child: pages,
    );
  }

  @override
  void dispose() {
    widget.ctrl?._detach(this);
    _feed.dispose();
    _pool.dispose();
    _pageController.dispose();
    for (final notifier in _likeNotifiers.values) {
      notifier.dispose();
    }
    super.dispose();
  }
}
