// Static SVG rendering via the Rust (usvg) parser: parse once through FFI,
// bake the flat display list into a cached ui.Picture, then replay it every
// frame. Mirrors the caching shape of fvendor's static_svg_fast.dart, but the
// parse step is Rust/FFI instead of the pure-Dart parser.
//
// 静态 SVG 渲染，走 Rust（usvg）解析：一次性过 FFI 解析，把扁平显示列表烘焙成
// 缓存的 ui.Picture，之后每帧重放。缓存思路参照 fvendor 的
// static_svg_fast.dart，区别是解析这一步换成 Rust/FFI。

import 'dart:collection';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import 'animation/svg_theme.dart';
import 'rust/api/svg.dart';

/// A recorded static SVG picture plus its intrinsic (viewport) size.
///
/// 录制好的静态 SVG picture，附带其固有（viewport）尺寸。
class RustSvgPictureInfo {
  /// Bundles a recorded [picture] with its intrinsic [size].
  ///
  /// 把录制好的 [picture] 与固有 [size] 打包。
  const RustSvgPictureInfo(this.picture, this.size);

  /// The recorded display list. / 录制好的显示列表。
  final ui.Picture picture;

  /// Intrinsic width/height from the SVG's `width`/`height`/viewBox.
  ///
  /// 来自 SVG `width`/`height`/viewBox 的固有宽高。
  final Size size;
}

/// Process-wide LRU cache of Rust-parsed static SVG pictures, keyed by the
/// raw SVG source string.
///
/// 进程级 LRU 缓存，缓存 Rust 解析出的静态 SVG picture，键为原始 SVG 源串。
class RustSvgPictureCache {
  RustSvgPictureCache._();

  /// Shared instance. / 共享单例。
  static final RustSvgPictureCache instance = RustSvgPictureCache._();

  final LinkedHashMap<(String, int?), RustSvgPictureInfo> _entries =
      LinkedHashMap<(String, int?), RustSvgPictureInfo>();

  /// Max cached pictures before least-recently-used ones are dropped.
  ///
  /// 缓存上限，超出后淘汰最久未用的条目。
  int maximumSize = 200;

  /// Optional hook invoked with the wall-clock time spent on a cache-miss
  /// parse+record. No-op by default (zero overhead); benchmarks/tests may
  /// set this to collect a parse-time distribution.
  ///
  /// 可选钩子：缓存未命中时的解析+录制耗时会回调给它。默认不设置（零开销）；
  /// 基准测试/单测可以设置它来采集解析耗时分布。
  void Function(Duration elapsed)? onParseMiss;

  /// Returns a cached picture for [source], parsing + recording on a miss.
  ///
  /// [currentColorArgb] (0xAARRGGBB) substitutes for `currentColor` in the
  /// source and is part of the cache key, so the same source recolored
  /// differently doesn't collide in the cache.
  ///
  /// Throws whatever the Rust parser / recorder throws on invalid SVG; callers
  /// should catch and fall back to an error widget.
  ///
  /// 返回 [source] 对应的缓存 picture，未命中则解析并录制。
  ///
  /// [currentColorArgb]（0xAARRGGBB）用于替换源中的 `currentColor`，且是缓存键
  /// 的一部分，所以同一源串用不同颜色渲染不会在缓存里互相冲突。
  ///
  /// SVG 非法时会抛出 Rust 解析器/录制过程的异常；调用方应捕获并回退到错误组件。
  RustSvgPictureInfo getOrRender(String source, {int? currentColorArgb}) {
    final key = (source, currentColorArgb);
    final hit = _entries.remove(key);
    if (hit != null) {
      _entries[key] = hit; // move to most-recently-used
      return hit;
    }
    final stopwatch = onParseMiss == null ? null : (Stopwatch()..start());
    final info = _render(source, currentColorArgb);
    if (stopwatch != null) onParseMiss!(stopwatch.elapsed);
    _store(key, info);
    return info;
  }

  /// Returns the already-cached picture for [source]/[currentColorArgb], or
  /// null when it isn't cached — never parses and never records.
  ///
  /// Exists so a widget's `build` can take the warm path without first having
  /// to decide *how* to render on a miss: [SvgXStatic] sniffs the source for
  /// `<image>` (to choose the sync vs async render) only after this returns
  /// null, so a cached icon pays a hash lookup instead of a full regex scan on
  /// every rebuild.
  ///
  /// 返回 [source]/[currentColorArgb] 已缓存的 picture；未缓存时返回 null——
  /// 不解析、不录制。
  ///
  /// 存在的意义是让控件 `build` 走热路径时不必先判断"未命中该怎么渲染"：
  /// [SvgXStatic] 只在本方法返回 null 之后才去嗅探源里的 `<image>`（决定走同步
  /// 还是异步渲染），于是已缓存的图标每次重建只付一次哈希查找，而不是一整趟
  /// 正则扫描。
  ///
  /// Example:
  /// ```dart
  /// final info = RustSvgPictureCache.instance.peek(source);
  /// if (info != null) { /* warm path */ }
  /// ```
  RustSvgPictureInfo? peek(String source, {int? currentColorArgb}) {
    final key = (source, currentColorArgb);
    final hit = _entries.remove(key);
    if (hit == null) return null;
    _entries[key] = hit; // move to most-recently-used
    return hit;
  }

