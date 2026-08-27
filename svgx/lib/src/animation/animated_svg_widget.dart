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
import 'svgx_animation_quality.dart';

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
    this.quality,
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

  /// How much per-icon animation smoothness this instance may trade away for
  /// frame throughput under high concurrency; null uses
  /// [SvgXAnimationQuality.defaultQuality].
  ///
  /// Pass [SvgXAnimationQuality.exact] to opt this icon out of all
  /// degradation. See [SvgXAnimationQuality] for exactly what is given up.
  ///
  /// 本实例在高并发下可以拿多少"单图标动画流畅度"去换帧吞吐；null 表示使用
  /// [SvgXAnimationQuality.defaultQuality]。
  ///
  /// 传 [SvgXAnimationQuality.exact] 可让本图标完全不参与降级。具体牺牲了什么
  /// 见 [SvgXAnimationQuality]。
  final SvgXAnimationQuality? quality;

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
  final List<_ClockSubscription> _subscriptions = <_ClockSubscription>[];

  /// Display frames seen since the shared ticker started, the counter every
  /// subscription's frame-divisor test is taken against.
  ///
  /// 共享 ticker 启动以来经过的显示帧数，每个订阅的帧除数判定都以它为基准。
  int _tickCount = 0;

  /// Monotonic phase allocator. Consecutive subscribers get consecutive
  /// phases, so under any divisor N a run of subscribers spreads evenly
  /// across all N frames of the cycle rather than all landing on the same
  /// one — in a scrolling grid, cells mount in visual order, so this makes
  /// "half the icons repaint this frame, the other half next frame" fall out
  /// for free. Never reset while subscribers exist; wrap-around at 2^53 is
  /// irrelevant since only `% divisor` is ever read.
  ///
  /// 单调递增的相位分配器。相邻订阅者拿到相邻相位，因此在任意除数 N 下，一串
  /// 订阅者会均匀铺满周期里的 N 帧，而不是全挤在同一帧——滚动网格里格子是按视觉
  /// 顺序挂载的，于是"这一帧重绘一半图标、下一帧重绘另一半"就自然成立了。有
  /// 订阅者存在期间绝不重置；只会读它的 `% divisor`，因此 2^53 回绕无关紧要。
  int _nextPhase = 0;

  /// Elapsed time since the shared ticker last started from idle.
  ///
  /// 共享 ticker 上一次从空闲状态启动以来经过的时间。
  Duration get elapsed => _elapsed;

  /// How many icons are animating right now — the concurrency figure every
  /// [SvgXAnimationQuality] gate is evaluated against.
  ///
  /// 当前有多少图标在播放动画——所有 [SvgXAnimationQuality] 门控判定所依据的并发
  /// 数值。
  int get subscriberCount => _subscriptions.length;

  void _onTick(Duration elapsed) {
    _elapsed = elapsed;
    final tick = ++_tickCount;
    // Concurrency is measured as "how many icons are subscribed right now",
    // which is what the degradation threshold is defined against. Icons whose
    // finite animations have already settled have unsubscribed themselves (see
    // [_SvgXAnimatedState._onGlobalTick]), so a screen of mostly-finished
    // icons correctly counts as low concurrency and stops degrading.
    //
    // 并发量的度量是"当前有多少图标处于订阅状态"，降级阈值正是针对这个定义的。
    // 有限动画已经定格的图标会自行取消订阅（见
    // [_SvgXAnimatedState._onGlobalTick]），因此一屏大多已播完的图标会正确地被
    // 算作低并发、不再降级。
    final concurrency = _subscriptions.length;
    // Snapshot before iterating: a subscriber's own callback may call
    // [unsubscribe] on itself (a finite animation settling), which would
    // otherwise mutate [_subscriptions] mid-iteration.
    //
    // 迭代前先拍快照：某个订阅者自己的回调可能在其中调用 [unsubscribe]（有限
    // 动画进入定格），若不这样做会在迭代中途修改 [_subscriptions]。
    for (final subscription in List<_ClockSubscription>.of(_subscriptions)) {
      final divisor = subscription.quality().frameDivisorFor(
        concurrency: concurrency,
        usesOffscreenLayers: subscription.usesOffscreenLayers,
      );
      // The whole point of the degradation: this subscriber's timeline does
      // not advance on this frame, so its `CustomPaint` stays clean and the
      // framework neither re-records its picture (UI-thread PAINT cost) nor
      // necessarily re-runs its offscreen render passes (raster-thread cost).
      //
      // 降级的全部意义就在这里：本订阅者的时间线这一帧不推进，于是它的
      // `CustomPaint` 保持干净，框架既不会重录它的 picture（UI 线程 PAINT
      // 开销），也不一定需要重跑它的离屏渲染通道（raster 线程开销）。
      if (divisor > 1 && (tick + subscription.phase) % divisor != 0) continue;
      subscription.onTick(elapsed);
    }
  }

  /// Registers [onTick] to be called with the shared elapsed time on eligible
  /// ticks, starting the shared ticker if this is the first subscriber.
  ///
  /// 注册 [onTick]，在符合条件的 tick 上带着共享经过时间被调用；若这是第一个
  /// 订阅者，则启动共享 ticker。
  ///
  /// [onTick] — the per-tick callback. / 逐 tick 回调。
  ///
  /// [usesOffscreenLayers] — whether this subscriber's document needs
  ///   `saveLayer` (see [SvgDocument.usesOffscreenLayers]); such documents may
  ///   be throttled harder.
  ///
  ///   本订阅者的文档是否需要 `saveLayer`（见
  ///   [SvgDocument.usesOffscreenLayers]）；这类文档可能被压得更狠。
  ///
  /// [quality] — read on every tick rather than captured, so reassigning
  ///   [SvgXAnimationQuality.defaultQuality] takes effect on live icons
  ///   without them having to re-subscribe.
  ///
  ///   每 tick 现读而非订阅时捕获，因此重新赋值
  ///   [SvgXAnimationQuality.defaultQuality] 对已存活的图标立即生效，无需重新
  ///   订阅。
  ///
  /// Returns the handle to pass back to [unsubscribe].
  ///
  ///   返回用于传回 [unsubscribe] 的句柄。
  _ClockSubscription subscribe(
    ValueChanged<Duration> onTick, {
    required bool usesOffscreenLayers,
    required SvgXAnimationQuality Function() quality,
  }) {
    final subscription = _ClockSubscription(
      onTick: onTick,
      phase: _nextPhase++,
      usesOffscreenLayers: usesOffscreenLayers,
      quality: quality,
    );
    _subscriptions.add(subscription);
    _ticker ??= Ticker(_onTick)..start();
    return subscription;
  }

  /// Unregisters [subscription]; stops (and disposes) the shared ticker once
  /// the last subscriber leaves, resetting [elapsed] so the next subscriber
  /// starts from a clean baseline.
  ///
  /// 取消注册 [subscription]；最后一个订阅者离开时停止（并 dispose）共享
  /// ticker，同时重置 [elapsed]，使下一个订阅者从干净的基线开始。
  void unsubscribe(_ClockSubscription subscription) {
    _subscriptions.remove(subscription);
    if (_subscriptions.isEmpty) {
      _ticker?.dispose();
      _ticker = null;
      _elapsed = Duration.zero;
      _tickCount = 0;
    }
  }
}

