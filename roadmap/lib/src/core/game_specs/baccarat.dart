/// 百家乐内置 [GameSpec]。
///
/// 行为与 TS 版本逐字节一致：B/P/T 三结果，主流 skip T，庄对/闲对/例牌三角标。
/// 移植自 `src/core/game-specs/baccarat.ts`。
library;

import '../game_spec.dart';

/// 百家乐规格实例。
///
/// ```dart
/// final engine = createEngine(ids, spec: baccaratSpec);
/// ```
final GameSpec baccaratSpec = GameSpec(
  id: 'baccarat',
  label: '百家乐',
  outcomes: const [
    OutcomeDef(code: 'B', label: '庄', paletteKey: 'banker', beadTextField: 'bankerTotal'),
    OutcomeDef(code: 'P', label: '闲', paletteKey: 'player', beadTextField: 'playerTotal'),
    // 和局双方同点，显示庄点（与行业惯例一致）。
    OutcomeDef(code: 'T', label: '和', paletteKey: 'tie', beadTextField: 'bankerTotal'),
  ],
  streams: const [
    StreamDef(
      id: 'main',
      label: '庄闲',
      selector: OutcomeSelector(('B', 'P')),
      // 和局不占格，累加到 skipCount。
      skipOutcomes: ['T'],
    ),
  ],
  markers: const [
    MarkerDef(
      code: 'bankerPair',
      label: '庄对',
      shape: MarkerShape.dot,
      position: MarkerPosition.topLeft,
      paletteKey: 'banker',
    ),
    MarkerDef(
      code: 'playerPair',
      label: '闲对',
      shape: MarkerShape.dot,
      position: MarkerPosition.bottomRight,
      paletteKey: 'player',
    ),
    // 例牌橙色内圆：实际颜色走 theme.palette.outcomes['natural']，
    // 缺省回落 defaultTheme 中补充的 0xFFFB8C00。
    MarkerDef(code: 'natural', label: '例牌', shape: MarkerShape.innerDot, paletteKey: 'tie'),
  ],
);