  /// Async counterpart of [getOrRender], for sources whose parsed scene
  /// contains embedded `<image>` bitmaps — decoding those requires
  /// `ui.instantiateImageCodec`, which is async, so this path can't stay
  /// fully synchronous. Sources with no images never hit the async decode
  /// step; callers that don't know in advance can always call this and it
  /// degrades to the same sync work as [getOrRender] wrapped in a
  /// synchronously-resolved [Future].
  ///
  /// [getOrRender] 的异步版本，供解析出的场景含内嵌 `<image>` 位图的源使用——
  /// 解码位图需要 `ui.instantiateImageCodec`，是异步的，这条路径没法保持全同步。
  /// 不含图片的源不会走异步解码这一步；调用方若不确定可以直接调用本方法，
  /// 无图片时会退化为与 [getOrRender] 相同的同步工作，包在一个同步 resolve 的
  /// [Future] 里。
  Future<RustSvgPictureInfo> getOrRenderAsync(
    String source, {
    int? currentColorArgb,
  }) {
    final key = (source, currentColorArgb);
    final hit = _entries.remove(key);
    if (hit != null) {
      _entries[key] = hit;
      return Future<RustSvgPictureInfo>.value(hit);
    }
    // Concurrent callers for the same key join the render already running
    // instead of starting their own. [SvgXStatic] reaches this from `build`
    // via a `FutureBuilder`, and a widget can rebuild many times while a
    // bitmap decode is in flight — each of those rebuilds used to kick off a
    // full parse + decode + record whose picture and decoded `ui.Image` were
    // then overwritten in the cache and orphaned undisposed. Rendering is
    // deterministic in the key, so sharing the one in-flight future is not
    // just cheaper, it is the same answer.
    //
    // 同一个键的并发调用会加入已在进行的渲染，而不是各自再起一次。
    // [SvgXStatic] 是在 `build` 里经 `FutureBuilder` 走到这儿的，而位图解码期间
    // 控件可能重建很多次——过去每一次重建都会重新发起一整趟解析 + 解码 + 录制，
    // 其 picture 与解码出的 `ui.Image` 随后在缓存里被覆盖、成为没人 dispose 的
    // 孤儿。渲染结果由键唯一决定，所以共用同一个在途 future 不只是更省，
    // 答案本来就是同一个。
    final pending = _inFlight[key];
    if (pending != null) return pending;
    final future = _renderAsync(key, source, currentColorArgb);
    _inFlight[key] = future;
    // Deregistration is hung off the future rather than written into
    // `_renderAsync`'s `finally`: an image-free source has no `await` at all,
    // so that `finally` would run *before* the line above and leave the entry
    // (and, through the key, the whole source string) stranded in the map
    // forever. `whenComplete` always defers to a microtask, which is after
    // this synchronous block and before any other caller can get in.
    //
    // 摘除动作挂在 future 上，而不是写进 `_renderAsync` 的 `finally`：无图片的
    // 源整条路径上没有任何 `await`，那个 `finally` 会在上面这行**之前**执行，
    // 于是条目（连同键里那整个源串）会永远卡在表里。`whenComplete` 一定推迟到
    // 一个 microtask，那已经在本同步块之后、且早于任何其它调用方进来。
    future.whenComplete(() {
      if (identical(_inFlight[key], future)) _inFlight.remove(key);
    });
    return future;
  }

  /// In-flight async renders, keyed the same way as [_entries].
  /// 正在进行中的异步渲染，键与 [_entries] 一致。
  final Map<(String, int?), Future<RustSvgPictureInfo>> _inFlight =
      <(String, int?), Future<RustSvgPictureInfo>>{};

  /// Body of [getOrRenderAsync]'s cache-miss path.
  ///
  /// [getOrRenderAsync] 未命中分支的主体。
  Future<RustSvgPictureInfo> _renderAsync(
    (String, int?) key,
    String source,
    int? currentColorArgb,
  ) async {
    final stopwatch = onParseMiss == null ? null : (Stopwatch()..start());
    final scene = parseSvg(data: source, currentColor: currentColorArgb);
    final RustSvgPictureInfo info;
    if (scene.images.isEmpty) {
      info = _recordScene(scene, const []);
    } else {
      final decoded = await Future.wait(scene.images.map(_decodeImage));
      info = _recordScene(scene, decoded);
    }
    if (stopwatch != null) onParseMiss!(stopwatch.elapsed);
    _store(key, info);
    return info;
  }

  /// Decodes one [SvgImage]'s raw bytes into a [ui.Image].
  /// 把 [SvgImage] 的原始字节解码为 [ui.Image]。
  Future<ui.Image> _decodeImage(SvgImage image) async {
    final codec = await ui.instantiateImageCodec(
      Uint8List.fromList(image.data),
    );
    // Disposed as soon as the single frame is out: the codec keeps its own
    // native decode buffers, separate from the returned image, and only one
    // frame is ever requested. Left undisposed they survive until the GC gets
    // round to the finalizer — a cost that shows up in RSS, not in the Dart
    // heap.
    //
    // 取到唯一那一帧后立即 dispose：codec 持有自己的原生解码缓冲，与返回的
    // image 相互独立，而这里只会取一帧。不 dispose 的话它们要等到 GC 处理
    // finalizer 才释放——这笔成本体现在 RSS 上，而不是 Dart heap 上。
    try {
      final frame = await codec.getNextFrame();
      return frame.image;
    } finally {
      codec.dispose();
    }
  }

