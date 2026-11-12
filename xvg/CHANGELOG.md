## 0.1.0

Initial release.

* Static SVG: Rust (`usvg`) parsing into a cached `ui.Picture` — shapes,
  gradients, patterns, clip-path, mask, filters (Gaussian blur), `currentColor`,
  group/element opacity, embedded base64 images. Only `data:` URIs are decoded;
  `<image href>` never touches the local file system. Reference graphs and CSS
  are bounded to resist amplification attacks; parse untrusted SVG in a
  background isolate.
* Animated SVG: an original Dart-side engine, parsed once and sampled every
  frame with no per-frame FFI crossing.
  * SMIL: `<animate>`, `<animateTransform>`, `<animateMotion>`, `<set>`, clock
    values, begin-value-lists with syncbase/offset instances, restart rules.
  * CSS (SVGator CSS exports and a general subset): `@keyframes`, `animation`
    shorthand/longhand, per-keyframe `cubic-bezier`/`steps`, `transform` lists,
    `offset-path`, `d: path()` morphing, colors and `stroke-dasharray`.
    `transition-*`, `var()`/`calc()` and SVGator's JS export are not supported.
  * Group opacity, nested masks, clip paths, luminance/alpha masks and blur.
* `Xvg` dispatches to the static or animated path based on the source, with
  `string/asset/network/file/memory` constructors. `NetworkXvg`, `AssetXvg`,
  `FileXvg` and `MemoryXvg` sniff bytes and hand bitmaps to Flutter's decoder.
* Playback control: `XvgAnimationController` (play/pause/stop/seek, signed
  rates, once/loop/ping-pong ranges, duration fitting, cues), Flutter
  `Animation` driving via `XvgAnimated.animation`, and element/loop events
  (`onEvent`, CSS `@keyframes` events included). Animations pause while
  `TickerMode` is disabled.
* `XvgDocumentCache` with async parsing in a persistent isolate and `prewarm`.
* `XvgPixelSnap` viewport pixel alignment (`auto`, `always`, `never`).
* `XvgAnimationQuality` performance trade-offs on the animated path.
* Precompiled native libraries ship in the package (Android ×4 ABIs, iOS
  xcframework, macOS framework, Linux x64/arm64, Windows x64/arm64); consumers
  never compile Rust.
