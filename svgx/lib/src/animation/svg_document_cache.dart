// Process-wide bounded cache of parsed animated [SvgDocument]s, mirroring what
// `RustSvgxPictureCache` does for the static path. Without it, every mount of
// an animated icon re-runs the full XML parse + timeline build — which, in a
// scrolling list, is once per cell per appearance.
//
// Eviction is random, not LRU — see [SvgxDocumentCache._evictOne] for the
// measured reason.
//
// 进程级有上限缓存，缓存已解析的动画 [SvgDocument]，与静态路径的
// `RustSvgxPictureCache` 对应。没有它的话，动画图标每次挂载都要重跑一遍完整的
// XML 解析 + 时间线构建——在滚动列表里就是每格每次出现都跑一次。
//
// 淘汰策略是随机而非 LRU——实测理由见 [SvgxDocumentCache._evictOne]。

import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'document_parse_worker.dart';
import 'svg_document_parser.dart';

/// Worker cutoff in estimated opening tags. / worker 阈值，以估算开始标签计。
/// Windows host, 55 SVGator samples, 2026-11-05: three full warm-up passes,
/// then min-of-5 synchronous parses per source (no cache or file I/O timed).
/// Windows 主机，55 个 SVGator 样本：整组预热三轮，再逐源取五次同步解析最小值，
/// 计时不含缓存及文件读取。分桶如下 / Tags vs host parse time in ms:
///
/// | Tags / 标签 | Samples / 数量 | Median / 中位 | Range / 范围 |
/// |-------------|----------------|---------------|--------------|
/// | <50         | 41             | 0.364         | 0.155–2.557  |
/// | 50–99       | 6              | 1.001         | 0.500–1.941  |
/// | 100–199     | 4              | 3.233         | 0.840–6.458  |
/// | 200–399     | 3              | 6.915         | 6.580–8.068  |
/// | >=400       | 1              | 17.004        | 17.004       |
///
/// Fit: ms = 0.1249 + 0.01978 * tags (r=0.9663); 3ms predicts 145 tags.
/// Choose 128 conservatively: a 131-tag source takes 4.099ms; all six >=3ms
/// sources use the worker, while 48/55 sources stay local. Tags approximate
/// parse cost, not rendered node count; long paths/text can still cost more.
/// 回归的 3ms 点约为 145 标签；保守取 128，覆盖 131 标签却耗时 4.099ms 的样本。
/// 全部六个 >=3ms 样本进入 worker，48/55 留在主线程。标签仅近似解析成本，
/// 不等于渲染节点数；长路径或文本仍可能耗时较多。
const documentParseWorkerNodeThreshold = 128;

/// Delay before retrying failed worker startup. / worker 启动失败后的重试间隔。
const _documentParseWorkerCooldown = Duration(seconds: 60);

// Shared character codes for both scans. / 两个扫描入口共用的字符码。
const _lessThan = 0x3c;
const _greaterThan = 0x3e;
const _colon = 0x3a;
const _slash = 0x2f;
const _asciiUpperA = 0x41;
const _asciiUpperZ = 0x5a;
const _asciiLowerA = 0x61;
const _asciiLowerZ = 0x7a;
const _nonBreakingSpace = 0xa0;
const _imageNameLength = 5;
const _noName = -1;

