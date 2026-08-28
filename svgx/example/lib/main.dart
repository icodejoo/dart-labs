import 'dart:async';

import 'package:flutter/material.dart';
import 'package:svgx/svgx.dart';

// The line-md `confirm_circle` icon SVG source, verbatim. Its `<g>` element
// already uses `fill="none"` (the upstream `fill="currentColor"` bug fixed) so
// the stroke-draw circle + checkmark animation stays visible instead of being
// hidden behind a solid filled disc.
const String kConfirmCircleSvg =
    '<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="24" height="24" preserveAspectRatio="xMidYMid meet" viewBox="0 0 24 24"><g fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" stroke-width="2"><path stroke-dasharray="60" stroke-dashoffset="60" d="M3 12C3 7.02944 7.02944 3 12 3C16.9706 3 21 7.02944 21 12C21 16.9706 16.9706 21 12 21C7.02944 21 3 16.9706 3 12Z"><animate fill="freeze" attributeName="stroke-dashoffset" dur="0.5s" values="60;0"/></path><path stroke-dasharray="14" stroke-dashoffset="14" d="M8 12L11 15L16 10"><animate fill="freeze" attributeName="stroke-dashoffset" begin="0.6s" dur="0.2s" values="14;0"/></path></g></svg>';

// mdi:check-circle — a single filled path, no stroke, no `<animate>`. Proves
// the Rust usvg → display-list → ui.Picture static path end to end.
const String kStaticCheckCircleSvg =
    '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24">'
    '<path fill="#FF7A00" d="M12 2C6.47 2 2 6.47 2 12s4.47 10 10 10 10-4.47 10-10S17.53 2 12 2m-1.94 14.5L5.7 12.11l1.41-1.42l2.95 2.96l6.24-6.25l1.41 1.42z"/>'
    '</svg>';

// svg-spinners `180-ring`, verbatim (Iconify's `svg-spinners` collection —
// icons/180-ring.svg). Proves `<animateTransform type="rotate">` with
// `repeatCount="indefinite"`: the foreground arc rotates 0deg->360deg about
// its own center (12,12) forever, layered over a static translucent ring.
const String kSpinnerSvg =
    '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24">'
    '<path fill="currentColor" d="M12,1A11,11,0,1,0,23,12,11,11,0,0,0,12,1Zm0,19a8,8,0,1,1,8-8A8,8,0,0,1,12,20Z" opacity=".25"/>'
    '<path fill="currentColor" d="M12,4a8,8,0,0,1,7.89,6.7A1.53,1.53,0,0,0,21.38,12h0a1.5,1.5,0,0,0,1.48-1.75,11,11,0,0,0-21.72,0A1.5,1.5,0,0,0,2.62,12h0a1.53,1.53,0,0,0,1.49-1.3A8,8,0,0,1,12,4Z">'
    '<animateTransform attributeName="transform" dur="0.75s" repeatCount="indefinite" type="rotate" values="0 12 12;360 12 12"/>'
    '</path></svg>';

// A synthetic, unambiguous rotation proof: a small square offset to the top
// of the viewBox, orbiting the center forever via `<animateTransform
// type="rotate" repeatCount="indefinite">`. Unlike the subtle opacity
// contrast in a real spinner icon, an off-center marker makes rotation
// impossible to miss frame-to-frame.
const String kRotationMarkerSvg =
    '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24">'
    '<circle cx="12" cy="12" r="10" fill="none" stroke="#DDDDDD" stroke-width="1"/>'
    '<rect x="10" y="1" width="4" height="4" fill="#2A6DF4">'
    '<animateTransform attributeName="transform" dur="2s" repeatCount="indefinite" type="rotate" values="0 12 12;360 12 12"/>'
    '</rect></svg>';

