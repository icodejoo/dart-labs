// Top-level dispatch widget: routes an SVG source string to the animated
// (original Dart-side SMIL engine) or static (Rust usvg → ui.Picture)
// renderer, per the "split by asset" architecture decision in CLAUDE.md.
//
// 顶层分发组件：按 CLAUDE.md 的"按资产切分"架构决定，把 SVG 源串路由到动画
// 路径（原创 Dart 侧 SMIL 引擎）或静态路径（Rust usvg → ui.Picture）。

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import 'animation/animated_svg_widget.dart';
import 'animation/animation_detector.dart';
import 'animation/svg_theme.dart';
import 'animation/xvg_animation_controller.dart';
import 'animation/xvg_animation_info.dart';
import 'animation/xvg_animation_quality.dart';
import 'pixel_snap_layer.dart';
import 'rust/frb_generated.dart';
import 'rust_static_svg.dart';
import 'platform_file.dart'
    if (dart.library.js_interop) 'platform_file_web.dart';
import 'svg_source_loader.dart';

/// Default implicit playback speed. / 默认隐式播放速率。
const _normalPlaybackRate = 1.0;

/// Constructor validation messages. / 构造参数校验消息。
const _positiveMaxFps = 'maxFps must be positive';

/// Invalid implicit rate message. / 非法隐式速率消息。
const _finitePlaybackRate = 'playbackRate must be finite';

/// External-controller rate message. / 外部控制器速率消息。
const _controllerRate =
    'Use the controller playbackRate when providing a controller';

/// Mutually exclusive drivers message. / 驱动互斥消息。
const _exclusiveDrivers = 'controller and animation are mutually exclusive';

/// External-animation defaults message. / 外部动画默认参数消息。
const _animationDefaults =
    'Leave autoplay and playbackRate at defaults when providing animation';

/// Renders static SVGs or supported SMIL `<animate>`, `<animateTransform>`,
/// `<animateMotion>`, `<set>` and CSS `@keyframes` animations.
/// Use implicit [autoplay]/[playbackRate], a shared [controller], or a Flutter
/// [animation] (mutually exclusive with [controller]). Animation-only options
/// and callbacks are ignored for static sources; [theme], [colorFilter],
/// [onError] and [errorBuilder] apply to both rendering paths.
///
/// 渲染静态 SVG 或支持的 SMIL 四类动画元素与 CSS `@keyframes`。
/// 三种播放模式为隐式自动播放、共享控制器、Flutter Animation 驱动；后两者互斥。
/// 静态源忽略动画专属参数及回调；主题、滤镜和错误处理在两条路径均生效。
///
/// ```dart
/// Xvg.string(svgSource, controller: controller, width: 48, height: 48)
/// ```
class Xvg extends StatefulWidget {
  /// Initializes the native (Rust) rendering backend. Call once, before
  /// rendering any Xvg widget — typically in `main()` before `runApp`.
  /// Calling it again after the first successful call is a no-op.
  ///
  /// 初始化原生（Rust）渲染后端，在渲染任何 Xvg 组件前调用一次——通常放在
  /// `main()` 里 `runApp` 之前。首次成功调用后再次调用是空操作。
  ///
  /// Example:
  /// ```dart
  /// void main() async {
  ///   WidgetsFlutterBinding.ensureInitialized();
  ///   await Xvg.ensureInitialized();
  ///   runApp(const MyApp());
  /// }
  /// ```
  static Future<void> ensureInitialized() {
    if (RustLib.instance.initialized) return Future<void>.value();
    return RustLib.init();
  }

