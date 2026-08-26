// Public animated-SVG widget: parses the source once, then drives an
// [AnimationController] that samples the timeline and repaints every frame
// via [AnimatedSvgPainter]. This is the original replacement for the
// vendored F `AnimatedSvgPicture` — see svgx CLAUDE.md. Original
// implementation.
//
// 公开的动画 SVG 组件：只解析一次源串，之后用 [AnimationController] 驱动，
// 在每帧对时间线采样并通过 [AnimatedSvgPainter] 重绘。这是替代 vendor 的 F
// 中 `AnimatedSvgPicture` 的原创实现——见 svgx CLAUDE.md。原创实现。

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'animated_svg_painter.dart';
import 'svg_document_cache.dart';
import 'svg_document_parser.dart';
import 'svg_theme.dart';

/// Renders a SMIL-animated SVG string using this project's original
/// animation engine (parse → timeline → per-frame sample → paint).
///
/// See svgx CLAUDE.md for the supported SMIL subset: `<animate>` on
/// `stroke-dashoffset` (and, generically, any single-numeric presentation
/// attribute) with `values`/`from`-`to`, `dur`, a numeric `begin` delay, and
/// `fill="freeze"`. `<animateTransform>`, `<animateMotion>`, and CSS
/// `@keyframes` animation are **not supported**.
///
/// Example:
/// ```dart
/// SvgXAnimated.string(svgSource, width: 48, height: 48)
/// ```
///
/// 用本项目原创动画引擎（解析 → 时间线 → 逐帧采样 → 绘制）渲染 SMIL 动画
/// SVG 字符串。
///
/// 支持的 SMIL 子集见 svgx CLAUDE.md：作用于 `stroke-dashoffset`（泛化后可作用
/// 于任意单一数值型表现属性）的 `<animate>`，配合 `values`/`from`-`to`、
/// `dur`、数值型 `begin` 延迟与 `fill="freeze"`。**不支持**
/// `<animateTransform>`、`<animateMotion>` 及 CSS `@keyframes` 动画。
///
/// 用例：
/// ```dart
/// SvgXAnimated.string(svgSource, width: 48, height: 48)
/// ```
class SvgXAnimated extends StatefulWidget {
  /// Creates the animated renderer from a raw SVG string.
  ///
  /// 用原始 SVG 字符串创建动画渲染组件。
  const SvgXAnimated.string(
    this.source, {
    super.key,
    this.width,
    this.height,
    this.fit = BoxFit.contain,
    this.alignment = Alignment.center,
    this.theme,
  });

  /// Raw SVG markup containing SMIL `<animate>` elements.
  ///
  /// 含 SMIL `<animate>` 元素的原始 SVG 源。
  final String source;

  /// Target width; null uses the SVG's intrinsic width. / 目标宽度，null 用固有宽。
  final double? width;

  /// Target height; null uses the SVG's intrinsic height. / 目标高度，null 用固有高。
  final double? height;

  /// How the picture is inscribed into the box. / picture 如何适配到盒子。
  final BoxFit fit;

  /// Alignment within the box. / 在盒子内的对齐方式。
  final Alignment alignment;

  /// Theme controlling `currentColor`; defaults to opaque black.
  ///
  /// 控制 `currentColor` 的主题；默认不透明黑色。
  final SvgTheme? theme;

  @override
  State<SvgXAnimated> createState() => _SvgXAnimatedState();
}