// A static (no `<animate>`) filled path using `currentColor` — exercises the
// Rust static path's new `currentColor` substitution via `SvgXStatic`'s
// `theme` param, resolved through `parse_svg`'s `current_color` FFI arg.
const String kStaticCurrentColorSvg =
    '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24">'
    '<path fill="currentColor" d="M12 2C6.47 2 2 6.47 2 12s4.47 10 10 10 10-4.47 10-10S17.53 2 12 2m-1.94 14.5L5.7 12.11l1.41-1.42l2.95 2.96l6.24-6.25l1.41 1.42z"/>'
    '</svg>';

// A circle with a thick, semi-transparent stroke over an opaque fill.
// Rendered twice below with default paint-order (fill then stroke) vs
// `paint-order="stroke fill"` — the overlap band where stroke crosses fill
// looks visually different depending on which is painted on top.
String _paintOrderCircleSvg({required bool strokeFirst}) =>
    '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24">'
    '<circle cx="12" cy="12" r="8" fill="#2A6DF4" stroke="#FF0000" stroke-opacity="0.5" stroke-width="6"'
    '${strokeFirst ? ' paint-order="stroke fill"' : ''}/>'
    '</svg>';

// --- Feature demos added to visually verify recently-completed engine
// features (see svgx CLAUDE.md "当前动画引擎支持" / static-path notes).
// Each demo is a standalone SVG string exercising exactly one feature.

// 1. `<image>` embedded base64 PNG — a 1x1 red-pixel PNG data URI, scaled up
// to fill the viewBox. Exercises `SvgNodeKind.image` /
// `resolveImageNodes`/`_decodeDataUriImage` on the animated path.
const String kEmbeddedImageSvg =
    '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24">'
    '<image href="data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==" '
    'x="0" y="0" width="24" height="24"/>'
    '</svg>';

// 2. Named CSS colors — `fill="tomato"` / `stroke="cornflowerblue"`.
// Exercises `_normalizeColorAttributes` -> `resolveColorToHex`.
const String kNamedColorsSvg =
    '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24">'
    '<circle cx="12" cy="12" r="9" fill="tomato" stroke="cornflowerblue" stroke-width="3"/>'
    '</svg>';

// 3. `<g transform="...">` static transform — combined translate/rotate/scale
// wrapping a square. Exercises the `transform` attribute parsed on any node
// (not just animateTransform targets) via `parseTransformMatrix`.
const String kGroupTransformSvg =
    '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24">'
    '<g transform="translate(12,12) rotate(45) scale(0.6)">'
    '<rect x="-8" y="-8" width="16" height="16" fill="#2A6DF4"/>'
    '</g></svg>';

// 4. `<animateTransform type="skewX">` — a square continuously shearing along
// X. Exercises `SmilTransformType.skewX`.
const String kSkewXSvg =
    '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24">'
    '<rect x="8" y="8" width="8" height="8" fill="#2A6DF4">'
    '<animateTransform attributeName="transform" type="skewX" dur="1.5s" '
    'values="0;30;0;-30;0" repeatCount="indefinite"/>'
    '</rect></svg>';

// 5. `<use>` referencing a `<defs>`-defined shape that itself carries an
// `<animate>` — the clone plays the same animation independently. Exercises
// `_resolveUse`'s "re-parse the target including its own animate children"
// semantics.
const String kUseAnimatedSvg =
    '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24">'
    '<defs><circle id="pulsingDot" cx="0" cy="0" r="3" fill="#2A6DF4">'
    '<animate attributeName="r" values="3;6;3" dur="1s" repeatCount="indefinite"/>'
    '</circle></defs>'
    '<use xlink:href="#pulsingDot" x="8" y="12"/>'
    '<use xlink:href="#pulsingDot" x="16" y="12"/>'
    '</svg>';

