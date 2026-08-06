import 'dart:async';

import '../model/feed_item.dart';
import 'engine_pool.dart';
import 'feed_prefetcher.dart';

/// Resolves the feed item at [index], or `null` to signal the feed ends
/// there (no more items past this point).
///
/// 解析索引 [index] 处的 feed 条目；返回 `null` 表示 feed 到此为止（往后
/// 没有更多条目）。
typedef MovaFeedLoader = Future<MovaFeedItem?> Function(int index);

/// Drives a [MovaFeedEnginePool] through a vertical feed of [MovaFeedItem]s
/// (bilibili/douyin-style "swipe for next video"): the page the viewer is on
/// plays on its own engine while its neighbours are already opened and
/// parked on theirs, so a swipe swaps between two live surfaces instead of
/// tearing one down and rebuilding it.
///
/// Replaces the original single-engine design (one engine, repeated
/// [MovaFeedEnginePool.bind]-equivalent `open()` calls) — see doc/SPEC.md's
/// feed entry for the black-flash / stale-frame artifacts that forced the
/// change and the on-device memory measurement that made a pool affordable.
///
/// Not a Flutter widget — this is plain, testable core logic. The UI layer
/// (`MovaFeedPlayer`) owns the `PageView` and the pool's lifetime, calls
/// [activate] on page settle, and [slotFor]/[peek] to render each page.
///
/// 用一个 [MovaFeedEnginePool] 驱动纵向 feed 的 [MovaFeedItem] 列表
/// （bilibili/抖音式"上滑下一个视频"）：观众所在页在自己的引擎上播放，相邻页
/// 早已在各自引擎上打开并停住，因此一次上滑是在两个活着的画面之间交换，而非
/// 推倒一个再重建。
///
/// 它取代了最初的单引擎设计（一个引擎，反复 `open()` 切换）——迫使这次改动的
/// 黑屏闪烁/残留旧帧两个瑕疵，以及让引擎池变得可负担的真机内存实测，见
/// doc/SPEC.md 的 feed 条目。
///
/// 不是 Flutter widget——这是纯粹、可测试的 core 逻辑。UI 层
/// （`MovaFeedPlayer`）持有 `PageView` 与池的生命周期，在翻页定格时调用
/// [activate]，用 [slotFor]/[peek] 渲染每一页。
class MovaFeedCtrl {
  /// Creates a feed controller.
  ///
  /// 创建一个 feed 控制器。
  ///
  /// - [pool]: the engine pool this controller drives; the caller owns its
  ///   lifetime and disposes it / 该控制器驱动的引擎池；其生命周期由调用方
  ///   持有并负责释放
  /// - [loader]: resolves items by index / 按索引解析条目
  /// - [prefetchDepth]: how many items ahead of the active one get their
  ///   *network* path warmed. Indices the pool already holds an engine for
  ///   are skipped — those are being opened for real, so a duplicate ranged
  ///   GET would buy nothing. Defaults conservatively to 1 (see doc/SPEC.md's
  ///   device-tiering conclusion — this stays host-configurable rather than
  ///   mova guessing device class) / 提前预热多少条条目的*网络*链路。池中
  ///   已有引擎的索引会被跳过——那些正在被真正打开，重复发一次 Range GET 毫无
  ///   收益。默认取保守值 1（见 doc/SPEC.md 的设备分档结论——这项保持宿主可配，
  ///   而非 mova 自行猜测机型档位）
  /// - [prefetcher]: warm-up strategy; defaults to
  ///   [NetworkWarmFeedPrefetcher] / 预热策略，默认
  ///   [NetworkWarmFeedPrefetcher]
  MovaFeedCtrl({
    required this.pool,
    required this.loader,
    this.prefetchDepth = 1,
    MovaFeedPrefch? prefetcher,
  }) : prefetcher = prefetcher ?? const NetworkWarmFeedPrefetcher();

  /// The engine pool this controller drives.
  ///
  /// 该控制器驱动的引擎池。
  final MovaFeedEnginePool pool;

  /// Resolves items by index.
  ///
  /// 按索引解析条目。
  final MovaFeedLoader loader;

  /// How many items ahead of the active one get their network path warmed.
  ///
  /// 提前预热多少条条目的网络链路。
  final int prefetchDepth;

