// Cheap syntactic sniff for whether an SVG source needs the animated engine
// at all, so [SvgX] can route plain icons to the faster Rust static path.
//
// 廉价的语法级嗅探，判断 SVG 源是否需要动画引擎，供 [SvgX] 把普通图标路由到
// 更快的 Rust 静态路径。

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
  static final RegExp _animatePattern = RegExp(r'<animate[\s>]', caseSensitive: false);
  static final RegExp _animateTransformPattern = RegExp(r'<animateTransform[\s>]', caseSensitive: false);
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
  static final RegExp _animateMotionPattern = RegExp(r'<animateMotion[\s>]', caseSensitive: false);
  static final RegExp _setPattern = RegExp(r'<set[\s>]', caseSensitive: false);

  /// Returns true if [source] contains a SMIL `<animate>`,
  /// `<animateTransform>`, `<animateMotion>`, or `<set>` tag.
  ///
  /// 若 [source] 含 SMIL `<animate>`、`<animateTransform>`、`<animateMotion>`
  /// 或 `<set>` 标签则返回 true。
  static bool hasAnimations(String source) =>
      _animatePattern.hasMatch(source) ||
      _animateTransformPattern.hasMatch(source) ||
      _animateMotionPattern.hasMatch(source) ||
      _setPattern.hasMatch(source);
}