// 6. Syncbase `begin` — a "relay": the second `<animate>` only starts once the
// first (`id="firstAnim"`) ends, via `begin="firstAnim.end"`. Exercises
// `parseSmilBeginSpec`'s syncbase form + `resolveSmilBeginTimes`.
//
// Neither `<animate>` has `repeatCount="indefinite"` — a syncbase relay can't
// use it on the *first* animation, because `resolveSmilBeginTimes` treats an
// indefinitely-repeating target's `.end` as never arriving (by design: an
// indefinite loop has no end to sync to) and disables the second animation
// entirely. So the relay plays once (2s total) and freezes — see
// `_RestartingSvg` below, which remounts this widget on a timer so the demo
// page shows the relay repeating instead of freezing after the first play.
const String kSyncbaseRelaySvg =
    '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24">'
    '<circle cx="12" cy="12" r="10" fill="none" stroke="#DDDDDD" stroke-width="1"/>'
    '<rect x="2" y="10" width="4" height="4" fill="#2A6DF4">'
    '<animate id="firstAnim" attributeName="x" from="2" to="9" dur="1s" fill="freeze"/>'
    '<animate attributeName="x" begin="firstAnim.end" from="9" to="18" dur="1s" fill="freeze"/>'
    '</rect></svg>';

// 7. `<animateMotion>` — a small circle traveling along a wavy path with
// `rotate="auto"`. Exercises `_parseAnimateMotion`/`_sampleMotionPath`.
const String kAnimateMotionSvg =
    '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24">'
    '<path d="M2,12 Q7,2 12,12 T22,12" fill="none" stroke="#DDDDDD" stroke-width="1"/>'
    '<circle r="2" fill="#FF7A00">'
    '<animateMotion path="M2,12 Q7,2 12,12 T22,12" dur="2s" rotate="auto" repeatCount="indefinite"/>'
    '</circle></svg>';

// 8. Static gradients — a rect filled with a `linearGradient` defined in
// `<defs>`. No `<animate>`, so this routes through the Rust (usvg) static
// path rather than the animated engine.
const String kLinearGradientSvg =
    '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24">'
    '<defs><linearGradient id="grad1" x1="0" y1="0" x2="1" y2="1">'
    '<stop offset="0%" stop-color="#2A6DF4"/>'
    '<stop offset="100%" stop-color="#FF7A00"/>'
    '</linearGradient></defs>'
    '<rect x="2" y="2" width="20" height="20" rx="4" fill="url(#grad1)"/>'
    '</svg>';

// 9. Animated `<mask>` (Task 1, 2026-08-25): a blue circle revealed
// left-to-right by a growing white mask rect. Exercises `SvgNode.maskId` +
// `AnimatedSvgPainter._applyMaskLayer` sampling the mask content per frame.
const String kAnimatedMaskSvg =
    '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24">'
    '<defs><mask id="reveal"><rect x="0" y="0" width="0" height="24" fill="#FFFFFF">'
    '<animate attributeName="width" from="0" to="24" dur="1.5s" repeatCount="indefinite"/>'
    '</rect></mask></defs>'
    '<circle cx="12" cy="12" r="10" fill="#2A6DF4" mask="url(#reveal)"/>'
    '</svg>';

// 10. `<text>` (Task 2, 2026-08-25): plain text content with an opacity
// fade-in, proving the generic per-frame animation mechanism applies to text
// like any other node kind.
const String kTextSvg =
    '<svg xmlns="http://www.w3.org/2000/svg" width="80" height="24" viewBox="0 0 80 24">'
    '<text x="2" y="17" font-size="16" font-family="sans-serif" fill="#2A6DF4">'
    'svgx'
    '<animate attributeName="opacity" values="0.2;1;0.2" dur="2s" repeatCount="indefinite"/>'
    '</text></svg>';

// 11. `<animateMotion keyPoints/keyTimes>` (Task 3, 2026-08-25): the marker
// spends most of its time near the start of the path then rushes to the end
// — keyPoints="0;0.1;1" with even keyTimes makes the first half of the
// duration cover only 10% of the arc length.
const String kAnimateMotionKeyPointsSvg =
    '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24">'
    '<path d="M2,12 Q7,2 12,12 T22,12" fill="none" stroke="#DDDDDD" stroke-width="1"/>'
    '<circle r="2" fill="#FF7A00">'
    '<animateMotion path="M2,12 Q7,2 12,12 T22,12" keyPoints="0;0.1;1" keyTimes="0;0.5;1" '
    'dur="2s" repeatCount="indefinite"/>'
    '</circle></svg>';

