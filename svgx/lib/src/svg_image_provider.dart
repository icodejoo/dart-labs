// ImageProvider bridge for Svgx, so an SVG can be used anywhere Flutter
// wants an ImageProvider — DecorationImage being the motivating case (a
// CustomPainter has no such slot). One concrete class per source kind
// (StringSvgx/AssetSvgx/NetworkSvgx/FileSvgx/MemorySvgx), mirroring the
// AssetImage/NetworkImage/FileImage/MemoryImage family rather than one class
// with named constructors — each has its own concrete, directly-comparable
// fields, so none of them need a synthetic identity key the way a single
// closure-capturing class would. Static sources rasterize once; animated
// (SMIL) sources rasterize on their own timer at a self-imposed frame rate —
// see the shared class doc below (`_svgxDoc`) for why that frame rate exists
// and why it's lower than the 60Hz SvgxAnimated widget path uses.
//
// Svgx 的 ImageProvider 桥接层，让 SVG 能用在 Flutter 期待 ImageProvider 的任何
// 地方——促成这个需求的场景是 DecorationImage（CustomPainter 没有这个插槛）。
// 每种源各自一个具体类（StringSvgx/AssetSvgx/NetworkSvgx/FileSvgx/MemorySvgx），
// 对应 AssetImage/NetworkImage/FileImage/MemoryImage 那一套，而不是一个类里塞
// 命名构造函数——每个类都有自己具体、可直接比较的字段，都不需要像单个闭包捕获类
// 那样造一个合成身份键。静态源只光栅化一次；动画（SMIL）源按自定的帧率用自己的
// 定时器光栅化——为什么有这个帧率、为什么比 SvgxAnimated 控件路径的 60Hz 更低，
// 见下面共享的类文档（`_svgxDoc`）。

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import 'animation/animated_svg_painter.dart';
import 'animation/animation_detector.dart';
import 'animation/svg_document_cache.dart';
import 'animation/svg_document_parser.dart';
import 'animation/svg_theme.dart';
import 'rust_static_svg.dart';
import 'svg_source_loader.dart';

/// Oversampling factor applied on top of the device's own pixel density when
/// rasterizing an SVG image provider — see `_resolveSize`'s doc comment (on
/// `_SvgImageStreamCompleter`) for why an offscreen `toImage` snapshot needs
/// this and a direct-to-surface [SvgxAnimated]/[SvgxStatic] paint doesn't.
///
/// 通过 SVG image provider 光栅化时，在设备自身像素密度之上再叠加的超采样倍数
/// ——为什么离屏 `toImage` 快照需要它、而直接画上表面的
/// [SvgxAnimated]/[SvgxStatic] 不需要，见 `_SvgImageStreamCompleter` 上
/// `_resolveSize` 的文档注释。
const _supersample = 2;

