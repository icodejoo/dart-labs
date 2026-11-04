## Unreleased

* Fix animated group opacity: keep opacity local to each node, multiply nested
  opacity through offscreen group compositing, and composite overlapping fill
  and stroke before fading. Preserve SMIL/CSS opacity animation and single-paint
  alpha fast paths; unify effect order as filter → clip → mask → opacity.
  For nodes with their own transform, open mask/blur layers after the transform:
  blur sigma now scales with that transform, and clip trims the blurred result
  (previously these nodes clipped before blurring).
* Skip zero-opacity nodes and their subtrees for the current sampled frame;
  rendering resumes when animated opacity becomes nonzero. Fold opacity into
  blur layers without an intervening mask and into single-paint geometry leaves
  under eligible single-child wrappers, avoiding unnecessary offscreen layers.

* Parser/CSS/SMIL review fixes: first duplicate id wins; namespaced gradient
  inheritance and stop/animation alignment preserve document order; degenerate
  radial gradients use the final stop; only single source blurs and transparent
  Figma layer-blur prefixes are accepted, while shadow chains remain ignored.
* Normalize paint keywords and px stroke lengths/dash tokens; reject invalid dash
  lists, cap dash expansion at 5000 dash-plus-gap segments (about 2500 drawn
  dashes) and `<use>` instances at 100000 nodes. Preflight each whole instance;
  skip it atomically on budget exhaustion and internally flag `useExpansionTruncated`.
  Preflight uses the same namespace-collapsed href/id attributes as expansion;
  animation elements, unsupported children and unresolved uses share the budget.
* CSS keyframe colors share the parser color hook; runtime `currentColor`, delayed
  backwards fill, and unsupported transform origins/boxes now have explicit
  diagnostics. Two-length pixel transform origins wrap the transform list;
  later transforms still suppress earlier tracks when paused or unsupported.
  Only unknown keyframes, no valid values, zero duration without forwards fill,
  and zero iterations allow earlier transform tracks to survive.
* Bound malformed CSS string/function recovery and memoize descendant selectors;
  ignore unsupported `calc()` and fallback-bearing `var()` declarations while
  preserving earlier CSS values (without applying the fallback). Plain `var()`,
  `env()` and CSS-wide keywords clear accumulated CSS values, falling back to
  presentation attributes and then inherited/default values.
  Detect self-closing/namespaced SMIL and avoid caching large source strings.
* SMIL clocks accept full/partial clocks and h/min/s/ms units. Oversized durations
  saturate at 1e7 seconds and oversized positive begins never start; begin lists
  remain unsupported and fall back to zero offset.

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
