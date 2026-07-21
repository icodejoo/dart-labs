/// Built-in [GameSpec] for roulette.
///
/// The bead-plate chart works out of the box: each number is one outcome,
/// with code/label both being the number itself, colored via paletteKey —
/// red numbers use `red`, black numbers use `blue` (reusing the derived
/// road's red/blue color slots; `palette.red/blue` defaults to red/blue in
/// the theme), and zero uses `tie` (green scheme). To get a strict "black"
/// color for black numbers, no code change is needed — just override the theme:
///
/// ```dart
/// resolveTheme(palette: (p) => p.copyWith(
///   outcomes: {for (var n in blackNumbers) '$n': 0xFF212121},
/// ));
/// ```
///
/// Data feed format: `RawResult(no: n, winner: '17', ...)` — winner holds the number string directly.
///
/// The big/small and odd/even derived streams are already declared via
/// [RangeSelector]/[MarkSelector] (zero is skipped via `skipOutcomes`, the
/// same sweep mechanism as sic bo's triple), but they depend on
/// `extras.number` / `marks.odd`, and the [RawResult] currently stored by
/// the store has no channel for these two fields — wiring up the derived
/// streams requires the data layer to support [GenericResult] first (the
/// same gap as sic bo's big/small and odd/even roads).
library;

import '../game_spec.dart';

/// Red numbers on a European roulette wheel (same as American). Black numbers are the other 18 among 1-36.
const Set<int> rouletteRedNumbers = {1, 3, 5, 7, 9, 12, 14, 16, 18, 19, 21, 23, 25, 27, 30, 32, 34, 36};

/// Roulette spec instance (European single-zero, 0-36 for 37 outcomes total).
///
/// ```dart
/// final engine = createEngine(['beadPlate'], spec: rouletteSpec);
/// store.append(RawResult(no: 1, winner: '17', bankerPair: false, playerPair: false));
/// ```
final GameSpec rouletteSpec = GameSpec(
  id: 'roulette',
  label: '轮盘',
  outcomes: [
    // Zero: green scheme (the tie color slot defaults to green 0xFF43A047).
    const OutcomeDef(code: '0', label: '0', paletteKey: 'tie'),
    for (var n = 1; n <= 36; n++)
      OutcomeDef(
        code: '$n',
        label: '$n',
        paletteKey: rouletteRedNumbers.contains(n) ? 'red' : 'blue',
      ),
  ],
  streams: const [
    StreamDef(
      id: 'main',
      label: '大小',
      selector: RangeSelector(
        field: 'number',
        buckets: (
          RangeBucket(token: 'S', min: 1, max: 18),
          RangeBucket(token: 'B', min: 19, max: 36),
        ),
        // Zero does not advance the big/small road (skipped and accumulated into skipCount), same handling as sic bo's triple.
        skipOutcomes: ['0'],
      ),
    ),
    StreamDef(
      id: 'oddEven',
      label: '单双',
      selector: MarkSelector(code: 'odd', tokens: ('O', 'E')),
      skipOutcomes: ['0'],
    ),
  ],
  // Roulette has no badge markers.
);