  /// Warm-up strategy applied to items within [prefetchDepth].
  ///
  /// 应用于 [prefetchDepth] 范围内条目的预热策略。
  final MovaFeedPrefch prefetcher;

  /// Resolved items, keyed by index; also doubles as the local like-state
  /// store (see [toggleLike]).
  ///
  /// 已解析的条目，按索引存放；同时兼作本地点赞状态存储（见 [toggleLike]）。
  final Map<int, MovaFeedItem> _cache = <int, MovaFeedItem>{};

  /// In-flight [loader] calls, so concurrent [ensure] calls for the same
  /// index share one load instead of racing.
  ///
  /// 进行中的 [loader] 调用；同一索引的并发 [ensure] 调用共享一次加载，
  /// 而非互相竞争。
  final Map<int, Future<MovaFeedItem?>> _pending = <int, Future<MovaFeedItem?>>{};

  /// The index most recently passed to [activate], or `null` before the
  /// first activation.
  ///
  /// 最近一次传入 [activate] 的索引；首次激活前为 `null`。
  int? _activeIndex;

  /// The index most recently passed to [activate].
  ///
  /// 最近一次传入 [activate] 的索引。
  int? get activeIndex => _activeIndex;

  /// The pool slot bound to [index], or `null` if no engine currently holds
  /// it (the page fell outside the warm window, e.g. mid-fling).
  ///
  /// 绑定到 [index] 的池 slot；若当前没有引擎持有它则为 `null`（该页落在了
  /// 热窗口之外，例如快速连划途中）。
  ///
  /// - [index]: the feed index to look up / 要查询的 feed 索引
  MovaFeedSlot? slotFor(int index) => pool.slotFor(index);

  /// Synchronously returns the cached item at [index], or `null` if it
  /// hasn't resolved yet — for rendering a page's chrome without awaiting.
  ///
  /// 同步返回 [index] 处已缓存的条目；若尚未解析完成则为 `null`——供渲染
  /// 页面 chrome 时使用，无需等待。
  ///
  /// - [index]: the feed index to look up / 要查询的 feed 索引
  MovaFeedItem? peek(int index) => _cache[index];

  /// Resolves the item at [index], caching the result; concurrent calls for
  /// the same unresolved index share one [loader] invocation.
  ///
  /// 解析 [index] 处的条目并缓存结果；同一未解析索引的并发调用共享一次
  /// [loader] 调用。
  ///
  /// - [index]: the feed index to resolve / 要解析的 feed 索引
  Future<MovaFeedItem?> ensure(int index) {
    final cached = _cache[index];
    if (cached != null) return Future.value(cached);
    return _pending.putIfAbsent(index, () async {
      // `finally` (not a line after `await`): a throwing `loader` must not
      // leave `index` permanently stuck in `_pending` — `putIfAbsent` would
      // then keep handing back the same already-failed future forever,
      // silently blocking every future retry for that index.
      //
      // 用 `finally`（而非 `await` 之后的一行）：`loader` 抛异常时不能把
      // `index` 永远留在 `_pending` 里——否则 `putIfAbsent` 会一直把同一个
      // 已失败的 future 发回去，悄悄挡住这个索引此后的所有重试。
      try {
        final item = await loader(index);
        if (item != null) _cache[index] = item;
        return item;
      } finally {
        _pending.remove(index);
      }
    });
  }

  /// Makes [index] the playing page: narrows the pool's warm window around
  /// it, binds and plays its engine, and warms its neighbours in the
  /// background.
  ///
  /// Does nothing if [loader] resolves `null` for [index] (feed ended).
  /// Neighbour warm-up and network prefetch are fire-and-forget: their
  /// failures never surface here or block the active switch.
  ///
  /// Calls that land while a previous [activate] is still switching never
  /// race it — they only update which index is wanted next; the in-flight
  /// call picks that up once it settles, and every caller (the stale ones
  /// included) resolves once the pool has actually settled on the *latest*
  /// requested index. See [_runActivateLoop]'s doc comment for why this
  /// matters.
  ///
  /// 把 [index] 变成正在播放的那一页：把池的热窗口收拢到它周围，绑定并播放
  /// 它的引擎，同时在后台预热它的邻居。
  ///
  /// 若 [loader] 对 [index] 解析出 `null`（feed 已到尽头）则什么也不做。
  /// 邻居预热与网络预取都是发射后不管：它们的失败绝不会在此暴露，也不会阻塞
  /// 当前切换。
  ///
  /// 在前一次 [activate] 仍在切换期间落地的调用绝不会与它竞速——它们只是更新
  /// "接下来想要哪个索引"，进行中的那次调用会在自己收尾后接着处理；每个调用方
  /// （包括那些"过期"的）都会在池真正定格到*最新*请求的索引后才 resolve。
  /// 为什么这很重要见 [_runActivateLoop] 的文档注释。
  ///
  /// - [index]: the feed index the viewer settled on / 观众定格停留的 feed 索引
  Future<void> activate(int index) {
    _pendingIndex = index;
    return _activateLoop ??= _runActivateLoop();
  }

