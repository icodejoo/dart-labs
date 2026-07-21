/// Gold-ring celebration effect controller for long dragon streaks.
///
/// Ported from `src/panel/ux/celebration.ts` (simplified to a toggle
/// controller, for the same reason as `pulse.dart`——the actual celebration
/// animation is left to the consumer to layer on as needed).
library;

/// Patterns that can trigger a celebration.
enum CelebrationPattern { dragon, singleHop, doubleHop }

/// Celebration effect options.
class CelebrationOptions {
  /// Trigger patterns; defaults to firing only on a dragon streak.
  final List<CelebrationPattern> pattern;

  const CelebrationOptions({this.pattern = const [CelebrationPattern.dragon]});
}

/// Gold-ring celebration effect controller for long dragon streaks.
class CelebrationEffect {
  bool enabled;
  final CelebrationOptions options;

  CelebrationEffect({this.enabled = true, this.options = const CelebrationOptions()});

  /// Toggle the effect on/off.
  void toggle(bool on) => enabled = on;
}

/// Create a dragon-streak celebration effect controller (enabled by default).
CelebrationEffect createCelebrationEffect({CelebrationOptions options = const CelebrationOptions()}) =>
    CelebrationEffect(options: options);