/// Creates a provider from a raw SVG string.
///
/// **Static sources** rasterize once, cached by Flutter's own [ImageCache]
/// through normal [ImageProvider] value equality — no different from
/// [AssetImage]/[NetworkImage] in that respect.
///
/// **Animated (SMIL) sources** rasterize repeatedly, one frame at a time,
/// pushed through a custom [ImageStreamCompleter] — but at a *self-imposed*
/// frame rate ([animationFrameRate], default 30), not the 60Hz [SvgxAnimated]
/// widget path uses. That's a deliberate, structural trade-off, not a
/// shortcut: [SvgxAnimated] hands `dart:ui` a [ui.Picture] directly for the
/// GPU to consume, while every frame here is additionally rasterized into a
/// brand-new [ui.Image] first — `DecorationImage`'s contract only knows how
/// to consume a decoded image, not a paint callback — and a fresh offscreen
/// render-target allocation every frame is a real, measured cost the engine
/// team calls out as something that "should not occur in a frame workload"
/// (see https://github.com/flutter/flutter/issues/13498). Halving the rate
/// to 30Hz halves how often that allocation happens; it does not remove it.
/// If an SVG needs to look smooth at 60Hz, prefer [SvgxAnimated]/`Svgx` (a
/// real widget in the tree) over squeezing it through an [ImageProvider].
///
/// A rasterized animated frame only ever shows this document's *base*
/// (non-animated-property) appearance if [SvgDocumentCache] fails to parse
/// it as animated for some reason — in the ordinary case the same SMIL
/// engine [SvgxAnimated] uses drives every frame, so animation content is
/// fully supported here, just at a lower, capped rate.
///
/// [width]/[height] pick the raster resolution. Both are optional:
/// - Neither given → falls back to the primary display's logical width with
///   height derived from the SVG's own intrinsic aspect ratio.
/// - Only one given → the other is derived from the SVG's own intrinsic
///   aspect ratio.
///
/// 用原始 SVG 字符串创建 provider。
///
/// **静态源**只光栅化一次，通过 [ImageProvider] 常规的值相等语义接入 Flutter
/// 自带的 [ImageCache]——这一点上跟 [AssetImage]/[NetworkImage] 没有区别。
///
/// **动画（SMIL）源**反复光栅化，一次一帧，经自定义 [ImageStreamCompleter]
/// 推送——但按*自定*帧率（[animationFrameRate]，默认 30），不是
/// [SvgxAnimated] 控件路径用的 60Hz。这是刻意的结构性取舍，不是抄近路：
/// [SvgxAnimated] 把 [ui.Picture] 直接交给 `dart:ui` 给 GPU 消费，而这里每一帧
/// 都要先额外光栅化成一张全新的 [ui.Image]——`DecorationImage` 的契约只认已解码
/// 的图像，不认绘制回调——每帧一次全新的离屏渲染目标分配是真实、已被实测的
/// 成本，引擎团队自己就说这"不该发生在帧工作负载里"（见
/// https://github.com/flutter/flutter/issues/13498）。把频率减半到 30Hz 能让这次
/// 分配的发生次数减半，但消除不了它。若 SVG 需要在 60Hz 下看起来流畅，优先用
/// [SvgxAnimated]/`Svgx`（组件树里的真实控件），而不是硬塞进 [ImageProvider]。
///
/// 只有当 [SvgDocumentCache] 出于某种原因未能把它解析为动画文档时，光栅化出的
/// 动画帧才会只显示该文档的*基底*（未受动画属性驱动）外观——正常情况下驱动每一
/// 帧的是与 [SvgxAnimated] 相同的 SMIL 引擎，所以动画内容在这里是完整支持的，
/// 只是帧率更低、有上限。
///
/// [width]/[height] 决定光栅分辨率。二者均可选：
/// - 都不给 → 落到主显示器的逻辑宽度，高度按 SVG 自身固有宽高比推导。
/// - 只给一个 → 另一个按 SVG 自身固有宽高比推导。
class StringSvgx extends ImageProvider<StringSvgx> {
  /// Creates the provider. / 创建 provider。
  const StringSvgx(
    this.source, {
    this.width,
    this.height,
    this.colorFilter,
    this.theme,
    this.animationFrameRate = 30,
  });

  /// Raw SVG markup, animated or static. / 原始 SVG 源，动画或静态均可。
  final String source;

  /// Target raster width; see the class doc for the full resolution order.
  ///
  /// 目标光栅宽度；完整的解析优先级见类文档。
  final double? width;

  /// Target raster height; see the class doc for the full resolution order.
  ///
  /// 目标光栅高度；完整的解析优先级见类文档。
  final double? height;

  /// Recolor filter, baked into the rasterized pixels (there is no widget
  /// tree here to wrap in [ColorFiltered]).
  ///
  /// 重着色滤镜，直接烘焙进光栅化的像素里（这里没有组件树可以套
  /// [ColorFiltered]）。
  final ColorFilter? colorFilter;

  /// Theme controlling `currentColor`. / 控制 `currentColor` 的主题。
  final SvgTheme? theme;

  /// How often an animated source re-rasterizes, in frames per second — see
  /// the class doc for why this exists and defaults below 60.
  ///
  /// 动画源重新光栅化的频率（帧/秒）——为什么存在、为什么默认低于 60，见类文档。
  final int animationFrameRate;

