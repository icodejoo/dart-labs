/// GameSpec：游戏规格抽象。
///
/// 把百家乐语义从类型系统抽离为数据，使同一套引擎/插件/渲染层支持任意
/// "离散结果流"类游戏。零 Flutter 依赖，可在纯 Dart 环境直接使用。
/// 移植自 `src/core/game-spec.ts`。
library;

/// 一种可能的局结果定义。
class OutcomeDef {
  /// 结果代码，在同一 [GameSpec] 内唯一，如 "B"、"P"、"T"、"D"。
  final String code;

  /// UI 文案（珠盘圆内字、统计面板行名）。
  final String label;

  /// 取色键：指向 Palette 的既有键（"banker"/"player"/"tie"/"red"/"blue"）。
  final String paletteKey;

  /// 珠盘数字模式下，本结果从 [GenericResult.extras] 取哪个字段显示；缺省回退显示 [label]。
  final String? beadTextField;

  const OutcomeDef({
    required this.code,
    required this.label,
    required this.paletteKey,
    this.beadTextField,
  });
}

/// dot 形状角标的角位。
enum MarkerPosition { topLeft, topRight, bottomLeft, bottomRight }

/// 布尔角标形状："dot" 角点（对子）| "innerDot" 内实心圆（例牌）。
enum MarkerShape { dot, innerDot }

/// 布尔角标定义（泛化庄对/闲对/例牌）。
class MarkerDef {
  /// 标记代码，对应 [GenericResult.marks] 的键，如 "bankerPair"。
  final String code;

  /// UI 文案（统计面板/tooltip）。
  final String label;

  /// 呈现形状。
  final MarkerShape shape;

  /// dot 形状的角位，缺省 topLeft。
  final MarkerPosition position;

  /// 取色键，同 [OutcomeDef.paletteKey]。
  final String paletteKey;

  const MarkerDef({
    required this.code,
    required this.label,
    required this.shape,
    this.position = MarkerPosition.topLeft,
    required this.paletteKey,
  });
}

/// 声明式流选择器（sealed class，穷尽 switch 匹配）。
sealed class StreamSelector {
  const StreamSelector();
}

/// 直接取 outcome 代码作为 token（百家乐主流、龙虎主流）。
final class OutcomeSelector extends StreamSelector {
  /// 走路的二元 token 列表，恰好 2 个，决定 predict 的两个假设值。
  final (String, String) tokens;

  const OutcomeSelector(this.tokens);
}

/// 分桶定义（闭区间）。
class RangeBucket {
  final String token;
  final double min;
  final double max;

  const RangeBucket({required this.token, required this.min, required this.max});
}

/// 按数值字段分桶（骰宝大小：extras.total 4-10 → "S"，11-17 → "B"）。
final class RangeSelector extends StreamSelector {
  /// [GenericResult.extras] 中的字段名。
  final String field;

  /// 分桶定义，恰好 2 个。
  final (RangeBucket, RangeBucket) buckets;

  /// 命中即跳过整局的结果代码（骰宝围骰通吃）。
  final List<String>? skipOutcomes;

  const RangeSelector({required this.field, required this.buckets, this.skipOutcomes});
}

/// 按布尔标记走路（单双路等）。
final class MarkSelector extends StreamSelector {
  /// [GenericResult.marks] 中的键。
  final String code;

  /// (true 对应的 token, false 对应的 token)。
  final (String, String) tokens;

  const MarkSelector({required this.code, required this.tokens});
}

/// 路流定义：声明如何从一局结果得到走路 token。
class StreamDef {
  /// 流 id，每个 [GameSpec] 必须有 id 为 "main" 的主流。
  final String id;

  /// UI 名称（面板多流切换用）。
  final String label;

  /// 选择器。
  final StreamSelector selector;

  /// 不占格的结果代码列表（百家乐的 "T"）。
  final List<String>? skipOutcomes;