/// Counts opening tags and detects images in one scan, without substrings or
/// regexes. Image detection matches `<(?:[^<>\s/:]+:)?image(?=[\s/>])`, including
/// non-XML prefixes and tag-like text in comments/CDATA. Matching is case-sensitive.
/// Returns immediately on an image; `tagCount` is incomplete in that case and
/// must only be used when `hasImageElement` is false.
/// 单次扫描计数开始标签并检测图片，不建子串或正则；图片检测与上述正则等价，
/// 保留非 XML 前缀、注释及 CDATA 中的伪标签匹配，且大小写敏感。
/// 命中图片即返回，此时 tagCount 不完整，仅在 hasImageElement 为 false 时可用。
@visibleForTesting
({int tagCount, bool hasImageElement}) scanSourceForWorker(String source) {
  final units = source.codeUnits;
  final length = units.length;
  var count = 0;
  var nameStart = _noName;
  var hasPrefix = false;
  for (var i = 0; i < length; i++) {
    final unit = units[i];
    if (unit == _lessThan) {
      if (i + 1 < length) {
        final next = units[i + 1];
        if ((next >= _asciiUpperA && next <= _asciiUpperZ) ||
            (next >= _asciiLowerA && next <= _asciiLowerZ)) {
          count++;
        }
      }
      // Every '<' restarts detection, even inside a rejected name.
      // 每个 '<' 都重新开始检测，包括被拒绝名称内部的 '<'。
      nameStart = i + 1;
      hasPrefix = false;
      continue;
    }
    if (nameStart == _noName) continue;
    if (unit == _colon) {
      // A single nonempty prefix; a second colon cannot match the regex.
      // 仅允许一个非空前缀；第二个冒号不可能匹配正则。
      if (!hasPrefix && i > nameStart) {
        hasPrefix = true;
        nameStart = i + 1;
      } else {
        nameStart = _noName;
      }
      continue;
    }
    // ECMAScript RegExp \s, including Unicode spaces and BOM, but not U+0085.
    // ECMAScript 正则的 \s，含 Unicode 空白及 BOM，不含 U+0085。
    final isSpace =
        (unit >= 0x09 && unit <= 0x0d) ||
        unit == 0x20 ||
        (unit >= _nonBreakingSpace &&
            (unit == _nonBreakingSpace ||
                unit == 0x1680 ||
                (unit >= 0x2000 && unit <= 0x200a) ||
                unit == 0x2028 ||
                unit == 0x2029 ||
                unit == 0x202f ||
                unit == 0x205f ||
                unit == 0x3000 ||
                unit == 0xfeff));
    if (isSpace || unit == _slash || unit == _greaterThan) {
      // Compare 'image' only at a real delimiter; EOF is not a delimiter.
      // 仅在真实分隔符处比较 'image'；串尾不算分隔符。
      if (i - nameStart == _imageNameLength &&
          units[nameStart] == 0x69 &&
          units[nameStart + 1] == 0x6d &&
          units[nameStart + 2] == _asciiLowerA &&
          units[nameStart + 3] == 0x67 &&
          units[nameStart + 4] == 0x65) {
        return (tagCount: count, hasImageElement: true);
      }
      nameStart = _noName;
    }
  }
  return (tagCount: count, hasImageElement: false);
}

/// Counts `<` followed by an ASCII letter in one allocation-free character scan.
/// Excludes closing tags, declarations and processing instructions; self-closing
/// tags count once. Tag-like text inside comments/CDATA may slightly overcount.
/// 单次遍历 codeUnits，不建子串或正则；只数 `<` 后跟 ASCII 字母的开始标签。
/// 闭合标签、声明及处理指令不计，自闭合计一次；注释或 CDATA 内伪标签允许少量多计。
@visibleForTesting
int estimateDocumentParseNodeCount(String source) {
  final units = source.codeUnits;
  var count = 0;
  for (var i = 0; i + 1 < units.length; i++) {
    if (units[i] != _lessThan) continue;
    final next = units[i + 1];
    if ((next >= _asciiUpperA && next <= _asciiUpperZ) ||
        (next >= _asciiLowerA && next <= _asciiLowerZ)) {
      count++;
    }
  }
  return count;
}

/// Maximum remembered root-only sources. / 最多记住的仅主线程源数量。
const _maximumRootOnlySources = 256;

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
/// 进程级随机淘汰缓存，缓存已解析的动画 SVG 文档，键为原始源串。
///
/// 只缓存**不含** `<image>` 节点的文档。图片节点解码出的位图由
/// `resolveImageNodes` 存在**节点自身**上，把这类文档在多个控件间共享就意味着
/// 重复解码并覆盖共享的可变状态；除此之外，文档在解析阶段跑完
/// `resolveSmilBeginTimes` 之后就是不可变的，共享是安全的。图标资产基本不会
/// 内嵌位图，所以这条排除在实践中不损失什么，却彻底避开了可变状态的隐患。
///
/// Example:
/// ```dart
/// SvgxDocumentCache.instance.maximumSize = 500;
/// ```
class SvgxDocumentCache {
  SvgxDocumentCache._();