  @override
  Future<StringSvgx> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<StringSvgx>(this);

  @override
  bool operator ==(Object other) =>
      other is StringSvgx &&
      other.source == source &&
      other.width == width &&
      other.height == height &&
      other.colorFilter == colorFilter &&
      other.theme == theme &&
      other.animationFrameRate == animationFrameRate;

  @override
  int get hashCode =>
      Object.hash(source, width, height, colorFilter, theme, animationFrameRate);

  @override
  ImageStreamCompleter loadImage(StringSvgx key, ImageDecoderCallback decode) =>
      _svgImageStreamCompleter(
        sourceFuture: SynchronousFuture<String>(source),
        width: width,
        height: height,
        colorFilter: colorFilter,
        theme: theme,
        animationFrameRate: animationFrameRate,
      );
}

/// Creates a provider from an SVG asset, resolved the same way [AssetImage]
/// resolves [assetName]/[bundle]/[package] — see [StringSvgx]'s class doc for
/// the rest of the static/animated/[width]/[height] behavior shared by every
/// class in this family.
///
/// 用 SVG asset 创建 provider，`assetName`/`bundle`/`package` 的解析方式与
/// [AssetImage] 一致——本家族其余共有的静态/动画/[width]/[height] 行为见
/// [StringSvgx] 的类文档。
class AssetSvgx extends ImageProvider<AssetSvgx> {
  /// Creates the provider. / 创建 provider。
  const AssetSvgx(
    this.assetName, {
    this.bundle,
    this.package,
    this.width,
    this.height,
    this.colorFilter,
    this.theme,
    this.animationFrameRate = 30,
  });

  /// The asset key, before [package] resolution. / asset key（[package] 解析前）。
  final String assetName;

  /// Bundle to load from; the ambient [rootBundle] when null.
  ///
  /// 加载所用的 bundle；为 null 时用环境 [rootBundle]。
  final AssetBundle? bundle;

  /// Package [assetName] belongs to, resolved the same way [AssetImage] does.
  ///
  /// [assetName] 所属的包，解析方式与 [AssetImage] 一致。
  final String? package;

  final double? width;
  final double? height;
  final ColorFilter? colorFilter;
  final SvgTheme? theme;
  final int animationFrameRate;

  @override
  Future<AssetSvgx> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<AssetSvgx>(this);

  @override
  bool operator ==(Object other) =>
      other is AssetSvgx &&
      other.assetName == assetName &&
      other.bundle == bundle &&
      other.package == package &&
      other.width == width &&
      other.height == height &&
      other.colorFilter == colorFilter &&
      other.theme == theme &&
      other.animationFrameRate == animationFrameRate;

  @override
  int get hashCode => Object.hash(
    assetName,
    bundle,
    package,
    width,
    height,
    colorFilter,
    theme,
    animationFrameRate,
  );

  @override
  ImageStreamCompleter loadImage(AssetSvgx key, ImageDecoderCallback decode) =>
      _svgImageStreamCompleter(
        sourceFuture: SvgSourceLoader.instance.asset(
          assetName,
          bundle: bundle,
          package: package,
        ),
        width: width,
        height: height,
        colorFilter: colorFilter,
        theme: theme,
        animationFrameRate: animationFrameRate,
      );
}

/// Creates a provider from an SVG fetched over HTTP(S). No response-level
/// caching beyond [SvgSourceLoader]'s in-memory LRU — this is a plain
/// one-shot fetch, not a full [NetworkImage]-style HTTP cache. See
/// [StringSvgx]'s class doc for the rest of the shared behavior.
///
/// 用通过 HTTP(S) 拉取的 SVG 创建 provider。除 [SvgSourceLoader] 的内存 LRU 外
/// 没有额外的响应级缓存——这是一次性拉取，不是完整的 [NetworkImage] 式 HTTP
/// 缓存。其余共有行为见 [StringSvgx] 的类文档。
class NetworkSvgx extends ImageProvider<NetworkSvgx> {
  /// Creates the provider. / 创建 provider。
  const NetworkSvgx(
    this.url, {
    this.headers,
    this.width,
    this.height,
    this.colorFilter,
    this.theme,
    this.animationFrameRate = 30,
  });