  /// Inserts [info] under [key], evicting the least-recently-used entry past
  /// [maximumSize]. Shared by the sync and async render paths.
  ///
  /// 把 [info] 存入 [key]，超出 [maximumSize] 时淘汰最久未用条目。
  /// 同步/异步渲染路径共用。
  void _store((String, int?) key, RustSvgPictureInfo info) {
    _entries[key] = info;
    if (_entries.length > maximumSize) {
      _entries.remove(_entries.keys.first);
    }
  }

  /// Clears the cache (used by tests / low-memory handlers).
  ///
  /// 清空缓存（供测试 / 低内存处理调用）。
  void clear() => _entries.clear();

  /// Number of pictures currently held. / 当前缓存的 picture 数量。
  ///
  /// Example:
  /// ```dart
  /// print(RustSvgPictureCache.instance.length);
  /// ```
  int get length => _entries.length;

  /// Approximate native (display-list) bytes held by the cached pictures.
  ///
  /// Sums each [ui.Picture.approximateBytesUsed]. Useful for sizing
  /// [maximumSize] against a real icon set instead of guessing: an entry count
  /// says nothing about cost, since one complex illustration can outweigh
  /// hundreds of icons.
  ///
  /// 缓存中 picture 占用的近似原生（显示列表）字节数。
  ///
  /// 累加各 [ui.Picture.approximateBytesUsed]。用途是拿真实图标集去标定
  /// [maximumSize] 而不是靠猜：条目数说明不了成本，一张复杂插画可能顶几百个图标。
  ///
  /// Example:
  /// ```dart
  /// final mb = RustSvgPictureCache.instance.approximateBytesUsed / 1e6;
  /// ```
  int get approximateBytesUsed {
    var total = 0;
    for (final info in _entries.values) {
      total += info.picture.approximateBytesUsed;
    }
    return total;
  }

  /// Parses [source] via Rust and records the display list into a picture.
  ///
  /// Respects each path's [SvgPath.strokeFirst]: paints stroke before fill
  /// when set (`paint-order="stroke fill"`), otherwise the SVG default of
  /// fill before stroke.
  ///
  /// 用 Rust 解析 [source]，并把显示列表录制成 picture。
  ///
  /// 遵循每个路径的 [SvgPath.strokeFirst]：为 true 时先描边后填充
  /// （`paint-order="stroke fill"`），否则按 SVG 默认的先填充后描边。
  RustSvgPictureInfo _render(String source, int? currentColorArgb) {
    final scene = parseSvg(data: source, currentColor: currentColorArgb);
    // scene.images is expected empty on this sync path — callers that know a
    // source may embed <image> should use getOrRenderAsync instead. If it's
    // non-empty anyway (sync path hit unexpectedly), images are simply
    // skipped here rather than throwing — no silent geometry corruption, and
    // the caller already chose the sync API.
    //
    // 这条同步路径预期 scene.images 为空——已知源可能含 <image> 的调用方应改用
    // getOrRenderAsync。若意外非空（同步路径被误用），这里直接跳过图片而非
    // 抛错——不破坏几何绘制，调用方本就选择了同步 API。
    return _recordScene(scene, const []);
  }

  /// Records [scene]'s images (already-decoded [decodedImages], matched by
  /// index to [SvgScene.images]) then paths into a picture. Images are drawn
  /// before paths — a simplifying z-order assumption, no interleaving with
  /// document order.
  ///
  /// 把 [scene] 的图片（[decodedImages] 已解码，按下标对应 [SvgScene.images]）
  /// 再加路径录制进一张 picture。图片先于路径绘制——简化的 z-order 假设，
  /// 不与文档顺序交错。
  RustSvgPictureInfo _recordScene(
    SvgScene scene,
    List<ui.Image> decodedImages,
  ) {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    for (var i = 0; i < decodedImages.length; i++) {
      final img = scene.images[i];
      canvas.drawImageRect(
        decodedImages[i],
        Rect.fromLTWH(
          0,
          0,
          decodedImages[i].width.toDouble(),
          decodedImages[i].height.toDouble(),
        ),
        Rect.fromLTWH(img.x, img.y, img.width, img.height),
        Paint(),
      );
    }
    for (final path in scene.paths) {
      _paintPath(canvas, path);
    }
    final picture = recorder.endRecording();
    return RustSvgPictureInfo(picture, Size(scene.width, scene.height));
  }