  /// Creates the dispatch widget from a raw SVG string.
  ///
  /// 用原始 SVG 字符串创建分发组件。
  const Xvg.string(
    this.source, {
    super.key,
    this.width,
    this.height,
    this.fit = BoxFit.contain,
    this.pixelSnap = XvgPixelSnap.auto,
    this.alignment = Alignment.center,
    this.colorFilter,
    this.theme,
    this.quality,
    this.controller,
    this.animation,
    this.animationSpan,
    this.autoplay = true,
    this.playbackRate = _normalPlaybackRate,
    this.maxFps,
    this.onLoaded,
    this.onError,
    this.errorBuilder,
    this.onEvent,
    this.onAnimationStart,
    this.onAnimationComplete,
    this.onAnimationLoop,
  }) : assert(maxFps == null || maxFps > 0, _positiveMaxFps),
       assert(
         playbackRate > double.negativeInfinity &&
             playbackRate < double.infinity,
         _finitePlaybackRate,
       ),
       assert(
         controller == null || playbackRate == _normalPlaybackRate,
         _controllerRate,
       ),
       assert(controller == null || animation == null, _exclusiveDrivers),
       assert(
         animation == null || (autoplay && playbackRate == _normalPlaybackRate),
         _animationDefaults,
       );

  /// Creates the dispatch widget from an SVG asset, resolved the same way
  /// [AssetImage] resolves [name]/[bundle]/[package].
  ///
  /// Keeps the previous SVG while loading, or initially an empty sized box.
  /// Load failures use [onError]/[errorBuilder] when supplied; otherwise they
  /// propagate to the ambient [ErrorWidget.builder].
  ///
  /// 用 SVG asset 创建组件，名称、bundle 和 package 按 AssetImage 规则解析。
  /// 加载期间保留旧图，首次为空盒子；错误交给已配置的处理器，否则传播至 ErrorWidget。
  static Widget asset(
    String name, {
    Key? key,
    AssetBundle? bundle,
    String? package,
    double? width,
    double? height,
    BoxFit fit = BoxFit.contain,
    XvgPixelSnap pixelSnap = XvgPixelSnap.auto,
    Alignment alignment = Alignment.center,
    ColorFilter? colorFilter,
    XvgTheme? theme,
    XvgAnimationQuality? quality,
    XvgAnimationController? controller,
    Animation<double>? animation,
    Duration? animationSpan,
    bool autoplay = true,
    double playbackRate = _normalPlaybackRate,
    double? maxFps,
    ValueChanged<XvgAnimationInfo>? onLoaded,
    void Function(Object error, StackTrace stackTrace)? onError,
    ImageErrorWidgetBuilder? errorBuilder,
    ValueChanged<XvgAnimationEvent>? onEvent,
    VoidCallback? onAnimationStart,
    VoidCallback? onAnimationComplete,
    ValueChanged<int>? onAnimationLoop,
  }) => _AsyncXvg(
    key: key,
    loadKey: (name, bundle, package),
    load: () =>
        SvgSourceLoader.instance.asset(name, bundle: bundle, package: package),
    width: width,
    height: height,
    fit: fit,
    pixelSnap: pixelSnap,
    alignment: alignment,
    colorFilter: colorFilter,
    theme: theme,
    quality: quality,
    controller: controller,
    animation: animation,
    animationSpan: animationSpan,
    autoplay: autoplay,
    playbackRate: playbackRate,
    maxFps: maxFps,
    onLoaded: onLoaded,
    onError: onError,
    errorBuilder: errorBuilder,
    onEvent: onEvent,
    onAnimationStart: onAnimationStart,
    onAnimationComplete: onAnimationComplete,
    onAnimationLoop: onAnimationLoop,
  );

