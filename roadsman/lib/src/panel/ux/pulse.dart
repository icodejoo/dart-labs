/// Pulsing halo effect controller for newly inserted cells.
///
/// Ported from `src/panel/ux/pulse.ts`. The TS version hand-rolls an
/// independent pulse animation frame loop at the demo layer, layering a
/// translucent stroked circle directly on the directive layer; the Flutter
/// version simplifies this to a toggle controller——the actual halo drawing
/// is left to the consumer to implement via an `AnimatedContainer`/
/// `CustomPaint` overlay layer. This controller only tracks "whether the
/// effect should currently be active", without re-implementing animation
/// sampling.
library;

/// Options for the pulsing halo effect.
class PulseOptions {
  /// Duration of a single pulse (ms), defaults to 2000ms.
  final int duration;

  /// Halo color (ARGB), defaults to gold.
  final int color;

  const PulseOptions({this.duration = 2000, this.color = 0xFFFFD700});
}

/// Pulsing halo effect controller.
class PulseEffect {
  bool enabled;
  final PulseOptions options;

  PulseEffect({this.enabled = true, this.options = const PulseOptions()});

  /// Toggle the effect on/off.
  void toggle(bool on) => enabled = on;
}

/// Create a pulsing halo effect controller (enabled by default).
PulseEffect createPulseEffect({PulseOptions options = const PulseOptions()}) =>
    PulseEffect(options: options);
