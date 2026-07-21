/// Built-in [GameSpec] for baccarat.
///
/// Behavior matches the TS version byte-for-byte: three outcomes B/P/T, the
/// main stream skips T, with banker-pair/player-pair/natural badge markers.
/// Ported from `src/core/game-specs/baccarat.ts`.
library;

import '../game_spec.dart';

/// Baccarat spec instance.
///
/// ```dart
/// final engine = createEngine(ids, spec: baccaratSpec);
/// ```
final GameSpec baccaratSpec = GameSpec(
  id: 'baccarat',
  label: 'Baccarat',
  outcomes: const [
    OutcomeDef(code: 'B', label: 'Banker', paletteKey: 'banker', beadTextField: 'bankerTotal'),
    OutcomeDef(code: 'P', label: 'Player', paletteKey: 'player', beadTextField: 'playerTotal'),
    // On a tie both sides have the same point total; display the banker's total (matches industry convention).
    OutcomeDef(code: 'T', label: 'Tie', paletteKey: 'tie', beadTextField: 'bankerTotal'),
  ],
  streams: const [
    StreamDef(
      id: 'main',
      label: 'Banker/Player',
      selector: OutcomeSelector(('B', 'P')),
      // A tie doesn't occupy a cell; it's accumulated into skipCount instead.
      skipOutcomes: ['T'],
    ),
  ],
  markers: const [
    MarkerDef(
      code: 'bankerPair',
      label: 'Banker Pair',
      shape: MarkerShape.dot,
      position: MarkerPosition.topLeft,
      paletteKey: 'banker',
    ),
    MarkerDef(
      code: 'playerPair',
      label: 'Player Pair',
      shape: MarkerShape.dot,
      position: MarkerPosition.bottomRight,
      paletteKey: 'player',
    ),
    // Natural's orange inner circle: the actual color comes from
    // theme.palette.outcomes['natural'], falling back to the 0xFFFB8C00
    // supplied in defaultTheme when absent.
    MarkerDef(code: 'natural', label: 'Natural', shape: MarkerShape.innerDot, paletteKey: 'tie'),
  ],
);