  /// Creates the dispatch widget from an SVG fetched over HTTP(S). No
  /// response-level caching beyond [SvgSourceLoader]'s in-memory LRU — this is
  /// a plain one-shot fetch, not a full `NetworkImage`-style HTTP cache.
  ///
  /// 用通过 HTTP(S) 拉取的 SVG 创建分发组件。除 [SvgSourceLoader] 的内存 LRU
  /// 外没有额外的响应级缓存——这是一次性拉取，不是完整的 `NetworkImage` 式
  /// HTTP 缓存。
  static Widget network(
    String url, {
    Key? key,
    Map<String, String>? headers,
    double? width,
    double? height,
    BoxFit fit = BoxFit.contain,
    XvgPixelSnap pixelSnap = XvgPixelSnap.auto,
    Alignment alignment = Alignment.center,
    ColorFilter? colorFilter,
    XvgTheme? theme,
    XvgAnimationQuality? quality,
    XvgAnimationController? controller,
    Animation<double>? animation,
    Duration? animationSpan,
    bool autoplay = true,
    double playbackRate = _normalPlaybackRate,
    double? maxFps,
    ValueChanged<XvgAnimationInfo>? onLoaded,
    void Function(Object error, StackTrace stackTrace)? onError,
    ImageErrorWidgetBuilder? errorBuilder,
    ValueChanged<XvgAnimationEvent>? onEvent,
    VoidCallback? onAnimationStart,
    VoidCallback? onAnimationComplete,
    ValueChanged<int>? onAnimationLoop,
  }) => _AsyncXvg(
    key: key,
    loadKey: (url, SvgSourceLoader.headersKey(headers)),
    load: () => SvgSourceLoader.instance.network(url, headers: headers),
    width: width,
    height: height,
    fit: fit,
    pixelSnap: pixelSnap,
    alignment: alignment,
    colorFilter: colorFilter,
    theme: theme,
    quality: quality,
    controller: controller,
    animation: animation,
    animationSpan: animationSpan,
    autoplay: autoplay,
    playbackRate: playbackRate,
    maxFps: maxFps,
    onLoaded: onLoaded,
    onError: onError,
    errorBuilder: errorBuilder,
    onEvent: onEvent,
    onAnimationStart: onAnimationStart,
    onAnimationComplete: onAnimationComplete,
    onAnimationLoop: onAnimationLoop,
  );

  /// Creates the dispatch widget from an SVG file on disk.
  ///
  /// 用磁盘上的 SVG 文件创建分发组件。
  static Widget file(
    File file, {
    Key? key,
    double? width,
    double? height,
    BoxFit fit = BoxFit.contain,
    XvgPixelSnap pixelSnap = XvgPixelSnap.auto,
    Alignment alignment = Alignment.center,
    ColorFilter? colorFilter,
    XvgTheme? theme,
    XvgAnimationQuality? quality,
    XvgAnimationController? controller,
    Animation<double>? animation,
    Duration? animationSpan,
    bool autoplay = true,
    double playbackRate = _normalPlaybackRate,
    double? maxFps,
    ValueChanged<XvgAnimationInfo>? onLoaded,
    void Function(Object error, StackTrace stackTrace)? onError,
    ImageErrorWidgetBuilder? errorBuilder,
    ValueChanged<XvgAnimationEvent>? onEvent,
    VoidCallback? onAnimationStart,
    VoidCallback? onAnimationComplete,
    ValueChanged<int>? onAnimationLoop,
  }) => _AsyncXvg(
    key: key,
    loadKey: file.path,
    load: () => SvgSourceLoader.instance.file(file),
    width: width,
    height: height,
    fit: fit,
    pixelSnap: pixelSnap,
    alignment: alignment,
    colorFilter: colorFilter,
    theme: theme,
    quality: quality,
    controller: controller,
    animation: animation,
    animationSpan: animationSpan,
    autoplay: autoplay,
    playbackRate: playbackRate,
    maxFps: maxFps,
    onLoaded: onLoaded,
    onError: onError,
    errorBuilder: errorBuilder,
    onEvent: onEvent,
    onAnimationStart: onAnimationStart,
    onAnimationComplete: onAnimationComplete,
    onAnimationLoop: onAnimationLoop,
  );

