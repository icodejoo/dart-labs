/// Prediction: assuming the next round is Banker/Player, would each of the
/// three derived roads gain a new cell, and what color would it be.
///
/// Ported from `src/core/predict.ts`.
library;

import 'roads/big_road.dart';
import 'roads/derived_road.dart';
import 'types.dart';

/// Return value of [predictNextOutcome]: prediction results for each of the three derived roads.
class PredictResult {
  final PredictionForRoad bigEyeBoy;
  final PredictionForRoad smallRoad;
  final PredictionForRoad cockroachRoad;

  const PredictResult({required this.bigEyeBoy, required this.smallRoad, required this.cockroachRoad});
}

/// Gives a probability lean for the next round's outcome based on historical stats.
///
/// Approach: hypothesize the next round is Banker or Player respectively,
/// recompute the three derived roads, and compare whether the entry count
/// grew by one versus the current state — the newly added entry is the
/// color the derived road would land on under that hypothesis. If no entry
/// was added, this derived road hasn't reached a point where it needs to
/// place a new cell under that hypothesis, so return null.
PredictResult predictNextOutcome(List<RawResult> results) {
  // The baseline big road is built only once (all three derived roads share this same big-road data).
  final baseBigRoad = buildBigRoad(results);
  final base = [1, 2, 3].map((k) => deriveRoad(baseBigRoad, k).entries.length).toList();

  (DerivedColor?, DerivedColor?, DerivedColor?) predict(String hypo) {
    final next = results.isNotEmpty ? results.last.no + 1 : 1;
    final hypoResults = [
      ...results,
      RawResult(no: next, winner: hypo, bankerPair: false, playerPair: false),
    ];
    final bigRoad2 = buildBigRoad(hypoResults);
    final out = <DerivedColor?>[];
    for (var i = 0; i < 3; i++) {
      final k = i + 1;
      final d2 = deriveRoad(bigRoad2, k);
      out.add(d2.entries.length > base[i] ? d2.entries.last : null);
    }
    return (out[0], out[1], out[2]);
  }

  final (bBE, bSR, bCR) = predict('B');
  final (pBE, pSR, pCR) = predict('P');

  return PredictResult(
    bigEyeBoy: PredictionForRoad(ifBanker: bBE, ifPlayer: pBE),
    smallRoad: PredictionForRoad(ifBanker: bSR, ifPlayer: pSR),
    cockroachRoad: PredictionForRoad(ifBanker: bCR, ifPlayer: pCR),
  );
}