  /// URL to fetch the SVG source from. / 拉取 SVG 源所用的 URL。
  final String url;

  /// Extra HTTP request headers. / 额外的 HTTP 请求头。
  final Map<String, String>? headers;

  final double? width;
  final double? height;
  final ColorFilter? colorFilter;
  final SvgTheme? theme;
  final int animationFrameRate;

  @override
  Future<NetworkSvgx> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<NetworkSvgx>(this);

  // `headers` compares by the Map's own `==` (identity for a non-`const`
  // Map), same known, benign limitation documented on `SvgSourceLoader` —
  // two equal-content-but-separately-built header maps miss `ImageCache`'s
  // dedup and each rasterize their own copy; harmless extra work, not a
  // wrong image, and `headers` is typically a literal at the call site
  // (where const canonicalization already makes this a non-issue).
  //
  // `headers` 按该 Map 自身的 `==` 比较（非 `const` Map 就是身份比较），是
  // `SvgSourceLoader` 上记录过的同一个已知、无害的局限——两份内容相同但分别
  // 构造的 headers 表会各自光栅化一份、错过 `ImageCache` 的去重；无害（多做
  // 一次工，不会给错图），且 `headers` 在调用处通常是字面量（此时 const
  // 规范化已经让这不成问题）。
  @override
  bool operator ==(Object other) =>
      other is NetworkSvgx &&
      other.url == url &&
      other.headers == headers &&
      other.width == width &&
      other.height == height &&
      other.colorFilter == colorFilter &&
      other.theme == theme &&
      other.animationFrameRate == animationFrameRate;

  @override
  int get hashCode => Object.hash(
    url,
    headers,
    width,
    height,
    colorFilter,
    theme,
    animationFrameRate,
  );

  @override
  ImageStreamCompleter loadImage(NetworkSvgx key, ImageDecoderCallback decode) =>
      _svgImageStreamCompleter(
        sourceFuture: SvgSourceLoader.instance.network(url, headers: headers),
        width: width,
        height: height,
        colorFilter: colorFilter,
        theme: theme,
        animationFrameRate: animationFrameRate,
      );
}

/// Creates a provider from an SVG file on disk. See [StringSvgx]'s class doc
/// for the rest of the shared behavior.
///
/// 用磁盘上的 SVG 文件创建 provider。其余共有行为见 [StringSvgx] 的类文档。
class FileSvgx extends ImageProvider<FileSvgx> {
  /// Creates the provider. / 创建 provider。
  const FileSvgx(
    this.file, {
    this.width,
    this.height,
    this.colorFilter,
    this.theme,
    this.animationFrameRate = 30,
  });

  /// The SVG file to load. / 要加载的 SVG 文件。
  final File file;

  final double? width;
  final double? height;
  final ColorFilter? colorFilter;
  final SvgTheme? theme;
  final int animationFrameRate;

  @override
  Future<FileSvgx> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<FileSvgx>(this);

  @override
  bool operator ==(Object other) =>
      other is FileSvgx &&
      // `File` has no value-equality override of its own (identity only),
      // so this compares `path` explicitly instead — matching `FileImage`'s
      // own `==`, which does the same for the same reason.
      //
      // `File` 自身没有值相等重写（只有身份比较），所以这里改为显式比较
      // `path`——与 `FileImage` 自己的 `==` 做法一致，理由相同。
      other.file.path == file.path &&
      other.width == width &&
      other.height == height &&
      other.colorFilter == colorFilter &&
      other.theme == theme &&
      other.animationFrameRate == animationFrameRate;

  @override
  int get hashCode => Object.hash(
    file.path,
    width,
    height,
    colorFilter,
    theme,
    animationFrameRate,
  );