// 12. Animated gradient (Task 4, 2026-08-25): the same rect as
// `kLinearGradientSvg`, but the gradient's own `x2`/`y2` animate and its first
// `<stop>` cycles colour — this SVG contains `<animate>` (on the gradient
// definition), so it routes through the animated engine rather than the
// static Rust path.
const String kAnimatedGradientSvg =
    '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24">'
    '<defs><linearGradient id="animGrad" x1="0" y1="0" x2="1" y2="0">'
    '<animate attributeName="x2" values="1;0;1" dur="2s" repeatCount="indefinite"/>'
    '<animate attributeName="y2" values="0;1;0" dur="2s" repeatCount="indefinite"/>'
    '<stop offset="0%" stop-color="#2A6DF4">'
    '<animate attributeName="stop-color" values="#2A6DF4;#FF7A00;#2A6DF4" dur="2s" repeatCount="indefinite"/>'
    '</stop>'
    '<stop offset="100%" stop-color="#FF7A00"/>'
    '</linearGradient></defs>'
    '<rect x="2" y="2" width="20" height="20" rx="4" fill="url(#animGrad)"/>'
    '</svg>';

Future<void> main() async {
  await RustLib.init();
  runApp(const MyApp());
}

/// Remounts an [SvgX.string] on a timer so a non-repeating (no
/// `repeatCount="indefinite"`) demo animation replays instead of staying
/// frozen at its final frame once played.
///
/// 定时重新挂载 [SvgX.string]，让不带 `repeatCount="indefinite"` 的演示动画
/// 反复重播，而不是播放一次后永远定格在终态。
class _RestartingSvg extends StatefulWidget {
  const _RestartingSvg(
    this.source, {
    required this.width,
    required this.height,
    required this.interval,
  });

  final String source;
  final double width;
  final double height;
  final Duration interval;

  @override
  State<_RestartingSvg> createState() => _RestartingSvgState();
}

