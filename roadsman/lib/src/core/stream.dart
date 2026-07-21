/// Stream selector execution layer: `resolveToken` / `colorForToken` / `labelForToken` / `getStreamDef`.
///
/// Zero Flutter dependency. Ported from `src/core/stream.ts`.
library;

import 'game_spec.dart';
import 'theme.dart';

/// Return value of [resolveToken] (sealed class).
sealed class TokenResult {
  const TokenResult();
}

/// Successfully resolved token.
final class TokenOk extends TokenResult {
  final String token;
  const TokenOk(this.token);
}

/// This round should be skipped (does not occupy a cell, e.g., baccarat tie / sicbo triple).
final class TokenSkip extends TokenResult {
  const TokenSkip();
}

/// Configuration error (selector does not match actual data).
final class TokenError extends TokenResult {
  final String message;
  const TokenError(this.message);
}

/// Derive road token from a round [GenericResult] according to the specified stream's [selector].
///
/// ```dart
/// final t = resolveToken(spec.streams[0].selector, result);
/// switch (t) {
///   case TokenSkip(): // skip (tie / triple, etc.)
///   case TokenError(:final message): // configuration error
///   case TokenOk(:final token): // token road
/// }
/// ```
TokenResult resolveToken(StreamSelector selector, GenericResult result) {
  switch (selector) {
    case OutcomeSelector(:final tokens):
      final (t0, t1) = tokens;
      if (t0 == result.outcome || t1 == result.outcome) {
        return TokenOk(result.outcome);
      }
      // skipOutcomes is at StreamDef level, selector does not directly hold skipOutcomes here --
      // caller must first use streamDef.skipOutcomes for skip judgment, here returns error as fallback.
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

/// Parse paletteKey ("banker"/"player"/"tie"/"red"/"blue" or any custom key) into
/// ARGB color. Custom keys beyond the built-in five first check `theme.palette.outcomes[key]`, if not found
/// fallback to `palette.blue` -- spec authors can invent new keys, as long as theme provides the corresponding color,
/// no need to modify this code.
///
/// ```dart
/// colorForPaletteKey('banker', theme); // 0xFFE53935
/// colorForPaletteKey('gold', theme);   // theme.palette.outcomes['gold'] ?? blue
/// ```
/// Each [GameSpec]'s outcome code → definition index, lazily built and cached per instance.
/// GameSpec has const constructor that cannot hold late fields, use Expando to hang on outside instance --
/// eliminate outcomes linear scan once per cell in colorForToken/labelForToken
/// (roulette 37 outcomes × once per cell color lookup, linear scan is the major overhead on layout hot path).
final Expando<Map<String, OutcomeDef>> _outcomeIndexCache = Expando();

/// Get [spec]'s outcome code → [OutcomeDef] index (O(1) lookup, cached per spec instance).
Map<String, OutcomeDef> outcomeIndexOf(GameSpec spec) =>
    _outcomeIndexCache[spec] ??= {for (final o in spec.outcomes) o.code: o};

int colorForPaletteKey(String key, Theme theme) => switch (key) {
  'banker' => theme.palette.banker,
  'player' => theme.palette.player,
  'tie' => theme.palette.tie,
  'red' => theme.palette.red,
  'blue' => theme.palette.blue,
  _ => theme.palette.outcomes?[key] ?? theme.palette.blue,
};

/// Parse display color by token (ARGB 32-bit integer), three-level fallback:
/// 1. `theme.palette.outcomes[token]` (custom color, highest priority)
/// 2. The corresponding color of this code's `paletteKey` in `spec.outcomes` (see [colorForPaletteKey])
/// 3. `stream.selector`'s tokens[0] → `palette.red`, tokens[1] → `palette.blue`
///
/// ```dart
/// final fill = colorForToken(spec, 'main', 'B', theme); // 0xFFE53935 (red, banker)
/// ```
int colorForToken(GameSpec spec, String streamId, String token, Theme theme) {
  final custom = theme.palette.outcomes?[token];
  if (custom != null) return custom;

  final outcomeDef = outcomeIndexOf(spec)[token];
  if (outcomeDef != null) return colorForPaletteKey(outcomeDef.paletteKey, theme);

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

/// Parse display copy by token, three-level fallback:
/// 1. `theme.labels.outcomes[token]`
/// 2. The label of this code in `spec.outcomes`
/// 3. The token literal itself
///
/// ```dart
/// labelForToken(baccaratSpec, 'B', theme); // 'Banker'
/// ```
String labelForToken(GameSpec spec, String token, Theme theme) {
  final custom = theme.labels.outcomes?[token];
  if (custom != null) return custom;

  // Backward compatibility bridge: under baccarat spec, continue to respect customization of theme.labels.banker/player/tie
  // (historically bead plate directly read these three fields). Limited to baccarat -- dragon-tiger's 'T' is tiger not tie,
  // cannot be mapped uniformly by code.
  if (spec.id == 'baccarat') {
    switch (token) {
      case 'B':
        return theme.labels.banker;
      case 'P':
        return theme.labels.player;
      case 'T':
        return theme.labels.tie;
    }
  }
  return outcomeIndexOf(spec)[token]?.label ?? token;
}

/// Find stream definition by id from [GameSpec], return main stream if not found (guarantees a return value).
StreamDef getStreamDef(GameSpec spec, String id) {
  for (final s in spec.streams) {
    if (s.id == id) return s;
  }
  for (final s in spec.streams) {
    if (s.id == 'main') return s;
  }
  throw StateError('GameSpec "${spec.id}" has no "main" stream');
}