  /// Creates the dispatch widget from raw SVG bytes already in memory,
  /// decoded as UTF-8 — unlike [asset]/[network]/[file], this is
  /// synchronous (no [_AsyncXvg] loading state), the same way
  /// [MemoryImage] never shows a loading frame.
  ///
  /// 用内存中已有的原始 SVG 字节创建分发组件，按 UTF-8 解码——跟
  /// [asset]/[network]/[file] 不同，这是同步的（没有 [_AsyncXvg] 的加载态），
  /// 与 [MemoryImage] 从不展示加载帧同理。
  static Widget memory(
    Uint8List bytes, {
    Key? key,
    double? width,
    double? height,
    BoxFit fit = BoxFit.contain,
    XvgPixelSnap pixelSnap = XvgPixelSnap.auto,
    Alignment alignment = Alignment.center,
    ColorFilter? colorFilter,
    XvgTheme? theme,
    XvgAnimationQuality? quality,
    XvgAnimationController? controller,
    Animation<double>? animation,
    Duration? animationSpan,
    bool autoplay = true,
    double playbackRate = _normalPlaybackRate,
    double? maxFps,
    ValueChanged<XvgAnimationInfo>? onLoaded,
    void Function(Object error, StackTrace stackTrace)? onError,
    ImageErrorWidgetBuilder? errorBuilder,
    ValueChanged<XvgAnimationEvent>? onEvent,
    VoidCallback? onAnimationStart,
    VoidCallback? onAnimationComplete,
    ValueChanged<int>? onAnimationLoop,
  }) => Xvg.string(
    utf8.decode(bytes),
    key: key,
    width: width,
    height: height,
    fit: fit,
    pixelSnap: pixelSnap,
    alignment: alignment,
    colorFilter: colorFilter,
    theme: theme,
    quality: quality,
    controller: controller,
    animation: animation,
    animationSpan: animationSpan,
    autoplay: autoplay,
    playbackRate: playbackRate,
    maxFps: maxFps,
    onLoaded: onLoaded,
    onError: onError,
    errorBuilder: errorBuilder,
    onEvent: onEvent,
    onAnimationStart: onAnimationStart,
    onAnimationComplete: onAnimationComplete,
    onAnimationLoop: onAnimationLoop,
  );

  /// Raw SVG markup, animated or static. / 原始 SVG 源，动画或静态均可。
  final String source;

  /// Target width; null uses the SVG's intrinsic width. / 目标宽度，null 用固有宽。
  final double? width;

  /// Target height; null uses the SVG's intrinsic height. / 目标高度，null 用固有高。
  final double? height;

  /// How the picture is inscribed into the box. / picture 如何适配到盒子。
  final BoxFit fit;

  /// Composition alignment; defaults to auto for mask/clip risk. Only positive
  /// axis-aligned scaling and translation apply; visual edges move <1 physical
  /// pixel. Layout, hit tests and semantics retain their original positions.
  /// See [XvgPixelSnap] for an example.
  /// 合成对齐默认 auto，仅遮罩/裁剪风险启用；仅平移及轴对齐正缩放生效，边缘
  /// 视觉修正 <1 物理像素；布局、点击及语义保留原位置，示例见 [XvgPixelSnap]。
  final XvgPixelSnap pixelSnap;

  /// Alignment within the box. / 在盒子内的对齐方式。
  final Alignment alignment;

  /// Optional recolor filter; the animated path uses [ColorFiltered], with
  /// no extra layer when unset.
  ///
  /// 可选重着色滤镜；动画路径通过 ColorFiltered 应用，未设置时无额外层。
  final ColorFilter? colorFilter;

  /// Theme controlling `currentColor`, honored by both the animated and
  /// static rendering paths.
  ///
  /// 控制 `currentColor` 的主题，动画与静态两条渲染路径均生效。
  final XvgTheme? theme;

  /// Animation quality/performance trade-off, forwarded to
  /// [XvgAnimated.string]; ignored for a static source (the static path
  /// renders a cached `ui.Picture` and has no per-frame sampling to degrade).
  ///
  /// 动画的画质/性能取舍，转发给 [XvgAnimated.string]；静态源忽略此参数
  /// （静态路径渲染的是缓存好的 `ui.Picture`，没有逐帧采样可降级）。
  final XvgAnimationQuality? quality;

