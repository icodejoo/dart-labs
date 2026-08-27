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

// Process-wide shared [Ticker] driving every [SvgXAnimated] instance's
// timeline, instead of each instance creating (and the framework scheduling)
// its own. A scroll grid of N concurrent animated icons previously meant N
// separate `Ticker`s all registered with `SchedulerBinding` — real-device
// profiling with N=1000 showed this scale is where the per-icon overhead
// compounds badly (see docs/performance-benchmarks.md's anim_fps numbers).
// One shared clock means one `Ticker`/one `SchedulerBinding` registration
// regardless of how many icons are animating.
//
// Each subscriber records [SharedAnimationClock.elapsed] at the moment it
// subscribes as its own start offset, so its local timeline still starts at
// zero exactly when it starts ticking (unaffected by how long the shared
// clock has already been running for other subscribers) — this preserves the
// exact per-instance timeline semantics the old per-instance `Ticker` had.
//
// Trade-off, documented rather than hidden: a `Ticker` obtained from
// `TickerProviderStateMixin.createTicker` auto-pauses when its widget's
// `TickerMode` ancestor is disabled (e.g. an offstage `TabBarView` page). A
// shared, context-free ticker can't do per-subscriber muting like that — an
// icon animating inside a hidden tab keeps ticking (cheaply: only the local
// `Duration` math runs; `CustomPaint` isn't actually painted while offstage).
// Backgrounding the whole app still stops everything, since `SchedulerBinding`
// stops scheduling frames regardless of ticker muting.
//
// 全进程共享的 [Ticker]，驱动所有 [SvgXAnimated] 实例的时间线，而非每个实例各建
// 一个（框架也各自调度一个）。此前 N 个并发动画图标的滚动网格意味着 N 个
// 独立 `Ticker` 各自向 `SchedulerBinding` 注册——真机实测 N=1000 时这个规模下
// 单图标开销会严重叠加（见 docs/performance-benchmarks.md 的 anim_fps
// 数据）。一个共享时钟意味着无论多少图标在动画，都只有一个
// `Ticker`/一次 `SchedulerBinding` 注册。
//
// 每个订阅者在订阅那一刻记录 [SharedAnimationClock.elapsed] 作为自己的起始
// 偏移，因此其本地时间线仍然从零开始（不受共享时钟已经为其它订阅者跑了多久
// 影响）——这与旧的逐实例 `Ticker` 时间线语义完全一致。
//
// 权衡点，如实记录而非隐藏：`TickerProviderStateMixin.createTicker` 拿到的
// `Ticker` 会在其控件的 `TickerMode` 祖先被禁用时自动暂停（例如隐藏的
// `TabBarView` 页面）。脱离 context 的共享 ticker 做不到这种按订阅者静音——
// 隐藏 tab 里的动画图标仍会继续 tick（开销很小：只跑本地 `Duration` 运算；
// `CustomPaint` 在 offstage 时本就不会真正绘制）。整个应用切后台时一切仍会
// 停止，因为 `SchedulerBinding` 在应用不可见时本就不再调度帧，与 ticker 是否
// 静音无关。
class _SharedAnimationClock {
  _SharedAnimationClock._();

  /// Shared instance. / 共享单例。
  static final _SharedAnimationClock instance = _SharedAnimationClock._();

  Ticker? _ticker;
  Duration _elapsed = Duration.zero;
  final Set<ValueChanged<Duration>> _listeners = {};

  /// Elapsed time since the shared ticker last started from idle.
  ///
  /// 共享 ticker 上一次从空闲状态启动以来经过的时间。
  Duration get elapsed => _elapsed;

  void _onTick(Duration elapsed) {
    _elapsed = elapsed;
    // Snapshot before iterating: a listener's own callback may call
    // [unsubscribe] on itself (a finite animation settling), which would
    // otherwise mutate [_listeners] mid-iteration.
    //
    // 迭代前先拍快照：某个监听者自己的回调可能在其中调用 [unsubscribe]（有限
    // 动画进入定格），若不这样做会在迭代中途修改 [_listeners]。
    for (final listener in List<ValueChanged<Duration>>.of(_listeners)) {
      listener(elapsed);
    }
  }

  /// Registers [listener] to be called with the shared elapsed time on every
  /// tick, starting the shared ticker if this is the first subscriber.
  ///
  /// 注册 [listener]，每次 tick 都会带着共享经过时间被调用；若这是第一个
  /// 订阅者，则启动共享 ticker。
  void subscribe(ValueChanged<Duration> listener) {
    _listeners.add(listener);
    _ticker ??= Ticker(_onTick)..start();
  }

  /// Unregisters [listener]; stops (and disposes) the shared ticker once the
  /// last subscriber leaves, resetting [elapsed] so the next subscriber
  /// starts from a clean baseline.
  ///
  /// 取消注册 [listener]；最后一个订阅者离开时停止（并 dispose）共享
  /// ticker，同时重置 [elapsed]，使下一个订阅者从干净的基线开始。
  void unsubscribe(ValueChanged<Duration> listener) {
    _listeners.remove(listener);
    if (_listeners.isEmpty) {
      _ticker?.dispose();
      _ticker = null;
      _elapsed = Duration.zero;
    }
  }
}

class _SvgXAnimatedState extends State<SvgXAnimated> {
  late SvgDocument _document;

