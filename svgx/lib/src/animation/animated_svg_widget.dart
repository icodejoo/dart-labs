import 'dart:math' show max;

import 'package:flutter/widgets.dart';

import '../pixel_snap_layer.dart';
import 'animated_svg_painter.dart';
import 'shared_animation_clock.dart';
import 'svg_document_cache.dart';
import 'svg_dom.dart';
import 'svg_document_parser.dart';
import 'svg_theme.dart';
import 'svgx_animation_controller.dart';
import 'svgx_animation_info.dart';
import 'svgx_animation_quality.dart';

/// Default automatic playback speed. / 默认自动播放速率。
const _normalPlaybackRate = 1.0;

/// Samples every display frame without throttling. / 无节流时每显示帧采样。
const _unthrottledDivisor = 1;

/// Renders supported SMIL `<animate>`, `<animateTransform>`, `<animateMotion>`,
/// `<set>` and CSS `@keyframes` animation subsets. Uses implicit playback,
/// a shared [controller], or a Flutter [animation].
///
/// Use [controller] for shared playback control, or [autoplay] and [playbackRate]
/// for automatic playback. TickerMode pauses playback when every widget using
/// the controller is disabled; Offstage alone does not pause it.
///
/// 渲染引擎支持的 SMIL `<animate>`、`<animateTransform>`、`<animateMotion>`、
/// `<set>` 与 CSS `@keyframes` 子集；提供隐式、共享控制器、Flutter Animation
/// 三种播放模式。用 [controller] 控制共享播放，或用
/// [autoplay]、[playbackRate] 自动播放。所有挂载控件的 TickerMode 都关闭时暂停；
/// 单独 Offstage 不暂停。
///
/// [animation] is mutually exclusive with [controller]; it supplies vsync and
/// TickerMode and bypasses shared-clock concurrency and frame skipping.
/// Prefer controller/implicit playback for many concurrent instances.
/// [animation] 与 [controller] 互斥，由驱动方提供 vsync 和 TickerMode，
/// 不计入共享时钟并发，也不参与跳帧降级；大量并发推荐用 controller/隐式模式。
///
/// ```dart
/// SvgxAnimated.string(svgSource, width: 48, height: 48)
/// ```
class SvgxAnimated extends StatefulWidget {
  /// Creates the animated renderer from a raw SVG string.
  ///
  /// 用原始 SVG 字符串创建动画渲染组件。
  const SvgxAnimated.string(
    this.source, {
    super.key,
    this.pixelSnap = SvgxPixelSnap.auto,
    this.width,
    this.height,
    this.fit = BoxFit.contain,
    this.alignment = Alignment.center,
    this.theme,
    this.quality,
    this.maxFps,
    this.playbackRate = _normalPlaybackRate,
    this.controller,
    this.animation,
    this.animationSpan,
    this.autoplay = true,
    this.onLoaded,
    this.onError,
    this.errorBuilder,
    this.onAnimationStart,
    this.onAnimationComplete,
    this.onAnimationLoop,
    this.onEvent,
  }) : assert(maxFps == null || maxFps > 0, 'maxFps must be positive'),
       assert(
         playbackRate > double.negativeInfinity &&
             playbackRate < double.infinity,
         'playbackRate must be finite',
       ),
       assert(
         controller == null || playbackRate == _normalPlaybackRate,
         'Use the controller playbackRate when providing a controller',
       ),
       assert(
         controller == null || animation == null,
         'controller and animation are mutually exclusive',
       ),
       assert(
         animation == null || (autoplay && playbackRate == _normalPlaybackRate),
         'Leave autoplay and playbackRate at defaults when providing animation',
       );

  /// Raw SVG markup containing supported SMIL or CSS animations.
  ///
  /// 含支持的 SMIL 或 CSS 动画的原始 SVG 源。
  final String source;

  /// Composition alignment; defaults to auto for mask/clip risk. Only positive
  /// axis-aligned scaling and translation apply; visual edges move <1 physical
  /// pixel. Layout, hit tests and semantics retain their original positions.
  /// See [SvgxPixelSnap] for an example.
  /// 合成对齐默认 auto，仅遮罩/裁剪风险启用；仅平移及轴对齐正缩放生效，边缘
  /// 视觉修正 <1 物理像素；布局、点击及语义保留原位置，示例见 [SvgxPixelSnap]。
  final SvgxPixelSnap pixelSnap;

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
  final SvgxTheme? theme;