  /// Shared playback control; mutually exclusive with [animation].
  /// 共享播放控制，与 [animation] 互斥。
  final XvgAnimationController? controller;

  /// Document time = value × span; driver owns vsync and start/completion.
  /// 文档时间为值乘映射时长；驱动方负责 vsync 和开始/完成状态。
  final Animation<double>? animation;

  /// External time span; null uses natural duration, unknown duration errors.
  /// 外部映射时长；null 使用自然时长，无法确定时报告错误。
  final Duration? animationSpan;

  /// Starts implicit playback; must remain true with [animation].
  /// 是否启动隐式播放；传入 [animation] 时须保留 true。
  final bool autoplay;

  /// Finite signed implicit speed; leave default with either explicit driver.
  /// 有限有符号隐式速率；显式驱动时保留默认值。
  final double playbackRate;

  /// Positive sampling cap; ignored with [animation]. Shared controllers use
  /// the most permissive attached cap, as in [XvgAnimated.maxFps].
  /// 正采样帧率上限；[animation] 模式忽略；共享控制器取挂载控件中最宽松的上限。
  final double? maxFps;

  /// Called when an animated source and its embedded images are ready.
  /// 动画源及内嵌图片就绪时调用；静态源不调用。
  final ValueChanged<XvgAnimationInfo>? onLoaded;

  /// Receives load/parse/span failures; static failures notify after the frame.
  /// 接收加载、解析、时长映射错误；静态失败在帧结束后通知。
  final void Function(Object error, StackTrace stackTrace)? onError;

  /// Replacement on load/parse/span failure. Without either error handler,
  /// load errors propagate to ErrorWidget; parse errors retain renderer defaults.
  /// 加载、解析、时长映射失败时的替代内容。未设错误处理时加载错误传播至
  /// ErrorWidget，解析错误沿用渲染器默认行为；仅设 onError 时显示空盒子。
  final ImageErrorWidgetBuilder? errorBuilder;

  /// Playback and element events in all animation drive modes.
  /// 所有动画驱动模式的播放与元素事件。
  final ValueChanged<XvgAnimationEvent>? onEvent;

  /// First playback tick; not called with [animation].
  /// 首次播放 tick；[animation] 模式不调用。
  final VoidCallback? onAnimationStart;

  /// Natural finite completion, excluding manual ranges and [animation].
  /// 有限文档自然完成；手动片段及 [animation] 模式不调用。
  final VoidCallback? onAnimationComplete;

  /// Known document loop crossings; iteration starts at one.
  /// 已知文档周期的穿越回调；轮次从一开始。
  final ValueChanged<int>? onAnimationLoop;

  /// Creates source dispatch state. / 创建源分发状态。
  @override
  State<Xvg> createState() => _XvgState();
}

/// Selects the static or animated renderer when the SVG source changes.
/// 在 SVG 源变化时选择静态或动画渲染器。
class _XvgState extends State<Xvg> {
  late bool _animated;

  /// Invalidates deferred static error notifications. / 使延后的静态错误通知失效。
  int _staticErrorGeneration = 0;

  /// Suppresses duplicate notifications on rebuild. / 避免重建重复通知。
  bool _staticErrorReported = false;
  @override
  void initState() {
    super.initState();
    _animated = AnimationDetector.hasAnimations(widget.source);
  }

