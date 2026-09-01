library;

// Advanced/test-only: prefer Svgx.ensureInitialized() to bring up the native
// backend. RustLib itself is exposed for RustLib.initMock()/.dispose() in
// tests that need to inject a fake API or force early teardown.
export 'src/rust/frb_generated.dart' show RustLib;

// Original SMIL animation engine (parse -> timeline -> per-frame sample ->
// paint), see svgx CLAUDE.md architecture decision: animation stays in Dart
// while Rust handles static parsing. Does NOT vendor any third-party engine.
export 'src/animation/animated_svg_widget.dart' show SvgxAnimated;
export 'src/animation/svg_document_cache.dart' show SvgxDocumentCache;
export 'src/animation/svg_theme.dart' show SvgxTheme;
// Opt-out-able, deliberately lossy performance trade-offs for the animated
// path — read its class doc before changing the default, it says exactly what
// fidelity is traded away and at what concurrency.
export 'src/animation/svgx_animation_quality.dart' show SvgxAnimationQuality;

// Rust (usvg) backed static SVG renderer.
export 'src/rust_static_svg.dart' show SvgxStatic, RustSvgxPictureCache;

// ImageProvider bridge (DecorationImage, precacheImage, etc.), mirroring
// AssetImage/NetworkImage/FileImage/MemoryImage — see StringSvgx's class doc
// for the animated-source frame-rate trade-off shared by all five.
export 'src/svg_image_provider.dart'
    show StringSvgx, AssetSvgx, NetworkSvgx, FileSvgx, MemorySvgx;

// Primary public API: dispatches to animated (original SMIL engine) or
// static (Rust) rendering.
export 'src/svgx_widget.dart' show Svgx;