  const StreamDef({required this.id, required this.label, required this.selector, this.skipOutcomes});
}

/// 游戏规格：一个游戏的全部声明。
///
/// ```dart
/// final spec = GameSpec(
///   id: 'custom',
///   label: '自定义',
///   outcomes: [
///     OutcomeDef(code: 'A', label: '甲', paletteKey: 'banker'),
///     OutcomeDef(code: 'B', label: '乙', paletteKey: 'player'),
///   ],
///   streams: [
///     StreamDef(id: 'main', label: '主流', selector: OutcomeSelector(('A', 'B'))),
///   ],
/// );
/// ```
class GameSpec {
  /// 规格 id，"baccarat" | "dragonTiger" | "sicbo" | 自定义。
  final String id;

  /// 游戏名称（面板标题等）。
  final String label;

  /// 全部可能结果。
  final List<OutcomeDef> outcomes;

  /// 路流列表，必含 id="main"。
  final List<StreamDef> streams;

  /// 角标标记（可空）。
  final List<MarkerDef>? markers;

  const GameSpec({
    required this.id,
    required this.label,
    required this.outcomes,
    required this.streams,
    this.markers,
  });
}

/// 泛化后的单局结果，core 内部通行格式。对外 API 保留 [RawResult]（见 `types.dart`），
/// 由适配层转换。
class GenericResult {
  /// 局号，从 1 开始单调递增。
  final int no;

  /// 结果代码，必须 ∈ `spec.outcomes[].code`。
  final String outcome;

  /// 布尔标记，键 ∈ `spec.markers[].code`；缺键视为 false。
  final Map<String, bool>? marks;

  /// 数值附加字段（骰宝 total/die1-3、百家乐点数等），供 range 选择器与 tooltip 使用。
  final Map<String, num>? extras;

  const GenericResult({required this.no, required this.outcome, this.marks, this.extras});
}

/// [validateGameSpec] 的返回值（sealed class）。
sealed class ValidateResult {
  const ValidateResult();
}

/// 校验通过。
final class ValidateOk extends ValidateResult {
  final GameSpec spec;
  const ValidateOk(this.spec);
}

/// 校验失败。
final class ValidateError extends ValidateResult {
  final List<String> errors;
  const ValidateError(this.errors);
}

const _validPaletteKeys = ['banker', 'player', 'tie', 'red', 'blue'];

