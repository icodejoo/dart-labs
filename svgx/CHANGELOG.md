## Unreleased

* CSS animation support on the animated path (SVGator CSS exports and a general
  subset): `@keyframes` with `animation` shorthand/longhand, per-keyframe
  `cubic-bezier`/`steps` easing, all four `direction` values, `transform`
  lists, `offset-path` motion, `d: path()` morphing, `fill`/`stroke`/`stop-color`
  and `stroke-dasharray` lists. `Svgx` now routes sources containing
  `@keyframes` to the animated path. `transition-*`, `var()`/`calc()`, and
  SVGator's JS export are not supported.
* Animated path: `fill-rule`/`clip-rule`, `mask-type="alpha"`, two-value
  `feGaussianBlur stdDeviation`, compact arc flags in path data.
* The root `<svg>` `background-color` / `background` (solid colour) is painted
  across the whole canvas on the animated path.
* Fix: `display="none"` is honoured on the animated path; `clip-path` on an
  element with its own `transform` is now applied in the element's coordinate
  system, and so is `mask`.
* Fix: `opacity` is now clamped to `[0, 1]`; `cubic-bezier` easing falls back to
  bisection when Newton's method does not converge.
* Fix (SMIL): `calcMode="discrete"` now splits the duration into `n` equal steps
  so the last value is reachable; trailing `;` in `values`/`keyTimes` no longer
  drops the animation; `begin` accepts ids containing `-` and `begin="indefinite"`
  never starts; an `<animate>` with a missing, `indefinite` or non-positive `dur`
  has no effect instead of overriding the target forever; `NaN`/`Infinity` and
  huge `repeatCount` values no longer make the whole document fail to parse or
  wrap a syncbase `begin` negative; `<set dur="-1s" repeatCount="indefinite">`
  no longer keeps the ticker running.
* Security: the static parser no longer resolves `<image href>` against the
  local file system (or UNC paths). Only embedded `data:` URIs are decoded, so
  an untrusted SVG cannot read files such as `/dev/zero` or probe private
  app directories. Native libraries under `prebuilt/` must be rebuilt for the
  fix to ship.

## 0.1.1

* Docs: completed dartdoc coverage on the full public API surface; README no
  longer compares against `flutter_svg`.

## 0.1.0

Initial release.

* Static SVG rendering via Rust (`usvg`) parsing into a cached `ui.Picture` —
  shapes, gradients, patterns, clip-path, mask, filters (Gaussian blur),
  `currentColor`, embedded base64 images.
* Animated SVG rendering via an original Dart-side SMIL engine (`<animate>`,
  `<animateTransform>`, `<animateMotion>`, `<set>`) — parses once, samples and
  paints every frame in pure Dart, no per-frame FFI crossing.
* `Svgx` dispatches automatically to the static or animated path based on
  whether the source contains SMIL animation markers.
* `SvgxAnimationQuality` for opt-in/opt-out performance trade-offs on the
  animated path (adaptive frame-skipping, mask-as-clip approximation).