  /// Refreshes source detection and error notification identity. / 刷新源检测与错误通知标识。
  @override
  void didUpdateWidget(Xvg oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source != widget.source || oldWidget.theme != widget.theme) {
      _staticErrorGeneration++;
      _staticErrorReported = false;
    }
    if (oldWidget.source != widget.source) {
      _animated = AnimationDetector.hasAnimations(widget.source);
    }
  }

  /// Builds fallback content and defers one notification per source/theme.
  /// 构建替代内容，并为每次源或主题变更延后通知一次。
  Widget _buildStaticError(
    BuildContext context,
    Object error,
    StackTrace stack,
  ) {
    if (!_staticErrorReported && widget.onError != null) {
      _staticErrorReported = true;
      final generation = _staticErrorGeneration;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && generation == _staticErrorGeneration) {
          widget.onError?.call(error, stack);
        }
      });
    }
    return widget.errorBuilder?.call(context, error, stack) ??
        SizedBox(width: widget.width, height: widget.height);
  }

  /// Dispatches the source and forwards renderer options. / 分发源并转发渲染参数。
  @override
  Widget build(BuildContext context) {
    if (_animated) {
      final child = XvgAnimated.string(
        widget.source,
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        pixelSnap: widget.pixelSnap,
        alignment: widget.alignment,
        theme: widget.theme,
        quality: widget.quality,
        controller: widget.controller,
        animation: widget.animation,
        animationSpan: widget.animationSpan,
        autoplay: widget.autoplay,
        playbackRate: widget.playbackRate,
        maxFps: widget.maxFps,
        onLoaded: widget.onLoaded,
        onError: widget.onError,
        errorBuilder: widget.errorBuilder,
        onEvent: widget.onEvent,
        onAnimationStart: widget.onAnimationStart,
        onAnimationComplete: widget.onAnimationComplete,
        onAnimationLoop: widget.onAnimationLoop,
      );
      return widget.colorFilter == null
          ? child
          : ColorFiltered(colorFilter: widget.colorFilter!, child: child);
    }
    return XvgStatic(
      widget.source,
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      pixelSnap: widget.pixelSnap,
      alignment: widget.alignment,
      colorFilter: widget.colorFilter,
      theme: widget.theme,
      errorBuilder: widget.onError != null || widget.errorBuilder != null
          ? _buildStaticError
          : null,
    );
  }
}

/// Loads a source string via [load] once, then hands it to [Xvg.string] —
/// backs [Xvg.asset]/[Xvg.network].
///
/// A [StatefulWidget] rather than a `FutureBuilder`, specifically to avoid
/// [FutureBuilder]'s flicker-on-rebuild: [FutureBuilder] treats every rebuild
/// as a brand new [Future] (even a cache hit resolves on a fresh microtask,
/// not synchronously within the same build), so a parent rebuilding this
/// widget every frame — anything above it doing so, not just this widget's
/// own lifecycle — would bounce the loaded content back to the blank
/// placeholder and immediately forward again, every time. [_AsyncXvgState]
/// instead keeps the loaded source across rebuilds and only kicks off a new
/// load in [didUpdateWidget] when [loadKey] actually changes — the same
/// reason [Image] doesn't reload an unchanged [AssetImage] on every rebuild.
///
/// 用 [load] 加载一次源字符串，再交给 [Xvg.string]——支撑
/// [Xvg.asset]/[Xvg.network]。
///
/// 用 [StatefulWidget] 而非 `FutureBuilder`，专为规避 [FutureBuilder] 的
/// "重建即闪烁"问题：[FutureBuilder] 把每次重建都当成一个全新的 [Future]
/// （即便是缓存命中，也要等到下一个 microtask 才 resolve，不会在同一次 build
/// 内同步完成），于是只要父级重建本控件——不只是本控件自身生命周期内，是
/// *任何*上层重建都会触发——已加载好的内容就会先弹回空白占位、再立刻弹回来，
/// 每次都这样。[_AsyncXvgState] 则跨重建保留已加载的源，只在 [loadKey] 真的
/// 变化时才在 [didUpdateWidget] 里重新加载——[Image] 不会为一个没变的
/// [AssetImage] 每次重建都重新加载，是同一个道理。
class _AsyncXvg extends StatefulWidget {
  /// Creates a source loader with renderer options. / 创建携带渲染参数的源加载器。
  const _AsyncXvg({
    super.key,
    required this.loadKey,
    required this.load,
    this.width,
    this.height,
    required this.fit,
    required this.pixelSnap,
    required this.alignment,
    this.colorFilter,
    this.theme,
    this.quality,
    this.controller,
    this.animation,
    this.animationSpan,
    this.autoplay = true,
    this.playbackRate = _normalPlaybackRate,
    this.maxFps,
    this.onLoaded,
    this.onError,
    this.errorBuilder,
    this.onEvent,
    this.onAnimationStart,
    this.onAnimationComplete,
    this.onAnimationLoop,
  }) : assert(maxFps == null || maxFps > 0, _positiveMaxFps),
       assert(
         playbackRate > double.negativeInfinity &&
             playbackRate < double.infinity,
         _finitePlaybackRate,
       ),
       assert(
         controller == null || playbackRate == _normalPlaybackRate,
         _controllerRate,
       ),
       assert(controller == null || animation == null, _exclusiveDrivers),
       assert(
         animation == null || (autoplay && playbackRate == _normalPlaybackRate),
         _animationDefaults,
       );

