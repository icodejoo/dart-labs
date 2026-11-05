## Unreleased

**已知阻断(发布前必须处理)**:`SvgScene`/`SvgMask`/`SvgPattern` 的线格式新增了 `commands` 字段。目前只有 Windows x64 预编译库已重编,其余平台(iOS xcframework、macOS framework、Linux x64/arm64、Windows arm64,以及按需核对 Android 四个 ABI)的预编译库必须全平台重编并更新 MANIFEST 后才能发布,否则 SSE 解码错位。

* Add byte sniffing to `NetworkSvgx`, `AssetSvgx`, `FileSvgx` and `MemorySvgx`:
  SVG uses svgx; bitmap and unknown bytes use Flutter's native decoder through
  the supplied decode callback, preserving `ResizeImage` and animated GIF/WebP.
  Bitmap signatures override content type. `StringSvgx` remains SVG text;
  `Svgx.*` widget text loading and its LRU are unchanged. Provider-only SVG
  parameters do not affect bitmaps; gzip SVG (`svgz`) remains unsupported.
* Parse SVG path data into internal pure typed verb/coordinate buffers before
  building `ui.Path`, preserving legacy geometry, tolerant truncation and
  endpoint arcs via `arcToPoint`. Motion-path metrics and sampling are unchanged.
* Align ImageProvider SVG animation rendering with app frames using a
  `timeDilation`-aware timer and scheduler timestamps. Gaps exceeding four
  animation intervals advance only one interval; losing the last listener
  pauses progress. Finite documents render their final frame once and stop.
  `SvgxAnimationController` does not control ImageProviders.

* Add `SvgxAnimated.animation` / `animationSpan` to map Flutter animation values
  to document time without a shared-clock subscription. Negative times clamp
  to zero; positive overshoot is preserved. Unknown natural durations require
  an explicit span and otherwise use the existing loading-error handlers.
  The driver owns start/completion status; svgx emits neither event in this mode.
  The first sync after (re)attaching behaves like a seek, so mounting midway
  does not replay events since zero.
* Add `SvgxAnimated.onEvent` in all three playback modes for element and loop
  events, retaining the no-listener path without per-frame timeline queries.
* Keep `playbackRate` stable through ping-pong reflections using an internal
  direction. `reverse()` reverses current travel; pause/play preserves reflection,
  while selecting or clearing a range resets it to the requested rate direction.

* Forward all animation controls, readiness/error callbacks and playback/element
  events through `Svgx.string/asset/network/file/memory`, with matching constructor
  assertions. Static sources ignore animation-only options; both renderers honor
  `errorBuilder` / `onError`. Asset/network/file load failures use supplied handlers
  and preserve the default ambient `ErrorWidget` behavior when neither is supplied.
* Add an animation-control example page using original SMIL artwork and the
  top-level `Svgx.string` API: playback, seek, signed rates, once/loop/ping-pong
  ranges, duration fitting, recent element events and a curved Flutter driver.
  Cover all five entries, pending-load cleanup and the real page's interactions
  with widget tests.

* Emit CSS `@keyframes` begin/end/repeat events using the animation name as
  `id`, once per element and animation declaration across all property channels.
  Same-named animations on different elements each emit their own events;
  CSS names remain separate from SMIL syncbase ids. Sampling is unchanged.

* Add `SvgxDocumentCache.getOrParseAsync` and sequential, failure-tolerant
  `prewarm`. Image-free sources with at least 128 estimated opening tags use a
  persistent parser isolate with native color/transform checks and shared in-flight work;
  pre-check is a single allocation-free scan.
  Root-isolate-only UI operations retry synchronously and are remembered;
  unavailable workers fall back to synchronous parsing, with a 60-second
  cooldown after initialization or spawn failures. Parse errors propagate.
  `SvgxAnimated` shows a sized placeholder until ready,
  preserves synchronous small-source frames and rejects stale completions.

* Add `SvgxAnimationController` and implicit controllers for `SvgxAnimated`:
  play/pause/stop/seek, finite signed playback rates, reversible completion,
  once/loop/ping-pong ranges, duration fitting, cues and playback/element events.
  Shared controllers use one shared-clock subscription; all attached widgets
  must disable `TickerMode` before their timeline pauses.
  Unbounded reverse playback at zero requires seeking forward or selecting a
  range; the numeric safety ceiling is never used as a restart endpoint.
* Add `SvgxAnimated.controller`, `autoplay`, `onLoaded`, `onError` and
  `errorBuilder`. Parse failures now emit an error and show the error builder
  or a sized empty box; unhandled failures are reported through `FlutterError`.
* Fix animation start offsets: the first subscribed tick preserves the current
  document time exactly. Seek redraws immediately, including while paused.
* Change `onAnimationLoop` to count `settleTime + k * loopPeriod` crossings
  instead of `totalDuration` multiples. Pure indefinite animations now report
  loops when their steady-state period is known (for example, `dur="2s"`).
  A source change resets an implicit controller; an external controller keeps
  its time and adopts the first ready attached document's animation information.
* Upgrade dependencies: usvg 0.49, svgtypes 0.16, flutter_rust_bridge 2.13.
* Fix the static path's root `background-color` offset (only the main tree uses
  the parent group transform; sub-roots keep the old behavior).