  @override
  ImageStreamCompleter loadImage(FileSvgx key, ImageDecoderCallback decode) =>
      _svgImageStreamCompleter(
        sourceFuture: SvgSourceLoader.instance.file(file),
        width: width,
        height: height,
        colorFilter: colorFilter,
        theme: theme,
        animationFrameRate: animationFrameRate,
      );
}

/// Creates a provider from raw SVG bytes already in memory, decoded as
/// UTF-8. See [StringSvgx]'s class doc for the rest of the shared behavior.
///
/// 用内存中已有的原始 SVG 字节创建 provider，按 UTF-8 解码。其余共有行为见
/// [StringSvgx] 的类文档。
class MemorySvgx extends ImageProvider<MemorySvgx> {
  /// Creates the provider. / 创建 provider。
  const MemorySvgx(
    this.bytes, {
    this.width,
    this.height,
    this.colorFilter,
    this.theme,
    this.animationFrameRate = 30,
  });

  /// Raw SVG bytes, decoded as UTF-8. / 原始 SVG 字节，按 UTF-8 解码。
  final Uint8List bytes;

  final double? width;
  final double? height;
  final ColorFilter? colorFilter;
  final SvgTheme? theme;
  final int animationFrameRate;

  @override
  Future<MemorySvgx> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<MemorySvgx>(this);

  @override
  bool operator ==(Object other) =>
      other is MemorySvgx &&
      // `Uint8List` has no value-equality override, same as `MemoryImage`'s
      // own `bytes` field — two calls that happen to pass identical-content
      // but separately-allocated byte lists won't dedupe in `ImageCache`,
      // mirroring `MemoryImage`'s documented behavior exactly.
      //
      // `Uint8List` 没有值相等重写，与 `MemoryImage` 自己的 `bytes` 字段同理
      // ——两次调用即便内容相同但字节数组是分别分配的，不会在 `ImageCache` 里
      // 去重，与 `MemoryImage` 文档记录的行为完全一致。
      other.bytes == bytes &&
      other.width == width &&
      other.height == height &&
      other.colorFilter == colorFilter &&
      other.theme == theme &&
      other.animationFrameRate == animationFrameRate;

  @override
  int get hashCode => Object.hash(
    bytes,
    width,
    height,
    colorFilter,
    theme,
    animationFrameRate,
  );

  @override
  ImageStreamCompleter loadImage(MemorySvgx key, ImageDecoderCallback decode) =>
      _svgImageStreamCompleter(
        sourceFuture: SynchronousFuture<String>(utf8.decode(bytes)),
        width: width,
        height: height,
        colorFilter: colorFilter,
        theme: theme,
        animationFrameRate: animationFrameRate,
      );
}

/// Shared entry point every class in this file's [ImageProvider.loadImage]
/// delegates to — the one place that knows how to turn "a future resolving
/// to SVG source text plus a few render options" into an [ImageStreamCompleter],
/// regardless of which concrete provider class asked for it.
///
/// 本文件里每个类的 [ImageProvider.loadImage] 都委托到这个共享入口——唯一知道
/// 怎么把"一个 resolve 出 SVG 源文本的 future 加上几个渲染选项"变成
/// [ImageStreamCompleter] 的地方，不管是哪个具体 provider 类发起的请求。
ImageStreamCompleter _svgImageStreamCompleter({
  required Future<String> sourceFuture,
  required double? width,
  required double? height,
  required ColorFilter? colorFilter,
  required SvgTheme? theme,
  required int animationFrameRate,
}) => _SvgImageStreamCompleter(
  sourceFuture: sourceFuture,
  width: width,
  height: height,
  colorFilter: colorFilter,
  theme: theme,
  animationFrameRate: animationFrameRate,
);

