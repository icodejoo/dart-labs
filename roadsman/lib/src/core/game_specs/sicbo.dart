/// Built-in [GameSpec] for sic bo.
///
/// The multi-stream design is the litmus test for this abstraction:
/// - `main` (big/small road): range selector, `extras.total` 4-10 → S, 11-17 → B, skips on triple
/// - `oddEven` (odd/even road): mark selector, `marks.odd` true → O, false → E, skips on triple
///
/// Ported from `src/core/game-specs/sicbo.ts`.
library;

import '../game_spec.dart';

/// Sic bo spec instance.
///
/// ```dart
/// final engine = createEngine(ids, spec: sicboSpec);
/// // Data format: GenericResult(no, outcome: "N"|"TRIPLE", marks: {odd}, extras: {total, die1, die2, die3})
/// //
/// // Big/small road token color rule (range stream, tokens not present in outcomes):
/// // tokens[0]="S" → palette.red, tokens[1]="B" → palette.blue
/// ```
final GameSpec sicboSpec = GameSpec(
  id: 'sicbo',
  label: '骰宝',
  outcomes: const [
    // Normal round (non-triple): sic bo has no inherent binary matchup, so
    // outcome only records whether it was a triple; the road-building is
    // entirely derived from the range/mark streams off extras.
    OutcomeDef(code: 'N', label: '普通', paletteKey: 'blue', beadTextField: 'total'),
    // Triple (all three dice show the same value): tie color scheme, sweeps all bets.
    OutcomeDef(code: 'TRIPLE', label: '围骰', paletteKey: 'tie', beadTextField: 'total'),
  ],
  streams: const [
    StreamDef(
      id: 'main',
      label: '大小',
      selector: RangeSelector(
        field: 'total',
        buckets: (
          RangeBucket(token: 'S', min: 4, max: 10),
          RangeBucket(token: 'B', min: 11, max: 17),
        ),
        // Triple sweeps everything, so the big/small road treats it as a skip (accumulates skipCount, rendered as a slash + count).
        skipOutcomes: ['TRIPLE'],
      ),
    ),
    StreamDef(
      id: 'oddEven',
      label: '单双',
      selector: MarkSelector(code: 'odd', tokens: ('O', 'E')),
      // Skipped on triple; the odd/even road does not advance.
      skipOutcomes: ['TRIPLE'],
    ),
  ],
  // Sic bo has no badge markers.
);
