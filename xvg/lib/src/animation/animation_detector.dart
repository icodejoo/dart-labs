// Syntactic detection shared by animation queries and renderer dispatch.
// 动画查询与渲染分发共用的语法检测。

import 'dart:collection';

/// Detects SMIL/CSS animations and sources requiring the Dart renderer.
/// 检测 SMIL/CSS 动画，以及需要 Dart 渲染器的源。
class AnimationDetector {
  /// Prevents instantiation of the detector. / 禁止实例化检测器。
  AnimationDetector._();

  /// Animation bit in the shared detection result. / 共享检测结果中的动画位。
  static const _animationFlag = 1;

  /// Text bit in the shared detection result. / 共享检测结果中的文字位。
  static const _textFlag = 2;

  /// Largest source retained by the memo. / 允许记忆的源串长度上限。
  static const _maximumMemoSourceLength = 4096;

  // Every tag alternative is anchored on `[\s/>]` right after the tag name,
  // never on a trailing `\b`: `\b` after "animate" does NOT match
  // `<animateTransform` ("e" and "T" are both word characters), which once
  // silently routed animateTransform-only SVGs to the static path. The same
  // pitfall hit `<animateMotion>` (missing from the list until 2026-08-25, so
  // the example app's motion demo sat still). Approach cross-checked against
  // `full_svg_flutter`'s `animation_detector.dart` (MIT, see
  // `benchmark/baseline_f/full_svg_flutter_lib/src/animation/`); the pattern
  // itself is written fresh. The same anchor keeps `<text` from matching
  // `<textPath`/`<textarea`.
  //
  // Performance (2026-08-26): one alternation in a single `RegExp` instead of
  // one `RegExp` per tag, because a static source must be scanned to the end
  // before "no match" is known; `--dart-define=LIB=micro`
  // (`detect_animations_static_sources`, 1000 real Mdi icons): 1.142us ->
  // 0.351us per icon. Adding the `(text)` branch (2026-11-13) kept it a single
  // scan: uncached ~1088 -> ~1111 ns per icon (+2.1%, local JIT).
  //
  // 每个标签分支都锚定在标签名后紧跟的 `[\s/>]`，不用结尾的 `\b`：`animate`
  // 后的 `\b` **不会**匹配 `<animateTransform`（"e" 与 "T" 都是单词字符），
  // 曾导致只用 animateTransform 的 SVG 被静默路由到静态路径；`<animateMotion>`
  // 踩过同一个坑（2026-08-25 前漏列，example 的运动示例不动）。思路参考
  // `full_svg_flutter` 的 `animation_detector.dart`（MIT，见
  // `benchmark/baseline_f/full_svg_flutter_lib/src/animation/`），正则为重新编写。
  // 同一锚点也让 `<text` 不会误命中 `<textPath`/`<textarea`。
  //
  // 性能（2026-08-26）：合并成一条 `RegExp` 的多分支，而非每个标签一条——静态源
  // 必须扫到结尾才能判定"不匹配"。1000 个真实 Mdi 图标实测单图标
  // 1.142us -> 0.351us。2026-11-13 加入 `(text)` 分支后仍是一次扫描：
  // 不走缓存时约 1088 -> 1111 ns（+2.1%，本机 JIT）。
  /// Scans all markers together; group 1 identifies text, not animation.
  /// 一次扫描所有标记；捕获组 1 区分文字与动画，各标签均要求完整名称边界。
  static final RegExp _enginePattern = RegExp(
    r'<(?:[\w-]+:)?(?:(text)|animateTransform|animateMotion|animate|set)[\s/>]|@(?:-(?:webkit|moz|o|ms)-)?keyframes',
    caseSensitive: false,
  );

  // Why the memo earns its keep: `Xvg.build` asks on every rebuild of every
  // icon, and a marker-free source is the expensive case (full scan). A
  // scrolling list re-mounts the same few hundred sources over and over.
  // Measured on 1000 real Mdi icons: ~0.389us per scan vs ~0.04us per lookup.
  //
  // 缓存的价值：`Xvg.build` 对每个图标的每次重建都要问一遍，而无标记的源恰恰
  // 最贵（必须全量扫描）；滚动列表会反复挂载同一批几百个源。1000 个真实 Mdi
  // 图标实测：扫描约 0.389us，查表约 0.04us。
  /// Shared insertion-ordered results; hits perform no regex scan.
  /// 按插入顺序保存两个查询共用的结果；命中时不运行正则。
  static final LinkedHashMap<String, int> _memo = LinkedHashMap<String, int>();

  /// Maximum number of distinct short sources remembered by both queries.
  /// 两个查询共同记忆的短源数量上限；超出时淘汰最早插入的源。
  static int maximumMemoSize = 1024;

  /// Returns whether [source] contains SMIL tags or CSS keyframes.
  /// 检测 SMIL 四类标签或 CSS keyframes（含厂商前缀），不区分大小写。
  /// 单独的文字不会被视为动画；结果按源记忆，超过 4096 字符不保留。
  ///
  /// ```dart
  /// AnimationDetector.hasAnimations('<svg><animate dur="1s"/></svg>'); // true
  /// ```
  static bool hasAnimations(String source) =>
      (_detect(source) & _animationFlag) != 0;

  /// Returns whether [source] contains animations or a `<text>` element.
  /// 含动画或 `<text>` 元素时返回 true；文字标签大小写不敏感，名称后必须是
  /// 空白、`>` 或 `/`，不会误匹配 `<textarea>` 或 `<textPath>`。
  /// 与 [hasAnimations] 共用结果缓存，超过 4096 字符的源不保留。
  ///
  /// ```dart
  /// AnimationDetector.needsDartEngine('<svg><text>Hi</text></svg>'); // true
  /// ```
  static bool needsDartEngine(String source) => _detect(source) != 0;

  /// Retrieves shared flags without retaining large sources.
  /// 读取共享标记；长源只扫描，不进入缓存。
  static int _detect(String source) {
    if (source.length > _maximumMemoSourceLength) return _scan(source);
    final memoized = _memo[source];
    if (memoized != null) return memoized;
    final result = _scan(source);
    _memo[source] = result;
    if (_memo.length > maximumMemoSize) _memo.remove(_memo.keys.first);
    return result;
  }

  /// Scans once, stopping when an animation makes both answers true.
  /// 单次扫描；发现动画即可确定两个查询都为 true，无需继续查找文字。
  static int _scan(String source) {
    var flags = 0;
    for (final match in _enginePattern.allMatches(source)) {
      if (match[1] == null) return flags | _animationFlag;
      flags = _textFlag;
    }
    return flags;
  }

  /// Forgets answers for both queries (tests / low-memory handlers).
  /// 清空两个查询共用的全部记忆结果（供测试 / 低内存处理调用）。
  static void clearMemo() => _memo.clear();
}
