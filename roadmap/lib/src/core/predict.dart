/// 问路：假设下一局为庄/闲时，三条衍生路会不会多长出一格、落什么颜色。
///
/// 移植自 `src/core/predict.ts`。
library;

import 'roads/big_road.dart';
import 'roads/derived_road.dart';
import 'types.dart';

/// [predictNextOutcome] 的返回值：三条衍生路各自的问路结果。
class PredictResult {
  final PredictionForRoad bigEyeBoy;
  final PredictionForRoad smallRoad;
  final PredictionForRoad cockroachRoad;

  const PredictResult({required this.bigEyeBoy, required this.smallRoad, required this.cockroachRoad});
}

/// 基于历史统计给出下一局各结果的概率倾向。
///
/// 做法：分别假设下一局开庄/开闲，重算三条衍生路，比较条目数是否比当前多一个——
/// 多出的那一个就是"这局如果这样开，衍生路会落的颜色"；没有多出说明这个假设下
/// 该衍生路还没走到需要落子的位置，返回 null。
PredictResult predictNextOutcome(List<RawResult> results) {
  final base = [1, 2, 3].map((k) => deriveRoad(buildBigRoad(results), k).entries.length).toList();

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