  /// Identity of what [load] fetches — compared by value in
  /// [_AsyncXvgState.didUpdateWidget] to decide whether to reload.
  ///
  /// [load] 拉取内容的身份——在 [_AsyncXvgState.didUpdateWidget] 里按值比较，
  /// 决定是否要重新加载。
  final Object loadKey;

  /// Fetches the SVG source text (already routed through
  /// [SvgSourceLoader]'s cache by the caller). / 拉取 SVG 源文本（调用方已经
  /// 路由过 [SvgSourceLoader] 的缓存）。
  final Future<String> Function() load;

  final double? width;
  final double? height;
  final BoxFit fit;

  /// Composition alignment; defaults to auto for mask/clip risk. Only positive
  /// axis-aligned scaling and translation apply; visual edges move <1 physical
  /// pixel. Layout, hit tests and semantics retain their original positions.
  /// See [XvgPixelSnap] for an example.
  /// 合成对齐默认 auto，仅遮罩/裁剪风险启用；仅平移及轴对齐正缩放生效，边缘
  /// 视觉修正 <1 物理像素；布局、点击及语义保留原位置，示例见 [XvgPixelSnap]。
  final XvgPixelSnap pixelSnap;

  final Alignment alignment;
  final ColorFilter? colorFilter;
  final XvgTheme? theme;
  final XvgAnimationQuality? quality;

  /// Shared playback control; mutually exclusive with [animation].
  /// 共享播放控制，与 [animation] 互斥。
  final XvgAnimationController? controller;

  /// Document time = value × span; driver owns vsync and start/completion.
  /// 文档时间为值乘映射时长；驱动方负责 vsync 和开始/完成状态。
  final Animation<double>? animation;

  /// External time span; null uses natural duration, unknown duration errors.
  /// 外部映射时长；null 使用自然时长，无法确定时报告错误。
  final Duration? animationSpan;

  /// Starts implicit playback; must remain true with [animation].
  /// 是否启动隐式播放；传入 [animation] 时须保留 true。
  final bool autoplay;

  /// Finite signed implicit speed; leave default with either explicit driver.
  /// 有限有符号隐式速率；显式驱动时保留默认值。
  final double playbackRate;

  /// Positive sampling cap; ignored with [animation]. Shared controllers use
  /// the most permissive attached cap, as in [XvgAnimated.maxFps].
  /// 正采样帧率上限；[animation] 模式忽略；共享控制器取挂载控件中最宽松的上限。
  final double? maxFps;

  /// Called when an animated source and its embedded images are ready.
  /// 动画源及内嵌图片就绪时调用；静态源不调用。
  final ValueChanged<XvgAnimationInfo>? onLoaded;

  /// Receives load/parse/span failures; static failures notify after the frame.
  /// 接收加载、解析、时长映射错误；静态失败在帧结束后通知。
  final void Function(Object error, StackTrace stackTrace)? onError;