  /// This instance's local-timeline start point, as an offset into
  /// [_SharedAnimationClock.elapsed] captured at subscribe time — see
  /// [_SharedAnimationClock]'s doc comment.
  ///
  /// 本实例本地时间线的起点，是订阅那一刻记录下的
  /// [_SharedAnimationClock.elapsed] 偏移——见 [_SharedAnimationClock] 的文档
  /// 注释。
  Duration _startOffset = Duration.zero;

  /// Whether this instance is currently subscribed to the shared clock.
  ///
  /// 本实例当前是否已订阅共享时钟。
  bool _ticking = false;

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

  // Bumped on every `_parseAndStart` call and captured by that call's async
  // image-decode continuation. A source swap (`didUpdateWidget`) can start a
  // new parse+decode before a prior one's `resolveImageNodes` future
  // resolves; without this guard, the stale continuation would still be
  // `mounted` and would flip `_imagesReady`/start `_ticker` for the *new*
  // document using its own (still-live) fields, racing ahead of the new
  // document's own decode.
  //
  // 每次 `_parseAndStart` 调用都会自增，并被该次调用的异步图片解码续体捕获。
  // 源切换（`didUpdateWidget`）可能在上一次 `resolveImageNodes` 的 future
  // 落地前就发起新的解析+解码；没有这个校验，过期的续体仍然满足 `mounted`，
  // 会用*新*文档仍然存活的字段错误地把 `_imagesReady` 置真、启动
  // `_ticker`，抢在新文档自己的解码完成之前。
  int _parseGeneration = 0;

  @override
  void initState() {
    super.initState();
    _parseAndStart();
  }

  @override
  void didUpdateWidget(SvgXAnimated oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source != widget.source) {
      _stopTicking();
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
    final generation = ++_parseGeneration;
    final parsed = SvgDocumentCache.instance.getOrParse(widget.source);
    _document = parsed.document;
    _elapsed.value = Duration.zero;
    if (parsed.hasImages) {
      _imagesReady = false;
      // Ticking only starts once decode completes, so elapsed time (and thus
      // the SMIL timeline) doesn't advance behind the scenes while a
      // placeholder is showing — avoids the animation appearing to jump
      // ahead the moment images become ready.
      //
      // 要等解码完成才开始 tick，避免占位展示期间时间线在背后偷跑——不然
      // 图片就绪的瞬间动画会像是突然跳到了后面的进度。
      resolveImageNodes(_document).then((_) {
        if (!mounted || generation != _parseGeneration) return;
        setState(() => _imagesReady = true);
        _startTicking();
      });
    } else {
      _imagesReady = true;
      _startTicking();
    }
  }

  void _startTicking() {
    _startOffset = _SharedAnimationClock.instance.elapsed;
    _SharedAnimationClock.instance.subscribe(_onGlobalTick);
    _ticking = true;
  }

  void _stopTicking() {
    if (!_ticking) return;
    _SharedAnimationClock.instance.unsubscribe(_onGlobalTick);
    _ticking = false;
  }

  void _onGlobalTick(Duration globalElapsed) {
    final local = globalElapsed - _startOffset;
    _elapsed.value = local;
    // Finite (non-looping) documents stop ticking once every animation has
    // settled into its final state, instead of burning frames forever on a
    // now-static picture.
    //
    // 有限（不循环）的文档在所有动画都进入最终状态后停止 ticking，而不是
    // 对着一张已经静止的画面持续消耗帧。
    if (!_document.hasIndefiniteLoop && local >= _document.totalDuration) {
      _stopTicking();
    }
  }

  @override
  void dispose() {
    _stopTicking();
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
    final child = SizedBox(
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
    );
    // Kept deliberately, and re-tested rather than assumed. Removing this
    // boundary was measured on a Huawei STG-AL00 (`LIB=anim_fps ITEMS=1000`,
    // median of 4 runs) *after* the document-cache and style-cache fixes had
    // moved the bottleneck from build onto raster — the case where a
    // per-icon layer could plausibly have been the thing costing raster time.
    // It changed nothing: real_fps 30.00 -> 30.13, build 20.25ms -> 20.24ms,
    // raster 21.86ms -> 21.98ms, all inside run-to-run spread. So the boundary
    // is free here, and it is retained because it is *not* free to omit for
    // the case this benchmark doesn't cover: a single animated icon sitting
    // inside an otherwise-static parent that repaints for its own reasons,
    // where the boundary is what keeps this painter's per-tick repaint from
    // dragging the parent's subtree along with it. (The grid case can't show
    // that benefit because every icon shares one clock and so is dirty on the
    // same frame anyway.)
    //
    // 刻意保留，而且是重新实测而非想当然。移除这个边界的效果在华为 STG-AL00 上
    // 测过（`LIB=anim_fps ITEMS=1000`，4 次运行取中位数），且是在文档缓存与样式
    // 缓存两项修复已经把瓶颈从 build 移到 raster *之后*测的——也就是"逐图标图层
    // 可能正是 raster 耗时元凶"这个最有理由成立的时机。结果毫无变化：real_fps
    // 30.00 -> 30.13，build 20.25ms -> 20.24ms，raster 21.86ms -> 21.98ms，全部
    // 落在运行间波动内。所以这个边界在此场景是免费的；保留它，是因为在本基准
    // 覆盖不到的另一种场景下"去掉"并不免费：单个动画图标处在一个因自身原因重绘
    // 的静态父树里时，正是这个边界拦住了本绘制器的逐帧重绘去连累父级子树。
    // （网格场景显示不出这个收益，因为所有图标共用一个时钟，本来就在同一帧全脏。）
    return RepaintBoundary(child: child);
  }
}
