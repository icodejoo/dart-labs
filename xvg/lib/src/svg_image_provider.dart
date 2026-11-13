// SVG and native bitmap ImageProviders with byte sniffing and shared ImageCache.
// SVG 动画按 Timer → vsync 采样；位图使用 Flutter 原生多帧解码与 ImageCache。

// ImageProviders produce integer-pixel images; composition snapping is unnecessary.
// ImageProvider 输出整像素图像，无需合成阶段对齐。
import 'dart:async';
import 'dart:convert';
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
import 'platform_file.dart'
    if (dart.library.js_interop) 'platform_file_web.dart';
import 'svg_source_loader.dart';
import 'svg_source_sniffer.dart';

/// Oversampling factor applied on top of the device's own pixel density when
/// rasterizing an SVG image provider — see `_resolveSize`'s doc comment (on
/// `_SvgImageStreamCompleter`) for why an offscreen `toImage` snapshot needs
/// this and a direct-to-surface [AnimatedXvg]/[StaticXvg] paint doesn't.
///
/// 通过 SVG image provider 光栅化时，在设备自身像素密度之上再叠加的超采样倍数
/// ——为什么离屏 `toImage` 快照需要它、而直接画上表面的
/// [AnimatedXvg]/[StaticXvg] 不需要，见 `_SvgImageStreamCompleter` 上
/// `_resolveSize` 的文档注释。
const _supersample = 2;

/// Default SVG animation rate. / 默认 SVG 动画帧率。
const _defaultAnimationFrameRate = 30;

/// Maximum raster dimension. / 最大光栅像素尺寸。
const _maximumRasterDimension = 4096;

/// Gaps above four intervals count as a pause, tolerating ordinary frame jitter.
/// 超过四个间隔视为暂停，容忍正常帧抖动。
const _pauseGapIntervals = 4;

/// Content type for the explicit SVG text provider. / 显式 SVG 文本源的类型。
const _svgContentType = 'image/svg+xml';

