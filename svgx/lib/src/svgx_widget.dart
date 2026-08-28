// Top-level dispatch widget: routes an SVG source string to the animated
// (original Dart-side SMIL engine) or static (Rust usvg → ui.Picture)
// renderer, per the "split by asset" architecture decision in CLAUDE.md.
//
// 顶层分发组件：按 CLAUDE.md 的"按资产切分"架构决定，把 SVG 源串路由到动画
// 路径（原创 Dart 侧 SMIL 引擎）或静态路径（Rust usvg → ui.Picture）。

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import 'animation/animated_svg_widget.dart';
import 'animation/animation_detector.dart';
import 'animation/svg_theme.dart';
import 'animation/svgx_animation_quality.dart';
import 'rust_static_svg.dart';
import 'svg_source_loader.dart';

/// Renders an SVG string, automatically picking the animated or static
/// rendering path.
///
/// Detection is done via [AnimationDetector.hasAnimations]: if the source
/// contains SMIL (`<animate>`, `<set>`) animation markers, it renders through
/// [SvgXAnimated.string] (this project's original SMIL engine); otherwise it
/// renders through [SvgXStatic] (Rust `usvg` parser → cached [ui.Picture]).
/// CSS `@keyframes`/`animation-*` animation is not yet detected/supported —
/// see `lib/src/animation/animation_detector.dart`.
///
/// 渲染 SVG 字符串，自动选择动画或静态渲染路径。
///
/// 通过 [AnimationDetector.hasAnimations] 判定：若源串含 SMIL（`<animate>`、
/// `<set>`）动画标记，走 [SvgXAnimated.string]（本项目原创 SMIL 引擎）；否则走
/// [SvgXStatic]（Rust `usvg` 解析器 → 缓存的 [ui.Picture]）。CSS
/// `@keyframes`/`animation-*` 动画暂不检测/支持——见
/// `lib/src/animation/animation_detector.dart`。
///
/// Example:
/// ```dart
/// SvgX.string(svgSource, width: 48, height: 48)
/// ```
class SvgX extends StatelessWidget {
  /// Creates the dispatch widget from a raw SVG string.
  ///
  /// 用原始 SVG 字符串创建分发组件。
  const SvgX.string(
    this.source, {
    super.key,
    this.width,
    this.height,
    this.fit = BoxFit.contain,
    this.alignment = Alignment.center,
    this.colorFilter,
    this.theme,
    this.quality,
  });