  /// Luminance coefficients used to turn a `<mask>`'s rendered content into
  /// coverage, per SVG's `luminanceToAlpha`.
  ///
  /// Matrix layout and the `dstIn` + [ColorFilter.matrix] technique below are
  /// adapted from `full_svg_flutter` (MIT), file
  /// `benchmark/baseline_f/full_svg_flutter_lib/src/animation/animated_svg_painter_mask_luminance.dart`,
  /// function `_createLuminanceMaskPaint`. That implementation uses the sRGB
  /// coefficients (0.2126/0.7152/0.0722); the values here are SVG 1.1's
  /// `feColorMatrix type="luminanceToAlpha"` constants — the difference is
  /// below one 8-bit level and either is defensible.
  ///
  /// 把 `<mask>` 渲染内容转成覆盖度所用的亮度系数，对应 SVG 的
  /// `luminanceToAlpha`。
  ///
  /// 下面矩阵的排布以及 `dstIn` + [ColorFilter.matrix] 的做法改编自
  /// `full_svg_flutter`（MIT），文件
  /// `benchmark/baseline_f/full_svg_flutter_lib/src/animation/animated_svg_painter_mask_luminance.dart`
  /// 的 `_createLuminanceMaskPaint` 函数。该实现用的是 sRGB 系数
  /// （0.2126/0.7152/0.0722）；这里用的是 SVG 1.1 `feColorMatrix
  /// type="luminanceToAlpha"` 的常量——两者差异小于 8 位色阶的 1，均可接受。
  static const double _luminanceR = 0.2125;
  static const double _luminanceG = 0.7154;
  static const double _luminanceB = 0.0721;

  /// Highest pattern tile resolution, in device pixels per axis. Caps the
  /// `toImageSync` allocation for pathological `<pattern>` tile sizes.
  ///
  /// 图案贴片的最大分辨率（每轴设备像素）。为异常大的 `<pattern>` 贴片尺寸
  /// 兜住 `toImageSync` 的内存分配。
  static const int _maxPatternTilePx = 1024;

  /// Paints one [SvgPath], honoring its inherited clip regions, mask and
  /// Gaussian blur.
  ///
  /// [nested] is set when painting mask content or pattern-tile content: those
  /// sub-display-lists are drawn plainly (no further clip/mask/blur/pattern
  /// recursion) — see svgx CLAUDE.md for the documented limitation.
  ///
  /// 绘制单个 [SvgPath]，并应用其继承的裁剪区域、遮罩与高斯模糊。
  ///
  /// 绘制遮罩内容或图案贴片内容时置 [nested]：这些子显示列表按朴素方式绘制
  /// （不再递归处理裁剪/遮罩/模糊/图案）——限制说明见 svgx CLAUDE.md。
  void _paintPath(Canvas canvas, SvgPath path, {bool nested = false}) {
    final uiPath = _toUiPath(path);
    uiPath.fillType = path.evenOdd
        ? ui.PathFillType.evenOdd
        : ui.PathFillType.nonZero;

    final effects = path.effects;
    final clips = nested
        ? const <SvgClip>[]
        : (effects?.clips ?? const <SvgClip>[]);
    final blur = nested ? null : effects?.blur;
    final mask = nested ? null : effects?.mask;
    final needsSave = clips.isNotEmpty || blur != null || mask != null;

    if (needsSave) canvas.save();
    for (final clip in clips) {
      canvas.clipPath(_toUiClipPath(clip));
    }
    if (blur != null) {
      canvas.saveLayer(
        null,
        Paint()
          ..imageFilter = ui.ImageFilter.blur(
            sigmaX: blur.stdDevX,
            sigmaY: blur.stdDevY,
          ),
      );
    }
    final Rect? maskRect = mask == null
        ? null
        : Rect.fromLTWH(mask.x, mask.y, mask.width, mask.height);
    if (mask != null) {
      canvas
        ..clipRect(maskRect!)
        ..saveLayer(maskRect, Paint());
    }

    void paintFill() {
      if (!path.hasFill) return;
      final shader = _fillShader(path);
      canvas.drawPath(
        uiPath,
        shader != null
            ? (Paint()
                ..style = PaintingStyle.fill
                ..shader = shader)
            : (Paint()
                ..style = PaintingStyle.fill
                ..color = Color(path.fillArgb)),
      );
    }

    void paintStroke() {
      if (!path.hasStroke) return;
      final shader = _strokeShader(path);
      canvas.drawPath(
        uiPath,
        shader != null
            ? (Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = path.strokeWidth
                ..shader = shader)
            : (Paint()
                ..style = PaintingStyle.stroke
                ..color = Color(path.strokeArgb)
                ..strokeWidth = path.strokeWidth),
      );
    }

    if (path.strokeFirst) {
      paintStroke();
      paintFill();
    } else {
      paintFill();
      paintStroke();
    }

    if (mask != null) {
      // Composite the mask's own content as coverage: its luminance (or alpha)
      // becomes the destination layer's alpha via BlendMode.dstIn.
      // 把遮罩自身内容作为覆盖度合成：经 BlendMode.dstIn，其亮度（或 alpha）
      // 成为目标图层的 alpha。
      canvas.saveLayer(maskRect, _maskCoveragePaint(mask.kind));
      for (final maskPath in mask.paths) {
        _paintPath(canvas, maskPath, nested: true);
      }
      canvas
        ..restore()
        ..restore();
    }
    if (blur != null) canvas.restore();
    if (needsSave) canvas.restore();
  }

