## Unreleased

- **Breaking**: `XvgStatic` renamed to `StaticXvg` and `XvgAnimated` renamed to `AnimatedXvg` (Flutter-style naming; no deprecated aliases). `Xvg` is unchanged.

## 0.2.0

- **Breaking**: `maxFps` renamed to `fps`: null follows global; 0 freezes at the first frame; `double.infinity` is unlimited and ignores global.
- Add `Xvg.fps` for live global animation frame-rate control; external `animation` drivers and static sources are unaffected.
- `Xvg.ensureInitialized({double? fps})` sets the initial global `Xvg.fps` at startup (non-null only, applied on every call).
- Fix: the macOS prebuilt `xvg.framework/xvg` symlink pointed to the old `Versions/Current/svgx` name, and the published archive stored the framework symlinks as plain files, so linking a macOS app failed with `framework 'xvg' not found`. The link now points to `Versions/Current/xvg`, and releases are published from a Linux GitHub Actions job that keeps real symlinks.

## 0.1.3

- Docs: README wording rewritten in plain language.
- Add an experimental Flutter Web demo using Rust wasm, synchronous web initialization, browser source loading, and main-thread SMIL parsing. Native bridge and supported pub platforms remain unchanged.
- Build and deploy the demo under `xvg/demo/`; wasm artifacts are generated in CI and excluded from the pub package.

## 0.1.2

- Docs: new Chinese README (`README.zh-CN.md`); both READMEs gain a detailed `Xvg.string` guide, a complete API reference (caches, animation controller/events, image providers, `RustLib`) and table of contents. Dartdoc added for `XvgPixelSnap` members.
- A static showcase page is published at https://icodejoo.github.io/dart-labs/xvg/ (not part of the package).

## 0.1.1

- **Fix:** 0.1.0 was published without `lib/src/rust/` (the generated flutter_rust_bridge Dart bindings): an unanchored `rust/` rule in `.pubignore` also excluded it, so the package did not compile. The rule now only excludes the top-level `rust/` crate. Use 0.1.1.

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