  /// Creates the dispatch widget from an SVG asset, resolved the same way
  /// [AssetImage] resolves [name]/[bundle]/[package].
  ///
  /// Shows a blank [width]x[height] box while loading (no `loadingBuilder`
  /// parameter — YAGNI until a caller actually needs one) and lets a load
  /// error propagate to the ambient [ErrorWidget.builder], matching
  /// [Image.asset]'s default behavior.
  ///
  /// 用 SVG asset 创建分发组件，`name`/`bundle`/`package` 的解析方式与
  /// [AssetImage] 一致。
  ///
  /// 加载期间显示一个空白的 [width]x[height] 占位（不提供 `loadingBuilder`
  /// 参数——在有调用方真正需要之前，属于 YAGNI）；加载失败则让错误传播给环境
  /// [ErrorWidget.builder]，与 [Image.asset] 的默认行为一致。
  static Widget asset(
    String name, {
    Key? key,
    AssetBundle? bundle,
    String? package,
    double? width,
    double? height,
    BoxFit fit = BoxFit.contain,
    Alignment alignment = Alignment.center,
    ColorFilter? colorFilter,
    SvgTheme? theme,
    SvgXAnimationQuality? quality,
  }) => _AsyncSvgX(
    key: key,
    loadKey: (name, bundle, package),
    load: () => SvgSourceLoader.instance.asset(name, bundle: bundle, package: package),
    width: width,
    height: height,
    fit: fit,
    alignment: alignment,
    colorFilter: colorFilter,
    theme: theme,
    quality: quality,
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
    Alignment alignment = Alignment.center,
    ColorFilter? colorFilter,
    SvgTheme? theme,
    SvgXAnimationQuality? quality,
  }) => _AsyncSvgX(
    key: key,
    loadKey: (url, headers),
    load: () => SvgSourceLoader.instance.network(url, headers: headers),
    width: width,
    height: height,
    fit: fit,
    alignment: alignment,
    colorFilter: colorFilter,
    theme: theme,
    quality: quality,
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
    Alignment alignment = Alignment.center,
    ColorFilter? colorFilter,
    SvgTheme? theme,
    SvgXAnimationQuality? quality,
  }) => _AsyncSvgX(
    key: key,
    loadKey: file,
    load: () => SvgSourceLoader.instance.file(file),
    width: width,
    height: height,
    fit: fit,
    alignment: alignment,
    colorFilter: colorFilter,
    theme: theme,
    quality: quality,
  );

  /// Creates the dispatch widget from raw SVG bytes already in memory,
  /// decoded as UTF-8 — unlike [asset]/[network]/[file], this is
  /// synchronous (no [_AsyncSvgX] loading state), the same way
  /// [MemoryImage] never shows a loading frame.
  ///
  /// 用内存中已有的原始 SVG 字节创建分发组件，按 UTF-8 解码——跟
  /// [asset]/[network]/[file] 不同，这是同步的（没有 [_AsyncSvgX] 的加载态），
  /// 与 [MemoryImage] 从不展示加载帧同理。
  static Widget memory(
    Uint8List bytes, {
    Key? key,
    double? width,
    double? height,
    BoxFit fit = BoxFit.contain,
    Alignment alignment = Alignment.center,
    ColorFilter? colorFilter,
    SvgTheme? theme,
    SvgXAnimationQuality? quality,
  }) => SvgX.string(
    utf8.decode(bytes),
    key: key,
    width: width,
    height: height,
    fit: fit,
    alignment: alignment,
    colorFilter: colorFilter,
    theme: theme,
    quality: quality,
  );

  /// Raw SVG markup, animated or static. / 原始 SVG 源，动画或静态均可。
  final String source;

  /// Target width; null uses the SVG's intrinsic width. / 目标宽度，null 用固有宽。
  final double? width;

  /// Target height; null uses the SVG's intrinsic height. / 目标高度，null 用固有高。
  final double? height;

  /// How the picture is inscribed into the box. / picture 如何适配到盒子。
  final BoxFit fit;

  /// Alignment within the box. / 在盒子内的对齐方式。
  final Alignment alignment;

  /// Optional recolor filter. / 可选的重着色滤镜。
  final ColorFilter? colorFilter;

  /// Theme controlling `currentColor`, honored by both the animated and
  /// static rendering paths.
  ///
  /// 控制 `currentColor` 的主题，动画与静态两条渲染路径均生效。
  final SvgTheme? theme;

  /// Animation quality/performance trade-off, forwarded to
  /// [SvgXAnimated.string]; ignored for a static source (the static path
  /// renders a cached `ui.Picture` and has no per-frame sampling to degrade).
  ///
  /// 动画的画质/性能取舍，转发给 [SvgXAnimated.string]；静态源忽略此参数
  /// （静态路径渲染的是缓存好的 `ui.Picture`，没有逐帧采样可降级）。
  final SvgXAnimationQuality? quality;

  @override
  Widget build(BuildContext context) {
    if (AnimationDetector.hasAnimations(source)) {
      return SvgXAnimated.string(
        source,
        width: width,
        height: height,
        fit: fit,
        alignment: alignment,
        theme: theme,
        quality: quality,
      );
    }
    return SvgXStatic(
      source,
      width: width,
      height: height,
      fit: fit,
      alignment: alignment,
      colorFilter: colorFilter,
      theme: theme,
    );
  }
}