/// [ImageStreamCompleter] shared by every SVG [ImageProvider] in this file —
/// resolves the source text, then dispatches to a one-shot static raster or
/// a repeating animated raster loop, whichever the parsed source needs.
///
/// 本文件里每个 SVG [ImageProvider] 共用的 [ImageStreamCompleter]——先解析出
/// 源文本，再按需要分派到一次性静态光栅化或反复执行的动画光栅化循环。
class _SvgImageStreamCompleter extends ImageStreamCompleter {
  _SvgImageStreamCompleter({
    required Future<String> sourceFuture,
    required this.width,
    required this.height,
    required this.colorFilter,
    required this.theme,
    required this.animationFrameRate,
  }) {
    addOnLastListenerRemovedCallback(() {
      _timer?.cancel();
      _timer = null;
      // Pausing the clock alongside the timer, not just stopping the ticks,
      // matters for correctness: without it, a listener re-added later (e.g.
      // a DecorationImage scrolled back into view) would resume sampling at
      // however much *wall-clock* time passed while paused, jumping the SMIL
      // timeline forward instead of resuming where it left off.
      //
      // 连同定时器一起暂停时钟，而不只是停掉 tick，这一点关系到正确性：不这样
      // 做，之后再加回来的监听者（比如滚回视口的 DecorationImage）恢复采样时,
      // 用的会是暂停期间流逝掉的*墙钟*时间，把 SMIL 时间线直接推向前，而不是从
      // 暂停的地方接着播。
      _stopwatch?.stop();
    });
    sourceFuture.then(
      _start,
      onError: (Object error, StackTrace stackTrace) {
        reportError(
          context: ErrorDescription('while loading an SVG image'),
          exception: error,
          stack: stackTrace,
        );
      },
    );
  }

  final double? width;
  final double? height;
  final ColorFilter? colorFilter;
  final SvgTheme? theme;
  final int animationFrameRate;

  Timer? _timer;

  /// The animated path's timeline clock — null for a static source. Held at
  /// this level (not just inside [_startAnimated]'s closure) so
  /// [addOnLastListenerRemovedCallback]'s pause callback can reach it.
  ///
  /// 动画路径的时间线时钟——静态源为 null。放在这一层（而非只在
  /// [_startAnimated] 的闭包里）持有，好让
  /// [addOnLastListenerRemovedCallback] 的暂停回调能拿到它。
  Stopwatch? _stopwatch;

  /// Restarts the animated ticking loop after [addOnLastListenerRemovedCallback]
  /// paused it and a new listener arrives — null until [_startAnimated] sets
  /// it up, and only relevant for an animated source (a static source has no
  /// ticking to resume).
  ///
  /// 上一个监听者摘除、被 [addOnLastListenerRemovedCallback] 暂停之后，等新监听者
  /// 出现时重新启动动画 tick 循环——在 [_startAnimated] 完成设置之前为 null，且只
  /// 对动画源有意义（静态源没有 tick 循环需要恢复）。
  void Function()? _resumeTicking;

  @override
  void addListener(ImageStreamListener listener) {
    super.addListener(listener);
    if (_timer == null) _resumeTicking?.call();
  }

  void _start(String source) {
    if (AnimationDetector.hasAnimations(source)) {
      _startAnimated(source);
    } else {
      _emitStatic(source);
    }
  }

  Future<void> _emitStatic(String source) async {
    try {
      final currentColorArgb = theme?.currentColor.toARGB32();
      final info = await RustSvgPictureCache.instance.getOrRenderAsync(
        source,
        currentColorArgb: currentColorArgb,
      );
      final (w, h, scale) = _resolveSize(info.size);
      final image = await rasterizeSvgPicture(
        info,
        width: w,
        height: h,
        colorFilter: colorFilter,
      );
      setImage(ImageInfo(image: image, scale: scale));
    } catch (error, stackTrace) {
      reportError(
        context: ErrorDescription('while rasterizing a static SVG image'),
        exception: error,
        stack: stackTrace,
      );
    }
  }