  /// Paint that turns the layer it wraps into coverage for the layer beneath:
  /// luminance ([kind] 0) or plain alpha ([kind] 1).
  ///
  /// 把所包裹图层转成下层覆盖度的 Paint：亮度（[kind] 为 0）或直接取 alpha
  /// （[kind] 为 1）。
  Paint _maskCoveragePaint(int kind) {
    final paint = Paint()..blendMode = BlendMode.dstIn;
    if (kind == 0) {
      paint.colorFilter = const ColorFilter.matrix(<double>[
        0, 0, 0, 0, 0, //
        0, 0, 0, 0, 0, //
        0, 0, 0, 0, 0, //
        _luminanceR, _luminanceG, _luminanceB, 0, 0,
      ]);
    }
    return paint;
  }

  /// Shader for [path]'s fill: its pattern if it has one, else its gradient,
  /// else null (flat color). / [path] 填充所用的 shader：优先图案，其次渐变，
  /// 都没有则返回 null（纯色）。
  ui.Shader? _fillShader(SvgPath path) {
    final pattern = path.effects?.fillPattern;
    if (pattern != null) return _buildPatternShader(pattern);
    final gradient = path.fillGradient;
    return gradient == null ? null : _buildGradientShader(gradient);
  }

  /// Shader for [path]'s stroke. / [path] 描边所用的 shader。
  ui.Shader? _strokeShader(SvgPath path) {
    final pattern = path.effects?.strokePattern;
    if (pattern != null) return _buildPatternShader(pattern);
    final gradient = path.strokeGradient;
    return gradient == null ? null : _buildGradientShader(gradient);
  }

  /// Rasterizes a [SvgPattern]'s tile into a [ui.Image] and wraps it in a
  /// repeating [ui.ImageShader].
  ///
  /// The tile is recorded at a resolution derived from the pattern→absolute
  /// matrix's scale (capped at [_maxPatternTilePx]) so it stays crisp under
  /// the display list's own scaling, then the shader matrix maps image pixels
  /// back into absolute space.
  ///
  /// 把 [SvgPattern] 的贴片光栅化为 [ui.Image]，包成重复平铺的
  /// [ui.ImageShader]。
  ///
  /// 贴片按图案→绝对空间矩阵的缩放量决定分辨率（上限 [_maxPatternTilePx]），
  /// 以便在显示列表自身缩放下保持清晰；shader 矩阵再把图像像素映射回绝对空间。
  ui.Shader _buildPatternShader(SvgPattern pattern) {
    final m = pattern.matrix;
    final scaleX = _hypot(m[0], m[1]);
    final scaleY = _hypot(m[2], m[3]);
    final pxW = (pattern.width * scaleX).ceil().clamp(1, _maxPatternTilePx);
    final pxH = (pattern.height * scaleY).ceil().clamp(1, _maxPatternTilePx);

    final recorder = ui.PictureRecorder();
    final tileCanvas = Canvas(recorder)
      ..scale(pxW / pattern.width, pxH / pattern.height)
      ..translate(-pattern.x, -pattern.y);
    for (final tilePath in pattern.paths) {
      _paintPath(tileCanvas, tilePath, nested: true);
    }
    // The tile's display list exists only to be rasterized into `image`, and
    // nothing keeps it afterwards — but a dropped `ui.Picture` still holds its
    // native display list until the GC finalizes it. With a `_maxPatternTilePx`
    // tile this pairs with a rasterization of up to 1024x1024x4 bytes, so the
    // recorder is closed out explicitly instead of being left on the finalizer
    // queue.
    //
    // 贴片的显示列表只是为了光栅化成 `image`，之后没人再用——但被丢弃的
    // `ui.Picture` 在 GC 回收 finalizer 之前仍占着原生显示列表。在
    // `_maxPatternTilePx` 上限下它对应一次最大 1024x1024x4 字节的光栅化，
    // 所以这里显式收尾，而不是把它扔进 finalizer 队列。
    final tilePicture = recorder.endRecording();
    final ui.Image image;
    try {
      image = tilePicture.toImageSync(pxW, pxH);
    } finally {
      tilePicture.dispose();
    }

    // image pixels → tile-local → pattern-local → absolute.
    // 图像像素 → 贴片局部 → 图案局部 → 绝对空间。
    final toPatternLocal = _composeAffine(
      <double>[1, 0, 0, 1, pattern.x, pattern.y],
      <double>[pattern.width / pxW, 0, 0, pattern.height / pxH, 0, 0],
    );
    final full = _composeAffine(<double>[
      m[0],
      m[1],
      m[2],
      m[3],
      m[4],
      m[5],
    ], toPatternLocal);
    return ui.ImageShader(
      image,
      TileMode.repeated,
      TileMode.repeated,
      Float64List.fromList(<double>[
        full[0], full[1], 0, 0, //
        full[2], full[3], 0, 0, //
        0, 0, 1, 0, //
        full[4], full[5], 0, 1,
      ]),
    );
  }

  /// `sqrt(a² + b²)`, the magnitude of one affine basis vector.
  /// `sqrt(a² + b²)`，仿射变换某个基向量的模长。
  double _hypot(double a, double b) => math.sqrt(a * a + b * b);

