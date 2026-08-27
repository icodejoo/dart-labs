## 0.1.0

Initial release.

* Static SVG rendering via Rust (`usvg`) parsing into a cached `ui.Picture` —
  shapes, gradients, patterns, clip-path, mask, filters (Gaussian blur),
  `currentColor`, embedded base64 images.
* Animated SVG rendering via an original Dart-side SMIL engine (`<animate>`,
  `<animateTransform>`, `<animateMotion>`, `<set>`) — parses once, samples and
  paints every frame in pure Dart, no per-frame FFI crossing.
* `SvgX` dispatches automatically to the static or animated path based on
  whether the source contains SMIL animation markers.
* `SvgXAnimationQuality` for opt-in/opt-out performance trade-offs on the
  animated path (adaptive frame-skipping, mask-as-clip approximation).