  /// Shared instance. / 共享单例。
  static final SvgxDocumentCache instance = SvgxDocumentCache._();

  final LinkedHashMap<String, SvgDocument> _entries =
      LinkedHashMap<String, SvgDocument>();

  /// Shared futures for large, image-free sources. / 无图片大源共用的在途 Future。
  final _inFlight =
      <String, Future<({SvgDocument document, bool hasImages})>>{};

  /// Bounded root-only memoization, independent of document eviction.
  /// 有上限的仅主线程记忆，独立于文档缓存淘汰。
  final _rootOnlySources = <String>{};

  /// Prevents cleared caches being refilled by old work. / 防止旧请求重新填充已清空的缓存。
  int _cacheGeneration = 0;

  /// Startup failures temporarily bypass workers. / 启动失败后暂时绕过 worker。
  DateTime? _workerUnavailableUntil;

  /// One diagnostic per process, reset by tests. / 每进程仅打印一次，测试可重置。
  bool _didLogWorkerUnavailable = false;

  /// Injectable cooldown clock. / 可注入的冷却时钟。
  @visibleForTesting
  DateTime Function() debugWorkerClock = DateTime.now;

  /// Injectable startup retry delay. / 可注入的启动重试间隔。
  @visibleForTesting
  Duration debugWorkerCooldown = _documentParseWorkerCooldown;

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
  ///     SvgxDocumentCache.instance.getOrParse(svgSource);
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
    return _remember(source, parseAnimatedSvgDocument(source));
  }

  /// Returns [source]'s document and whether images still need decoding.
  /// Cache hits and small sources complete synchronously; large image-free
  /// sources parse in a persistent worker. Root-only UI operations retry on the
  /// calling isolate and are remembered. Worker infrastructure failures retry
  /// locally; startup failures also pause worker attempts for a cooldown.
  /// Parse failures retain their original error. Initialize svgx's native
  /// backend before calling this API.
  /// Image documents stay uncached and require decoding on the root isolate.
  /// Concurrent worker requests for the same source share a future.
  ///
  /// 返回 [source] 的文档与图片待解码标志。缓存命中及小源同步完成，无图片大源
  /// 在常驻 worker 解析。仅主 isolate 支持的 UI 操作会重试并记住；worker 基础设施
  /// 失败回退本地，启动失败另加冷却期；解析错误原样抛出。调用前须初始化原生后端。
  /// 含图片文档不缓存，须在主 isolate 解码；同源并发 worker 请求共用 Future。
  /// 适合大插画加载与启动预热。
  ///
  /// ```dart
  /// final parsed = await SvgxDocumentCache.instance.getOrParseAsync(svgSource);
  /// ```
  Future<({SvgDocument document, bool hasImages})> getOrParseAsync(
    String source,
  ) {
    final pending = _inFlight[source];
    if (pending != null) return pending;
    try {
      if (_entries.containsKey(source) ||
          _rootOnlySources.contains(source) ||
          (_workerUnavailableUntil != null &&
              debugWorkerClock().isBefore(_workerUnavailableUntil!))) {
        return SynchronousFuture(getOrParse(source));
      }
      final scan = scanSourceForWorker(source);
      if (scan.hasImageElement ||
          scan.tagCount < documentParseWorkerNodeThreshold) {
        return SynchronousFuture(getOrParse(source));
      }
    } catch (error, stack) {
      return Future.error(error, stack);
    }
    final generation = _cacheGeneration;
    late final Future<({SvgDocument document, bool hasImages})> result;
    result = _parseInWorker(source, generation).whenComplete(() {
      if (identical(_inFlight[source], result)) _inFlight.remove(source);
    });
    _inFlight[source] = result;
    return result;
  }

  /// Pre-parses [sources] sequentially, ignoring each failure and continuing.
  /// Completes when all sources have been attempted; normal cache limits and
  /// image exclusions apply. Initialize the native backend before calling.
  ///
  /// 逐个预解析 [sources]，忽略单项失败并继续；全部尝试后完成，沿用缓存上限和
  /// 图片排除规则。调用前须初始化原生后端。
  ///
  /// ```dart
  /// await SvgxDocumentCache.instance.prewarm(illustrations);
  /// ```
  Future<void> prewarm(Iterable<String> sources) async {
    for (final source in sources) {
      try {
        await getOrParseAsync(source);
      } catch (_) {
        // Loading the asset later still reports its error normally.
        // 稍后正式加载资产时仍会正常报告该错误。
      }
    }
  }

  /// Caches a fresh document using the same image exclusion on both paths.
  /// 两条路径用相同的图片排除规则缓存新文档。
  ({SvgDocument document, bool hasImages}) _remember(
    String source,
    SvgDocument document,
  ) {
    final hasImages = documentHasImages(document);
    if (!hasImages) {
      _entries[source] = document;
      while (_entries.isNotEmpty && _entries.length > maximumSize) {
        _evictOne();
      }
    }
    return (document: document, hasImages: hasImages);
  }

  /// Retries UI restrictions and unavailable infrastructure on the root isolate.
  /// UI 限制或基础设施不可用时在主 isolate 重试，解析错误保持原样。
  Future<({SvgDocument document, bool hasImages})> _parseInWorker(
    String source,
    int generation,
  ) async {
    try {
      final document = await DocumentParseWorker.instance.parse(source);
      if (generation != _cacheGeneration) {
        return (document: document, hasImages: documentHasImages(document));
      }
      final hit = _entries[source];
      return hit != null
          ? (document: hit, hasImages: false)
          : _remember(source, document);
    } on RootIsolateParseError {
      if (_rootOnlySources.length >= _maximumRootOnlySources) {
        _rootOnlySources.remove(
          _rootOnlySources.elementAt(
            _evictionRandom.nextInt(_rootOnlySources.length),
          ),
        );
      }
      _rootOnlySources.add(source);
      return _parseOnRoot(source, generation);
    } on DocumentParseWorkerUnavailable catch (error) {
      if (error.shouldCooldown) {
        _workerUnavailableUntil = debugWorkerClock().add(debugWorkerCooldown);
      }
      if (!_didLogWorkerUnavailable) {
        _didLogWorkerUnavailable = true;
        final reason = error.cause
            .toString()
            .replaceAll('\r', ' ')
            .replaceAll('\n', ' ');
        debugPrint(
          'SVGX document parse worker unavailable '
          '(${error.kind.name}: $reason); falling back to root parsing.',
          wrapWidth: null,
        );
      }
      return _parseOnRoot(source, generation);
    }
  }

  /// A fallback must not refill a cleared cache. / 回退不得重新填充已清空的缓存。
  ({SvgDocument document, bool hasImages}) _parseOnRoot(
    String source,
    int generation,
  ) {
    if (generation == _cacheGeneration) return getOrParse(source);
    final document = parseAnimatedSvgDocument(source);
    return (document: document, hasImages: documentHasImages(document));
  }

  /// Stops background work and clears asynchronous memoization for tests.
  /// 测试用：停止后台工作并清空异步记忆。
  @visibleForTesting
  Future<void> debugResetAsyncParsing() async {
    await DocumentParseWorker.instance.dispose();
    _rootOnlySources.clear();
    _inFlight.clear();
    _workerUnavailableUntil = null;
    _didLogWorkerUnavailable = false;
    debugWorkerClock = DateTime.now;
    debugWorkerCooldown = _documentParseWorkerCooldown;
    clear();
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
  void clear() {
    _cacheGeneration++;
    _entries.clear();
  }

  /// Number of parsed documents currently held. / 当前缓存的已解析文档数量。
  ///
  /// Example:
  /// ```dart
  /// print(SvgxDocumentCache.instance.length);
  /// ```
  int get length => _entries.length;
}