  /// Composes two `[a, b, c, d, e, f]` affines (`x' = a·x + c·y + e`,
  /// `y' = b·x + d·y + f`), returning `first ∘ second` — [second] applies
  /// first, then [first].
  ///
  /// 合成两个 `[a, b, c, d, e, f]` 仿射变换（`x' = a·x + c·y + e`，
  /// `y' = b·x + d·y + f`），返回 `first ∘ second`——先作用 [second]，再作用
  /// [first]。
  List<double> _composeAffine(List<double> first, List<double> second) =>
      <double>[
        first[0] * second[0] + first[2] * second[1],
        first[1] * second[0] + first[3] * second[1],
        first[0] * second[2] + first[2] * second[3],
        first[1] * second[2] + first[3] * second[3],
        first[0] * second[4] + first[2] * second[5] + first[4],
        first[1] * second[4] + first[3] * second[5] + first[5],
      ];

  /// Replays an [SvgClip]'s verbs/points into a [ui.Path] usable with
  /// [Canvas.clipPath]. / 把 [SvgClip] 的动词/坐标重放为可供
  /// [Canvas.clipPath] 使用的 [ui.Path]。
  ui.Path _toUiClipPath(SvgClip clip) {
    final path = _replay(clip.verbs, clip.points);
    path.fillType = clip.evenOdd
        ? ui.PathFillType.evenOdd
        : ui.PathFillType.nonZero;
    return path;
  }

  /// Builds a [ui.Shader] from a resolved [SvgGradient] (linear or radial).
  ///
  /// This was a real gap fixed 2026-08-25: `parse_svg` (`rust/src/api/svg.rs`)
  /// already resolves `<linearGradient>`/`<radialGradient>` fills/strokes into
  /// [SvgPath.fillGradient]/[SvgPath.strokeGradient] with full stop lists, but
  /// this Dart recorder never read those fields — it always painted with
  /// [SvgPath.fillArgb]/[SvgPath.strokeArgb], which `paint_argb` (Rust side)
  /// only ever fills with the gradient's *first* stop color as a fallback.
  /// The result: every gradient fill rendered as a flat single color instead
  /// of a real gradient, even though the Rust side had already done the hard
  /// geometry work.
  ///
  /// Linear: [SvgGradient.x1]/[y1]/[x2]/[y2] are already baked into absolute
  /// space by the Rust side, so they map directly to [ui.Gradient.linear]'s
  /// `from`/`to`. Radial: [x1]/[y1] is the local-space focal point,
  /// [x2]/[y2] the local-space center, [radius] the local-space radius, and
  /// [SvgGradient.matrix] (`[a, b, c, d, e, f]`) is the local→absolute affine
  /// that must be supplied as `matrix4` — see the field docs on
  /// [SvgGradient] (`lib/src/rust/api/svg.dart`) for why radial can't bake
  /// the transform into its endpoints the way linear does.
  ///
  /// 从已解析的 [SvgGradient]（线性或径向）构建 [ui.Shader]。
  ///
  /// 这是 2026-08-25 修复的一个真实缺口：`parse_svg`
  /// （`rust/src/api/svg.rs`）已经把 `<linearGradient>`/`<radialGradient>`
  /// 的填充/描边解析进 [SvgPath.fillGradient]/[SvgPath.strokeGradient]（带完整
  /// 色标列表），但这个 Dart 录制器从未读取过这些字段——一直用
  /// [SvgPath.fillArgb]/[SvgPath.strokeArgb] 绘制，而 Rust 侧的 `paint_argb`
  /// 对渐变只回退取*首个*色标颜色。结果：所有渐变填充都渲染成单一纯色，
  /// 尽管 Rust 侧已经做完了几何解析的硬活。
  ui.Shader _buildGradientShader(SvgGradient gradient) {
    final tileMode = switch (gradient.spread) {
      1 => TileMode.mirror,
      2 => TileMode.repeated,
      _ => TileMode.clamp,
    };
    var colors = gradient.stops.map((s) => Color(s.colorArgb)).toList();
    final stops = gradient.stops.map((s) => s.offset).toList();
    // ui.Gradient requires at least 2 colors; a single-stop gradient (SVG
    // allows this, degenerate as it is) is rendered as that stop's flat
    // color by duplicating it, rather than crashing.
    //
    // ui.Gradient 至少需要 2 个颜色；单色标渐变（SVG 语法允许，虽属退化用法）
    // 通过复制该色标渲染为该颜色的纯色，而非直接崩溃。
    if (colors.length < 2) {
      colors = colors.isEmpty
          ? const [Color(0xFF000000), Color(0xFF000000)]
          : [colors[0], colors[0]];
    }
    if (gradient.kind == 1) {
      final m = gradient.matrix;
      final matrix4 = Float64List.fromList(<double>[
        m[0],
        m[1],
        0,
        0,
        m[2],
        m[3],
        0,
        0,
        0,
        0,
        1,
        0,
        m[4],
        m[5],
        0,
        1,
      ]);
      return ui.Gradient.radial(
        Offset(gradient.x2, gradient.y2),
        gradient.radius,
        colors,
        stops.length >= 2 ? stops : null,
        tileMode,
        matrix4,
        Offset(gradient.x1, gradient.y1),
      );
    }
    return ui.Gradient.linear(
      Offset(gradient.x1, gradient.y1),
      Offset(gradient.x2, gradient.y2),
      colors,
      stops.length >= 2 ? stops : null,
      tileMode,
    );
  }

