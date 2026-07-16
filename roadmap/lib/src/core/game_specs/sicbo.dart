/// 骰宝内置 [GameSpec]。
///
/// 多流设计是这套抽象的试金石：
/// - `main`（大小路）：range 选择器，`extras.total` 4-10 → S，11-17 → B，围骰跳过
/// - `oddEven`（单双路）：mark 选择器，`marks.odd` true → O，false → E，围骰跳过
///
/// 移植自 `src/core/game-specs/sicbo.ts`。
library;

import '../game_spec.dart';

/// 骰宝规格实例。
///
/// ```dart
/// final engine = createEngine(ids, spec: sicboSpec);
/// // 数据格式：GenericResult(no, outcome: "N"|"TRIPLE", marks: {odd}, extras: {total, die1, die2, die3})
/// //
/// // 大小路 token 取色规则（range 流，token 不在 outcomes 里）：
/// // tokens[0]="S" → palette.red，tokens[1]="B" → palette.blue
/// ```
final GameSpec sicboSpec = GameSpec(
  id: 'sicbo',
  label: '骰宝',
  outcomes: const [
    // 普通局（非围骰）：骰宝没有天然二元对抗，outcome 仅记录围骰与否；
    // 走路全靠 range/mark 流从 extras 派生。
    OutcomeDef(code: 'N', label: '普通', paletteKey: 'blue', beadTextField: 'total'),
    // 围骰（三骰同点）：和局色系，通吃所有盘口。
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
        // 围骰通吃，大小盘视为跳过（累加 skipCount，呈现斜线+计数）。
        skipOutcomes: ['TRIPLE'],
      ),
    ),
    StreamDef(
      id: 'oddEven',
      label: '单双',
      selector: MarkSelector(code: 'odd', tokens: ('O', 'E')),
      // 围骰跳过，单双盘不走路。
      skipOutcomes: ['TRIPLE'],
    ),
  ],
  // 骰宝无角标标记。
);
