/// Double-tap-to-scroll-to-tail effect controller.
///
/// Ported from `src/panel/ux/double-tap.ts`. `RoadPanel` already has
/// double-tap gesture handling built in (see `onDoubleTap` in
/// `road_panel.dart`); this controller just gives callers who don't want to
/// use the `RoadPanel.onDoubleTap` parameter directly, and instead prefer the
/// TS version's "standalone toggleable effect" API style, an equivalent
/// option.
library;

/// Double-tap-to-scroll-to-tail effect controller.
class DoubleTapToTailEffect {
  bool enabled;
  final void Function() onDoubleTap;

  DoubleTapToTailEffect({required this.onDoubleTap, this.enabled = true});

  /// Toggle the effect on/off.
  void toggle(bool on) => enabled = on;

  /// Fire a double-tap-to-tail (only takes effect when [enabled]).
  void handleDoubleTap() {
    if (enabled) onDoubleTap();
  }
}

/// Create a double-tap-to-tail effect controller.
DoubleTapToTailEffect createDoubleTapToTail(void Function() onDoubleTap) =>
    DoubleTapToTailEffect(onDoubleTap: onDoubleTap);