  /// Replays a flattened [SvgPath]'s verbs/points into a [ui.Path].
  ///
  /// Points are already in absolute space (baked in by Rust via
  /// `abs_transform`), so no additional transform is applied here.
  ///
  /// 把扁平化的 [SvgPath] 动词/坐标重放为 [ui.Path]。点已在绝对空间
  /// （Rust 侧已用 `abs_transform` 烘焙），此处无需再做变换。
  ui.Path _toUiPath(SvgPath path) => _replay(path.verbs, path.points);

  /// Replays a verb/point stream (the encoding shared by [SvgPath] and
  /// [SvgClip]) into a [ui.Path].
  ///
  /// Typed as [Uint8List]/[Float32List] rather than `List<int>`/`List<double>`
  /// on purpose — that is what the FFI bridge actually produces, and reading
  /// through the `List` interface instead makes every element access an
  /// interface call returning a boxed value. An indexed loop is used over
  /// `for (final verb in verbs)` for the same reason: no iterator allocation.
  ///
  /// 刻意声明为 [Uint8List]/[Float32List] 而非 `List<int>`/`List<double>`——
  /// FFI 桥产出的本来就是这两种类型，而经由 `List` 接口读取会让每次元素访问都变成
  /// 一次返回装箱值的接口调用。用带下标的循环而不是 `for (final verb in verbs)`
  /// 也是同一个理由：不分配迭代器。
  ui.Path _replay(Uint8List verbs, Float32List points) {
    final uiPath = ui.Path();
    var i = 0;
    for (var v = 0; v < verbs.length; v++) {
      final verb = verbs[v];
      switch (verb) {
        case 0: // move
          uiPath.moveTo(points[i], points[i + 1]);
          i += 2;
        case 1: // line
          uiPath.lineTo(points[i], points[i + 1]);
          i += 2;
        case 2: // quad
          uiPath.quadraticBezierTo(
            points[i],
            points[i + 1],
            points[i + 2],
            points[i + 3],
          );
          i += 4;
        case 3: // cubic
          uiPath.cubicTo(
            points[i],
            points[i + 1],
            points[i + 2],
            points[i + 3],
            points[i + 4],
            points[i + 5],
          );
          i += 6;
        case 4: // close
          uiPath.close();
        default:
          break;
      }
    }
    return uiPath;
  }
}

/// Renders a static SVG (no animation) through the Rust `usvg` parser.
///
/// Parses [source] once via FFI, caches the resulting [ui.Picture], and
/// replays it on every rebuild. Intended for SVGs without `<animate>`/CSS
/// keyframes — see [SvgX] for the dispatch widget that picks this vs the
/// animated renderer automatically.
///
/// 通过 Rust `usvg` 解析器渲染静态（无动画）SVG。对 [source] 只过一次 FFI 解析，
/// 缓存生成的 [ui.Picture]，此后每次重建直接重放。适用于不含 `<animate>`/CSS
/// keyframes 的 SVG——需要自动判定走哪条渲染路径请用 [SvgX]。
///
/// Example:
/// ```dart
/// SvgXStatic('<svg ...>...</svg>', width: 48, height: 48)
/// ```
class SvgXStatic extends StatelessWidget {
  /// Creates the Rust-backed static SVG renderer. / 创建 Rust 静态 SVG 渲染器。
  const SvgXStatic(
    this.source, {
    super.key,
    this.width,
    this.height,
    this.fit = BoxFit.contain,
    this.alignment = Alignment.center,
    this.colorFilter,
    this.theme,
    this.errorBuilder,
  });

  /// Raw static SVG markup (no `<animate>`). / 原始静态 SVG 源（无 `<animate>`）。
  final String source;

  /// Target width; null uses the SVG's intrinsic width. / 目标宽度，null 用固有宽。
  final double? width;

  /// Target height; null uses the SVG's intrinsic height. / 目标高度，null 用固有高。
  final double? height;

  /// How the picture is inscribed into the box. / picture 如何适配到盒子。
  final BoxFit fit;

  /// Alignment within the box. / 在盒子内的对齐方式。
  final AlignmentGeometry alignment;

  /// Optional recolor filter. / 可选的重着色滤镜。
  final ColorFilter? colorFilter;

  /// Theme controlling `currentColor`; defaults to opaque black. Mirrors
  /// [SvgXAnimated]'s `theme` param for API consistency across the animated
  /// and static paths.
  ///
  /// 控制 `currentColor` 的主题；默认不透明黑色。与 [SvgXAnimated] 的 `theme`
  /// 参数保持一致的 API 形状，覆盖动画与静态两条路径。
  final SvgTheme? theme;

  /// Builder shown when parsing/recording throws (bad SVG, FFI error, etc.).
  ///
  /// 解析/录制抛错时（非法 SVG、FFI 错误等）展示的兜底构建器。
  final Widget Function(BuildContext, Object, StackTrace)? errorBuilder;