  /// How much per-icon animation smoothness this instance may trade away for
  /// frame throughput under high concurrency; null uses
  /// [SvgxAnimationQuality.defaultQuality].
  ///
  /// Pass [SvgxAnimationQuality.exact] to opt this icon out of all
  /// degradation. See [SvgxAnimationQuality] for exactly what is given up.
  /// A shared [controller] uses the smallest divisor requested by its mounted
  /// widgets, considering offscreen layers if any mounted document needs them.
  ///
  /// 本实例在高并发下可以拿多少"单图标动画流畅度"去换帧吞吐；null 表示使用
  /// [SvgxAnimationQuality.defaultQuality]。
  ///
  /// 传 [SvgxAnimationQuality.exact] 可让本图标完全不参与降级。具体牺牲了什么
  /// 见 [SvgxAnimationQuality]。
  /// 共用 [controller] 时取各挂载控件要求的最小除数；任一挂载文档需要离屏图层时，
  /// 全部画质需求都按有离屏图层计算。
  final SvgxAnimationQuality? quality;

  /// Requested sampling and repaint cap; null imposes no additional cap.
  /// A shared [controller] uses the most permissive mounted widget cap, so a
  /// higher cap or null on another widget can override this request. The
  /// resulting cap and [quality] are combined using the larger frame divisor.
  ///
  /// 请求的时间线采样和重绘频率上限；null 表示不额外限制。共用 [controller] 时
  /// 采用挂载控件中最宽松的上限，因此其它控件的更高上限或 null 可覆盖本请求。
  /// 最终上限与 [quality] 取更大的跳帧除数。
  /// Ignored with [animation]; sampling follows its notifications.
  /// 传入 [animation] 时不生效，采样跟随其通知。
  final double? maxFps;

  /// Finite playback speed when [controller] is null: negative reverses and
  /// zero pauses. Rate changes preserve the current time. With [controller],
  /// leave this at its default and set the controller's rate instead.
  ///
  /// [controller] 为空时的有限播放速率：负值倒放，零暂停；改速率保持当前时间。
  /// 传入 [controller] 时保留默认值，改用控制器的速率。
  /// Ignored with [animation]; must remain at the default.
  /// 传入 [animation] 时不生效，必须保留默认值。
  final double playbackRate;

  /// Optional shared playback controller; its time is preserved on source swaps.
  ///
  /// 可选共享播放控制器；换源时保留其时间。
  final SvgxAnimationController? controller;

  /// External document time: value × [animationSpan] (or naturalDuration).
  /// Values usually lie in 0..1; negative times clamp to zero, positive
  /// overshoot is allowed beyond the span. Mutually exclusive with [controller].
  /// No started/completed events are emitted; observe the driver's status.
  /// Disposing a Flutter AnimationController stops updates, retaining the frame;
  /// this widget never disposes the supplied animation.
  /// 外部文档时间为 value × [animationSpan]（或自然时长）。值通常在 0..1；
  /// 负时间钳到零，正向超调允许超过 span。与 [controller] 互斥。
  /// 不发 started/completed，请观察驱动方状态；释放 Flutter AnimationController
  /// 后停止更新并保留画面，控件不会释放传入的动画。
  final Animation<double>? animation;

  /// Mapping span for [animation]; null uses the document's natural duration.
  /// If both are unknown, reports through [onError]/[errorBuilder]/FlutterError.
  /// [animation] 的映射时长；null 使用文档自然时长。
  /// 两者均未知时，经 [onError]/[errorBuilder]/FlutterError 报告错误。
  final Duration? animationSpan;

  /// Starts automatic playback when no [controller] is supplied.
  ///
  /// 未传 [controller] 时是否自动播放。
  /// Ignored with [animation]; must remain true. / 传入 [animation] 时不生效，须为 true。
  final bool autoplay;

  /// Called once after this source and its embedded images are ready.
  ///
  /// 当前源及其内嵌图片就绪后调用一次。
  final ValueChanged<SvgxAnimationInfo>? onLoaded;