/// One [SvgXAnimated] instance's registration with [_SharedAnimationClock],
/// carrying everything the clock needs to decide whether that instance gets
/// this frame.
///
/// 一个 [SvgXAnimated] 实例在 [_SharedAnimationClock] 上的注册记录，携带时钟
/// 判定"这一帧要不要给它"所需的全部信息。
class _ClockSubscription {
  /// Creates a subscription record. / 创建一条订阅记录。
  _ClockSubscription({
    required this.onTick,
    required this.phase,
    required this.usesOffscreenLayers,
    required this.quality,
  });

  /// Called on every tick this subscription is eligible for.
  ///
  /// 在本订阅符合条件的每个 tick 上被调用。
  final ValueChanged<Duration> onTick;

  /// This subscription's offset within the frame-divisor cycle — see
  /// [_SharedAnimationClock._nextPhase].
  ///
  /// 本订阅在帧除数周期内的偏移——见 [_SharedAnimationClock._nextPhase]。
  final int phase;

  /// Whether this subscription's document needs a `saveLayer` offscreen
  /// target, which makes its frames the expensive ones.
  ///
  /// 本订阅的文档是否需要 `saveLayer` 离屏目标——这决定了它的帧属于昂贵的那类。
  final bool usesOffscreenLayers;

  /// Resolves the quality profile in force for this subscription, evaluated
  /// per tick — see [_SharedAnimationClock.subscribe].
  ///
  /// 解析本订阅当前生效的画质配置，逐 tick 求值——见
  /// [_SharedAnimationClock.subscribe]。
  final SvgXAnimationQuality Function() quality;
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

