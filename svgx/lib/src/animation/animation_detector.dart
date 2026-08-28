// Cheap syntactic sniff for whether an SVG source needs the animated engine
// at all, so [Svgx] can route plain icons to the faster Rust static path.
//
// 廉价的语法级嗅探，判断 SVG 源是否需要动画引擎，供 [Svgx] 把普通图标路由到
// 更快的 Rust 静态路径。

import 'dart:collection';

/// Detects SMIL animation markers (`<animate>`, `<animateTransform>`,
/// `<set>`) in raw SVG source.
///
/// Only SMIL is detected — CSS `@keyframes`/`animation-*`/`transition-*`
/// driven animation is **not supported** by this engine yet (see project
/// `CLAUDE.md`); an SVG that only uses CSS animation is treated as static and
/// will render its resting state without animating.
///
/// 检测原始 SVG 源中的 SMIL 动画标记（`<animate>`、`<animateTransform>`、
/// `<set>`）。
///
/// 仅检测 SMIL——CSS `@keyframes`/`animation-*`/`transition-*` 驱动的动画
/// **本引擎尚不支持**（见项目 `CLAUDE.md`）；仅含 CSS 动画的 SVG 会被当作
/// 静态渲染，展示其静止状态而不播放动画。
class AnimationDetector {
  AnimationDetector._();

  // One pattern per tag, each anchored on `[\s>]` right after the tag name,
  // rather than a single combined-alternation regex ending in a `\b` word
  // boundary. A combined `<\s*(animate|set)\b` pattern is a real pitfall:
  // `\b` after "animate" does NOT match `<animateTransform` (the "e" of
  // "animate" and the "T" of "Transform" are both word characters, so
  // there's no boundary between them) — this project actually hit that bug
  // first (animateTransform-only SVGs silently fell back to the static
  // path). Approach cross-checked against `full_svg_flutter`'s own
  // `lib/src/animation/animation_detector.dart` (`_animatePattern`/
  // `_animateTransformPattern`, MIT licensed — see
  // `benchmark/baseline_f/full_svg_flutter_lib/src/animation/
  // animation_detector.dart` in this repo), which already avoids this
  // pitfall by using separate per-tag patterns; the patterns themselves are
  // written fresh here for this engine's smaller supported-tag set (no CSS
  // detection — see svgx CLAUDE.md's CSS section).
  //
  // 每个标签一条独立正则，各自锚定在标签名后紧跟的 `[\s>]`，而非用一条以
  // `\b` 单词边界收尾的合并正则。合并写法 `<\s*(animate|set)\b` 有一个真实
  // 的坑：`animate` 后的 `\b` **不会**匹配 `<animateTransform`（"animate" 的
  // "e" 与 "Transform" 的 "T" 都是单词字符，二者之间没有边界）——本项目
  // 确实先踩了这个坑（只用 animateTransform 的 SVG 被静默误判为静态）。
  // 该思路参考自 `full_svg_flutter` 自身的
  // `lib/src/animation/animation_detector.dart`（`_animatePattern`/
  // `_animateTransformPattern`，MIT 许可——见本仓库
  // `benchmark/baseline_f/full_svg_flutter_lib/src/animation/
  // animation_detector.dart`），它已经用分标签正则规避了这个坑；具体正则是
  // 针对本引擎更小的支持标签集（不含 CSS 检测——见 svgx CLAUDE.md 的 CSS
  // 章节）重新写的。
  //
  // Performance (2026-08-26): the four per-tag patterns are combined into one
  // alternation *inside* a single `RegExp` rather than kept as four separate
  // `RegExp`s. Semantics are identical — every alternative still carries its
  // own `[\s>]` anchor, so the `\b` pitfall described above is still avoided
  // and `<animateTransform` cannot be matched by the `animate` branch. The
  // reason for merging: `hasMatch` on a static source has to scan the *whole*
  // string before it can report "no match", so four patterns meant four full
  // scans of every static icon on every rebuild. Measured with
  // `--dart-define=LIB=micro` (`detect_animations_static_sources`, 1000 real
  // Mdi icons): 1.142us -> 0.351us per icon.
  //
  // 性能（2026-08-26）：四条分标签正则合并进**一条** `RegExp` 的多分支，而非
  // 保留四个独立 `RegExp`。语义完全不变——每个分支各自仍带 `[\s>]` 锚点，
  // 因此上面说的 `\b` 坑依旧被规避，`animate` 分支也不可能匹配到
  // `<animateTransform`。合并的理由：静态源上 `hasMatch` 必须扫完**整个**
  // 字符串才能判定"不匹配"，四条正则就意味着每次重建都要把每个静态图标完整
  // 扫四遍。用 `--dart-define=LIB=micro` 实测
  // （`detect_animations_static_sources`，1000 个真实 Mdi 图标）：
  // 单图标 1.142us -> 0.351us。
  static final RegExp _animationPattern = RegExp(
    r'<(?:animateTransform|animateMotion|animate|set)[\s>]',
    caseSensitive: false,
  );
  // `<animateMotion>` hits the exact same "animate" + immediately-following
  // capital letter pitfall as `<animateTransform>` (see the class doc above)
  // — it was missing here entirely, which silently routed animateMotion-only
  // SVGs to the static usvg path (usvg drops SMIL, so the element just sits
  // still). Found 2026-08-25 while debugging the example app's
  // `<animateMotion>` demo not animating.
  //
  // `<animateMotion>` 和 `<animateTransform>` 踩的是同一个"animate 后紧跟大写
  // 字母"的坑（见上方类注释）——这里之前完全漏掉了它，导致只用
  // `<animateMotion>` 的 SVG 被静默路由去静态 usvg 路径（usvg 会丢弃 SMIL，
  // 元素直接静止不动）。2026-08-25 排查 example 应用的 `<animateMotion>` 示例
  // 不动时发现。
  // Memo of past answers, in insertion order so the oldest can be dropped once
  // [maximumMemoSize] is reached.
  //
  // Why it earns its keep: `Svgx.build` asks this question on every rebuild of
  // every icon, and a source with no animation markers is the expensive case —
  // `hasMatch` has to scan the *whole* string before it can answer "no". A
  // scrolling list mounts, disposes and re-mounts the same handful of hundreds
  // of sources over and over, so the same full scans repeat indefinitely.
  // Measured with `--dart-define=LIB=micro` on 1000 real Mdi icons: 0.389us per
  // icon for the scan, 0.04us-scale for a map lookup.
  //
  // 记录过往答案的表，按插入顺序存放，达到 [maximumMemoSize] 时丢弃最旧的一条。
  //
  // 它凭什么值得存在：`Svgx.build` 对每个图标的每次重建都要问一遍这个问题，而
  // 不含动画标记的源恰恰是最贵的情形——`hasMatch` 必须扫完**整个**字符串才能
  // 回答"没有"。滚动列表会把同一批几百个源反复挂载、销毁、再挂载，于是同样的
  // 全量扫描无限重复。`--dart-define=LIB=micro` 在 1000 个真实 Mdi 图标上实测：
  // 扫描单图标 0.389us，一次 map 查找是 0.04us 量级。
  static final LinkedHashMap<String, bool> _memo =
      LinkedHashMap<String, bool>();

