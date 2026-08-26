// Process-wide LRU cache of parsed animated [SvgDocument]s, mirroring what
// `RustSvgPictureCache` does for the static path. Without it, every mount of
// an animated icon re-runs the full XML parse + timeline build — which, in a
// scrolling list, is once per cell per appearance.
//
// 进程级 LRU 缓存，缓存已解析的动画 [SvgDocument]，与静态路径的
// `RustSvgPictureCache` 对应。没有它的话，动画图标每次挂载都要重跑一遍完整的
// XML 解析 + 时间线构建——在滚动列表里就是每格每次出现都跑一次。

import 'dart:collection';

import 'svg_document_parser.dart';

/// Process-wide LRU cache of parsed animated SVG documents, keyed by raw
/// source string.
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

  /// Max cached documents before least-recently-used ones are dropped.
  ///
  /// 缓存上限，超出后淘汰最久未用的条目。
  int maximumSize = 200;

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
    final hit = _entries.remove(source);
    if (hit != null) {
      _entries[source] = hit; // move to most-recently-used
      return (document: hit, hasImages: false);
    }
    final document = parseAnimatedSvgDocument(source);
    final hasImages = documentHasImages(document);
    if (!hasImages) {
      _entries[source] = document;
      if (_entries.length > maximumSize) {
        _entries.remove(_entries.keys.first);
      }
    }
    return (document: document, hasImages: hasImages);
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
