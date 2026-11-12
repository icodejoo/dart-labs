**English** | [简体中文](README.zh-CN.md)

# xvg

High-performance static & animated SVG rendering for Flutter.

## Contents

* [Demo](#demo)
* [Install](#install)
* [Quick start](#quick-start)
* [`Xvg.string` in depth](#xvgstring-in-depth)
* [Recoloring](#recoloring)
* [Animation playback](#animation-playback)
* [Animation quality](#animation-quality)
* [Static-only / animated-only widgets](#static-only--animated-only-widgets)
* [Migrating mixed-format images (ImageProvider)](#migrating-mixed-format-images)
* [API reference](#api-reference)
* [Notes and limits](#notes-and-limits)

## Demo

[icodejoo.github.io/dart-labs/xvg](https://icodejoo.github.io/dart-labs/xvg/) —
a static showcase page (feature tour, SVG previews, and measured performance).
The [experimental Flutter Web demo](https://icodejoo.github.io/dart-labs/xvg/demo/)
runs real xvg rendering with Rust compiled to wasm and Dart SMIL animation.
The pub package still supports native platforms only: consumers must build and
host wasm separately; no web prebuilt or automatic web setup ships in the package.

To build locally: `dart run tool/build_web.dart` from `xvg/`, then
`flutter build web --release --base-href /dart-labs/xvg/demo/` from `example/`.
Requires nightly-2026-06-24 with wasm32-unknown-unknown and wasm-bindgen-cli matching
Cargo.lock (0.2.130). wasm-opt is optional. Serve the output at that subpath.
Web bridge regeneration: `dart run tool/generate_web_bridge.dart` (FRB 2.13.0).
The script restores native bindings and produces the web sync variant only.
No COOP/COEP headers are required. Network access follows browser CORS rules;
file paths are unsupported. Large animated documents parse on the main thread.

* **Static SVG** parses through Rust (`usvg`) into a cached `ui.Picture`, then
  renders with Flutter's own GPU pipeline — no CPU rasterizer.
* **Animated SVG** (SMIL — `<animate>`, `<animateTransform>`,
  `<animateMotion>`, `<set>` — plus CSS `@keyframes`) runs through an original
  Dart-side engine: parse once, sample and paint every frame in pure Dart, so
  no per-frame data crosses the Rust FFI boundary.
* One widget, `Xvg`, auto-detects which path a source needs.

## Install

```yaml
dependencies:
  xvg: ^0.1.1
```

Bring up the native (Rust) backend once, before the first `Xvg` widget is
built:

```dart
import 'package:flutter/widgets.dart';
import 'package:xvg/xvg.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Xvg.ensureInitialized(); // a no-op after the first successful call
  runApp(const SizedBox.shrink());
}
```

Web is experimental in the source demo; the pub package does not declare web support.

## Quick start

```dart
import 'package:flutter/widgets.dart';
import 'package:xvg/xvg.dart';

const svgSource = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">
  <path d="M5 13l4 4L19 7" fill="none" stroke="currentColor" stroke-width="2"/>
</svg>''';

Widget quickStart() => const Xvg.string(svgSource, width: 48, height: 48);
```

`Xvg` inspects the source for SMIL and CSS `@keyframes` animation markers and
dispatches to the static or animated renderer accordingly — most callers never
need to think about which path they are on.

Five entries share the same rendering parameters:

| Entry | Source | Loading |
| --- | --- | --- |
| `Xvg.string(String)` | SVG markup you already hold | synchronous widget (const-constructible) |
| `Xvg.asset(String)` | asset bundle key (`bundle`, `package` like `AssetImage`) | async, text cached |
| `Xvg.network(String)` | HTTP(S) URL (optional `headers`) | async, text cached, 30 s timeouts |
| `Xvg.file(File)` | file on disk | async, text cached by path |
| `Xvg.memory(Uint8List)` | UTF-8 SVG bytes | synchronous, decoded then forwarded to `Xvg.string` |

## `Xvg.string` in depth

`Xvg.string` is the primitive: every other entry loads or decodes text and then
renders through it. It is the only entry that is a `const`-constructible widget
class (the others are static factory methods returning a `Widget`).

```dart
const Xvg.string(
  String source, {
  Key? key,
  double? width,
  double? height,
  BoxFit fit = BoxFit.contain,
  XvgPixelSnap pixelSnap = XvgPixelSnap.auto,
  Alignment alignment = Alignment.center,
  ColorFilter? colorFilter,
  XvgTheme? theme,
  XvgAnimationQuality? quality,
  XvgAnimationController? controller,
  Animation<double>? animation,
  Duration? animationSpan,
  bool autoplay = true,
  double playbackRate = 1.0,
  double? maxFps,
  ValueChanged<XvgAnimationInfo>? onLoaded,
  void Function(Object error, StackTrace stackTrace)? onError,
  ImageErrorWidgetBuilder? errorBuilder,
  ValueChanged<XvgAnimationEvent>? onEvent,
  VoidCallback? onAnimationStart,
  VoidCallback? onAnimationComplete,
  ValueChanged<int>? onAnimationLoop,
})
```

### Where the source string comes from

Any `String` containing SVG markup works. Typical origins:

**1. A literal or constant.** Best case: the string is created once, and the
widget can be `const`.

```dart
import 'package:flutter/widgets.dart';
import 'package:xvg/xvg.dart';

const _checkIcon = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">
  <path d="M5 13l4 4L19 7" fill="none" stroke="currentColor" stroke-width="2"/>
</svg>''';

Widget checkIcon() => const Xvg.string(_checkIcon, width: 24, height: 24);
```

**2. A variable or generated string.** Useful when part of the markup is
data-driven. Every distinct string is a separate cache entry, so keep the set of
distinct strings small and build each one once (see
[Performance](#caching-and-performance)).

```dart
import 'package:flutter/widgets.dart';
import 'package:xvg/xvg.dart';

String _dotSvg(Color color) {
  final rgb = (color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0');
  return '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">'
      '<circle cx="12" cy="12" r="10" fill="#$rgb"/></svg>';
}

// Built once per color, not inside build().
final _redDot = _dotSvg(const Color(0xFFE53935));

Widget redDot() => Xvg.string(_redDot, width: 16, height: 16);
```

**3. Read from assets, then passed in.** Prefer `Xvg.asset` for the plain case.
Load the text yourself when you need to preprocess it (replace placeholders,
strip a root `width`/`height`, pick a variant) or to keep the string in your own
state.

```dart
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:xvg/xvg.dart';

class AssetStringIcon extends StatefulWidget {
  const AssetStringIcon({super.key});

  @override
  State<AssetStringIcon> createState() => _AssetStringIconState();
}

class _AssetStringIconState extends State<AssetStringIcon> {
  // Created once; a new Future per build would reload on every rebuild.
  late final Future<String> _svg = rootBundle.loadString('assets/logo.svg');

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: _svg,
      builder: (context, snapshot) {
        final svg = snapshot.data;
        if (svg == null) return const SizedBox(width: 48, height: 48);
        return Xvg.string(svg, width: 48, height: 48);
      },
    );
  }
}
```

**4. Downloaded, then passed in.** Prefer `Xvg.network` for a plain GET. Fetch
it yourself when you need custom retry, authentication flows, sanitizing, or
sharing the bytes with other code.

```dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:xvg/xvg.dart';

Future<String> fetchSvg(Uri uri) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(uri);
    final response = await request.close();
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException('HTTP ${response.statusCode}', uri: uri);
    }
    return await response.transform(utf8.decoder).join();
  } finally {
    client.close();
  }
}

class RemoteStringIcon extends StatefulWidget {
  const RemoteStringIcon(this.uri, {super.key});

  final Uri uri;

  @override
  State<RemoteStringIcon> createState() => _RemoteStringIconState();
}

class _RemoteStringIconState extends State<RemoteStringIcon> {
  late Future<String> _svg = fetchSvg(widget.uri);

  @override
  void didUpdateWidget(RemoteStringIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.uri != widget.uri) _svg = fetchSvg(widget.uri);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: _svg,
      builder: (context, snapshot) {
        if (snapshot.hasError) return const Icon(Icons.error_outline);
        final svg = snapshot.data;
        if (svg == null) return const SizedBox(width: 64, height: 64);
        return Xvg.string(svg, width: 64, height: 64);
      },
    );
  }
}
```

**5. Bytes you already hold.** `Xvg.memory(bytes)` decodes UTF-8 and calls
`Xvg.string`; use it for a `Uint8List` from a database or an archive.

### Parameter reference

| Parameter | Default | Effect |
| --- | --- | --- |
| `source` | required | SVG markup. Animation markers decide the renderer when the source changes. |
| `width`, `height` | `null` | Target box. `null` falls back to the SVG's own width/height (or `viewBox`). Give both when the box must not change size while content loads or changes. |
| `fit` | `BoxFit.contain` | How the picture is inscribed in the box (same meaning as `Image.fit`). |
| `alignment` | `Alignment.center` | Where the picture sits in the box when `fit` leaves empty space. Takes `Alignment`, not `AlignmentGeometry`. |
| `colorFilter` | `null` | Flutter `ColorFilter` applied on both paths. Animated sources add a `ColorFiltered` layer only when a filter is supplied. |
| `theme` | `null` | `XvgTheme(currentColor: …)`; resolves the SVG `currentColor` keyword (default opaque black). |
| `pixelSnap` | `XvgPixelSnap.auto` | Composition-time alignment of the viewport to physical pixels. `auto` only for mask/clip documents; `always` / `never` override. |
| `quality` | `null` (uses `XvgAnimationQuality.defaultQuality`) | Animation throughput/fidelity trade-off. Ignored by static sources. |
| `controller` | `null` | Shared `XvgAnimationController`. Mutually exclusive with `animation`; leave `playbackRate` at 1.0 and set the controller's rate instead. |
| `animation` | `null` | Flutter `Animation<double>` drives document time (`value × animationSpan`). |
| `animationSpan` | `null` | Span mapped to `animation`'s 0..1; `null` uses the document's natural duration. |
| `autoplay` | `true` | Start implicit playback (no `controller`/`animation`). Must stay `true` with `animation`. |
| `playbackRate` | `1.0` | Finite signed speed for implicit playback; negative reverses, `0` pauses. Must stay `1.0` with `controller` or `animation`. |
| `maxFps` | `null` | Positive sampling/repaint cap; ignored with `animation`. |
| `onLoaded` | `null` | Animated source (and its embedded images) ready, with `XvgAnimationInfo`. Never called for static sources. |
| `onError` | `null` | Receives load/parse/span failures. Static failures are reported after the frame, once per source/theme change. |
| `errorBuilder` | `null` | Replacement content on failure (`ImageErrorWidgetBuilder`, like `Image.errorBuilder`). |
| `onEvent` | `null` | Playback and element begin/end/repeat events (`XvgAnimationEvent`). |
| `onAnimationStart` / `onAnimationComplete` / `onAnimationLoop` | `null` | First tick / natural finite completion / known loop crossings (iteration starts at one). Not called with `animation`. |

Invalid combinations are `assert`s in debug builds: non-positive `maxFps`,
non-finite `playbackRate`, `controller` together with `animation`, a
non-default `playbackRate` with `controller`, and a non-default `autoplay` or
`playbackRate` with `animation`.

There is intentionally no `semanticsLabel`, `placeholder` or `currentColor`
parameter: see [Accessibility](#accessibility), [Placeholders](#errors-and-placeholders)
and [Recoloring](#recoloring) below.

### Sizing

```dart
import 'package:flutter/widgets.dart';
import 'package:xvg/xvg.dart';

const svgSource = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">'
    '<circle cx="12" cy="12" r="10"/></svg>';

List<Widget> sizingExamples() => const [
  // Intrinsic size from the SVG (width/height attributes, else viewBox).
  Xvg.string(svgSource),
  // Fixed box; the picture is inscribed with BoxFit.contain, centered.
  Xvg.string(svgSource, width: 120, height: 60),
  // Fill the box, cropping the overflow, anchored to the top-left corner.
  Xvg.string(
    svgSource,
    width: 120,
    height: 60,
    fit: BoxFit.cover,
    alignment: Alignment.topLeft,
  ),
];
```

Constraints from the parent still apply: a size larger than the incoming
maximum is clamped, exactly as for a `CustomPaint`.

### `Xvg.string` compared with the other entries

| | `Xvg.string` | `Xvg.asset` / `.network` / `.file` | `Xvg.memory` |
| --- | --- | --- | --- |
| Result type | `Xvg` widget (`const`-able) | `Widget` (private async wrapper) | `Xvg` widget |
| Text available | immediately | after an async load | immediately |
| First frame | content (static: cold parse bounded per frame) | empty `SizedBox(width, height)` until loaded | content |
| Source change | re-detects animation, re-renders | keeps the previous SVG until the new text is loaded | as `Xvg.string` |
| Load failure | not applicable | `onError` / `errorBuilder`, else thrown to `ErrorWidget.builder` | UTF-8 decode failure throws while building |
| Text cache | none of its own; picture/document caches below | additionally an LRU of source text (100 entries, in-memory) | none |
| Same parameters | all of them | all of them (same list) | all of them (same list) |

All five accept exactly the same rendering parameters, so switching source kind
never changes the rest of the call.

### Animated sources

If the string contains SMIL (`<animate>`, `<animateTransform>`, `<animateMotion>`,
`<set>`) or CSS `@keyframes` (case-insensitive, vendor prefixes included) the
source is routed to the Dart-side animation engine and plays automatically:

```dart
import 'package:flutter/widgets.dart';
import 'package:xvg/xvg.dart';

const spinnerSvg = '''
<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24">
  <path fill="currentColor"
        d="M12,4a8,8,0,0,1,7.89,6.7A1.5,1.5,0,0,0,21.38,12h0a1.5,1.5,0,0,0,1.48-1.75,11,11,0,0,0-21.72,0A1.5,1.5,0,0,0,2.62,12h0a1.53,1.53,0,0,0,1.49-1.3A8,8,0,0,1,12,4Z">
    <animateTransform attributeName="transform" type="rotate"
        dur="0.75s" repeatCount="indefinite" values="0 12 12;360 12 12"/>
  </path>
</svg>''';

Widget spinner() => const Xvg.string(
  spinnerSvg,
  width: 32,
  height: 32,
  theme: XvgTheme(currentColor: Color(0xFF1E88E5)),
);
```

Behavior to know:

* Detection is a cheap syntactic sniff, not a semantic check. A static SVG that
  merely contains a `<set>` tag or an unused `@keyframes` rule is still routed to
  the animated engine (it renders correctly, just not on the Rust path).
  Use `XvgStatic` / `XvgAnimated` to pick a path explicitly.
* Animated documents play implicitly (`autoplay: true`, rate `1.0`), follow
  `TickerMode` (paused when every widget using a clock is disabled; `Offstage`
  alone does not pause) and `timeDilation`, and stop on their last frame when
  finite (`fill="freeze"` keeps the end state).
* Use `controller` (shared, seekable) or `animation` (driven by your own Flutter
  `AnimationController`) instead of implicit playback; see
  [Animation playback](#animation-playback).
* `onLoaded`, `onEvent`, `quality`, `maxFps`, `autoplay` and the controller /
  animation / callback parameters only matter for animated sources; a static
  source ignores them and attaches no listeners or controllers.
* `colorFilter` and `theme` work the same on both paths.

### Errors and placeholders

```dart
import 'package:flutter/material.dart';
import 'package:xvg/xvg.dart';

Widget safeIcon(String svg) => Xvg.string(
  svg,
  width: 24,
  height: 24,
  onError: (error, stack) => debugPrint('xvg failed: $error'),
  errorBuilder: (context, error, stack) =>
      const Icon(Icons.broken_image_outlined, size: 24),
);
```

* `errorBuilder` builds the replacement content; `onError` only reports. Give
  either or both.
* **Static source, no handler:** a parse failure renders an empty box of
  `width` x `height` silently. Pass `onError`/`errorBuilder` so a broken
  asset is not mistaken for an invisible icon.
* **Static source, only `onError`:** an empty box is shown and `onError` runs
  after the frame, once per failing source/theme change (not on every rebuild).
* **Animated source, no handler:** the failure is reported through
  `FlutterError.reportError` and an empty box is shown.
* `Xvg.asset` / `.network` / `.file`: load failures call `onError` /
  `errorBuilder`; with neither supplied, the original error is rethrown from
  `build` and reaches `ErrorWidget.builder`. `errorBuilder` receives the original
  error and stack, like `Image`.
* A cold static render that does not fit the current frame's time budget (see
  [caching](#caching-and-performance)) shows an empty `width` x `height` box for a
  frame or two before the picture appears. Sources with an `<image>` tag decode
  asynchronously and show the same empty box meanwhile.
* There is no `placeholder` parameter. For a loading state around your own
  fetch, wrap `Xvg.string` in a `FutureBuilder` as in the samples above; for
  `Xvg.asset/.network/.file` the loading state is the empty sized box, so always
  pass `width`/`height` to avoid layout jumps.

### Accessibility

xvg paints a picture and adds no semantics node. Describe it with Flutter's
own widgets:

```dart
import 'package:flutter/widgets.dart';
import 'package:xvg/xvg.dart';

Widget labelled(String svg) => Semantics(
  label: 'Payment completed',
  image: true,
  child: Xvg.string(svg, width: 48, height: 48),
);

Widget decorative(String svg) =>
    ExcludeSemantics(child: Xvg.string(svg, width: 16, height: 16));
```

### Caching and performance

| Cache | Used by | Key | Policy | Knobs |
| --- | --- | --- | --- | --- |
| `RustXvgPictureCache.instance` | static path | `(source, currentColor ARGB)` | LRU, 200 pictures | `maximumSize`, `clear()`, `length`, `approximateBytesUsed`, `peek`, `getOrRender`, `getOrRenderAsync`, `onParseMiss` |
| `XvgDocumentCache.instance` | animated path | source string | random eviction, 1000 documents; documents with `<image>` are never cached | `maximumSize`, `clear()`, `length`, `getOrParse`, `getOrParseAsync`, `prewarm` |
| source-text LRU | `Xvg.asset/.network/.file` only | key / URL / path | LRU, 100 entries | internal |

```dart
import 'package:flutter/foundation.dart';
import 'package:xvg/xvg.dart';

Future<void> tuneCaches(List<String> bigIllustrations) async {
  // Size the caches against your real icon set, not a guess.
  RustXvgPictureCache.instance.maximumSize = 500;
  XvgDocumentCache.instance.maximumSize = 2000;

  // Measure instead of guessing: entry counts say nothing about cost.
  debugPrint(
    '${RustXvgPictureCache.instance.length} pictures, '
    '${RustXvgPictureCache.instance.approximateBytesUsed} bytes',
  );
  RustXvgPictureCache.instance.onParseMiss = (elapsed) =>
      debugPrint('static cache miss took $elapsed');

  // Warm the animated-document cache off the first-frame path. Failures are
  // ignored here and reported normally when the widget later builds.
  await XvgDocumentCache.instance.prewarm(bigIllustrations);

  // Warm the static cache (synchronous; blocks the calling isolate).
  RustXvgPictureCache.instance.getOrRender(bigIllustrations.first);

  // Low-memory handler.
  RustXvgPictureCache.instance.clear();
  XvgDocumentCache.instance.clear();
}
```

Practical rules:

* **Create strings once.** Cache lookups hash the whole source. A `const`,
  `static final` or field string is hashed once; a new `String` built inside
  `build()` on every frame is rehashed every time, and a source that changes
  per frame (for example an interpolated color) creates a new cache entry per
  distinct value.
* **Recolor with `theme` / `colorFilter`, not by editing the string.**
  `currentColor` variants each cost one cached picture (the theme color is part
  of the key); a `colorFilter` reuses a single picture.
* **Cold static parses run synchronously on the UI isolate**, capped at an
  8 ms budget per frame (`ColdMountFrameBudget`): overflow mounts show an empty
  `width` x `height` box and render in following frames. The first frame of a
  huge, never-seen icon grid is therefore smooth, but give the widgets explicit
  sizes so the empty boxes do not jump. The budget never affects cache hits.
* **Parse untrusted or very large SVG off the UI thread.** The Rust parse call
  is synchronous. For animated documents, `XvgDocumentCache.getOrParseAsync`
  and `prewarm` move large image-free sources to a persistent worker isolate.
* **Many concurrent animated icons:** keep the default
  `XvgAnimationQuality` (adaptive frame skipping above 24 concurrent icons) or
  cap `maxFps`; use `XvgAnimationQuality.exact` for a hero icon that must never
  skip a frame.
* **ImageProvider rasters** use Flutter's `ImageCache`, not these caches.

### Common pitfalls

* Forgetting `await Xvg.ensureInitialized()` before the first widget builds.
* Expecting a web build. The pub package supports native FFI; the source demo has an experimental wasm build.
* A `colorFilter: ColorFilter.mode(color, BlendMode.srcIn)` flattens a
  multi-colored SVG to one color. Use `theme` when only `currentColor` should
  change.
* `stroke="currentColor"` without a `theme` is black. Set
  `theme: XvgTheme(currentColor: …)` or recolor with a filter.
* Passing `controller` and `animation` together, or a custom `playbackRate`
  with them, trips an `assert` (debug) and is a bug in release.
* Static `<image href>` supports only embedded `data:` URIs; local paths,
  `file://` and `data:image/svg+xml` are skipped.
* An empty box where the icon should be usually means a swallowed static parse
  error: add `onError`, or check the SVG against `doc/animation-engine-features.md`.
* Do not put a loading `FutureBuilder`'s `future:` expression inline in
  `build()`; that restarts the load on every rebuild.
* Dispose caller-owned `XvgAnimationController`s with their owner. xvg never
  disposes a controller or `Animation` you pass in.
* Reading an asset with `rootBundle.loadString` for a file that is already an
  asset: just use `Xvg.asset`; it caches the text and keeps the previous image
  while a new asset loads.

## Recoloring

```dart
import 'package:flutter/widgets.dart';
import 'package:xvg/xvg.dart';

const svgSource = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">'
    '<path stroke="currentColor" fill="none" d="M4 12h16"/></svg>';

List<Widget> recolor() => const [
  // Tint everything one color.
  Xvg.string(
    svgSource,
    width: 24,
    height: 24,
    colorFilter: ColorFilter.mode(Color(0xFF1E88E5), BlendMode.srcIn),
  ),
  // Only the `currentColor` keyword changes; other fills keep their colors.
  Xvg.string(
    svgSource,
    width: 24,
    height: 24,
    theme: XvgTheme(currentColor: Color(0xFF1E88E5)),
  ),
];
```

`colorFilter` applies to both rendering paths. Animated SVGs add a
`ColorFiltered` layer only when a filter is supplied. `XvgTheme` instances with
the same value compare equal, so rebuilding them preserves cache reuse.
`currentColor` in the source is controlled via `XvgTheme` on both paths.

`Xvg.network` compares sorted header values, and `Xvg.file` compares paths.
Changing the source keeps the previous SVG visible until its replacement loads.
Source loading isolates assets, bundles, files and header variants, and merges
concurrent requests for the same key. HTTP connection and response-header waits
each time out after 30 seconds.

`pixelSnap: XvgPixelSnap.auto` aligns mask/clip viewports during composition;
`always`/`never` override it on all SVG widget entries (translation and positive
scaling only, visual correction <1 physical pixel; layout, hits and semantics
retain their original positions).

## Animation playback

All five `Xvg.string/asset/network/file/memory` entries accept `controller`,
`animation`, `animationSpan`, `autoplay`, `playbackRate`, `maxFps`, `onLoaded`,
`onError`, `errorBuilder`, `onEvent`, `onAnimationStart`, `onAnimationComplete`
and `onAnimationLoop`, alongside `theme`, `quality` and `colorFilter`.

Choose implicit playback (`autoplay: true`, `playbackRate: 1.0` by default),
a shared `XvgAnimationController`, or a Flutter `Animation<double>`:

```dart
import 'package:flutter/widgets.dart';
import 'package:xvg/xvg.dart';

class ControlledIcon extends StatefulWidget {
  const ControlledIcon(this.svgSource, {super.key});

  final String svgSource;

  @override
  State<ControlledIcon> createState() => _ControlledIconState();
}

class _ControlledIconState extends State<ControlledIcon> {
  final controller = XvgAnimationController(autoplay: false);

  @override
  void dispose() {
    controller.dispose(); // Dispose caller-owned controllers with their owner.
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Xvg.string(
      widget.svgSource,
      controller: controller,
      onLoaded: (info) {
        controller.play();
        // Also: pause(), stop(), reverse(), seek(Duration), signed
        // playbackRate, fitDuration(target),
        controller.setRange(
          Duration.zero,
          info.settleTime,
          mode: XvgRangeMode.pingPong,
        );
      },
    );
  }
}
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
import 'package:flutter/widgets.dart';
import 'package:xvg/xvg.dart';

Widget driven(String svgSource, AnimationController myAnimationController) {
  return Xvg.string(
    svgSource,
    animation: myAnimationController,
    animationSpan: const Duration(seconds: 2), // Omit to use naturalDuration.
    onEvent: (event) => debugPrint('$event'), // Element begin/end/repeat, loops.
  );
}
```

Document time is `animation.value × span`: negative times clamp to zero;
positive overshoot may exceed the span. If neither an explicit span nor a
natural duration is known, `onError` / `errorBuilder` / `FlutterError` reports
the failure. `animation` and `controller` are mutually exclusive; leave
`autoplay` and `playbackRate` at their defaults with `animation`. Observe the
driver's `AnimationStatus` for start/completion: xvg emits neither event and
does not call `onAnimationStart` / `onAnimationComplete` in this mode.
`onEvent` works in implicit, controller and animation modes. The driver owns
vsync and TickerMode; these instances bypass shared-clock concurrency and
frame skipping (`maxFps` is ignored). Prefer controller/implicit playback for
many concurrent SVGs. Disposing the supplied Flutter AnimationController
retains the last frame; xvg removes its listener on replacement or unmount.

`Xvg.playbackRate` can change while mounted without jumping the timeline.

CSS `@keyframes` also emits begin/end/repeat events with `id` set to the
animation name, once per element and animation declaration across all property
channels; the event has no target-element id, so matching names on multiple
elements each emit a separate event with the same `id`.

Listening to events from any controller, without a widget callback:

```dart
import 'package:flutter/foundation.dart';
import 'package:xvg/xvg.dart';

void observe(XvgAnimationController controller) {
  controller.addEventListener((event) {
    switch (event) {
      case XvgAnimationLoaded(:final info):
        debugPrint('ready, natural duration ${info.naturalDuration}');
      case XvgAnimationStarted():
        debugPrint('started');
      case XvgAnimationCompleted(:final natural):
        debugPrint('completed (natural: $natural)');
      case XvgAnimationLooped(:final iteration):
        debugPrint('document loop $iteration');
      case XvgAnimationRangeLooped(:final iteration):
        debugPrint('range wrap $iteration');
      case XvgAnimationElementBegin(:final id):
        debugPrint('element $id began');
      case XvgAnimationElementEnd(:final id):
        debugPrint('element $id ended');
      case XvgAnimationElementRepeat(:final id, :final iteration):
        debugPrint('element $id repeat $iteration');
      case XvgAnimationError(:final error):
        debugPrint('failed: $error');
    }
  });
  controller.addCue(const Duration(seconds: 1), () => debugPrint('t = 1 s'));
}
```

## Animation quality

For the animated path, `XvgAnimationQuality` trades fidelity for throughput
under high concurrency (e.g. a scrolling grid of many animated icons) —
adaptive frame-skipping is the default; see its class doc for the full set of
opt-in/opt-out trade-offs and exactly what each one costs.

```dart
import 'package:flutter/widgets.dart';
import 'package:xvg/xvg.dart';

Widget qualityExamples(String svgSource) {
  // Process-wide default (used when a widget passes no `quality`).
  XvgAnimationQuality.defaultQuality = const XvgAnimationQuality(
    frameSkipThreshold: 8,
    maxFrameDivisor: 3,
  );
  return Column(
    children: [
      Xvg.string(svgSource, quality: const XvgAnimationQuality()),
      // Never degrade this one.
      Xvg.string(svgSource, quality: XvgAnimationQuality.exact),
    ],
  );
}
```

## Static-only / animated-only widgets

`XvgStatic` and `XvgAnimated` are the two renderers `Xvg` dispatches to,
exported for callers who already know which one they need (e.g. an icon set
known ahead of time to be all-static).

```dart
import 'package:flutter/widgets.dart';
import 'package:xvg/xvg.dart';

Widget staticOnly(String svg) => XvgStatic(
  svg,
  width: 24,
  height: 24,
  theme: const XvgTheme(currentColor: Color(0xFF424242)),
  errorBuilder: (context, error, stack) => const SizedBox(width: 24, height: 24),
);

Widget animatedOnly(String svg) =>
    XvgAnimated.string(svg, width: 24, height: 24, maxFps: 30);
```

`XvgStatic` takes no animation or controller parameters and its `alignment` is
an `AlignmentGeometry`; its `errorBuilder` is
`Widget Function(BuildContext, Object, StackTrace)`. `XvgAnimated.string` accepts the
same animation, quality and callback parameters as `Xvg.string`.

## Migrating mixed-format images

Replace `Image.network(url)` with `Image(image: NetworkXvg(url))` when a URL
may return SVG or a bitmap. `AssetXvg`, `FileXvg` and `MemoryXvg` also detect
SVG bytes and fall back to Flutter's native decoder for PNG/JPEG/GIF/WebP/BMP
and other engine-supported formats, including animated GIF/WebP.
`StringXvg` remains an SVG markup input. `Xvg.asset/network/file` widgets
keep their existing SVG-only text loading behavior.

```dart
import 'package:flutter/widgets.dart';
import 'package:xvg/xvg.dart';

Widget providers(String url) => Column(
  children: [
    Image(image: NetworkXvg(url)),
    Image(image: ResizeImage(NetworkXvg(url), width: 128)),
    Image(image: const StringXvg('<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24"/>')),
    DecoratedBox(
      decoration: BoxDecoration(
        image: DecorationImage(
          image: AssetXvg('assets/background.svg', width: 360),
        ),
      ),
      child: const SizedBox(width: 360, height: 200),
    ),
  ],
);
```

Bitmap decoding honors `ResizeImage`; migrate `Image.network`'s `cacheWidth`
and `cacheHeight` using `ResizeImage.resizeIfNeeded(cacheWidth, cacheHeight,
NetworkXvg(url))`. Provider `width`/`height` select SVG raster resolution
only; provider `colorFilter`, `theme` and
`animationFrameRate` do not affect bitmaps. Use `Image.color` and
`Image.colorBlendMode` to tint either format. Flutter's `ImageCache` caches
provider results; raw provider bytes do not use the widgets' text LRU.
ImageProvider rasters are uniformly reduced to at most 4096 pixels per side,
with their scale adjusted to preserve logical size.

SVG animations pause without listeners, follow `timeDilation`, and stop at
their final frame for finite documents. Frame gaps exceeding four animation
intervals count as a pause and advance only one interval on resume.
`XvgAnimationController` does not control ImageProviders. Gzip SVG (`svgz`)
is unsupported: gzip payloads go to the native decoder and retain its error.

## API reference

Everything exported by `package:xvg/xvg.dart`:

| Symbol | Kind | Purpose |
| --- | --- | --- |
| `Xvg` | widget | Dispatching widget. `Xvg.string` constructor; `Xvg.asset`, `Xvg.network`, `Xvg.file`, `Xvg.memory` static factories; `Xvg.ensureInitialized()`. |
| `XvgStatic` | widget | Rust (`usvg`) static renderer. Parameters: `source`, `pixelSnap`, `width`, `height`, `fit`, `alignment`, `colorFilter`, `theme`, `errorBuilder`. |
| `RustXvgPictureCache` | class | Process-wide LRU of recorded static pictures. `instance`, `maximumSize` (200), `onParseMiss`, `getOrRender`, `getOrRenderAsync`, `peek`, `clear`, `length`, `approximateBytesUsed`. |
| `XvgAnimated` | widget | Dart-side SMIL / CSS `@keyframes` renderer. `XvgAnimated.string` with the animation, quality and callback parameters of `Xvg.string`. |
| `XvgDocumentCache` | class | Process-wide cache of parsed animated documents. `instance`, `maximumSize` (1000), `getOrParse`, `getOrParseAsync`, `prewarm`, `clear`, `length`. |
| `XvgTheme` | class | `currentColor` resolution (`const XvgTheme({Color currentColor})`, default black). Value equality. |
| `XvgAnimationInfo` | class | Read-only duration facts: `settleTime`, `loops`, `loopPeriod`, `naturalDuration`. |
| `XvgAnimationController` | class | Shared playback: `XvgAnimationController({autoplay, playbackRate})`; `time`, `status`, `info`, `playbackRate`; `play`, `pause`, `stop`, `seek`, `reverse`, `setRange`, `clearRange`, `fitDuration`; `addCue` / `removeCue`; `addEventListener` / `removeEventListener`; `addListener` / `removeListener`; `dispose`. Its `attach`, `detach`, `setVisible`, `documentLoading`, `documentError` and `driveTo` members are `@internal` plumbing for the widgets. |
| `XvgPlaybackStatus` | enum | `loading`, `playing`, `paused`, `completed`, `error`. |
| `XvgRangeMode` | enum | `once`, `loop`, `pingPong` (range boundary behavior). |
| `XvgAnimationEvent` | sealed class | Base of the events below. |
| `XvgAnimationLoaded`, `XvgAnimationStarted`, `XvgAnimationCompleted`, `XvgAnimationLooped`, `XvgAnimationRangeLooped`, `XvgAnimationElementBegin`, `XvgAnimationElementEnd`, `XvgAnimationElementRepeat`, `XvgAnimationError` | final classes | Playback and element events; carry `info`, `natural`, `iteration`, `id` / `elementId`, `error` / `stack` as applicable. |
| `XvgAnimationQuality` | class | Fidelity/throughput profile: `adaptiveFrameSkipping`, `frameSkipThreshold`, `maxFrameDivisor`, `offscreenLayerFrameDivisor`, `approximateSimpleMasksAsClip`; presets `balanced`, `exact`; global `defaultQuality`. |
| `XvgPixelSnap` | enum | `auto`, `always`, `never` viewport alignment to physical pixels. |
| `StringXvg`, `AssetXvg`, `NetworkXvg`, `FileXvg`, `MemoryXvg` | `ImageProvider`s | For `Image`, `DecorationImage`, `precacheImage`. Common parameters `width`, `height`, `colorFilter`, `theme`, `animationFrameRate` (default 30); plus `source` / `assetName`+`bundle`+`package` / `url`+`headers` / `file` / `bytes`. |
| `RustLib` | class | Generated flutter_rust_bridge entry point, exposed for `RustLib.initMock()` / `RustLib.dispose()` in tests. Prefer `Xvg.ensureInitialized()` to start the backend. |

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
[repository](https://github.com/icodejoo/dart-labs/tree/xvg/xvg).