  void _startAnimated(String source) {
    final parsed = SvgDocumentCache.instance.getOrParse(source);
    final document = parsed.document;
    final ready = parsed.hasImages
        ? resolveImageNodes(document)
        : SynchronousFuture<void>(null);
    ready.then((_) {
      // The load can resolve after the last listener already left (e.g. the
      // DecorationImage scrolled away before the parse/decode finished) — in
      // that case there is nothing to burn frames rendering for, so this
      // skips straight to "paused", the same state
      // `addOnLastListenerRemovedCallback` puts it in. `_resumeTicking` is
      // still wired up below so a listener arriving later starts it for
      // real.
      //
      // 加载可能在最后一个监听者已经离开之后才完成（比如 DecorationImage 在
      // 解析/解码结束前就滚出了视口）——这种情况下没有观众可供渲染帧，于是直接
      // 跳到"已暂停"状态，与 `addOnLastListenerRemovedCallback` 会置入的状态
      // 相同。下面仍会设好 `_resumeTicking`，之后真有监听者出现时能正常启动。
      final intrinsicSize = Size(document.width, document.height);
      final (w, h, scale) = _resolveSize(intrinsicSize);
      final stopwatch = _stopwatch = Stopwatch()..start();
      final clock = ValueNotifier<Duration>(Duration.zero);
      final painter = AnimatedSvgPainter(
        root: document.root,
        intrinsicSize: intrinsicSize,
        clock: clock,
        theme: theme ?? const SvgTheme(),
        fit: BoxFit.contain,
        alignment: Alignment.center,
        gradients: document.gradients,
        clipPaths: document.clipPaths,
        masks: document.masks,
      );
      Future<void> renderFrame() async {
        clock.value = stopwatch.elapsed;
        final image = await _rasterizePainter(painter, w, h, colorFilter);
        setImage(ImageInfo(image: image, scale: scale));
      }
      final interval = Duration(
        milliseconds: (1000 / animationFrameRate).round(),
      );
      void restart() {
        stopwatch.start();
        unawaited(renderFrame());
        _timer = Timer.periodic(interval, (_) => unawaited(renderFrame()));
      }
      _resumeTicking = restart;
      if (hasListeners) {
        restart();
      } else {
        stopwatch.stop();
      }
    });
  }