  /// Upper bound on how many distinct sources [hasAnimations] remembers.
  ///
  /// Entries are a `bool` plus a reference to a string the caller already
  /// holds, so the cap is about bounding retention, not size. Note the shape of
  /// the miss case: a working set larger than this that is cycled through in a
  /// fixed order never hits (the entry for a source is evicted just before it
  /// comes round again), and then each call pays the scan *plus* a failed
  /// lookup. The default is set well above the few hundred distinct icons a
  /// scrolling UI keeps in flight.
  ///
  /// [hasAnimations] 最多记住多少个不同的源。
  ///
  /// 每条记录只是一个 `bool` 加一个调用方本就持有的字符串引用，所以这个上限是
  /// 用来约束"持有多久"而非"占多大"。注意未命中情形的形态：如果工作集比这个
  /// 上限还大、且按固定顺序循环访问，就会一次都命中不了（某个源的记录恰好在它
  /// 再次轮到之前被淘汰），此时每次调用要付扫描**外加**一次失败的查找。默认值
  /// 定得远高于滚动界面同时在飞的那几百个不同图标。
  static int maximumMemoSize = 1024;

  /// Returns true if [source] contains a SMIL `<animate>`,
  /// `<animateTransform>`, `<animateMotion>`, or `<set>` tag.
  ///
  /// The answer is memoized per source string — see [maximumMemoSize].
  ///
  /// 若 [source] 含 SMIL `<animate>`、`<animateTransform>`、`<animateMotion>`
  /// 或 `<set>` 标签则返回 true。
  ///
  /// 结果按源字符串记忆——见 [maximumMemoSize]。
  ///
  /// Example:
  /// ```dart
  /// AnimationDetector.hasAnimations('<svg><animate dur="1s"/></svg>'); // true
  /// ```
  static bool hasAnimations(String source) {
    final memoized = _memo[source];
    if (memoized != null) return memoized;
    final result = _animationPattern.hasMatch(source);
    _memo[source] = result;
    if (_memo.length > maximumMemoSize) _memo.remove(_memo.keys.first);
    return result;
  }

  /// Forgets every memoized answer (used by tests / low-memory handlers).
  ///
  /// 清空全部记忆结果（供测试 / 低内存处理调用）。
  static void clearMemo() => _memo.clear();
}
