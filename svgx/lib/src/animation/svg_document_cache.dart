// Process-wide bounded cache of parsed animated [SvgDocument]s, mirroring what
// `RustSvgPictureCache` does for the static path. Without it, every mount of
// an animated icon re-runs the full XML parse + timeline build — which, in a
// scrolling list, is once per cell per appearance.
//
// Eviction is random, not LRU — see [SvgDocumentCache._evictOne] for the
// measured reason.
//
// 进程级有上限缓存，缓存已解析的动画 [SvgDocument]，与静态路径的
// `RustSvgPictureCache` 对应。没有它的话，动画图标每次挂载都要重跑一遍完整的
// XML 解析 + 时间线构建——在滚动列表里就是每格每次出现都跑一次。
//
// 淘汰策略是随机而非 LRU——实测理由见 [SvgDocumentCache._evictOne]。

import 'dart:collection';
import 'dart:math' as math;

import 'svg_document_parser.dart';

/// Process-wide bounded cache of parsed animated SVG documents, keyed by raw
/// source string, with random eviction (see [maximumSize]).
///
/// Only documents with **no** `<image>` node are cached. An image node's
/// decoded bitmap is stored *on the node* by `resolveImageNodes`, so sharing
/// such a document between widgets would mean re-decoding into (and
/// overwriting) shared mutable state; everything else in a parsed document is
/// immutable after `resolveSmilBeginTimes` runs at parse time, so sharing is
/// safe. Icon assets essentially never embed bitmaps, so this exclusion costs
/// nothing in practice and keeps the mutable-state hazard out entirely.
///
/// 进程级 LRU 缓存，缓存已解析的动画 SVG 文档，键为原始源串。
///
/// 只缓存**不含** `<image>` 节点的文档。图片节点解码出的位图由
/// `resolveImageNodes` 存在**节点自身**上，把这类文档在多个控件间共享就意味着
/// 重复解码并覆盖共享的可变状态；除此之外，文档在解析阶段跑完
/// `resolveSmilBeginTimes` 之后就是不可变的，共享是安全的。图标资产基本不会
/// 内嵌位图，所以这条排除在实践中不损失什么，却彻底避开了可变状态的隐患。
///
/// Example:
/// ```dart
/// SvgDocumentCache.instance.maximumSize = 500;
/// ```
class SvgDocumentCache {
  SvgDocumentCache._();

  /// Shared instance. / 共享单例。
  static final SvgDocumentCache instance = SvgDocumentCache._();

  final LinkedHashMap<String, SvgDocument> _entries =
      LinkedHashMap<String, SvgDocument>();

  /// Max cached documents before a randomly-chosen one is dropped (see
  /// [_evictOne]).
  ///
  /// The default was raised from 200 to 1000 after measuring the cliff it sat
  /// on. A cache smaller than the working set that is *cycled through in a
  /// fixed order* — exactly what scrolling a grid of icons does — is the
  /// pathological case for LRU: each entry is evicted just before it is asked
  /// for again, so the hit rate is not "reduced", it is **zero**. The cost per
  /// miss is not only the XML re-parse; the discarded document also takes its
  /// warm per-node geometry cache with it (`SvgNode.cachedGeometry`), so the
  /// next mount re-parses every `d` string in the icon as well.
  ///
  /// Measured on a Huawei STG-AL00 (Android 12, Impeller GLES), `LIB=anim_fps
  /// ITEMS=1000`, 399 distinct real SMIL icons tiled to 1000 cells, median of
  /// 4 runs — cap 200 (below the 399-document working set) vs cap 500 (above
  /// it), identical code otherwise:
  ///
  /// | cap | build avg | real fps |
  /// |-----|-----------|----------|
  /// | 200 | 33.96ms   | 21.86    |
  /// | 500 | 20.92ms   | 29.20    |
  ///
  /// RSS peak moved 234.8MB -> 239.7MB, i.e. holding all 399 parsed documents
  /// instead of 200 cost about 5MB.
  ///
  /// 1000 is chosen to sit above the distinct-icon count of a realistic
  /// screenful-plus-cache working set rather than to be unbounded; see
  /// [_evictOne] for why exceeding it no longer falls off the same cliff.
  ///
  /// 缓存上限，超出后淘汰条目。
  ///
  /// 默认值在实测到它所处的悬崖之后，由 200 提高到 1000。当缓存小于工作集、且
  /// 工作集*按固定顺序循环访问*时——滚动图标网格正是如此——就是 LRU 的病态
  /// 情形：每个条目都恰好在再次被请求之前被淘汰，于是命中率不是"降低"，而是
  /// **归零**。每次未命中的代价不只是重跑 XML 解析；被丢弃的文档还会带走它已经
  /// 预热好的逐节点几何缓存（`SvgNode.cachedGeometry`），于是下次挂载还要把图标
  /// 里每一个 `d` 字符串重新解析一遍。
  ///
  /// 在华为 STG-AL00（Android 12，Impeller GLES）上实测，`LIB=anim_fps
  /// ITEMS=1000`，399 个互异的真实 SMIL 图标平铺到 1000 格，4 次运行取中位数
  /// ——上限 200（低于 399 的工作集）对比上限 500（高于工作集），其余代码完全
  /// 相同：
  ///
  /// | 上限 | build 均值 | 实测 FPS |
  /// |------|-----------|----------|
  /// | 200  | 33.96ms   | 21.86    |
  /// | 500  | 20.92ms   | 29.20    |
  ///
  /// RSS 峰值从 234.8MB 变为 239.7MB，即完整持有 399 份已解析文档而非 200 份，
  /// 代价约 5MB。
  ///
  /// 选 1000 是为了高于"一屏加缓存区"这种现实工作集的互异图标数，而不是为了
  /// 不设上限；超过上限后为何不再掉进同一个悬崖，见 [_evictOne]。
  int maximumSize = 1000;