  /// Resolution order for the *logical* raster size: explicit [width]/[height]
  /// first, an aspect-ratio-derived missing half second, then
  /// [SchedulerBinding]'s primary view as a last resort. The returned pixel
  /// dimensions are that logical size scaled by the view's
  /// `devicePixelRatio`, paired with a matching [ImageInfo.scale] so the
  /// rasterized image is exactly as sharp on a high-DPI display as
  /// [SvgxAnimated]/[SvgxStatic] are — painting and [ui.Picture.toImage] both
  /// at the *logical* size then relying on Flutter to stretch the result up
  /// to fill the physical pixels would reproduce exactly the visible
  /// aliasing/blur this guards against.
  ///
  /// [ImageConfiguration]'s own `size` isn't consulted here: by the time
  /// [ImageProvider.loadImage] runs, the configuration that produced the key
  /// isn't threaded through to this completer (only the key itself is) — a
  /// caller that needs to pin the raster to its exact box size should pass
  /// explicit [width]/[height].
  ///
  /// 光栅*逻辑*尺寸的解析优先级：显式 [width]/[height] 优先，其次按宽高比推导
  /// 缺失的那一半，最后落到 [SchedulerBinding] 的主视图兜底。返回的像素尺寸是
  /// 该逻辑尺寸乘上视图的 `devicePixelRatio`，并配一个对应的 [ImageInfo.scale]，
  /// 使光栅化出的图像在高 DPI 屏幕上跟 [SvgxAnimated]/[SvgxStatic] 一样清晰——
  /// 若只按*逻辑*尺寸去画+ [ui.Picture.toImage]，再让 Flutter 把结果拉伸填满
  /// 物理像素，正好会重现这里要规避的锯齿/模糊。
  ///
  /// 这里不查 [ImageConfiguration] 自带的 `size`：[ImageProvider.loadImage]
  /// 运行时，产出 key 的那份 configuration 并未一路传给这个 completer（只传了
  /// key 本身）——需要精确贴合容器尺寸的调用方应显式传 [width]/[height]。
  (int width, int height, double scale) _resolveSize(Size intrinsicSize) {
    // A zero/negative/NaN intrinsic dimension (a malformed or not-yet-known
    // SVG size) would otherwise divide out to a non-finite aspect ratio that
    // silently propagates into `.round()` below.
    //
    // 固有宽高为零/负/NaN（畸形或尚未解析出的 SVG 尺寸）时，宽高比本会算出
    // 非有限值，并悄悄传播进下面的 `.round()`。
    final aspect = intrinsicSize.width > 0 && intrinsicSize.height > 0
        ? intrinsicSize.width / intrinsicSize.height
        : 1.0;
    double? w = width;
    double? h = height;
    if (w != null && h == null) h = w / aspect;
    if (h != null && w == null) w = h * aspect;
    final view = SchedulerBinding.instance.platformDispatcher.views.first;
    if (w == null || h == null) {
      w ??= view.physicalSize.width / view.devicePixelRatio;
      h ??= w / aspect;
    }
    // Oversample by [_supersample] beyond the device's own pixel density,
    // then let Flutter's normal (bilinear-filtered) downscale during
    // compositing smooth the result — a supersampling AA pass. This matters
    // specifically because this image comes from `ui.Picture.toImage`, an
    // *offscreen* render target: unlike the main swapchain surface
    // `SvgxAnimated`/`SvgxStatic` paint onto directly (which the engine gives
    // MSAA), an ad-hoc offscreen target rasterizes each frame's vector edges
    // single-sample, i.e. aliased, regardless of how correctly its overall
    // pixel *density* matches the device — raising the density alone (the
    // devicePixelRatio multiply above) sharpens blur but does not by itself
    // smooth an edge that was rasterized without any multisampling at all.
    //
    // 在设备自身像素密度之上再超采样 [_supersample] 倍，再让 Flutter 合成阶段
    // 正常的（双线性过滤）降采样把结果磨平——相当于一次超采样抗锯齿。这里之所以
    // 单独需要它：这张图来自 `ui.Picture.toImage`，是一个*离屏*渲染目标——不同于
    // `SvgxAnimated`/`SvgxStatic` 直接画上去、引擎会给 MSAA 的主 swapchain 表面，
    // 临时搭建的离屏目标本就按单样本（即有锯齿）光栅化每一帧的矢量边缘，跟它整体
    // 像素*密度*对不对没关系——只把密度提高（上面乘 devicePixelRatio 那步）能让
    // 图像更清晰，但不会让一条压根没做多重采样的边缘变平滑。
    final dpr = view.devicePixelRatio * _supersample;
    return (
      (w * dpr).round().clamp(1, 4096),
      (h * dpr).round().clamp(1, 4096),
      dpr,
    );
  }

  @override
  void onDisposed() {
    _timer?.cancel();
    super.onDisposed();
  }
}

/// Rasterizes one frame of [painter] into a [width]x[height] [ui.Image],
/// applying [colorFilter] first if given — the animated-path counterpart to
/// [rasterizeSvgPicture] (which does the same job for a static [SvgPath]'s
/// already-recorded [ui.Picture]); kept separate because this path paints
/// fresh from an [AnimatedSvgPainter] every call rather than replaying one
/// fixed picture.
///
/// 把 [painter] 的一帧光栅化成 [width]x[height] 的 [ui.Image]，若给了
/// [colorFilter] 先应用它——是 [rasterizeSvgPicture](对静态 [SvgPath] 已录制好的
/// [ui.Picture] 做同样的事）在动画路径上的对应版本；单独一份是因为这条路径每次
/// 调用都要从 [AnimatedSvgPainter] 现画一帧，而不是重放一份固定的 picture。
Future<ui.Image> _rasterizePainter(
  CustomPainter painter,
  int width,
  int height,
  ColorFilter? colorFilter,
) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final w = width.toDouble();
  final h = height.toDouble();
  if (colorFilter != null) {
    canvas.saveLayer(Rect.fromLTWH(0, 0, w, h), Paint()..colorFilter = colorFilter);
  }
  painter.paint(canvas, Size(w, h));
  if (colorFilter != null) canvas.restore();
  final framePicture = recorder.endRecording();
  try {
    return await framePicture.toImage(width, height);
  } finally {
    framePicture.dispose();
  }
}
