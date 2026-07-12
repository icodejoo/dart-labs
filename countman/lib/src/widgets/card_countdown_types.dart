/// Per-digit transition used by [CardCountdown] when a value changes.
///
/// The layout/measurement code in `card_countdown.dart` is
/// transition-agnostic — adding a new value here only means adding a
/// matching branch in `FlipCardPainter`'s per-cell dispatch. All three share
/// the same `CardCountdown.duration` timing knob.
enum CountdownType {
  /// Split-flap card flip (the original/default look) — the card is cut in
  /// half; the top half falls away while the bottom half stays put, like a
  /// mechanical flip calendar/clock.
  calendar,

  /// Old digit slides out, new digit slides in from the opposite edge.
  /// See `CardCountdown.scaleEffect`/`opacityEffect`.
  slide,

  /// The whole card — background and digit together — rotates around the
  /// X axis as one rigid plane (like flipping a physical card over), not
  /// split into two halves like [calendar]. See
  /// `CardCountdown.perspective`/`scaleEffect`/`opacityEffect`.
  flip,
}

/// Enter/exit behavior for a [CountdownType.slide]/[CountdownType.flip]
/// digit's scale (`CardCountdown.scaleEffect`) or opacity (`CardCountdown.opacityEffect`).
enum SlideEffect {
  /// No effect — pure translation/rotation.
  none,

  /// Applies only to the entering (new) digit.
  enter,

  /// Applies only to the exiting (old) digit.
  exit,

  /// Applies to both simultaneously.
  both,
}