/// 校验任意值（通常来自 JSON 反序列化的 `Map<String, dynamic>`）是否为合法 [GameSpec]。
///
/// 手写校验（不引第三方 schema 库），逐字段核对结构，供"自定义游戏规格"这类运行时
/// 输入场景使用。校验通过时仍返回原始 `Map`（由调用方自行转 [GameSpec]），因为
/// Dart 侧强类型转换需要调用方决定字段缺省值，这里只负责报错。
///
/// ```dart
/// final result = validateGameSpecJson(jsonDecode(userInput) as Map<String, dynamic>);
/// switch (result) {
///   case ValidateError(:final errors): print(errors);
///   case ValidateOkJson(:final json): // 转换为 GameSpec
/// }
/// ```
ValidateJsonResult validateGameSpecJson(Object? raw) {
  final errs = <String>[];

  if (raw is! Map) {
    return ValidateJsonError(['root: must be an object']);
  }
  final obj = raw;

  if (obj['id'] is! String || (obj['id'] as String).isEmpty) {
    errs.add('id: must be a non-empty string');
  }
  if (obj['label'] is! String) {
    errs.add('label: must be a string');
  }

  final outcomes = obj['outcomes'];
  if (outcomes is! List || outcomes.isEmpty) {
    errs.add('outcomes: must be a non-empty array');
  } else {
    final codes = <String>{};
    for (var i = 0; i < outcomes.length; i++) {
      final o = outcomes[i];
      if (o is! Map) {
        errs.add('outcomes[$i]: must be an object');
        continue;
      }
      final code = o['code'];
      if (code is! String || code.isEmpty) {
        errs.add('outcomes[$i].code: must be non-empty string');
      } else if (!codes.add(code)) {
        errs.add('outcomes[$i].code: duplicate "$code"');
      }
      if (o['label'] is! String) {
        errs.add('outcomes[$i].label: must be a string');
      }
      // 内置五键之外允许自定义键（运行时经 colorForPaletteKey 回落
      // theme.palette.outcomes[key]），这里只校验必须是非空字符串。
      final pk = o['paletteKey'];
      if (pk is! String || pk.isEmpty) {
        errs.add(
          'outcomes[$i].paletteKey: must be a non-empty string '
          '(built-ins: ${_validPaletteKeys.join("|")}, custom keys resolve via theme.palette.outcomes)',
        );
      }
    }
  }

  final streams = obj['streams'];
  if (streams is! List || streams.isEmpty) {
    errs.add('streams: must be a non-empty array');
  } else {
    final hasMain = streams.any((s) => s is Map && s['id'] == 'main');
    if (!hasMain) errs.add('streams: must contain a stream with id="main"');
    for (var i = 0; i < streams.length; i++) {
      final s = streams[i];
      if (s is! Map) {
        errs.add('streams[$i]: must be an object');
        continue;
      }
      if (s['id'] is! String) errs.add('streams[$i].id: must be a string');
      if (s['label'] is! String) errs.add('streams[$i].label: must be a string');
      final sel = s['selector'];
      if (sel is! Map) {
        errs.add('streams[$i].selector: must be an object');
        continue;
      }
      switch (sel['kind']) {
        case 'outcome':
          if (sel['tokens'] is! List || (sel['tokens'] as List).length != 2) {
            errs.add('streams[$i].selector.tokens: must be an array of exactly 2 strings');
          }
        case 'range':
          if (sel['field'] is! String) {
            errs.add('streams[$i].selector.field: must be a string');
          }
          if (sel['buckets'] is! List || (sel['buckets'] as List).length != 2) {
            errs.add('streams[$i].selector.buckets: must be an array of exactly 2 buckets');
          }
        case 'mark':
          if (sel['code'] is! String) {
            errs.add('streams[$i].selector.code: must be a string');
          }
          if (sel['tokens'] is! List || (sel['tokens'] as List).length != 2) {
            errs.add('streams[$i].selector.tokens: must be an array of exactly 2 strings');
          }
        default:
          errs.add('streams[$i].selector.kind: unknown kind "${sel['kind']}"');
      }
    }
  }

  final markers = obj['markers'];
  if (markers != null) {
    if (markers is! List) {
      errs.add('markers: must be an array if present');
    } else {
      final mcodes = <String>{};
      for (var i = 0; i < markers.length; i++) {
        final m = markers[i];
        if (m is! Map) {
          errs.add('markers[$i]: must be an object');
          continue;
        }
        final code = m['code'];
        if (code is! String || code.isEmpty) {
          errs.add('markers[$i].code: must be non-empty string');
        } else if (!mcodes.add(code)) {
          errs.add('markers[$i].code: duplicate "$code"');
        }
        if (!['dot', 'innerDot'].contains(m['shape'])) {
          errs.add('markers[$i].shape: must be "dot" or "innerDot"');
        }
      }
    }
  }

  if (errs.isNotEmpty) return ValidateJsonError(errs);
  return ValidateJsonOk(obj);
}

/// [validateGameSpecJson] 的返回值。
sealed class ValidateJsonResult {
  const ValidateJsonResult();
}

/// 校验通过，返回原始（已确认结构合法的）JSON Map。
final class ValidateJsonOk extends ValidateJsonResult {
  final Map json;
  const ValidateJsonOk(this.json);
}

/// 校验失败。
final class ValidateJsonError extends ValidateJsonResult {
  final List<String> errors;
  const ValidateJsonError(this.errors);
}
