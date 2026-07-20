/// 轮盘内置 [GameSpec]。
///
/// 露珠图（珠盘路）开箱即用：每个号码是一个 outcome，code/label 都是号码本身，
/// 取色走 paletteKey——红号 `red`、黑号 `blue`（沿用衍生路红蓝色位，主题里
/// `palette.red/blue` 默认就是红/蓝）、零号 `tie`（绿色系）。想要严格的
/// "黑色"号码配色，不用改代码，主题覆盖即可：
///
/// ```dart
/// resolveTheme(palette: (p) => p.copyWith(
///   outcomes: {for (var n in blackNumbers) '$n': 0xFF212121},
/// ));
/// ```
///
/// 数据喂法：`RawResult(no: n, winner: '17', ...)`——winner 直接放号码字符串。
///
/// 大小/单双两条衍生流已按 [RangeSelector]/[MarkSelector] 声明（0 号通过
/// `skipOutcomes` 跳过，同骰宝围骰通吃的机制），但它们依赖 `extras.number` /
/// `marks.odd`，而目前 store 存的 [RawResult] 没有这两个字段的通道——接入衍生
/// 路前需要先让数据层支持 [GenericResult]（与骰宝大小/单双路是同一个缺口）。
library;

import '../game_spec.dart';

/// 欧式轮盘的红色号码（美式相同）。黑色号码即 1-36 中的其余 18 个。
const Set<int> rouletteRedNumbers = {1, 3, 5, 7, 9, 12, 14, 16, 18, 19, 21, 23, 25, 27, 30, 32, 34, 36};

/// 轮盘规格实例（欧式单零，0-36 共 37 个 outcome）。
///
/// ```dart
/// final engine = createEngine(['beadPlate'], spec: rouletteSpec);
/// store.append(RawResult(no: 1, winner: '17', bankerPair: false, playerPair: false));
/// ```
final GameSpec rouletteSpec = GameSpec(
  id: 'roulette',
  label: '轮盘',
  outcomes: [
    // 零号：绿色系（tie 色位默认即绿色 0xFF43A047）。
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
        // 零号不走大小路（跳过并累加 skipCount），同骰宝围骰的处理方式。
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
  // 轮盘无角标标记。
);
