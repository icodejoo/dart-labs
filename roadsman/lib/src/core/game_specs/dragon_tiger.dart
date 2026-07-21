/// Built-in [GameSpec] for dragon tiger.
///
/// Outcomes: D (Dragon) / G (Tiger, using G=tiGer since T is already taken by
/// tie) / T (Tie). The main stream skips ties, with no pair/natural markers.
/// Ported from `src/core/game-specs/dragon-tiger.ts`.
library;

import '../game_spec.dart';

/// Dragon tiger spec instance.
///
/// ```dart
/// final engine = createEngine(ids, spec: dragonTigerSpec);
/// // Outcome sequence [D, D, T, G, D] → byOutcome = { D: 3, G: 1, T: 1 }
/// ```
final GameSpec dragonTigerSpec = GameSpec(
  id: 'dragonTiger',
  label: 'Dragon/Tiger',
  outcomes: const [
    OutcomeDef(code: 'D', label: 'Dragon', paletteKey: 'banker', beadTextField: 'dragonTotal'),
    // Note: code uses G (tiGer) rather than T, because T is already taken by tie — don't change this once settled.
    OutcomeDef(code: 'G', label: 'Tiger', paletteKey: 'player', beadTextField: 'tigerTotal'),
    OutcomeDef(code: 'T', label: 'Tie', paletteKey: 'tie', beadTextField: 'dragonTotal'),
  ],
  streams: const [
    StreamDef(
      id: 'main',
      label: 'Dragon/Tiger',
      selector: OutcomeSelector(('D', 'G')),
      skipOutcomes: ['T'],
    ),
  ],
  // Dragon tiger has no pair/natural markers.
);
