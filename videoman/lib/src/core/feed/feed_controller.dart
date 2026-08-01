import 'dart:async';

import '../api.dart';
import '../model/feed_item.dart';
import 'feed_prefetcher.dart';

/// Resolves the feed item at [index], or `null` to signal the feed ends
/// there (no more items past this point).
///
/// 解析索引 [index] 处的 feed 条目；返回 `null` 表示 feed 到此为止（往后
/// 没有更多条目）。
typedef VmFeedLoader = Future<VmFeedItem?> Function(int index);

/// Drives a single [VmApi] through a vertical feed of [VmFeedItem]s
/// (bilibili/douyin-style "swipe for next video"), on the single-kernel
/// architecture decided during design: one live playback engine, switched
/// via repeated [VmApi.open] calls, rather than a pool of parallel engines —
/// see doc/SPEC.md's feed entry for the memory/CPU trade-off this was
/// weighed against.
///
/// Not a Flutter widget — this is plain, testable core logic. The UI layer
/// (`VmFeedPlayer`) owns the `PageView` and calls [activate] on page settle,
/// [ensure]/[peek] to render chrome for pages not yet current.
///
/// 用单个 [VmApi] 驱动一个纵向 feed 的 [VmFeedItem] 列表
/// （bilibili/douyin 式"上滑下一个视频"），采用设计阶段定下的单内核架构：
/// 只有一个存活的播放引擎，通过反复调用 [VmApi.open] 切换，而非并行维护一个
/// 引擎池——这背后的内存/CPU 取舍见 doc/SPEC.md 的 feed 条目。
///
/// 不是 Flutter widget——这是纯粹、可测试的 core 逻辑。UI 层
/// （`VmFeedPlayer`）持有 `PageView`，在翻页定格时调用 [activate]，用
/// [ensure]/[peek] 为尚未成为当前页的页面渲染 chrome。
class VmFeedController {
  /// Creates a feed controller.
  ///
  /// 创建一个 feed 控制器。
  ///
  /// - [api]: the single engine this controller drives / 该控制器驱动的唯一
  ///   引擎
  /// - [loader]: resolves items by index / 按索引解析条目
  /// - [prefetchDepth]: how many items ahead of the active one get warmed;
  ///   defaults conservatively to 1 (see doc/SPEC.md's device-tiering
  ///   conclusion — this stays host-configurable rather than videoman
  ///   guessing device class) / 提前预热多少条（相对当前活跃条目）；默认取
  ///   保守值 1（见 doc/SPEC.md 的设备分档结论——这项保持宿主可配，而非
  ///   videoman 自行猜测机型档位）
  /// - [prefetcher]: warm-up strategy; defaults to
  ///   [NetworkWarmFeedPrefetcher] / 预热策略，默认
  ///   [NetworkWarmFeedPrefetcher]
  VmFeedController({
    required this.api,
    required this.loader,
    this.prefetchDepth = 1,
    VmFeedPrefetcher? prefetcher,
  }) : prefetcher = prefetcher ?? const NetworkWarmFeedPrefetcher();

  /// The single engine this controller drives.
  ///
  /// 该控制器驱动的唯一引擎。
  final VmApi api;

  /// Resolves items by index.
  ///
  /// 按索引解析条目。
  final VmFeedLoader loader;

  /// How many items ahead of the active one get warmed.
  ///
  /// 提前预热多少条（相对当前活跃条目）。
  final int prefetchDepth;

  /// Warm-up strategy applied to items within [prefetchDepth].
  ///
  /// 应用于 [prefetchDepth] 范围内条目的预热策略。
  final VmFeedPrefetcher prefetcher;

  /// Resolved items, keyed by index; also doubles as the local like-state
  /// store (see [toggleLike]).
  ///
  /// 已解析的条目，按索引存放；同时兼作本地点赞状态存储（见 [toggleLike]）。
  final Map<int, VmFeedItem> _cache = <int, VmFeedItem>{};

  /// In-flight [loader] calls, so concurrent [ensure] calls for the same
  /// index share one load instead of racing.
  ///
  /// 进行中的 [loader] 调用；同一索引的并发 [ensure] 调用共享一次加载，
  /// 而非互相竞争。
  final Map<int, Future<VmFeedItem?>> _pending = <int, Future<VmFeedItem?>>{};

  /// The index most recently passed to [activate], or `null` before the
  /// first activation.
  ///
  /// 最近一次传入 [activate] 的索引；首次激活前为 `null`。
  int? _activeIndex;

  /// The index most recently passed to [activate].
  ///
  /// 最近一次传入 [activate] 的索引。
  int? get activeIndex => _activeIndex;

  /// Synchronously returns the cached item at [index], or `null` if it
  /// hasn't resolved yet — for rendering non-active pages' chrome without
  /// awaiting.
  ///
  /// 同步返回 [index] 处已缓存的条目；若尚未解析完成则为 `null`——供渲染
  /// 非当前页的 chrome 时使用，无需等待。
  VmFeedItem? peek(int index) => _cache[index];

  /// Resolves the item at [index], caching the result; concurrent calls for
  /// the same unresolved index share one [loader] invocation.
  ///
  /// 解析 [index] 处的条目并缓存结果；同一未解析索引的并发调用共享一次
  /// [loader] 调用。
  Future<VmFeedItem?> ensure(int index) {
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

  /// Switches the single engine to the item at [index] and fires
  /// best-effort prefetch for the [prefetchDepth] items ahead.
  ///
  /// Does nothing if [loader] resolves `null` for [index] (feed ended).
  /// Prefetch is fire-and-forget: its failures never surface here or block
  /// the active switch.
  ///
  /// 把唯一引擎切换到 [index] 处的条目，并对往后 [prefetchDepth] 条条目发起
  /// 尽力而为的预取。
  ///
  /// 若 [loader] 对 [index] 解析为 `null`（feed 已结束）则什么都不做。预取是
  /// 即发即忘的：其失败绝不会在此冒出，也不会阻塞当前切换。
  Future<void> activate(int index) async {
    final item = await ensure(index);
    if (item == null) return;
    _activeIndex = index;
    await api.open(item.source);
    for (var depth = 1; depth <= prefetchDepth; depth++) {
      final aheadIndex = index + depth;
      unawaited(ensure(aheadIndex).then((ahead) {
        if (ahead != null) prefetcher.prime(ahead.source);
      }));
    }
  }

  /// The local like state for [index]: `(liked: false, count: 0)` if the
  /// item hasn't resolved yet.
  ///
  /// [index] 的本地点赞状态；条目尚未解析时为 `(liked: false, count: 0)`。
  ({bool liked, int count}) likeStateOf(int index) {
    final item = _cache[index];
    return (liked: item?.initialLiked ?? false, count: item?.initialLikeCount ?? 0);
  }

  /// Flips the local like state for [index], persists it into the item
  /// cache (so scrolling away and back keeps the toggle), and fires
  /// [VmFeedItem.onLikeChanged]. A no-op returning `(liked: false, count: 0)`
  /// if the item hasn't resolved yet.
  ///
  /// 翻转 [index] 的本地点赞状态，落回条目缓存（使滑走再滑回时切换结果仍在），
  /// 并触发 [VmFeedItem.onLikeChanged]。若条目尚未解析则为空操作，返回
  /// `(liked: false, count: 0)`。
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
  /// [api], which the caller owns.
  ///
  /// 清空已缓存条目并丢弃所有进行中的加载；不会释放 [api]——它由调用方持有。
  void dispose() {
    _cache.clear();
    _pending.clear();
  }
}