* Static path now honors `<g>` and element `opacity`: groups composite as a whole
  via `saveLayer`, `opacity=0` subtrees are skipped, and `opacity=1` adds no
  extra command payload.
* Fix luminance masks ignoring the mask content's own alpha (previously 255).
* Bound mask/pattern command expansion with a budget to prevent amplification OOM.
* Pause animations while `TickerMode` is disabled (covered routes, inactive
  `TabBarView` pages); progress stays continuous on resume. `Offstage` alone
  does not disable `TickerMode`.
* Animated path: per-node style cache compares themes by value, so instances
  sharing one parsed document with equal but distinct `SvgxTheme` objects no
  longer miss the cache every frame.
* Add `SvgxAnimationInfo` (`settleTime`, `loops`, `loopPeriod`,
  `naturalDuration`), computed once at parse time. `loopPeriod` is the LCM of
  indefinite animations' periods (alternate counts twice), null when unknown or
  over 60s — groundwork for the upcoming playback controller.

* Fix CSS Color 4 `#rgba` on the Dart animation path across paint attributes,
  styles, CSS keyframes, gradient stops and SMIL color channels.
* Expand chained `<use>` references while preserving cycle detection, depth
  limits and the existing whole-instance expansion budget.
* SMIL animate on fill/stroke/stop-color of plain elements now interpolates,
  including multisegment values, discrete timing and inherited group paints.
  Animating color does not drive currentColor, which still resolves from theme.
* Support SMIL begin-value-lists with offset/syncbase instances, restart rules,
  freeze and seeded cyclic dependencies. Expand forward loops lazily instead of
  stopping after 64 intervals; keep their Ticker alive. Bound each animation at
  20000 intervals, share document instance/work budgets, and flag the entire
  connected component on truncation. Discard intervals ending at/before zero
  before restart and quotas; omit intervals whose explicit ends all precede begin.
  Restart/end/min/max apply only to components containing a begin list;
  accumulate remains unsupported. Event list items never fire. Preserve the legacy
  single-value/CSS timing paths; cover real Iconify loops and exact SVGator
  CSS frame comparison against HEAD.

* Bound static SVG reference graphs at 32 edges, including all duplicate-id
  candidates, inline URLs, marker shorthand and use/pattern/filter href chains.
  Independently scan CSS using simplecss 0.2.2's token boundaries (functions
  stop at the first closing parenthesis); ambiguous syntax uses document-wide
  expanding-subtree/non-gradient-URL edges, including ordinary subtrees reached
  through weighted use/feImage/pattern/filter references. Common declarations
  and pseudo selectors retain the known tag/id/class and ancestor constraints.
  Remove the sum across independent CSS resource depths, allowing Illustrator
  illustrations with many independent clips/masks/gradients. Keep 4000 approximate
  rules/selectors; allow 8,000,000 element-rule pairs/CSS edges. Reject cumulative
  elements * depth^combinators above 32M; no separate combinator count cap.
  These conservative limits may reject valid large or ambiguous stylesheets.
  Exercise fixed attacks in 1 MiB subprocess stacks: debug 500 seeded CSS
  fragments / 2000 parses, release 3000 / 12000, using a 100-layer CSS chain;
  compare complete SSE bytes with HEAD. Checked CSS resource references use a
  native worker (64-bit 64 MiB; 32-bit 16 MiB); gradient-only CSS
  stays inline. One/two-resource cycles retain upstream behavior. Worker stacks
  cannot recover aborts; mobile, 32-bit and threadless stacks remain unmeasured.
  Debug/release each pass 82 tests (3 existing ignored). Frozen corpus comparison
  covers 11,187 sources / 22,374 parses with identical full SSE and error records;
  no new errors; none of the 142 nonempty styled documents uses the fallback.
  Full-suite observed ranges are about 29–37s debug / 31–51s release,
  depending on host load (higher load can take longer). Preserve the 2880-case
  and two real Illustrator wire snapshots. At the 8M all-matching boundary,
  observed ranges are about 0.9–1.4s release / 4.7–5.3s debug; higher host load
  can take longer. MDI1000's alternating seven-round mean median stays within
  host noise: 14.851 → 14.220 µs (−4.25%; round ranges 13.059–18.104 /
  13.584–17.560 µs).
  parse_svg is synchronous FRB work on the calling thread, usually the UI isolate;
  heavy in-budget inputs have observed ranges of about 0.9–1.4s release /
  4.7–5.3s debug, depending on host load; phones may take longer. Parse untrusted
  SVG in a background isolate. These checks cover the measured corpus and fixed
  cases, not all SVG syntax; see
  doc/animation-engine-features.md for measured limits and remaining risks.

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

* Fix SMIL to-only animations using parse-time underlying numeric/path/colour
  values, including inherited presentation attributes and existing CSS cascade.
  Approximate to-only transforms with per-type identities; other-animation
  composition and by-animations remain unsupported.

* Install element clips before opacity/mask/filter layers in the animated
  renderer, so their composites honor the clip; no offscreen passes added.

* Fix animated luminance masks ignoring content alpha, including opacity and
  color-alpha animations, by compositing onto black within the existing layer.

* Add composition-time SVG viewport pixel alignment with `SvgxPixelSnap.auto`
  (default), `always` and `never` on every widget entry; reuse parsed risk
  metadata and retained pictures under translation and positive scaling.

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
