# svgx

High-performance static & animated SVG rendering for Flutter.

## Demo

[icodejoo.github.io/dart-labs/svgx](https://icodejoo.github.io/dart-labs/svgx/) —
a static showcase (feature tour, live SVG previews, and measured performance
numbers). Not a live in-browser Flutter demo: svgx's static path renders
through Rust (`usvg`) via native FFI, which has no web/wasm build here.

* **Static SVG** parses through Rust (`usvg`) into a cached `ui.Picture`, then
  renders with Flutter's own GPU pipeline — no CPU rasterizer.
* **Animated SVG** (SMIL — `<animate>`, `<animateTransform>`,
  `<animateMotion>`, `<set>`) runs through an original Dart-side engine:
  parse once, sample and paint every frame in pure Dart, so no per-frame data
  crosses the Rust FFI boundary.
* One widget, `Svgx`, auto-detects which path a source needs.

## Usage

```dart
import 'package:svgx/svgx.dart';

Svgx.string(
  svgSource,
  width: 48,
  height: 48,
)
```

`Svgx` inspects the source for SMIL and CSS `@keyframes` animation markers and dispatches to the
static or animated renderer accordingly — most callers never need to think
about which path they're on.

### Recoloring

```dart
Svgx.string(
  svgSource,
  width: 24,
  height: 24,
  colorFilter: ColorFilter.mode(Colors.blue, BlendMode.srcIn),
)
```

`colorFilter` applies to both rendering paths. Animated SVGs add a
`ColorFiltered` layer only when a filter is supplied. Theme instances with the
same values compare equal, so rebuilding them preserves image cache reuse.

`Svgx.network` compares sorted header values, and `Svgx.file` compares paths.
Changing the source keeps the previous SVG visible until its replacement loads.
Source loading isolates assets, bundles, files and header variants, and merges
concurrent requests for the same key. HTTP connection and response-header waits
each time out after 30 seconds.

`Svgx.playbackRate` can change while mounted without jumping the timeline.
ImageProvider rasters are uniformly reduced to at most 4096 pixels per side,
with their scale adjusted to preserve logical size.

`currentColor` in the source is controlled separately via `SvgxTheme`, honored
by both the static and animated rendering paths:

```dart
Svgx.string(svgSource, theme: SvgxTheme(currentColor: Colors.blue))
```

### Animation playback

All five `Svgx.string/asset/network/file/memory` entries accept `controller`,
`animation`, `animationSpan`, `autoplay`, `playbackRate`, `maxFps`, `onLoaded`,
`onError`, `errorBuilder`, `onEvent`, `onAnimationStart`, `onAnimationComplete`
and `onAnimationLoop`, alongside `theme`, `quality` and `colorFilter`.

Choose implicit playback (`autoplay: true`, `playbackRate: 1.0` by default),
a shared `SvgxAnimationController`, or a Flutter `Animation<double>`:

```dart
final controller = SvgxAnimationController(autoplay: false);
Svgx.string(svgSource, controller: controller, onLoaded: (info) {
  controller.play();
});
// Also: pause(), stop(), reverse(), seek(Duration), signed playbackRate,
// setRange(start, end, mode: SvgxRangeMode.pingPong), fitDuration(target).
// Dispose caller-owned controllers when their owner is disposed.
```

Static sources ignore animation-only parameters and callbacks, including
`onLoaded` and `onEvent`; they do not attach a controller or animation listener.
`onError` and `errorBuilder` handle both static and animated parse failures.
Static `onError` runs after the frame, once per failed source/theme change.
Asset/network/file loading failures use either supplied handler; callback-only
handling shows an empty sized box. With neither handler, load failures still
propagate to the ambient `ErrorWidget.builder`. `errorBuilder` receives the
original error and stack, as with Flutter images.

The example app's **动画控制** button opens original SMIL demos with playback,
seek, rates, once/loop/ping-pong ranges, duration fitting, a bounded event log,
and a curved Flutter animation driver. No third-party SVG assets are used there.

Drive an SVG with a Flutter `Animation<double>` (including curved animations):

```dart
Svgx.string(
  svgSource,
  animation: myAnimationController,
  animationSpan: const Duration(seconds: 2), // Omit to use naturalDuration.
  onEvent: (event) => debugPrint('$event'), // Element begin/end/repeat and loops.
)
```

Document time is `animation.value × span`: negative times clamp to zero;
positive overshoot may exceed the span. If neither an explicit span nor a
natural duration is known, `onError` / `errorBuilder` / `FlutterError` reports
the failure. `animation` and `controller` are mutually exclusive; leave
`autoplay` and `playbackRate` at their defaults with `animation`. Observe the
driver's `AnimationStatus` for start/completion: svgx emits neither event and
does not call `onAnimationStart` / `onAnimationComplete` in this mode.
`onEvent` works in implicit, controller and animation modes. The driver owns
vsync and TickerMode; these instances bypass shared-clock concurrency and
frame skipping (`maxFps` is ignored). Prefer controller/implicit playback for
many concurrent SVGs. Disposing the supplied Flutter AnimationController
retains the last frame; svgx removes its listener on replacement or unmount.

CSS `@keyframes` also emits begin/end/repeat events with `id` set to the
animation name, once per element and animation declaration across all property
channels; the event has no target-element id, so matching names on multiple
elements each emit a separate event with the same `id`.

### Animation quality

For the animated path, `SvgxAnimationQuality` trades fidelity for throughput
under high concurrency (e.g. a scrolling grid of many animated icons) —
adaptive frame-skipping is the default; see its class doc for the full set of
opt-in/opt-out trade-offs and exactly what each one costs.

```dart
Svgx.string(
  svgSource,
  quality: const SvgxAnimationQuality(),
)
```

### Static-only / animated-only widgets

`SvgxStatic` and `SvgxAnimated` are the two renderers `Svgx` dispatches to,
exported for callers who already know which one they need (e.g. an icon set
known ahead of time to be all-static).

### Migrating mixed-format images

Replace `Image.network(url)` with `Image(image: NetworkSvgx(url))` when a URL
may return SVG or a bitmap. `AssetSvgx`, `FileSvgx` and `MemorySvgx` also detect
SVG bytes and fall back to Flutter's native decoder for PNG/JPEG/GIF/WebP/BMP
and other engine-supported formats, including animated GIF/WebP.
`StringSvgx` remains an SVG markup input. `Svgx.asset/network/file` widgets
keep their existing SVG-only text loading behavior.

```dart
Image(image: NetworkSvgx(url))
Image(image: ResizeImage(NetworkSvgx(url), width: 128))
```

Bitmap decoding honors `ResizeImage`; migrate `Image.network`'s `cacheWidth`
and `cacheHeight` using `ResizeImage.resizeIfNeeded(cacheWidth, cacheHeight,
NetworkSvgx(url))`. Provider `width`/`height` select SVG raster resolution
only; provider `colorFilter`, `theme` and
`animationFrameRate` do not affect bitmaps. Use `Image.color` and
`Image.colorBlendMode` to tint either format. Flutter's `ImageCache` caches
provider results; raw provider bytes do not use the widgets' text LRU.

SVG animations pause without listeners, follow `timeDilation`, and stop at
their final frame for finite documents. Frame gaps exceeding four animation
intervals count as a pause and advance only one interval on resume.
`SvgxAnimationController` does not control ImageProviders. Gzip SVG (`svgz`)
is unsupported: gzip payloads go to the native decoder and retain its error.
Web is unsupported by this native FFI / `dart:io` implementation.

## Notes and limits

* **Static `<image href>`**: only embedded `data:` URIs are decoded. Local
  paths, UNC paths and `file://` are never read, and `data:image/svg+xml` is
  skipped. This is a behavior change from the default `usvg` resolver.
* **SMIL `begin` lists** (`0;a.end+0.2s`) are supported on the animated path.
  Event-based begins (`click`, ...) are not supported.
* **`#rgba`** colors (4-digit hex) are supported on the animated path.
* **Untrusted SVG**: `parse_svg` is a synchronous call and blocks the calling
  thread, so parse untrusted input on a background isolate. Input beyond the
  size/complexity limits throws an error instead of crashing; see
  `doc/animation-engine-features.md` for the limits.

## Design

Static parsing is delegated to `usvg` (the same crate `resvg` builds on), so
static feature coverage tracks a mature, actively-maintained parser rather
than a hand-rolled one. Rendering — static and animated alike — stays on
Flutter's own GPU pipeline; nothing is rasterized on the CPU.

## Status

Actively developed. See `doc/` in the repository for the full acceptance
criteria, supported-feature matrix, and performance benchmark history.

## Contributing

Issues and PRs welcome at the
[repository](https://github.com/icodejoo/dart-labs/tree/main/svgx).