/// Creates an image provider from raw SVG markup, including animations.
///
/// [width] and [height] select the SVG raster size. If one is omitted, the
/// SVG aspect ratio determines it; if both are omitted, the primary display's
/// logical width is used. [animationFrameRate] defaults to 30 frames per second.
/// [theme] supplies currentColor and [colorFilter] recolors SVG pixels.
///
/// Asset, network, file, and memory providers also accept native bitmap bytes.
/// Bitmaps ignore SVG sizing, filtering, theme, and animation-rate options;
/// use [ResizeImage] for bitmap decode dimensions. String input remains SVG text.
/// Animation controllers do not affect ImageProvider playback.
///
/// Example: `Image(image: StringXvg('<svg width="24" height="24"/>'))`.
///
/// 用原始 SVG 文本创建图像 provider，支持动画。[width]/[height] 指定 SVG
/// 光栅尺寸，缺一项时由宽高比推导；均省略时使用主显示器的逻辑宽度。
/// [animationFrameRate] 默认为每秒 30 帧，[theme] 提供 currentColor，
/// [colorFilter] 对 SVG 像素重着色。
///
/// asset、network、file、memory provider 也接受原生位图字节；位图忽略
/// SVG 的尺寸、滤镜、主题和动画帧率选项，解码尺寸使用 [ResizeImage]。
/// String 输入仍为 SVG 文本。动画控制器不作用于 ImageProvider。
///
/// 示例：`Image(image: StringXvg('<svg width="24" height="24"/>'))`。
class StringXvg extends ImageProvider<StringXvg> {
  /// Creates the provider. / 创建 provider。
  const StringXvg(
    this.source, {
    this.width,
    this.height,
    this.colorFilter,
    this.theme,
    this.animationFrameRate = _defaultAnimationFrameRate,
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
  final XvgTheme? theme;

  /// How often an animated source re-rasterizes, in frames per second — see
  /// the class doc for why this exists and defaults below 60.
  ///
  /// 动画源重新光栅化的频率（帧/秒）——为什么存在、为什么默认低于 60，见类文档。
  final int animationFrameRate;

  @override
  Future<StringXvg> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<StringXvg>(this);

  @override
  bool operator ==(Object other) =>
      other is StringXvg &&
      other.source == source &&
      other.width == width &&
      other.height == height &&
      other.colorFilter == colorFilter &&
      other.theme == theme &&
      other.animationFrameRate == animationFrameRate;

  @override
  int get hashCode => Object.hash(
    source,
    width,
    height,
    colorFilter,
    theme,
    animationFrameRate,
  );

  /// Loads SVG text as image frames. / 将 SVG 文本加载为图像帧。
  @override
  ImageStreamCompleter loadImage(StringXvg key, ImageDecoderCallback decode) =>
      _svgImageStreamCompleter(
        sourceFuture: SynchronousFuture<SvgSourceBytes>(
          SvgSourceBytes(utf8.encode(source), contentType: _svgContentType),
        ),
        cacheKey: key,
        decode: decode,
        width: width,
        height: height,
        colorFilter: colorFilter,
        theme: theme,
        animationFrameRate: animationFrameRate,
      );
}

/// Creates a provider from an SVG or bitmap asset, resolved like [AssetImage]
/// resolves [assetName]/[bundle]/[package] — see [StringXvg]'s class doc for
/// the rest of the static/animated/[width]/[height] behavior shared by every
/// class in this family.
///
/// 用 SVG 或位图 asset 创建 provider，`assetName`/`bundle`/`package` 的解析方式与
/// [AssetImage] 一致——本家族其余共有的静态/动画/[width]/[height] 行为见
/// [StringXvg] 的类文档。
class AssetXvg extends ImageProvider<AssetXvg> {
  /// Creates the provider. / 创建 provider。
  const AssetXvg(
    this.assetName, {
    this.bundle,
    this.package,
    this.width,
    this.height,
    this.colorFilter,
    this.theme,
    this.animationFrameRate = _defaultAnimationFrameRate,
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

  /// Target raster width; see [StringXvg]'s class doc for the full resolution order.
  ///
  /// 目标光栅宽度；完整的解析优先级见 [StringXvg] 类文档。
  final double? width;

  /// Target raster height; see [StringXvg]'s class doc for the full resolution order.
  ///
  /// 目标光栅高度；完整的解析优先级见 [StringXvg] 类文档。
  final double? height;

  /// SVG recolor filter; ignored for bitmaps.
  ///
  /// SVG 重着色滤镜；位图忽略此参数。
  final ColorFilter? colorFilter;

  /// Theme controlling `currentColor`. / 控制 `currentColor` 的主题。
  final XvgTheme? theme;

  /// How often an animated source re-rasterizes, in frames per second — see
  /// [StringXvg]'s class doc for why this exists and defaults below 60.
  ///
  /// 动画源重新光栅化的频率（帧/秒）——为什么存在、为什么默认低于 60，见
  /// [StringXvg] 类文档。
  final int animationFrameRate;

  @override
  Future<AssetXvg> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<AssetXvg>(this);

  @override
  bool operator ==(Object other) =>
      other is AssetXvg &&
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

  /// Loads SVG or native bitmap bytes. / 加载 SVG 或原生位图字节。
  @override
  ImageStreamCompleter loadImage(AssetXvg key, ImageDecoderCallback decode) =>
      _svgImageStreamCompleter(
        sourceFuture: SvgSourceLoader.instance
            .assetBytes(assetName, bundle: bundle, package: package)
            .then((bytes) => SvgSourceBytes(bytes)),
        cacheKey: key,
        decode: decode,
        width: width,
        height: height,
        colorFilter: colorFilter,
        theme: theme,
        animationFrameRate: animationFrameRate,
      );
}

/// Creates a provider from an HTTP(S) SVG or native bitmap URL.
/// [headers] are sent with the request; non-200 responses report
/// [NetworkImageLoadException]. Decoded images use Flutter's [ImageCache].
/// See [StringXvg] for SVG sizing and animation behavior.
///
/// 用 HTTP(S) SVG 或原生位图 URL 创建 provider。[headers] 随请求发送；
/// 非 200 响应报告 [NetworkImageLoadException]，解码图片使用 Flutter [ImageCache]。
/// SVG 尺寸与动画行为见 [StringXvg]。
class NetworkXvg extends ImageProvider<NetworkXvg> {
  /// Creates the provider. / 创建 provider。
  const NetworkXvg(
    this.url, {
    this.headers,
    this.width,
    this.height,
    this.colorFilter,
    this.theme,
    this.animationFrameRate = _defaultAnimationFrameRate,
  });

  /// URL for SVG or bitmap bytes. / SVG 或位图字节的 URL。
  final String url;

  /// Extra HTTP request headers. / 额外的 HTTP 请求头。
  final Map<String, String>? headers;

  /// Target raster width; see [StringXvg]'s class doc for the full resolution order.
  ///
  /// 目标光栅宽度；完整的解析优先级见 [StringXvg] 类文档。
  final double? width;

  /// Target raster height; see [StringXvg]'s class doc for the full resolution order.
  ///
  /// 目标光栅高度；完整的解析优先级见 [StringXvg] 类文档。
  final double? height;

  /// SVG recolor filter; ignored for bitmaps.
  ///
  /// SVG 重着色滤镜；位图忽略此参数。
  final ColorFilter? colorFilter;

  /// Theme controlling `currentColor`. / 控制 `currentColor` 的主题。
  final XvgTheme? theme;

  /// How often an animated source re-rasterizes, in frames per second — see
  /// [StringXvg]'s class doc for why this exists and defaults below 60.
  ///
  /// 动画源重新光栅化的频率（帧/秒）——为什么存在、为什么默认低于 60，见
  /// [StringXvg] 类文档。
  final int animationFrameRate;

  @override
  Future<NetworkXvg> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<NetworkXvg>(this);

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
      other is NetworkXvg &&
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

  /// Loads SVG or native bitmap bytes. / 加载 SVG 或原生位图字节。
  @override
  ImageStreamCompleter loadImage(NetworkXvg key, ImageDecoderCallback decode) {
    final chunks = StreamController<ImageChunkEvent>();
    final source = SvgSourceLoader.instance
        .networkBytes(
          url,
          headers: headers,
          onBytesReceived: (loaded, total) => chunks.add(
            ImageChunkEvent(
              cumulativeBytesLoaded: loaded,
              expectedTotalBytes: total,
            ),
          ),
        )
        .whenComplete(() => unawaited(chunks.close()));
    return _svgImageStreamCompleter(
      sourceFuture: source,
      cacheKey: key,
      decode: decode,
      chunkEvents: chunks.stream,
      width: width,
      height: height,
      colorFilter: colorFilter,
      theme: theme,
      animationFrameRate: animationFrameRate,
    );
  }
}

/// Creates a provider from an SVG or bitmap file on disk. See [StringXvg]'s class doc
/// for the rest of the shared behavior.
///
/// 用磁盘上的 SVG 或位图文件创建 provider。其余共有行为见 [StringXvg] 的类文档。
class FileXvg extends ImageProvider<FileXvg> {
  /// Creates the provider. / 创建 provider。
  const FileXvg(
    this.file, {
    this.width,
    this.height,
    this.colorFilter,
    this.theme,
    this.animationFrameRate = _defaultAnimationFrameRate,
  });

  /// SVG or bitmap file to load. / 要加载的 SVG 或位图文件。
  final File file;

  /// Target raster width; see [StringXvg]'s class doc for the full resolution order.
  ///
  /// 目标光栅宽度；完整的解析优先级见 [StringXvg] 类文档。
  final double? width;

  /// Target raster height; see [StringXvg]'s class doc for the full resolution order.
  ///
  /// 目标光栅高度；完整的解析优先级见 [StringXvg] 类文档。
  final double? height;

  /// SVG recolor filter; ignored for bitmaps.
  ///
  /// SVG 重着色滤镜；位图忽略此参数。
  final ColorFilter? colorFilter;

  /// Theme controlling `currentColor`. / 控制 `currentColor` 的主题。
  final XvgTheme? theme;

  /// How often an animated source re-rasterizes, in frames per second — see
  /// [StringXvg]'s class doc for why this exists and defaults below 60.
  ///
  /// 动画源重新光栅化的频率（帧/秒）——为什么存在、为什么默认低于 60，见
  /// [StringXvg] 类文档。
  final int animationFrameRate;

  @override
  Future<FileXvg> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<FileXvg>(this);

  @override
  bool operator ==(Object other) =>
      other is FileXvg &&
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

  /// Loads SVG or native bitmap bytes. / 加载 SVG 或原生位图字节。
  @override
  ImageStreamCompleter loadImage(FileXvg key, ImageDecoderCallback decode) =>
      _svgImageStreamCompleter(
        sourceFuture: SvgSourceLoader.instance
            .fileBytes(file)
            .then((bytes) => SvgSourceBytes(bytes)),
        cacheKey: key,
        decode: decode,
        width: width,
        height: height,
        colorFilter: colorFilter,
        theme: theme,
        animationFrameRate: animationFrameRate,
      );
}

/// Creates a provider from SVG (UTF-8) or native bitmap bytes in memory. See [StringXvg]'s class doc for the rest of the shared behavior.
///
/// 用内存中的 SVG（UTF-8）或原生位图字节创建 provider。其余共有行为见
/// [StringXvg] 的类文档。
class MemoryXvg extends ImageProvider<MemoryXvg> {
  /// Creates the provider. / 创建 provider。
  const MemoryXvg(
    this.bytes, {
    this.width,
    this.height,
    this.colorFilter,
    this.theme,
    this.animationFrameRate = _defaultAnimationFrameRate,
  });

  /// SVG (UTF-8) or native bitmap bytes. / SVG（UTF-8）或原生位图字节。
  final Uint8List bytes;

  /// Target raster width; see [StringXvg]'s class doc for the full resolution order.
  ///
  /// 目标光栅宽度；完整的解析优先级见 [StringXvg] 类文档。
  final double? width;

  /// Target raster height; see [StringXvg]'s class doc for the full resolution order.
  ///
  /// 目标光栅高度；完整的解析优先级见 [StringXvg] 类文档。
  final double? height;

  /// SVG recolor filter; ignored for bitmaps.
  ///
  /// SVG 重着色滤镜；位图忽略此参数。
  final ColorFilter? colorFilter;

  /// Theme controlling `currentColor`. / 控制 `currentColor` 的主题。
  final XvgTheme? theme;

  /// How often an animated source re-rasterizes, in frames per second — see
  /// [StringXvg]'s class doc for why this exists and defaults below 60.
  ///
  /// 动画源重新光栅化的频率（帧/秒）——为什么存在、为什么默认低于 60，见
  /// [StringXvg] 类文档。
  final int animationFrameRate;

  @override
  Future<MemoryXvg> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<MemoryXvg>(this);

  @override
  bool operator ==(Object other) =>
      other is MemoryXvg &&
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
  int get hashCode =>
      Object.hash(bytes, width, height, colorFilter, theme, animationFrameRate);

  /// Loads SVG or native bitmap bytes. / 加载 SVG 或原生位图字节。
  @override
  ImageStreamCompleter loadImage(MemoryXvg key, ImageDecoderCallback decode) =>
      _svgImageStreamCompleter(
        sourceFuture: SynchronousFuture<SvgSourceBytes>(SvgSourceBytes(bytes)),
        cacheKey: key,
        decode: decode,
        width: width,
        height: height,
        colorFilter: colorFilter,
        theme: theme,
        animationFrameRate: animationFrameRate,
      );
}

/// Sniffs loaded bytes, preserving Flutter's bitmap decode callback.
/// 嗅探已加载字节，并保留 Flutter 的位图解码回调。
ImageStreamCompleter _svgImageStreamCompleter({
  required Future<SvgSourceBytes> sourceFuture,
  required Object cacheKey,
  required ImageDecoderCallback decode,
  Stream<ImageChunkEvent>? chunkEvents,
  required double? width,
  required double? height,
  required ColorFilter? colorFilter,
  required XvgTheme? theme,
  required int animationFrameRate,
}) => _SourceImageStreamCompleter(
  sourceFuture: sourceFuture,
  cacheKey: cacheKey,
  decode: decode,
  chunkEvents: chunkEvents,
  svgCompleter: (source) => _SvgImageStreamCompleter(
    sourceFuture: SynchronousFuture<String>(source),
    width: width,
    height: height,
    colorFilter: colorFilter,
    theme: theme,
    animationFrameRate: animationFrameRate,
  ),
);

/// Forwards a byte-selected SVG or native stream while preserving ownership.
/// The private inner keepAlive belongs to this outer stream, so ImageCache's
/// outer handles preserve decoded state without keeping animation listeners.
/// 转发按字节选择的 SVG 或原生图像流并管理所有权；内层 keepAlive 归外层所有，
/// ImageCache 的外层句柄因此保留解码状态，但不会让无监听动画继续播放。
class _SourceImageStreamCompleter extends ImageStreamCompleter {
  /// Begins loading without committing to a decoder. / 开始加载，稍后选择解码器。
  _SourceImageStreamCompleter({
    required Future<SvgSourceBytes> sourceFuture,
    required this.cacheKey,
    required ImageDecoderCallback decode,
    required ImageStreamCompleter Function(String) svgCompleter,
    Stream<ImageChunkEvent>? chunkEvents,
  }) {
    _listener = ImageStreamListener(
      _forwardImage,
      onChunk: _forwardChunk,
      onError: _forwardError,
    );
    _chunks = chunkEvents?.listen(_forwardChunk, onError: _forwardError);
    unawaited(_load(sourceFuture, decode, svgCompleter));
  }

  /// Provider key evicted after loading or rendering errors. / 出错后移除的 provider 键。
  final Object cacheKey;

  /// Selected decoder stream. / 选定的解码流。
  ImageStreamCompleter? _inner;

  /// Owns the inner stream throughout this stream's lifetime. / 随外层寿命持有内层。
  ImageStreamCompleterHandle? _innerHandle;

  /// Non-owning reference to the image owned by setImage, used to skip replay.
  /// 非所有权引用，图像归 setImage 持有，仅用于跳过内层重复补发。
  ImageInfo? _forwardedImage;

  /// Single forwarding subscription. / 唯一转发监听者。
  late final ImageStreamListener _listener;

  /// Loading progress subscription. / 加载进度订阅。
  StreamSubscription<ImageChunkEvent>? _chunks;

  /// Whether the inner listener is currently attached. / 是否已挂上内层监听者。
  bool _attached = false;

  /// Whether this outer stream has been disposed. / 外层是否已销毁。
  bool _disposed = false;

  /// Loads and selects a stream; a late codec is disposed before publication.
  /// 加载并选择图像流；销毁后才完成的 codec 直接释放。
  Future<void> _load(
    Future<SvgSourceBytes> sourceFuture,
    ImageDecoderCallback decode,
    ImageStreamCompleter Function(String) svgCompleter,
  ) async {
    try {
      final source = await sourceFuture;
      if (_disposed) return;
      final ImageStreamCompleter inner;
      if (isSvgSource(source.bytes, contentType: source.contentType)) {
        inner = svgCompleter(utf8.decode(source.bytes));
      } else {
        // The supplied callback owns the buffer, including ResizeImage sizing.
        // 传入回调拥有 buffer，并应用 ResizeImage 的解码尺寸。
        final codec = await decode(
          await ui.ImmutableBuffer.fromUint8List(source.bytes),
        );
        if (_disposed) {
          codec.dispose();
          return;
        }
        inner = MultiFrameImageStreamCompleter(
          codec: SynchronousFuture<ui.Codec>(codec),
          scale: 1,
        );
      }
      _inner = inner;
      _innerHandle = inner.keepAlive();
      if (hasListeners) _attach();
    } catch (error, stack) {
      _forwardError(error, stack);
    }
  }

  /// Attaches once, allowing synchronous image delivery and reentrant disposal.
  /// 只挂载一次，允许同步交付图像和重入销毁。
  void _attach() {
    if (_disposed || _attached || !hasListeners || _inner == null) return;
    _attached = true;
    _inner!.addListener(_listener);
  }

  /// Pauses the decoder without releasing its cached state. / 暂停解码且保留缓存状态。
  void _detach() {
    if (!_attached) return;
    _attached = false;
    _inner!.removeListener(_listener);
  }

  /// Takes ownership of the clone supplied to an inner listener.
  /// 接管内层为监听回调克隆的 ImageInfo，setImage 再为外层监听者克隆。
  void _forwardImage(ImageInfo image, bool synchronousCall) {
    if (_disposed || !hasListeners) {
      image.dispose();
      return;
    }
    final previous = _forwardedImage;
    if (synchronousCall && previous != null && image.isCloneOf(previous)) {
      image.dispose();
      return;
    }
    _forwardedImage = image;
    setImage(image);
  }

  /// Relays byte progress while alive. / 存活时转发字节进度。
  void _forwardChunk(ImageChunkEvent event) {
    if (!_disposed) reportImageChunkEvent(event);
  }

  /// Preserves the original decoder or transport error. / 保留原始解码或传输错误。
  void _forwardError(Object error, StackTrace? stack) {
    if (_disposed) return;
    // Let ImageCache register pending entries before allowing a fresh retry.
    // 等 ImageCache 登记在途条目后再移除，使下次请求可重新加载。
    scheduleMicrotask(() {
      PaintingBinding.instance.imageCache.evict(cacheKey);
    });
    reportError(
      context: ErrorDescription('while loading an SVG or bitmap image'),
      exception: error,
      stack: stack,
    );
  }

  /// Restarts the inner stream for the first active listener. / 首个监听者恢复内层。
  @override
  void addListener(ImageStreamListener listener) {
    super.addListener(listener);
    _attach();
  }

  /// Pauses on every listener cycle. / 每一轮监听周期结束时暂停内层。
  @override
  void removeListener(ImageStreamListener listener) {
    super.removeListener(listener);
    if (!hasListeners && !_disposed) _detach();
  }

  /// Releases the inner stream and loading subscription. / 释放内层图像流与加载订阅。
  @override
  void onDisposed() {
    _disposed = true;
    _forwardedImage = null;
    _detach();
    _innerHandle?.dispose();
    _innerHandle = null;
    _inner = null;
    unawaited(_chunks?.cancel());
    _chunks = null;
    super.onDisposed();
  }
}

/// [ImageStreamCompleter] shared by every SVG [ImageProvider] in this file —
/// resolves the source text, then dispatches to a one-shot static raster or
/// a repeating animated raster loop, whichever the parsed source needs.
///
/// 本文件里每个 SVG [ImageProvider] 共用的 [ImageStreamCompleter]——先解析出
/// 源文本，再按需要分派到一次性静态光栅化或反复执行的动画光栅化循环。
class _SvgImageStreamCompleter extends ImageStreamCompleter {
  /// Resolves SVG text and initializes its renderer. / 解析 SVG 文本并初始化渲染器。
  _SvgImageStreamCompleter({
    required Future<String> sourceFuture,
    required this.width,
    required this.height,
    required this.colorFilter,
    required this.theme,
    required this.animationFrameRate,
  }) {
    Future<String>.value(sourceFuture)
        .then((source) {
          if (!_disposed) _start(source);
        })
        .catchError((Object error, StackTrace stack) {
          _report(error, stack);
        });
  }

  /// Logical SVG width. / SVG 逻辑宽度。
  final double? width;

  /// Logical SVG height. / SVG 逻辑高度。
  final double? height;

  /// Filter baked into SVG pixels. / 烘焙到 SVG 像素中的滤镜。
  final ColorFilter? colorFilter;

  /// SVG currentColor theme. / SVG currentColor 主题。
  final XvgTheme? theme;

  /// Maximum SVG animation sampling rate. / SVG 动画的最高采样帧率。
  final int animationFrameRate;

  /// Timer that requests the next app frame. / 请求下一应用帧的定时器。
  Timer? _timer;

  /// Cancellable app-frame request. / 可取消的应用帧请求。
  int? _frameCallbackId;

  /// Whether the completer is disposed. / 补全器是否已销毁。
  bool _disposed = false;

  /// Prevents overlapping rasterization futures. / 阻止光栅化 Future 重叠。
  bool _rendering = false;

  /// Invalidates in-flight images across listener pauses. / 监听暂停时使在途图像失效。
  int _listenerGeneration = 0;

  /// Accumulated scheduler time, excluding pauses. / 排除暂停的累计调度虚拟时间。
  Duration _elapsed = Duration.zero;

  /// Previous vsync timestamp, already adjusted by timeDilation.
  /// 上一 vsync 时间戳，SchedulerBinding 已应用 timeDilation。
  Duration? _lastFrameTimestamp;

  /// Nominal virtual sampling interval. / 虚拟采样的标称间隔。
  Duration _interval = Duration.zero;

  /// True only after the finite document's final frame was published.
  /// 有限文档的末帧成功发布后才为 true。
  bool _settled = false;

  /// Animated rendering continuation; null for static sources.
  /// 动画渲染续体；静态源为 null。
  Future<void> Function()? _renderNextFrame;

  /// Painter clock owned by this stream. / 本图像流持有的画笔时钟。
  ValueNotifier<Duration>? _clock;

  /// Reports loading/rendering errors while this completer is alive.
  /// 在补全器存活时报告加载或渲染错误。
  void _report(Object error, StackTrace stack) {
    if (_disposed) return;
    reportError(
      context: ErrorDescription('while loading or rendering an SVG image'),
      exception: error,
      stack: stack,
    );
  }

  /// Publishes a current frame, returning whether ownership was transferred.
  /// 发布仍有效的当前帧，返回是否已转移图像所有权。
  bool _publish(ui.Image image, double scale, int generation) {
    if (_disposed || !hasListeners || generation != _listenerGeneration) {
      image.dispose();
      return false;
    }
    setImage(ImageInfo(image: image, scale: scale));
    return true;
  }

  /// Cancels scheduled work and forgets the wall-time baseline.
  /// 取消已排队工作并清空墙钟基线。
  void _pause() {
    _listenerGeneration++;
    _timer?.cancel();
    _timer = null;
    final callbackId = _frameCallbackId;
    if (callbackId != null) {
      SchedulerBinding.instance.cancelFrameCallbackWithId(callbackId);
      _frameCallbackId = null;
    }
    _lastFrameTimestamp = null;
  }

  /// Resumes from the last virtual time for the first listener.
  /// 首个监听者从上次虚拟时间恢复。
  @override
  void addListener(ImageStreamListener listener) {
    final wasPaused = !hasListeners;
    super.addListener(listener);
    if (wasPaused && !_disposed && hasListeners && !_settled) {
      final render = _renderNextFrame;
      if (render != null && !_rendering) unawaited(render());
    }
  }

  /// Pauses after each last listener, including repeated keepAlive cycles.
  /// 每轮最后一个监听者离开时暂停，包括重复的 keepAlive 周期。
  @override
  void removeListener(ImageStreamListener listener) {
    super.removeListener(listener);
    if (!hasListeners && !_disposed) _pause();
  }

  /// Routes SVG text to a static or animated renderer. / 将 SVG 文本分流到静态或动画渲染。
  void _start(String source) {
    if (AnimationDetector.hasAnimations(source)) {
      _startAnimated(source);
    } else {
      unawaited(_emitStatic(source));
    }
  }

  /// Rasterizes a static SVG once, retaining it for keepAlive users.
  /// 静态 SVG 只光栅化一次，为 keepAlive 使用者保留结果。
  Future<void> _emitStatic(String source) async {
    try {
      final currentColorArgb = theme?.currentColor.toARGB32();
      final info = await RustXvgPictureCache.instance.getOrRenderAsync(
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
      if (_disposed) {
        image.dispose();
      } else {
        setImage(ImageInfo(image: image, scale: scale));
      }
    } catch (error, stackTrace) {
      _report(error, stackTrace);
    }
  }

  /// Prepares animation resources and renders the initial virtual-time frame.
  /// 准备动画资源并渲染初始虚拟时间帧。
  void _startAnimated(String source) {
    final parsed = XvgDocumentCache.instance.getOrParse(source);
    final document = parsed.document;
    final ready = parsed.hasImages
        ? resolveImageNodes(document)
        : SynchronousFuture<void>(null);
    Future<void>.value(ready)
        .then((_) {
          if (_disposed) return;
          final intrinsicSize = Size(document.width, document.height);
          final (w, h, scale) = _resolveSize(intrinsicSize);
          final clock = _clock = ValueNotifier<Duration>(Duration.zero);
          final painter = AnimatedSvgPainter(
            root: document.root,
            intrinsicSize: intrinsicSize,
            clock: clock,
            theme: theme ?? const XvgTheme(),
            fit: BoxFit.contain,
            alignment: Alignment.center,
            gradients: document.gradients,
            clipPaths: document.clipPaths,
            masks: document.masks,
            backgroundColor: document.backgroundColor,
          );
          _interval = Duration(
            microseconds: (Duration.microsecondsPerSecond / animationFrameRate)
                .round(),
          );

          /// Rasterizes one virtual time; only a delivered final frame settles.
          /// 光栅化一个虚拟时刻；只有已交付的末帧才结束动画。
          Future<void> renderFrame() async {
            if (_rendering || _disposed || !hasListeners || _settled) return;
            _rendering = true;
            final generation = _listenerGeneration;
            final finishes =
                !document.info.loops && _elapsed >= document.info.settleTime;
            if (finishes) _elapsed = document.info.settleTime;
            try {
              clock.value = _elapsed;
              final image = await _rasterizePainter(painter, w, h, colorFilter);
              if (_publish(image, scale, generation) && finishes) {
                _settled = true;
              }
            } catch (error, stack) {
              _report(error, stack);
            } finally {
              _rendering = false;
              _scheduleNextFrame();
            }
          }

          _renderNextFrame = renderFrame;
          if (hasListeners) unawaited(renderFrame());
        })
        .catchError((Object error, StackTrace stack) {
          _report(error, stack);
        });
  }

  /// Waits a dilated interval before requesting vsync, matching Flutter's
  /// multi-frame decoder; no rasterization occurs while frames are suspended.
  /// 按 Flutter 多帧解码器的方式，等待膨胀间隔后请求 vsync；停帧时不光栅化。
  void _scheduleNextFrame() {
    if (_disposed ||
        !hasListeners ||
        _settled ||
        _timer != null ||
        _frameCallbackId != null) {
      return;
    }
    _timer = Timer(_interval * timeDilation, () {
      _timer = null;
      if (_disposed || !hasListeners || _settled) return;
      _frameCallbackId = SchedulerBinding.instance.scheduleFrameCallback(
        _handleAppFrame,
      );
    });
  }

  /// Advances scheduler-adjusted virtual time; long gaps count as one interval.
  /// 推进已由调度器调整的虚拟时间；长间隔只计一个采样间隔。
  void _handleAppFrame(Duration timestamp) {
    _frameCallbackId = null;
    if (_disposed || !hasListeners || _settled) return;
    final previous = _lastFrameTimestamp;
    _lastFrameTimestamp = timestamp;
    final delta = previous == null ? _interval : timestamp - previous;
    _elapsed += delta > _interval * _pauseGapIntervals || delta.isNegative
        ? _interval
        : delta;
    final render = _renderNextFrame;
    if (render != null) unawaited(render());
  }

  /// Resolution order for the *logical* raster size: explicit [width]/[height]
  /// first, an aspect-ratio-derived missing half second, then
  /// [SchedulerBinding]'s primary view as a last resort. The returned pixel
  /// dimensions are that logical size scaled by the view's
  /// `devicePixelRatio`, paired with a matching [ImageInfo.scale] so the
  /// rasterized image is exactly as sharp on a high-DPI display as
  /// [AnimatedXvg]/[StaticXvg] are — painting and [ui.Picture.toImage] both
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
  /// 使光栅化出的图像在高 DPI 屏幕上跟 [AnimatedXvg]/[StaticXvg] 一样清晰——
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
    final views = SchedulerBinding.instance.platformDispatcher.views;
    final view = views.isEmpty ? null : views.first;
    if (w == null || h == null) {
      w ??= view == null
          ? intrinsicSize.width
          : view.physicalSize.width / view.devicePixelRatio;
      h ??= w / aspect;
    }
    // Oversample by [_supersample] beyond the device's own pixel density,
    // then let Flutter's normal (bilinear-filtered) downscale during
    // compositing smooth the result — a supersampling AA pass. This matters
    // specifically because this image comes from `ui.Picture.toImage`, an
    // *offscreen* render target: unlike the main swapchain surface
    // `AnimatedXvg`/`StaticXvg` paint onto directly (which the engine gives
    // MSAA), an ad-hoc offscreen target rasterizes each frame's vector edges
    // single-sample, i.e. aliased, regardless of how correctly its overall
    // pixel *density* matches the device — raising the density alone (the
    // devicePixelRatio multiply above) sharpens blur but does not by itself
    // smooth an edge that was rasterized without any multisampling at all.
    //
    // 在设备自身像素密度之上再超采样 [_supersample] 倍，再让 Flutter 合成阶段
    // 正常的（双线性过滤）降采样把结果磨平——相当于一次超采样抗锯齿。这里之所以
    // 单独需要它：这张图来自 `ui.Picture.toImage`，是一个*离屏*渲染目标——不同于
    // `AnimatedXvg`/`StaticXvg` 直接画上去、引擎会给 MSAA 的主 swapchain 表面，
    // 临时搭建的离屏目标本就按单样本（即有锯齿）光栅化每一帧的矢量边缘，跟它整体
    // 像素*密度*对不对没关系——只把密度提高（上面乘 devicePixelRatio 那步）能让
    // 图像更清晰，但不会让一条压根没做多重采样的边缘变平滑。
    final dpr = (view?.devicePixelRatio ?? 1) * _supersample;
    final pw = w * dpr;
    final ph = h * dpr;
    final largest = pw > ph ? pw : ph;
    final reduction = largest > _maximumRasterDimension
        ? _maximumRasterDimension / largest
        : 1.0;
    final pixelWidth = (pw * reduction).round().clamp(
      1,
      _maximumRasterDimension,
    );
    final pixelHeight = (ph * reduction).round().clamp(
      1,
      _maximumRasterDimension,
    );
    return (pixelWidth, pixelHeight, pixelWidth / w);
  }

  /// Cancels animation work and releases the painter clock. / 取消动画并释放画笔时钟。
  @override
  void onDisposed() {
    _disposed = true;
    _pause();
    _renderNextFrame = null;
    _clock?.dispose();
    _clock = null;
    super.onDisposed();
  }
}

/// Override rasterization to test in-flight ownership and reentrancy.
/// 覆盖光栅化以测试在途图像所有权和重入。
@visibleForTesting
Future<ui.Image> Function(CustomPainter, int, int, ColorFilter?)?
debugSvgRasterize;

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
  final override = debugSvgRasterize;
  if (override != null) return override(painter, width, height, colorFilter);
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final w = width.toDouble();
  final h = height.toDouble();
  if (colorFilter != null) {
    canvas.saveLayer(
      Rect.fromLTWH(0, 0, w, h),
      Paint()..colorFilter = colorFilter,
    );
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