  /// Receives parsing or animation-span failures with their stack traces.
  ///
  /// 接收解析或动画映射时长失败及其堆栈。
  final void Function(Object error, StackTrace stackTrace)? onError;

  /// Builds replacement content on failure; null uses an empty sized box.
  ///
  /// 失败时构建替代内容；null 使用指定尺寸的空盒子。
  final ImageErrorWidgetBuilder? errorBuilder;

  /// Called once, on the first tick after this instance starts ticking.
  ///
  /// 本实例开始 ticking 后的第一个 tick 上调用一次。
  /// Never called with [animation]. / 传入 [animation] 时不触发。
  final VoidCallback? onAnimationStart;

  /// Called once when a finite (non-looping) document naturally settles into
  /// its final frame — never called for a document with
  /// [SvgDocument.hasIndefiniteLoop], and never called when ticking stops for
  /// any other reason (source swap, unmount, or a manually configured range).
  ///
  /// 有限（非循环）文档自然播完定格时调用一次——[SvgDocument.hasIndefiniteLoop]
  /// 的文档永不触发，因其它原因（源切换、卸载或手动配置的片段）停止 ticking 时也不触发。
  /// Never called with [animation]. / 传入 [animation] 时不触发。
  final VoidCallback? onAnimationComplete;

  /// Called at each `settleTime + iteration * loopPeriod` crossing for a
  /// looping document with a known period; iteration starts at one.
  ///
  /// 循环文档有已知周期时，在每次穿越 `settleTime + iteration * loopPeriod`
  /// 时调用，iteration 从一开始。
  final ValueChanged<int>? onAnimationLoop;

  /// Receives playback and element begin/end/repeat events in all drive modes.
  /// 在所有驱动模式下接收播放事件及元素 begin/end/repeat 事件。
  final ValueChanged<SvgxAnimationEvent>? onEvent;

  /// Creates the renderer state. / 创建渲染状态。
  @override
  State<SvgxAnimated> createState() => _SvgxAnimatedState();
}

/// Overrides embedded-image decoding in lifecycle tests.
///
/// 在生命周期测试中替换内嵌图片解码。
@visibleForTesting
Future<void> Function(SvgDocument)? debugResolveAnimatedImages;

/// Owns source readiness and binds the painter to controller time.
///
/// 管理源就绪状态，并把绘制器绑定到控制器时间。
class _SvgxAnimatedState extends State<SvgxAnimated> {
  /// Current parsed source, absent after a parsing failure. / 当前解析结果，解析失败时为空。
  SvgDocument? _document;

  /// Controller shared with the painter. / 与绘制器共享的控制器。
  late SvgxAnimationController _controller;

  /// Whether this state owns the controller. / 本状态是否拥有控制器。
  bool _ownsController = false;

  /// Whether widget callbacks currently need an event subscription.
  ///
  /// 控件回调当前是否需要事件订阅。
  bool _bridgingEvents = false;

  /// Animation currently carrying our value listener. / 当前挂载值监听的动画。
  Animation<double>? _listenedAnimation;

  /// Resolved external mapping span after document readiness.
  /// 文档就绪后解析出的外部映射时长。
  Duration? _animationSpan;

  /// Whether decoded images belong exclusively to this state.
  ///
  /// 已解码图片是否由本状态独占。
  bool _ownsImages = false;

  /// Current inherited visibility. / 当前继承的可见状态。
  bool _tickerModeEnabled = false;

  /// Whether parsing and embedded image decoding have finished.
  /// 解析和内嵌图片解码是否完成。
  bool _imagesReady = true;

  /// Rejects stale parse/image continuations and deferred callbacks.
  ///
  /// 用于拒绝过期的解析、图片续体和延迟回调。
  int _parseGeneration = 0;

  /// Last source generation whose loaded callback was delivered.
  /// 最近已交付加载回调的源代数。
  int _loadedGeneration = -1;

  /// Current parsing error. / 当前解析错误。
  Object? _error;

  /// Stack associated with the current error. / 当前错误的堆栈。
  StackTrace? _errorStack;

  /// Creates the playback binding before parsing. / 解析前创建播放绑定。
  @override
  void initState() {
    super.initState();
    _bindController();
    _parseAndStart();
  }

