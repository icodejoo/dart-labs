/// 龙虎内置 [GameSpec]。
///
/// 结果：D（龙）/ G（虎，沿用 G=tiGer，T 已被和局占用）/ T（和）。
/// 主流 skip 和局，无对子/例牌标记。移植自 `src/core/game-specs/dragon-tiger.ts`。
library;

import '../game_spec.dart';

/// 龙虎规格实例。
///
/// ```dart
/// final engine = createEngine(ids, spec: dragonTigerSpec);
/// // 结果序列 [D, D, T, G, D] → byOutcome = { D: 3, G: 1, T: 1 }
/// ```
final GameSpec dragonTigerSpec = GameSpec(
  id: 'dragonTiger',
  label: '龙虎',
  outcomes: const [
    OutcomeDef(code: 'D', label: '龙', paletteKey: 'banker', beadTextField: 'dragonTotal'),
    // 注意：code 用 G（tiGer）而非 T，因为 T 已被和局占用，确定后不要改。
    OutcomeDef(code: 'G', label: '虎', paletteKey: 'player', beadTextField: 'tigerTotal'),
    OutcomeDef(code: 'T', label: '和', paletteKey: 'tie', beadTextField: 'dragonTotal'),
  ],
  streams: const [
    StreamDef(
      id: 'main',
      label: '龙虎',
      selector: OutcomeSelector(('D', 'G')),
      skipOutcomes: ['T'],
    ),
  ],
  // 龙虎无对子/例牌标记。
);