  /// Returns the parsed document for [source] (parsing on a miss) together
  /// with whether it holds `<image>` nodes that still need an async decode.
  ///
  /// `hasImages` is reported here rather than left to the caller because a
  /// cache hit already knows the answer is false — image documents are never
  /// cached — which saves the caller a full tree walk on the hot path.
  ///
  /// 返回 [source] 对应的已解析文档（未命中则解析），并一并给出它是否含仍需
  /// 异步解码的 `<image>` 节点。
  ///
  /// `hasImages` 由这里给出而不是留给调用方判断，是因为缓存命中时答案必然为
  /// false——含图片的文档从不入缓存——这样热路径上就省掉一次完整的树遍历。
  ///
  /// Example:
  /// ```dart
  /// final (document: doc, hasImages: _) =
  ///     SvgDocumentCache.instance.getOrParse(svgSource);
  /// ```
  ({SvgDocument document, bool hasImages}) getOrParse(String source) {
    // A plain lookup, with no recency bookkeeping: this used to `remove` the
    // entry and reinsert it to move it to the most-recently-used end, which
    // now buys nothing at all — [_evictOne] picks its victim at random and
    // never consults insertion order. Dropping it takes a hash-table delete
    // plus an insert off the hit path, which in a scrolling grid is the single
    // hottest path this class has.
    //
    // 单纯查表，不做任何 recency 记账：这里原先会 `remove` 再重新插入，把条目移到
    // 最近使用端，而现在这么做毫无收益——[_evictOne] 随机挑牺牲者，从不参考插入
    // 顺序。去掉它，就从命中路径上省掉一次哈希表删除加一次插入，而在滚动网格里
    // 命中路径正是本类最热的路径。
    final hit = _entries[source];
    if (hit != null) return (document: hit, hasImages: false);
    final document = parseAnimatedSvgDocument(source);
    final hasImages = documentHasImages(document);
    if (!hasImages) {
      _entries[source] = document;
      if (_entries.length > maximumSize) _evictOne();
    }
    return (document: document, hasImages: hasImages);
  }

  /// Random source for [_evictOne]. Seeded deterministically so a debugging
  /// session and its rerun evict the same way.
  ///
  /// [_evictOne] 的随机源。用固定种子，使调试时的一次运行与其复现跑出相同的
  /// 淘汰序列。
  final math.Random _evictionRandom = math.Random(0x53564758); // "SVGX"

  /// Drops one entry to get back under [maximumSize], choosing a random
  /// victim rather than the least-recently-used one.
  ///
  /// This is a deliberate departure from strict LRU, and the reason is the
  /// failure mode documented on [maximumSize]: under a cyclic scan of a
  /// working set larger than the cache — a scrolling icon grid — strict LRU
  /// always evicts precisely the entry that is about to be requested next, so
  /// it hits **0%** of the time. Random eviction has no such adversarial
  /// relationship with the access order: a cyclic scan of N distinct
  /// documents through a cache of capacity C keeps roughly C/N of them
  /// resident, so the hit rate degrades smoothly toward that ratio instead of
  /// collapsing to zero. LRU's advantage — recency actually predicting reuse —
  /// is worth little here anyway, because every document in the cycle is
  /// equally likely to come back.
  ///
  /// The keys are walked with `elementAt` because [LinkedHashMap] exposes no
  /// indexed access; the walk is O(index) but runs only on an eviction, i.e.
  /// only once the cache is already full.
  ///
  /// 丢弃一个条目以回到 [maximumSize] 以内，随机挑选牺牲者而非挑最久未用的。
  ///
  /// 这是对严格 LRU 的刻意偏离，理由就是 [maximumSize] 上记录的那个失效模式：
  /// 当工作集大于缓存并被循环扫描时——滚动图标网格即是——严格 LRU 每次淘汰的
  /// 恰好是下一步就要被请求的那个条目，因此命中率是 **0%**。随机淘汰与访问顺序
  /// 之间不存在这种对抗关系：容量为 C 的缓存循环扫描 N 份互异文档时，大约能留住
  /// 其中 C/N，于是命中率是平滑地退化到这个比例，而不是崩到零。而 LRU 的优势
  /// ——"最近用过"确实能预测"还会再用"——在这里本就价值不大，因为循环里每份
  /// 文档回来的概率都相同。
  ///
  /// 用 `elementAt` 遍历键，是因为 [LinkedHashMap] 没有下标访问；这个遍历是
  /// O(index)，但只在发生淘汰时才跑，也就是缓存已经满了之后才跑。
  void _evictOne() {
    final victim = _entries.keys.elementAt(
      _evictionRandom.nextInt(_entries.length),
    );
    _entries.remove(victim);
  }

  /// Clears the cache (used by tests / low-memory handlers).
  ///
  /// 清空缓存（供测试 / 低内存处理调用）。
  void clear() => _entries.clear();

  /// Number of parsed documents currently held. / 当前缓存的已解析文档数量。
  ///
  /// Example:
  /// ```dart
  /// print(SvgDocumentCache.instance.length);
  /// ```
  int get length => _entries.length;
}