  /// Chooses the external controller or creates an owned drive binding.
  ///
  /// 选择外部控制器或创建自有驱动绑定。
  void _bindController() {
    _ownsController = widget.controller == null;
    _controller =
        widget.controller ??
        (widget.animation != null
            ? SvgxAnimationController.externallyDriven()
            : SvgxAnimationController(
                autoplay: widget.autoplay,
                playbackRate: widget.playbackRate,
              ));
    _updateEventBridge();
    _listenedAnimation = widget.animation;
    _listenedAnimation?.addListener(_onAnimationValue);
  }

  /// Maps each driver value change through the ready document span.
  /// 将驱动方的每次取值变化映射到就绪文档时长。
  void _onAnimationValue() => _syncAnimationValue();

  /// Pushes the driver's current value; [emitCrossings] false makes the
  /// initial sync after (re)attaching behave like a seek, so mounting midway
  /// does not replay every event since zero.
  /// 推送驱动方当前值；[emitCrossings] 为 false 时，（重新）挂载后的首次同步
  /// 等同 seek，中途挂载不会补发从零开始的全部事件。
  void _syncAnimationValue({bool emitCrossings = true}) {
    final span = _animationSpan;
    final animation = _listenedAnimation;
    if (animation == null || span == null || !_imagesReady || _error != null) {
      return;
    }
    _controller.driveTo(
      Duration(microseconds: (animation.value * span.inMicroseconds).round()),
      emitCrossings: emitCrossings,
    );
  }

  /// Subscribes only when a widget callback needs events.
  ///
  /// 仅在控件回调需要事件时订阅。
  void _updateEventBridge() {
    final needed =
        widget.onEvent != null ||
        widget.onAnimationStart != null ||
        widget.onAnimationComplete != null ||
        widget.onAnimationLoop != null;
    if (needed == _bridgingEvents) return;
    _bridgingEvents = needed;
    if (needed) {
      _controller.addEventListener(_onControllerEvent);
    } else {
      _controller.removeEventListener(_onControllerEvent);
    }
  }

  /// Releases this state's binding, disposing only an owned controller.
  ///
  /// 释放本状态的绑定，仅销毁自有控制器。
  void _unbindController() {
    // Flutter AnimationController permits removal after dispose and clears its
    // listeners on dispose; no ownership or status listener is needed here.
    // Flutter AnimationController 允许释放后移除监听，释放时也会清空监听者。
    _listenedAnimation?.removeListener(_onAnimationValue);
    _listenedAnimation = null;
    _animationSpan = null;
    if (_bridgingEvents) {
      _controller.removeEventListener(_onControllerEvent);
      _bridgingEvents = false;
    }
    _controller.detach(this);
    if (_ownsController) _controller.dispose();
  }

  /// Forwards events to widget callbacks, rejecting reentrant binding changes.
  ///
  /// 将事件转发给控件回调，拒绝重入后的绑定变更。
  void _onControllerEvent(SvgxAnimationEvent event) {
    final controller = _controller;
    final generation = _parseGeneration;
    widget.onEvent?.call(event);
    if (!mounted ||
        controller != _controller ||
        generation != _parseGeneration) {
      return;
    }
    if (!_imagesReady || _error != null) return;
    if (event is SvgxAnimationStarted) {
      widget.onAnimationStart?.call();
    } else if (event is SvgxAnimationCompleted &&
        event.natural &&
        _document?.info.loops == false) {
      widget.onAnimationComplete?.call();
    } else if (event is SvgxAnimationLooped) {
      widget.onAnimationLoop?.call(event.iteration);
    }
  }

