library;

export 'src/rust/api/simple.dart';
export 'src/rust/api/svg.dart'
    show parseSvg, SvgScene, SvgPath, SvgImage, SvgImageFormat;
export 'src/rust/frb_generated.dart' show RustLib;

// Original SMIL animation engine (parse -> timeline -> per-frame sample ->
// paint), see svgx CLAUDE.md architecture decision: animation stays in Dart
// while Rust handles static parsing. Does NOT vendor any third-party engine.
export 'src/animation/animated_svg_widget.dart' show SvgXAnimated;
export 'src/animation/svg_theme.dart' show SvgTheme;

// Rust (usvg) backed static SVG renderer.
export 'src/rust_static_svg.dart' show SvgXStatic, RustSvgPictureCache;

// Primary public API: dispatches to animated (original SMIL engine) or
// static (Rust) rendering.
export 'src/svgx_widget.dart' show SvgX;