  /// The index [activate] most recently requested but the loop hasn't
  /// started processing yet; `null` once picked up.
  ///
  /// [activate] 最近请求、但循环尚未开始处理的索引；一旦被取走即为 `null`。
  int? _pendingIndex;

  /// The single in-flight coalescing loop, or `null` when idle; every
  /// concurrent [activate] call shares and awaits this same future instead
  /// of starting its own competing switch.
  ///
  /// 唯一进行中的合并循环；空闲时为 `null`。并发的 [activate] 调用共享并
  /// 等待同一个 future，而非各自发起互相竞争的切换。
  Future<void>? _activateLoop;

  /// Drains [_pendingIndex] one target at a time, always converging on
  /// whichever index was most recently requested and silently skipping any
  /// superseded before this loop got to them (fast repeated swipes only ever
  /// need to land on the page the viewer actually stopped on).
  ///
  /// Serialising matters even with a pool: two overlapping activations would
  /// each call [MovaFeedEnginePool.retain] with their own window and then race
  /// for a free engine, so the loser could evict the very binding the winner
  /// just made — leaving the video on a page whose chrome (author/social
  /// rail) the UI has already moved past.
  ///
  /// 逐个目标地清空 [_pendingIndex]，始终收敛到最近一次请求的索引；本循环
  /// 处理到之前就被取代的目标会被静默跳过（快速连续上滑最终只需要落在观众
  /// 真正停留的那一页）。
  ///
  /// 即使有了引擎池，串行化依然必要：两次重叠的激活会各自用自己的窗口调用
  /// [MovaFeedEnginePool.retain]，再争抢空闲引擎，落败的一方可能把胜出方刚建立
  /// 的绑定淘汰掉——导致画面停在一个 chrome（作者/社交竖排）早已翻过去的页面上。
  Future<void> _runActivateLoop() async {
    try {
      while (_pendingIndex != null) {
        final index = _pendingIndex!;
        _pendingIndex = null;
        final item = await ensure(index);
        // A newer index already arrived while `ensure` was resolving —
        // `index` is stale before it ever reaches the pool; skip straight
        // to the newer one instead of opening a page nobody will see.
        //
        // 在 `ensure` 解析期间已经来了更新的索引——`index` 还没碰到池就已经
        // 过期；直接跳去处理更新的那个，而非打开一个没人会看到的页面。
        if (_pendingIndex != null) continue;
        if (item == null) continue;

        final window = movaFeedWindow(index, pool.size);
        // Retain *before* binding: the active page must be able to take an
        // engine even when the pool is already full, and the pages worth
        // keeping are exactly the ones still in the new window.
        //
        // 先 retain 再绑定：池已满时活跃页也必须能取到引擎，而值得留下的
        // 恰好就是仍在新窗口内的那些页。
        pool.retain(window);
        _activeIndex = index;
        await pool.bind(index, item.source, autoPlay: true);
        // Everything else in the pool must go quiet — a neighbour left
        // playing from a previous activation would keep its audio going
        // under the page the viewer is actually watching.
        //
        // 池中其余引擎必须安静下来——上一次激活遗留的、仍在播放的邻居，会在
        // 观众真正在看的这一页底下继续出声。
        await pool.focus(index);

        unawaited(_warmNeighbours(index, window));
        unawaited(_primeNetwork(index, window));
      }
    } finally {
      _activateLoop = null;
    }
  }