class _RestartingSvgState extends State<_RestartingSvg> {
  int _generation = 0;
  late final Timer _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(
      widget.interval,
      (_) => setState(() => _generation++),
    );
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SvgX.string(
      widget.source,
      key: ValueKey(_generation),
      width: widget.width,
      height: widget.height,
    );
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('svgx acceptance test')),
        body: Center(
          child: SingleChildScrollView(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // TEMP WSA DIAGNOSTIC PROBE — reverted before finishing.
                Container(
                  width: 300,
                  height: 80,
                  color: const Color(0xFFFFFF00),
                  alignment: Alignment.center,
                  child: const Text(
                    'plain text test',
                    style: TextStyle(fontSize: 28, color: Color(0xFFFF0000)),
                  ),
                ),
                const SizedBox(height: 24),
                const Text('Animated (original SMIL engine)'),
                const SizedBox(height: 8),
                SvgX.string(
                  kConfirmCircleSvg,
                  width: 96,
                  height: 96,
                  // The SVG strokes use `currentColor`; resolve it to orange so
                  // the circle + checkmark draw-on animation is clearly visible.
                  theme: const SvgTheme(currentColor: Color(0xFFFF7A00)),
                ),
                const SizedBox(height: 48),
                const Text('Looping animateTransform (svg-spinners 180-ring)'),
                const SizedBox(height: 8),
                SvgX.string(
                  kSpinnerSvg,
                  width: 96,
                  height: 96,
                  theme: const SvgTheme(currentColor: Color(0xFF2A6DF4)),
                ),
                const SizedBox(height: 48),
                const Text(
                  'Rotation marker (unambiguous animateTransform proof)',
                ),
                const SizedBox(height: 8),
                SvgX.string(kRotationMarkerSvg, width: 96, height: 96),
                const SizedBox(height: 48),
                const Text('Static (Rust usvg path)'),
                const SizedBox(height: 8),
                SvgX.string(kStaticCheckCircleSvg, width: 96, height: 96),
                const SizedBox(height: 48),
                const Text('Static currentColor (theme override → purple)'),
                const SizedBox(height: 8),
                SvgX.string(
                  kStaticCurrentColorSvg,
                  width: 96,
                  height: 96,
                  theme: const SvgTheme(currentColor: Color(0xFF9B30FF)),
                ),
                const SizedBox(height: 48),
                const Text(
                  'paint-order: default (fill then stroke) vs stroke-first',
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SvgX.string(
                      _paintOrderCircleSvg(strokeFirst: false),
                      width: 96,
                      height: 96,
                    ),
                    const SizedBox(width: 32),
                    SvgX.string(
                      _paintOrderCircleSvg(strokeFirst: true),
                      width: 96,
                      height: 96,
                    ),
                  ],
                ),
                const SizedBox(height: 48),
                const Text('Embedded <image> (base64 PNG)'),
                const SizedBox(height: 8),
                SvgX.string(kEmbeddedImageSvg, width: 96, height: 96),
                const SizedBox(height: 48),
                const Text(
                  'Named CSS colors (fill="tomato" stroke="cornflowerblue")',
                ),
                const SizedBox(height: 8),
                SvgX.string(kNamedColorsSvg, width: 96, height: 96),
                const SizedBox(height: 48),
                const Text(
                  'Static <g transform="translate() rotate() scale()">',
                ),
                const SizedBox(height: 8),
                SvgX.string(kGroupTransformSvg, width: 96, height: 96),
                const SizedBox(height: 48),
                const Text('animateTransform type="skewX"'),
                const SizedBox(height: 8),
                SvgX.string(kSkewXSvg, width: 96, height: 96),
                const SizedBox(height: 48),
                const Text('<use> of a <defs> shape with its own <animate>'),
                const SizedBox(height: 8),
                SvgX.string(kUseAnimatedSvg, width: 96, height: 96),
                const SizedBox(height: 48),
                const Text('Syncbase begin relay (begin="firstAnim.end")'),
                const SizedBox(height: 8),
                _RestartingSvg(
                  kSyncbaseRelaySvg,
                  width: 96,
                  height: 96,
                  interval: const Duration(seconds: 3),
                ),
                const SizedBox(height: 48),
                const Text('<animateMotion rotate="auto"> along a path'),
                const SizedBox(height: 8),
                SvgX.string(kAnimateMotionSvg, width: 96, height: 96),
                const SizedBox(height: 48),
                const Text('Static linearGradient fill'),
                const SizedBox(height: 8),
                SvgX.string(kLinearGradientSvg, width: 96, height: 96),
                const SizedBox(height: 48),
                const Text('Animated <mask> (Task 1)'),
                const SizedBox(height: 8),
                SvgX.string(kAnimatedMaskSvg, width: 96, height: 96),
                const SizedBox(height: 48),
                const Text('<text> with animated opacity (Task 2)'),
                const SizedBox(height: 8),
                SvgX.string(kTextSvg, width: 160, height: 48),
                const SizedBox(height: 48),
                const Text('<animateMotion keyPoints/keyTimes> (Task 3)'),
                const SizedBox(height: 8),
                SvgX.string(kAnimateMotionKeyPointsSvg, width: 96, height: 96),
                const SizedBox(height: 48),
                const Text('Animated gradient: geometry + stop-color (Task 4)'),
                const SizedBox(height: 8),
                SvgX.string(kAnimatedGradientSvg, width: 96, height: 96),
                const SizedBox(height: 48),
                const Text('SvgX.asset'),
                const SizedBox(height: 8),
                SvgX.asset('assets/icon.svg', width: 96, height: 96),
                const SizedBox(height: 48),
                const Text(
                  'SvgImageProvider in a DecorationImage — animated spinner, '
                  'rasterized per-frame through ImageProvider (not '
                  'CustomPainter)',
                ),
                const SizedBox(height: 8),
                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    image: DecorationImage(
                      image: SvgImageProvider.string(
                        kSpinnerSvg,
                        width: 96,
                        height: 96,
                        theme: const SvgTheme(currentColor: Color(0xFF2A6DF4)),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