  /// Reports inherited TickerMode to the controller. / 将继承的 TickerMode 告知控制器。
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // ignore: deprecated_member_use
    final enabled = TickerMode.of(context);
    if (enabled == _tickerModeEnabled) return;
    _tickerModeEnabled = enabled;
    _controller.setVisible(this, enabled);
  }

  /// Applies source/driver/span swaps and implicit playback settings.
  ///
  /// 应用源、驱动方或映射时长切换，以及隐式播放设置。
  @override
  void didUpdateWidget(SvgxAnimated oldWidget) {
    super.didUpdateWidget(oldWidget);
    final sourceChanged = oldWidget.source != widget.source;
    final controllerChanged =
        oldWidget.controller != widget.controller ||
        oldWidget.animation != widget.animation;
    final spanChanged =
        widget.animation != null &&
        oldWidget.animationSpan != widget.animationSpan;
    final resetImplicit = sourceChanged && widget.controller == null;
    if (controllerChanged || resetImplicit) {
      _unbindController();
      _bindController();
    } else {
      _updateEventBridge();
      if (_ownsController && widget.animation == null) {
        if (oldWidget.playbackRate != widget.playbackRate) {
          _controller.playbackRate = widget.playbackRate;
        }
        if (oldWidget.autoplay != widget.autoplay) {
          if (widget.autoplay) {
            _controller.play();
          } else {
            _controller.pause();
          }
        }
      }
    }
    if (sourceChanged) {
      final previous = _document;
      if (_ownsImages && previous != null) _disposeImages(previous);
      _parseAndStart();
    } else if (controllerChanged || spanChanged) {
      final document = _document;
      if (document != null && _imagesReady) {
        _error = null;
        _errorStack = null;
        _attach(document);
      } else if (_error != null) {
        _controller.documentError(this, _error!, _errorStack!);
      } else {
        _controller.documentLoading(this);
      }
    }
  }

  /// Parses through the async cache, preserving synchronous small-source frames.
  ///
  /// 通过异步缓存入口解析，保持小源同步首帧，并等待图片就绪。
  void _parseAndStart() {
    final generation = ++_parseGeneration;
    _controller.documentLoading(this);
    _document = null;
    _ownsImages = false;
    _error = null;
    _errorStack = null;
    _imagesReady = false;
    _animationSpan = null;
    var synchronous = true;
    try {
      SvgxDocumentCache.instance
          .getOrParseAsync(widget.source)
          .then(
            (parsed) {
              if (!mounted || generation != _parseGeneration) return;
              try {
                _acceptParsed(parsed, generation);
              } catch (error, stack) {
                _reportError(error, stack);
              }
              if (!synchronous && mounted && generation == _parseGeneration) {
                setState(() {});
              }
            },
            onError: (Object error, StackTrace stack) {
              if (!mounted || generation != _parseGeneration) return;
              _reportError(error, stack);
              if (!synchronous) setState(() {});
            },
          );
    } catch (error, stack) {
      _reportError(error, stack);
    } finally {
      synchronous = false;
    }
  }

  /// Continues a current parse through root-isolate image decoding and attach.
  /// 将当前解析结果继续交给主 isolate 图片解码及挂载流程。
  void _acceptParsed(
    ({SvgDocument document, bool hasImages}) parsed,
    int generation,
  ) {
    final document = parsed.document;
    _document = document;
    _ownsImages = parsed.hasImages;
    _imagesReady = !parsed.hasImages;
    if (parsed.hasImages) {
      /// Finishes only the current generation's decode. / 仅结束当前代的解码。
      void ready() {
        if (!mounted || generation != _parseGeneration) {
          _disposeImages(document);
          return;
        }
        setState(() => _imagesReady = true);
        _attach(document);
      }

      Future<void>.sync(
        () => (debugResolveAnimatedImages ?? resolveImageNodes)(document),
      ).then((_) => ready(), onError: (Object _, StackTrace _) => ready());
    } else {
      _attach(document);
    }
  }

  /// Routes parse and external-mapping failures through the same handlers.
  /// 将解析与外部映射失败交给同一组处理器。
  void _reportError(Object error, StackTrace stack) {
    final generation = _parseGeneration;
    _animationSpan = null;
    _error = error;
    _errorStack = stack;
    _controller.documentError(this, error, stack);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          generation != _parseGeneration ||
          !identical(error, _error)) {
        return;
      }
      final onError = widget.onError;
      if (onError != null) {
        onError(error, stack);
      } else if (widget.errorBuilder == null) {
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stack,
            library: 'svgx',
            context: ErrorDescription('while loading an animated SVG'),
          ),
        );
      }
    });
  }

  /// Validates external mapping and attaches a ready document.
  ///
  /// 验证外部映射并挂载就绪文档。
  void _attach(SvgDocument document) {
    if (widget.animation != null) {
      final span = widget.animationSpan ?? document.info.naturalDuration;
      if (span == null) {
        _reportError(
          StateError(
            'animationSpan is required when naturalDuration is unknown',
          ),
          StackTrace.current,
        );
        return;
      }
      _animationSpan = span;
    }
    _controller.attach(
      this,
      document: document,
      visible: _tickerModeEnabled,
      quality: _quality,
      fpsDivisor: _fpsDivisor,
    );
    _syncAnimationValue(emitCrossings: false);
    _notifyLoaded(document.info, _parseGeneration);
  }

  /// Defers load callbacks until parent builds are safe to update.
  ///
  /// 将加载回调延后到父级可安全更新的时机。
  void _notifyLoaded(SvgxAnimationInfo info, int generation) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          generation == _parseGeneration &&
          generation != _loadedGeneration &&
          _error == null) {
        _loadedGeneration = generation;
        widget.onLoaded?.call(info);
      }
    });
  }

  /// Resolves the widget's current quality. / 解析控件当前的画质。
  SvgxAnimationQuality _quality() =>
      widget.quality ?? SvgxAnimationQuality.defaultQuality;

  /// Converts the live display refresh rate and cap to a divisor.
  ///
  /// 把实时显示刷新率和帧率上限转换为除数。
  int _fpsDivisor() {
    final maxFps = widget.maxFps;
    if (maxFps == null) return _unthrottledDivisor;
    final refreshRate = View.of(context).display.refreshRate;
    if (refreshRate <= 0) return _unthrottledDivisor;
    return max(_unthrottledDivisor, (refreshRate / maxFps).round());
  }

  /// Resolves paint-time mask approximation using subscriber concurrency.
  ///
  /// 根据订阅者并发数决定绘制时的遮罩近似。
  bool _approximateMasks() => _quality().approximatesMasksAt(
    SharedAnimationClock.instance.subscriberCount,
  );

  /// Releases images owned by this uncached document. / 释放未缓存文档独占的图片。
  void _disposeImages(SvgDocument document) {
    /// Releases one subtree. / 释放一棵子树。
    void visit(SvgNode node) {
      node.resolvedImage?.dispose();
      node.resolvedImage = null;
      for (final child in node.children) {
        visit(child);
      }
    }

    visit(document.root);
  }

  /// Releases playback and owned images. / 释放播放绑定及自有图片。
  @override
  void dispose() {
    _parseGeneration++;
    _unbindController();
    final document = _document;
    if (_ownsImages && document != null) _disposeImages(document);
    super.dispose();
  }

  /// Builds a placeholder, error content, or a paint-only animated surface.
  ///
  /// 构建占位、错误内容或仅重绘的动画画面。
  @override
  Widget build(BuildContext context) {
    final document = _document;
    final w = widget.width ?? document?.width;
    final h = widget.height ?? document?.height;
    final error = _error;
    if (error != null) {
      return widget.errorBuilder?.call(context, error, _errorStack) ??
          SizedBox(width: w, height: h);
    }
    if (!_imagesReady || document == null) return SizedBox(width: w, height: h);
    // CustomPaint supplies its own preferred size; no redundant SizedBox.
    // CustomPaint 已提供首选尺寸，不额外包装 SizedBox。
    final child = CustomPaint(
      size: Size(w!, h!),
      painter: AnimatedSvgPainter(
        root: document.root,
        intrinsicSize: Size(document.width, document.height),
        clock: _controller.time,
        theme: widget.theme ?? const SvgxTheme(),
        fit: widget.fit,
        alignment: widget.alignment,
        gradients: document.gradients,
        clipPaths: document.clipPaths,
        masks: document.masks,
        backgroundColor: document.backgroundColor,
        approximateMasks: _approximateMasks,
        quality: _quality(),
      ),
    );
    // Isolate timeline repainting from otherwise static ancestors.
    // 将时间线重绘与其余静态祖先隔离。
    return pixelSnapBoundary(
      child: child,
      mode: widget.pixelSnap,
      hasRisk: document.hasPixelSnapRisk,
      intrinsicSize: Size(document.width, document.height),
      fit: widget.fit,
      alignment: widget.alignment,
    );
  }
}