  /// This instance's live registration with the shared clock, or null when it
  /// is not currently ticking.
  ///
  /// 本实例在共享时钟上的存活注册记录；当前未 ticking 时为 null。
  _ClockSubscription? _subscription;

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
    _subscription = _SharedAnimationClock.instance.subscribe(
      _onGlobalTick,
      usesOffscreenLayers: _document.usesOffscreenLayers,
      // A closure rather than a captured value so a mid-flight change to
      // either the widget's own `quality` or the global default is picked up
      // on the next tick — see [_SharedAnimationClock.subscribe].
      //
      // 用闭包而非捕获的值，这样控件自身的 `quality` 或全局默认值中途发生变化
      // 都能在下一个 tick 生效——见 [_SharedAnimationClock.subscribe]。
      quality: () => widget.quality ?? SvgXAnimationQuality.defaultQuality,
    );
  }

  void _stopTicking() {
    final subscription = _subscription;
    if (subscription == null) return;
    _SharedAnimationClock.instance.unsubscribe(subscription);
    _subscription = null;
  }

  /// Whether the painter may substitute a clip path for an eligible `<mask>`
  /// on this frame — a method (not a field) so the closure handed to the
  /// painter stays stable across builds while still reading the live
  /// concurrency and quality profile.
  ///
  /// 本帧绘制器是否可以用裁剪路径替代合格的 `<mask>`——写成方法（而非字段），使
  /// 交给绘制器的闭包在多次 build 间保持稳定，同时仍然读取实时的并发数与画质配置。
  ///
  /// Returns true when the approximation is in force.
  ///
  ///   近似生效时返回 true。
  bool _approximateMasks() =>
      (widget.quality ?? SvgXAnimationQuality.defaultQuality)
          .approximatesMasksAt(_SharedAnimationClock.instance.subscriberCount);

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
          // Evaluated per paint, not per build: concurrency changes as cells
          // scroll in and out, and this painter is not rebuilt on every tick
          // (that is the whole point of driving it through `repaint`).
          //
          // 逐次绘制求值，而非逐次 build：并发数会随格子滚进滚出而变化，而本绘制器
          // 并不会每 tick 重建（通过 `repaint` 驱动它的全部意义正在此）。
          approximateMasks: _approximateMasks,
          // Carried alongside the closure only so the painter's shouldRepaint
          // can see a runtime quality change — see AnimatedSvgPainter.quality.
          //
          // 与闭包一并传入，唯一目的是让绘制器的 shouldRepaint 能看到运行时的画质
          // 变化——见 AnimatedSvgPainter.quality。
          quality: widget.quality ?? SvgXAnimationQuality.defaultQuality,
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