// Drives the timeline with a raw [Ticker] (elapsed wall-clock time since
// start) rather than an [AnimationController] bounded to `[0, 1]`: SMIL
// `repeatCount` means different animations on the same document can have
// different effective lengths (or loop forever), and `SmilAnimation.sample`/
// `SmilTransformAnimation.sample` already do their own begin/duration/repeat
// math against an ever-increasing global time — a bounded controller would
// have to be reset/restarted per loop, which doesn't compose across
// independently-timed sibling animations (e.g. staggered spinner arcs).
//
// 用原始 [Ticker]（自启动以来的挂钟耗时）而非绑定在 `[0, 1]` 的
// [AnimationController] 驱动时间线：SMIL 的 `repeatCount` 意味着同一文档内
// 不同动画可能有不同的有效时长（甚至无限循环），而
// `SmilAnimation.sample`/`SmilTransformAnimation.sample` 本身已经针对一个
// 持续递增的全局时间做 begin/duration/repeat 运算——绑定的 controller 得每轮
// 重置/重启，无法应对彼此独立计时的兄弟动画（例如错峰起始的 spinner 弧线）。
class _SvgXAnimatedState extends State<SvgXAnimated>
    with SingleTickerProviderStateMixin {
  late SvgDocument _document;
  late Ticker _ticker;

  // The timeline position is published through a notifier the painter is
  // wired to (see AnimatedSvgPainter's `clock`), not through setState. A
  // per-tick setState would mark this element dirty and re-run build + layout
  // for every ticking icon on every frame; a Listenable handed to
  // CustomPainter.repaint makes the framework skip both phases and only mark
  // the RenderCustomPaint as needing paint — which is exactly what changed.
  // (Flutter's CustomPainter docs: the render object "will listen to the
  // Listenable and repaint whenever the animation ticks, avoiding both the
  // build and layout phases of the pipeline".)
  //
  // 时间线位置通过一个绘制器所绑定的 notifier 发布（见 AnimatedSvgPainter 的
  // `clock`），而不是通过 setState。每 tick 一次 setState 会把本 element 标记为
  // dirty，使每个正在 ticking 的图标每帧都重跑 build + layout；把 Listenable
  // 交给 CustomPainter.repaint 则让框架跳过这两个阶段，只把 RenderCustomPaint
  // 标记为需要重绘——变的正是这一点。（Flutter CustomPainter 文档原文：渲染
  // 对象"will listen to the Listenable and repaint whenever the animation
  // ticks, avoiding both the build and layout phases of the pipeline"。）
  final ValueNotifier<Duration> _elapsed = ValueNotifier(Duration.zero);

  // Documents with no <image> node never touch this — it starts true and
  // stays true, so the common case pays zero extra cost. A document with
  // images flips it false until resolveImageNodes' async decode completes,
  // during which build() shows a plain placeholder instead of ticking.
  //
  // 无 <image> 节点的文档完全不会碰这个字段——恒为 true，常见场景零额外
  // 开销。含图片的文档在 resolveImageNodes 异步解码完成前会置为 false，
  // 期间 build() 展示占位而非开始 ticking。
  bool _imagesReady = true;

  @override
  void initState() {
    super.initState();
    _parseAndStart();
  }

  @override
  void didUpdateWidget(SvgXAnimated oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source != widget.source) {
      _ticker.dispose();
      _parseAndStart();
    }
  }

  void _parseAndStart() {
    // Parsing goes through the shared LRU cache: in a scrolling list the same
    // icon source is mounted, disposed and re-mounted repeatedly, and the
    // parse is by far the most expensive part of a mount (measured with
    // `--dart-define=LIB=micro`, 399 real SMIL icons: parse 43.8us per icon
    // vs 0.1us for a cache hit).
    //
    // 解析走共享的 LRU 缓存：滚动列表里同一个图标源会被反复挂载、销毁、再挂载，
    // 而解析是一次挂载里最贵的一环（`--dart-define=LIB=micro` 实测，399 个真实
    // SMIL 图标：解析单图标 43.8us，缓存命中 0.1us）。
    final parsed = SvgDocumentCache.instance.getOrParse(widget.source);
    _document = parsed.document;
    _elapsed.value = Duration.zero;
    _ticker = createTicker(_onTick);
    if (parsed.hasImages) {
      _imagesReady = false;
      // Ticker only starts once decode completes, so elapsed time (and thus
      // the SMIL timeline) doesn't advance behind the scenes while a
      // placeholder is showing — avoids the animation appearing to jump
      // ahead the moment images become ready.
      //
      // ticker 要等解码完成才启动，避免占位展示期间时间线在背后偷跑——不然
      // 图片就绪的瞬间动画会像是突然跳到了后面的进度。
      resolveImageNodes(_document).then((_) {
        if (!mounted) return;
        setState(() => _imagesReady = true);
        _ticker.start();
      });
    } else {
      _imagesReady = true;
      _ticker.start();
    }
  }

  void _onTick(Duration elapsed) {
    _elapsed.value = elapsed;
    // Finite (non-looping) documents stop ticking once every animation has
    // settled into its final state, instead of burning frames forever on a
    // now-static picture.
    //
    // 有限（不循环）的文档在所有动画都进入最终状态后停止 ticking，而不是
    // 对着一张已经静止的画面持续消耗帧。
    if (!_document.hasIndefiniteLoop && elapsed >= _document.totalDuration) {
      _ticker.stop();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    // Safe to dispose here: the RenderCustomPaint that listens to this
    // notifier is detached (and drops its listener) when the element is
    // deactivated, which happens before unmount calls dispose. This is the
    // same lifetime the CustomPainter docs assume when they suggest passing an
    // AnimationController-backed Animation to `repaint`.
    //
    // 在此处 dispose 是安全的：监听本 notifier 的 RenderCustomPaint 会在 element
    // 被 deactivate 时 detach 并摘掉监听，而这发生在 unmount 调用 dispose 之前。
    // CustomPainter 文档建议把 AnimationController 支撑的 Animation 传给
    // `repaint` 时，假设的正是同一套生命周期。
    _elapsed.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final w = widget.width ?? _document.width;
    final h = widget.height ?? _document.height;
    if (!_imagesReady) {
      // Simple loading placeholder while embedded <image> bitmaps decode —
      // no dedicated state machine, per task scope.
      // 内嵌 <image> 位图解码期间的简单占位——按任务范围不做专门状态机。
      return SizedBox(width: w, height: h);
    }
    return RepaintBoundary(
      child: SizedBox(
        width: w,
        height: h,
        child: CustomPaint(
          size: Size(w, h),
          painter: AnimatedSvgPainter(
            root: _document.root,
            intrinsicSize: Size(_document.width, _document.height),
            clock: _elapsed,
            theme: widget.theme ?? const SvgTheme(),
            fit: widget.fit,
            alignment: widget.alignment,
            gradients: _document.gradients,
            clipPaths: _document.clipPaths,
            masks: _document.masks,
          ),
        ),
      ),
    );
  }
}
