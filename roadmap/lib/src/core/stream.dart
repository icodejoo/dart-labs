/// 流选择器执行层：`resolveToken` / `colorForToken` / `labelForToken` / `getStreamDef`。
///
/// 零 Flutter 依赖。移植自 `src/core/stream.ts`。
library;

import 'game_spec.dart';
import 'theme.dart';

/// [resolveToken] 的返回值（sealed class）。
sealed class TokenResult {
  const TokenResult();
}

/// 成功解析出 token。
final class TokenOk extends TokenResult {
  final String token;
  const TokenOk(this.token);
}

/// 该局应跳过（不占格，如百家乐和局/骰宝围骰）。
final class TokenSkip extends TokenResult {
  const TokenSkip();
}

/// 配置错误（selector 与实际数据不匹配）。
final class TokenError extends TokenResult {
  final String message;
  const TokenError(this.message);
}

/// 从一局 [GenericResult] 按指定流的 [selector] 推导走路 token。
///
/// ```dart
/// final t = resolveToken(spec.streams[0].selector, result);
/// switch (t) {
///   case TokenSkip(): // 跳过（和局/围骰等）
///   case TokenError(:final message): // 配置错误
///   case TokenOk(:final token): // token 走路
/// }
/// ```
TokenResult resolveToken(StreamSelector selector, GenericResult result) {
  switch (selector) {
    case OutcomeSelector(:final tokens):
      final (t0, t1) = tokens;
      if (t0 == result.outcome || t1 == result.outcome) {
        return TokenOk(result.outcome);
      }
      // skipOutcomes 在 StreamDef 层，此处 selector 不直接持有 skipOutcomes——
      // 调用方须先用 streamDef.skipOutcomes 做 skip 判断，这里返回 error 兜底。
      return TokenError('outcome "${result.outcome}" not in tokens [$t0,$t1]');

    case RangeSelector(:final field, :final buckets, :final skipOutcomes):
      if (skipOutcomes?.contains(result.outcome) ?? false) return const TokenSkip();
      final value = result.extras?[field];
      if (value == null) {
        return TokenError('extras field "$field" missing for range selector');
      }
      final (b0, b1) = buckets;
      if (value >= b0.min && value <= b0.max) return TokenOk(b0.token);
      if (value >= b1.min && value <= b1.max) return TokenOk(b1.token);
      return TokenError('value $value in "$field" not in any bucket');

    case MarkSelector(:final code, :final tokens):
      final flag = result.marks?[code] ?? false;
      return TokenOk(flag ? tokens.$1 : tokens.$2);
  }
}

/// 根据 token 解析显示颜色（ARGB 32 位整数），三级 fallback：
/// 1. `theme.palette.outcomes[token]`（自定义颜色，最高优先级）
/// 2. `spec.outcomes` 中该 code 的 `paletteKey` 对应颜色
/// 3. `stream.selector` 的 tokens[0] → `palette.red`，tokens[1] → `palette.blue`
///
/// ```dart
/// final fill = colorForToken(spec, 'main', 'B', theme); // 0xFFE53935（红，庄）
/// ```
int colorForToken(GameSpec spec, String streamId, String token, Theme theme) {
  final custom = theme.palette.outcomes?[token];
  if (custom != null) return custom;

  OutcomeDef? outcomeDef;
  for (final o in spec.outcomes) {
    if (o.code == token) {
      outcomeDef = o;
      break;
    }
  }
  if (outcomeDef != null) {
    return switch (outcomeDef.paletteKey) {
      'banker' => theme.palette.banker,
      'player' => theme.palette.player,
      'tie' => theme.palette.tie,
      'red' => theme.palette.red,
      'blue' => theme.palette.blue,
      _ => theme.palette.blue,
    };
  }

  StreamDef? stream;
  for (final s in spec.streams) {
    if (s.id == streamId) {
      stream = s;
      break;
    }
  }
  if (stream != null) {
    switch (stream.selector) {
      case OutcomeSelector(:final tokens):
        if (tokens.$1 == token) return theme.palette.red;
        if (tokens.$2 == token) return theme.palette.blue;
      case MarkSelector(:final tokens):
        if (tokens.$1 == token) return theme.palette.red;
        if (tokens.$2 == token) return theme.palette.blue;
      case RangeSelector(:final buckets):
        if (buckets.$1.token == token) return theme.palette.red;
        if (buckets.$2.token == token) return theme.palette.blue;
    }
  }

  return theme.palette.blue;
}

/// 根据 token 解析显示文案，三级 fallback：
/// 1. `theme.labels.outcomes[token]`
/// 2. `spec.outcomes` 中该 code 的 label
/// 3. token 字面量本身
///
/// ```dart
/// labelForToken(baccaratSpec, 'B', theme); // '庄'
/// ```
String labelForToken(GameSpec spec, String token, Theme theme) {
  final custom = theme.labels.outcomes?[token];
  if (custom != null) return custom;

  for (final o in spec.outcomes) {
    if (o.code == token) return o.label;
  }
  return token;
}

/// 从 [GameSpec] 中按 id 查找流定义，找不到时返回 main 流（保证总有返回值）。
StreamDef getStreamDef(GameSpec spec, String id) {
  for (final s in spec.streams) {
    if (s.id == id) return s;
  }
  for (final s in spec.streams) {
    if (s.id == 'main') return s;
  }
  throw StateError('GameSpec "${spec.id}" has no "main" stream');
}
