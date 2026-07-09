// Copied from flip_counter_plus (MIT) with namespace renames.
// Original: https://github.com/Itsxhadi/flip_counter_plus

/// The direction in which the stagger effect propagates across digits.
enum StaggerDirection {
  /// Animations start from the leftmost digit (most significant) and move right.
  leftToRight,

  /// Animations start from the rightmost digit (least significant) and move left.
  rightToLeft,
}

/// Predefined numeral systems for internationalization.
enum NumeralSystem {
  latin,
  easternArabic,
  persian,
  devanagari,
  bengali,
}

/// The transition type to use when animating between digits.
enum CounterTransitionType {
  /// Odometer rolling digits (vertical/horizontal scroll).
  /// Uses [Transform.translate] + [ClipRect] for compositor-layer animation.
  roll,
  fade,
  scale,
  fadeScale,
  rotate,
  flip,
  blur,
}

// ignore: library_private_types_in_public_api
const Map<NumeralSystem, List<String>> numeralSystemDigits = {
  NumeralSystem.latin:         ['0','1','2','3','4','5','6','7','8','9'],
  NumeralSystem.easternArabic: ['٠','١','٢','٣','٤','٥','٦','٧','٨','٩'],
  NumeralSystem.persian:       ['۰','۱','۲','۳','۴','۵','۶','۷','۸','۹'],
  NumeralSystem.devanagari:    ['०','१','२','३','४','५','६','७','८','९'],
  NumeralSystem.bengali:       ['০','১','২','৩','৪','৫','৬','৭','৮','৯'],
};