  /// Opens every non-active index in [window] on its own pooled engine,
  /// parked (not playing) on its first frame, so swiping onto it swaps to an
  /// already-live surface.
  ///
  /// Best-effort: a neighbour that fails to load or open just means that one
  /// page falls back to the placeholder when reached.
  ///
  /// 把 [window] 中每个非活跃索引在各自的池引擎上打开、停住（不播放）在首帧，
  /// 使滑到它时是切到一个已经活着的画面。
  ///
  /// 尽力而为：某个邻居加载或打开失败，只意味着滑到那一页时会退回占位。
  ///
  /// - [index]: the active feed index, skipped here / 当前活跃索引，此处跳过
  /// - [window]: the indices worth keeping warm / 值得保持热态的索引集合
  Future<void> _warmNeighbours(int index, List<int> window) async {
    for (final neighbour in window) {
      if (neighbour == index) continue;
      // Abandon warm-up the moment a new activation arrives: its own
      // `retain` is about to redraw the window anyway, and binding a
      // now-stale neighbour would evict an engine the new active page needs.
      //
      // 一旦有新的激活到来就放弃预热：它自己的 `retain` 马上就会重画窗口，
      // 而此时再绑定一个已过期的邻居，只会淘汰掉新活跃页需要的引擎。
      if (_pendingIndex != null || _activeIndex != index) return;
      final item = await ensure(neighbour);
      if (item == null) continue;
      if (_pendingIndex != null || _activeIndex != index) return;
      await pool.bind(neighbour, item.source, autoPlay: false);
    }
  }

  /// Warms the network path (DNS/TCP/TLS/CDN edge) for the [prefetchDepth]
  /// items ahead of [index] that no pooled engine is already opening.
  ///
  /// 为 [index] 往后 [prefetchDepth] 条中、尚无池引擎正在打开的条目预热网络
  /// 链路（DNS/TCP/TLS/CDN 边缘节点）。
  ///
  /// - [index]: the active feed index / 当前活跃的 feed 索引
  /// - [window]: indices the pool already covers, skipped here / 池已覆盖、
  ///   此处跳过的索引
  Future<void> _primeNetwork(int index, List<int> window) async {
    for (var depth = 1; depth <= prefetchDepth; depth++) {
      final ahead = index + depth;
      if (window.contains(ahead)) continue;
      final item = await ensure(ahead);
      if (item == null) continue;
      await prefetcher.prime(item.source);
    }
  }

  /// The local like state for [index]: `(liked: false, count: 0)` if the
  /// item hasn't resolved yet.
  ///
  /// [index] 的本地点赞状态；条目尚未解析时为 `(liked: false, count: 0)`。
  ///
  /// - [index]: the feed index to read / 要读取的 feed 索引
  ({bool liked, int count}) likeStateOf(int index) {
    final item = _cache[index];
    return (liked: item?.initialLiked ?? false, count: item?.initialLikeCount ?? 0);
  }

  /// Flips the local like state for [index], persists it into the item
  /// cache (so scrolling away and back keeps the toggle), and fires
  /// [MovaFeedItem.onLikeChanged]. A no-op returning `(liked: false, count: 0)`
  /// if the item hasn't resolved yet.
  ///
  /// 翻转 [index] 的本地点赞状态，落回条目缓存（使滑走再滑回时切换结果仍在），
  /// 并触发 [MovaFeedItem.onLikeChanged]。若条目尚未解析则为空操作，返回
  /// `(liked: false, count: 0)`。
  ///
  /// - [index]: the feed index to toggle / 要切换的 feed 索引
  ({bool liked, int count}) toggleLike(int index) {
    final item = _cache[index];
    if (item == null) return (liked: false, count: 0);
    final liked = !item.initialLiked;
    final count = item.initialLikeCount + (liked ? 1 : -1);
    _cache[index] = item.copyWith(initialLiked: liked, initialLikeCount: count);
    item.onLikeChanged?.call(liked, count);
    return (liked: liked, count: count);
  }

  /// Clears cached items and drops any in-flight loads; does not dispose
  /// [pool], which the caller owns.
  ///
  /// 清空已缓存条目并丢弃所有进行中的加载；不会释放 [pool]——它由调用方持有。
  void dispose() {
    _cache.clear();
    _pending.clear();
  }
}
