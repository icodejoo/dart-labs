import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import 'render_svg.dart';
import 'svg_theme.dart';

// Fast path for STATIC svgs: parse + record to a ui.Picture once, cache it by
// (source, theme, colorMapper), then replay the cached picture. Same strategy
// flutter_svg uses (parse → picture → cache → replay), letting full_svg render
// static content without re-parsing on every rebuild or routing through the
// heavier animated painter.
//
// 静态 SVG 快路径：解析并录制成 ui.Picture 一次，按 (source, theme, colorMapper)
// 缓存后重放。与 flutter_svg 同策略（解析→图→缓存→重放），让 full_svg 渲染
// 静态内容时不再每次重建都重解析、也不走更重的动画 painter。

/// Cache key: identical source + theme reuse the same recorded picture.
///
/// 缓存键：source 与 theme 相同即复用同一张录制好的 picture。
@immutable
class _PictureKey {
  const _PictureKey(this.source, this.theme, this.mapperId);

  final String source;
  final SvgTheme? theme;
  final int mapperId;

  @override
  bool operator ==(Object other) =>
      other is _PictureKey &&
      other.source == source &&
      other.theme == theme &&
      other.mapperId == mapperId;

  @override
  int get hashCode => Object.hash(source, theme, mapperId);
}

/// Process-wide LRU cache of recorded static SVG pictures.
///
/// 进程级静态 SVG picture 的 LRU 缓存。
class StaticSvgPictureCache {
  StaticSvgPictureCache._();

  /// Shared instance. / 共享单例。
  static final StaticSvgPictureCache instance = StaticSvgPictureCache._();

  final Map<_PictureKey, PictureInfo> _entries = <_PictureKey, PictureInfo>{};

  /// Max cached pictures before least-recently-used ones are dropped.
  ///
  /// 缓存上限，超出后淘汰最久未用的条目。
  int maximumSize = 200;

  /// Returns a cached picture for [source]/[theme], rendering + caching on miss.
  ///
  /// 返回 [source]/[theme] 对应的缓存 picture，未命中则渲染并缓存。
  PictureInfo getOrRender(
    String source, {
    SvgTheme? theme,
    ColorMapper? colorMapper,
  }) {
    final key = _PictureKey(source, theme, identityHashCode(colorMapper));
    final hit = _entries.remove(key);
    if (hit != null) {
      _entries[key] = hit; // move to most-recently-used
      return hit;
    }
    final info = renderSvgToPicture(
      source,
      theme: theme,
      colorMapper: colorMapper,
    );
    _entries[key] = info;
    // Evict LRU without disposing: a dropped picture may still be painted by a
    // live widget; its native memory is reclaimed by the GC finalizer instead.
    // 淘汰时不 dispose：被丢的 picture 可能仍被在世组件绘制，交给 GC 终结器回收
    // 原生内存，避免 use-after-free。
    if (_entries.length > maximumSize) {
      _entries.remove(_entries.keys.first);
    }
    return info;
  }

  /// Clears the cache (used by tests / low-memory handlers).
  ///
  /// 清空缓存（供测试 / 低内存处理调用）。
  void clear() => _entries.clear();
}

/// Renders a static SVG [source] by replaying a cached [ui.Picture].
///
/// 通过重放缓存的 [ui.Picture] 渲染静态 SVG [source]。
class StaticSvgFast extends StatelessWidget {
  /// Creates the fast static renderer. / 创建静态快路径渲染器。
  const StaticSvgFast({
    super.key,
    required this.source,
    this.width,
    this.height,
    this.fit = BoxFit.contain,
    this.alignment = Alignment.center,
    this.colorFilter,
    this.theme,
    this.colorMapper,
    this.clipToViewBox = true,
    this.clipBehavior = Clip.hardEdge,
    this.semanticsLabel,
    this.excludeFromSemantics = false,
    this.errorBuilder,
  });

  /// Raw SVG markup (static; no `<animate>`). / 原始 SVG（静态，无 `<animate>`）。
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

  /// Theme controlling `currentColor` / font units. / 控制 currentColor / 字体单位的主题。
  final SvgTheme? theme;

  /// Optional color substitution during parse. / 解析期的颜色替换。
  final ColorMapper? colorMapper;

  /// Whether to clip to the viewBox. / 是否按 viewBox 裁剪。
  final bool clipToViewBox;

  /// Clip behavior when clipping. / 裁剪时的行为。
  final Clip clipBehavior;

  /// Semantics label. / 无障碍标签。
  final String? semanticsLabel;

  /// Exclude from the semantics tree. / 从无障碍树中排除。
  final bool excludeFromSemantics;

  /// Builder shown when parsing/recording throws. / 解析/录制抛错时的兜底构建器。
  final Widget Function(BuildContext, Object, StackTrace)? errorBuilder;

  @override
  Widget build(BuildContext context) {
    final PictureInfo info;
    try {
      info = StaticSvgPictureCache.instance.getOrRender(
        source,
        theme: theme,
        colorMapper: colorMapper,
      );
    } catch (error, stackTrace) {
      return errorBuilder?.call(context, error, stackTrace) ??
          SizedBox(width: width, height: height);
    }

    final resolved = alignment.resolve(Directionality.maybeOf(context));
    final w = width ?? info.size.width;
    final h = height ?? info.size.height;

    Widget child = CustomPaint(
      size: Size(w, h),
      painter: _StaticPicturePainter(
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
    if (excludeFromSemantics) {
      child = ExcludeSemantics(child: child);
    } else if (semanticsLabel != null) {
      child = Semantics(label: semanticsLabel, image: true, child: child);
    }
    if (clipToViewBox && clipBehavior != Clip.none) {
      child = ClipRect(clipBehavior: clipBehavior, child: child);
    }
    return RepaintBoundary(child: child);
  }
}

/// Paints a recorded [ui.Picture], scaling from [pictureSize] to the paint box
/// per [fit] and [alignment].
///
/// 绘制录制好的 [ui.Picture]，按 [fit]/[alignment] 从 [pictureSize] 缩放到绘制盒。
class _StaticPicturePainter extends CustomPainter {
  _StaticPicturePainter({
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
  bool shouldRepaint(_StaticPicturePainter old) =>
      old.picture != picture ||
      old.pictureSize != pictureSize ||
      old.fit != fit ||
      old.alignment != alignment;
}