/// Loads a source string via [load] once, then hands it to [SvgX.string] —
/// backs [SvgX.asset]/[SvgX.network].
///
/// A [StatefulWidget] rather than a `FutureBuilder`, specifically to avoid
/// [FutureBuilder]'s flicker-on-rebuild: [FutureBuilder] treats every rebuild
/// as a brand new [Future] (even a cache hit resolves on a fresh microtask,
/// not synchronously within the same build), so a parent rebuilding this
/// widget every frame — anything above it doing so, not just this widget's
/// own lifecycle — would bounce the loaded content back to the blank
/// placeholder and immediately forward again, every time. [_AsyncSvgXState]
/// instead keeps the loaded source across rebuilds and only kicks off a new
/// load in [didUpdateWidget] when [loadKey] actually changes — the same
/// reason [Image] doesn't reload an unchanged [AssetImage] on every rebuild.
///
/// 用 [load] 加载一次源字符串，再交给 [SvgX.string]——支撑
/// [SvgX.asset]/[SvgX.network]。
///
/// 用 [StatefulWidget] 而非 `FutureBuilder`，专为规避 [FutureBuilder] 的
/// "重建即闪烁"问题：[FutureBuilder] 把每次重建都当成一个全新的 [Future]
/// （即便是缓存命中，也要等到下一个 microtask 才 resolve，不会在同一次 build
/// 内同步完成），于是只要父级重建本控件——不只是本控件自身生命周期内，是
/// *任何*上层重建都会触发——已加载好的内容就会先弹回空白占位、再立刻弹回来，
/// 每次都这样。[_AsyncSvgXState] 则跨重建保留已加载的源，只在 [loadKey] 真的
/// 变化时才在 [didUpdateWidget] 里重新加载——[Image] 不会为一个没变的
/// [AssetImage] 每次重建都重新加载，是同一个道理。
class _AsyncSvgX extends StatefulWidget {
  const _AsyncSvgX({
    super.key,
    required this.loadKey,
    required this.load,
    this.width,
    this.height,
    required this.fit,
    required this.alignment,
    this.colorFilter,
    this.theme,
    this.quality,
  });

  /// Identity of what [load] fetches — compared by value in
  /// [_AsyncSvgXState.didUpdateWidget] to decide whether to reload.
  ///
  /// [load] 拉取内容的身份——在 [_AsyncSvgXState.didUpdateWidget] 里按值比较，
  /// 决定是否要重新加载。
  final Object loadKey;

  /// Fetches the SVG source text (already routed through
  /// [SvgSourceLoader]'s cache by the caller). / 拉取 SVG 源文本（调用方已经
  /// 路由过 [SvgSourceLoader] 的缓存）。
  final Future<String> Function() load;

  final double? width;
  final double? height;
  final BoxFit fit;
  final Alignment alignment;
  final ColorFilter? colorFilter;
  final SvgTheme? theme;
  final SvgXAnimationQuality? quality;

  @override
  State<_AsyncSvgX> createState() => _AsyncSvgXState();
}

class _AsyncSvgXState extends State<_AsyncSvgX> {
  String? _source;
  Object? _error;

  /// [loadKey] the currently-held [_source]/[_error] resulted from — guards
  /// against a stale in-flight load resolving after [loadKey] has already
  /// moved on to a different asset/URL.
  ///
  /// 当前持有的 [_source]/[_error] 对应的 [loadKey]——防止一次仍在途的旧加载
  /// 在 [loadKey] 已经换成别的 asset/URL 之后才 resolve，覆盖新结果。
  Object? _resultKey;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(_AsyncSvgX oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.loadKey != oldWidget.loadKey) _load();
  }

  void _load() {
    final key = widget.loadKey;
    // Clear a stale error from a previous [loadKey] immediately — otherwise
    // `build()` keeps throwing it for the new key while this fresh load is
    // still in flight.
    //
    // 立即清掉上一个 [loadKey] 留下的旧错误——否则新一次加载还在途时，
    // `build()` 会一直把旧错误当成新 key 的结果抛出来。
    if (_error != null) {
      _error = null;
    }
    widget.load().then(
      (source) {
        if (!mounted || widget.loadKey != key) return;
        setState(() {
          _source = source;
          _error = null;
          _resultKey = key;
        });
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!mounted || widget.loadKey != key) return;
        setState(() {
          _error = error;
          _resultKey = key;
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // Propagate to the ambient ErrorWidget.builder, matching Image.asset's
    // default (no errorBuilder parameter — YAGNI until asked for).
    //
    // 传播给环境 ErrorWidget.builder，与 Image.asset 的默认行为一致（没有
    // errorBuilder 参数——在有人要之前属于 YAGNI）。
    if (_error != null) throw _error!;
    if (_source == null || _resultKey != widget.loadKey) {
      return SizedBox(width: widget.width, height: widget.height);
    }
    return SvgX.string(
      _source!,
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      alignment: widget.alignment,
      colorFilter: widget.colorFilter,
      theme: widget.theme,
      quality: widget.quality,
    );
  }
}