  /// Replacement on load/parse/span failure. Without either error handler,
  /// load errors propagate to ErrorWidget; parse errors retain renderer defaults.
  /// 加载、解析、时长映射失败时的替代内容。未设错误处理时加载错误传播至
  /// ErrorWidget，解析错误沿用渲染器默认行为；仅设 onError 时显示空盒子。
  final ImageErrorWidgetBuilder? errorBuilder;

  /// Playback and element events in all animation drive modes.
  /// 所有动画驱动模式的播放与元素事件。
  final ValueChanged<XvgAnimationEvent>? onEvent;

  /// First playback tick; not called with [animation].
  /// 首次播放 tick；[animation] 模式不调用。
  final VoidCallback? onAnimationStart;

  /// Natural finite completion, excluding manual ranges and [animation].
  /// 有限文档自然完成；手动片段及 [animation] 模式不调用。
  final VoidCallback? onAnimationComplete;

  /// Known document loop crossings; iteration starts at one.
  /// 已知文档周期的穿越回调；轮次从一开始。
  final ValueChanged<int>? onAnimationLoop;

  @override
  State<_AsyncXvg> createState() => _AsyncXvgState();
}

/// Retains source text and rejects stale load results. / 保留源文本并丢弃过期加载结果。
class _AsyncXvgState extends State<_AsyncXvg> {
  String? _source;
  Object? _error;

  /// Original load failure stack. / 原始加载失败堆栈。
  StackTrace? _errorStack;

  // 每次加载使用独立代次，防止 A→B→A 时第一次 A 的结果抢先覆盖。
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Reloads only when source identity changes. / 仅源标识变化时重新加载。
  @override
  void didUpdateWidget(_AsyncXvg oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.loadKey != oldWidget.loadKey) _load();
  }

  /// Loads one generation and delivers handled failures once. / 加载一代源并交付一次失败通知。
  void _load() {
    final generation = ++_loadGeneration;
    // Clear a stale error from a previous [loadKey] immediately — otherwise
    // `build()` keeps throwing it for the new key while this fresh load is
    // still in flight.
    //
    // 立即清掉上一个 [loadKey] 留下的旧错误——否则新一次加载还在途时，
    // `build()` 会一直把旧错误当成新 key 的结果抛出来。
    if (_error != null) {
      _error = null;
      _errorStack = null;
    }
    Future<String>.sync(widget.load).then(
      (source) {
        if (!mounted || generation != _loadGeneration) return;
        setState(() {
          _source = source;
          _error = null;
        });
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!mounted || generation != _loadGeneration) return;
        setState(() {
          _error = error;
          _errorStack = stackTrace;
        });
        widget.onError?.call(error, stackTrace);
      },
    );
  }

  /// Builds loaded content or preserves the configured failure policy. / 构建内容并遵循失败处理策略。
  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      final builder = widget.errorBuilder;
      if (builder != null) {
        return builder(context, _error!, _errorStack);
      }
      if (widget.onError != null) {
        return SizedBox(width: widget.width, height: widget.height);
      }
      Error.throwWithStackTrace(_error!, _errorStack!);
    }
    if (_source == null) {
      return SizedBox(width: widget.width, height: widget.height);
    }
    return Xvg.string(
      _source!,
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      pixelSnap: widget.pixelSnap,
      alignment: widget.alignment,
      colorFilter: widget.colorFilter,
      theme: widget.theme,
      quality: widget.quality,
      controller: widget.controller,
      animation: widget.animation,
      animationSpan: widget.animationSpan,
      autoplay: widget.autoplay,
      playbackRate: widget.playbackRate,
      maxFps: widget.maxFps,
      onLoaded: widget.onLoaded,
      onError: widget.onError,
      errorBuilder: widget.errorBuilder,
      onEvent: widget.onEvent,
      onAnimationStart: widget.onAnimationStart,
      onAnimationComplete: widget.onAnimationComplete,
      onAnimationLoop: widget.onAnimationLoop,
    );
  }
}