  // Cheap syntactic sniff (mirrors AnimationDetector's approach) so the
  // overwhelmingly common no-image case stays on the fully-sync build path
  // with zero added cost — only sources that might embed a bitmap pay for
  // the async branch below.
  //
  // 廉价语法级嗅探（思路同 AnimationDetector），让绝大多数无图片的场景保持
  // 全同步 build 路径、零额外开销——只有可能内嵌位图的源才走下面的异步分支。
  static final RegExp _imagePattern = RegExp(
    r'<image[\s>]',
    caseSensitive: false,
  );

  @override
  Widget build(BuildContext context) {
    final currentColorArgb = theme?.currentColor.toARGB32();
    // "Cheap" is relative: a regex that finds no match has to scan the whole
    // source, and during a scroll every visible icon rebuilds repeatedly while
    // its picture is already cached. So the cache lookup goes first and the
    // sniff only runs on a genuine miss (measured with `LIB=micro`: the sniff
    // costs 0.287us per icon, the lookup it replaces 0.079us).
    //
    // "廉价"是相对的：匹配不到的正则必须扫完整个源，而滚动过程中每个可见图标
    // 会在 picture 已缓存的情况下反复重建。因此先查缓存，只有真正未命中才做
    // 嗅探（`LIB=micro` 实测：嗅探单图标 0.287us，取代它的查找 0.079us）。
    final cached = RustSvgPictureCache.instance.peek(
      source,
      currentColorArgb: currentColorArgb,
    );
    if (cached != null) return _buildFromInfo(context, cached);
    if (!_imagePattern.hasMatch(source)) {
      return _buildSync(context, currentColorArgb);
    }
    return FutureBuilder<RustSvgPictureInfo>(
      future: RustSvgPictureCache.instance.getOrRenderAsync(
        source,
        currentColorArgb: currentColorArgb,
      ),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return errorBuilder?.call(
                context,
                snapshot.error!,
                snapshot.stackTrace ?? StackTrace.empty,
              ) ??
              SizedBox(width: width, height: height);
        }
        if (!snapshot.hasData) {
          // Simple loading placeholder while the bitmap decode is in flight —
          // no dedicated state machine per the task's scope.
          // 位图解码进行中的简单占位——按任务范围不做专门的状态机。
          return SizedBox(width: width, height: height);
        }
        return _buildFromInfo(context, snapshot.data!);
      },
    );
  }

  /// Fully-synchronous build path for sources with no `<image>` tag.
  /// 无 `<image>` 标签源的全同步 build 路径。
  Widget _buildSync(BuildContext context, int? currentColorArgb) {
    final RustSvgPictureInfo info;
    try {
      info = RustSvgPictureCache.instance.getOrRender(
        source,
        currentColorArgb: currentColorArgb,
      );
    } catch (error, stackTrace) {
      return errorBuilder?.call(context, error, stackTrace) ??
          SizedBox(width: width, height: height);
    }
    return _buildFromInfo(context, info);
  }

  /// Shared layout/paint wiring once a [RustSvgPictureInfo] is in hand,
  /// whether it arrived synchronously or via the async image-decode path.
  ///
  /// 拿到 [RustSvgPictureInfo] 之后共用的布局/绘制逻辑，无论它是同步拿到的
  /// 还是走异步图片解码路径拿到的。
  Widget _buildFromInfo(BuildContext context, RustSvgPictureInfo info) {
    final resolved = alignment.resolve(Directionality.maybeOf(context));
    final w = width ?? info.size.width;
    final h = height ?? info.size.height;

    Widget child = CustomPaint(
      size: Size(w, h),
      painter: _RustPicturePainter(
        picture: info.picture,
        pictureSize: info.size,
        fit: fit,
        alignment: resolved,
      ),
    );
    child = SizedBox(width: w, height: h, child: child);
    if (colorFilter != null) {
      child = ColorFiltered(colorFilter: colorFilter!, child: child);
    }
    return RepaintBoundary(child: child);
  }
}

/// Paints a recorded [ui.Picture], scaling from [pictureSize] to the paint
/// box per [fit]/[alignment].
///
/// 绘制录制好的 [ui.Picture]，按 [fit]/[alignment] 从 [pictureSize] 缩放到绘制盒。
class _RustPicturePainter extends CustomPainter {
  _RustPicturePainter({
    required this.picture,
    required this.pictureSize,
    required this.fit,
    required this.alignment,
  });

  final ui.Picture picture;
  final Size pictureSize;
  final BoxFit fit;
  final Alignment alignment;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || pictureSize.isEmpty) return;
    final fitted = applyBoxFit(fit, pictureSize, size);
    final dest = fitted.destination;
    final sx = dest.width / pictureSize.width;
    final sy = dest.height / pictureSize.height;
    final dx = (size.width - dest.width) * ((alignment.x + 1) / 2);
    final dy = (size.height - dest.height) * ((alignment.y + 1) / 2);
    canvas
      ..save()
      ..translate(dx, dy)
      ..scale(sx, sy)
      ..drawPicture(picture)
      ..restore();
  }

  @override
  bool shouldRepaint(_RustPicturePainter old) =>
      old.picture != picture ||
      old.pictureSize != pictureSize ||
      old.fit != fit ||
      old.alignment != alignment;
}
