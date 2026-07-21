/// GameSpec: game specification abstraction.
///
/// Extract baccarat semantics from the type system into data, allowing the same engine/plugins/rendering layer
/// to support any "discrete result stream" type game. Zero Flutter dependency, can be used directly in pure Dart environments.
/// Ported from `src/core/game-spec.ts`.
library;

/// A possible round result definition.
class OutcomeDef {
  /// Result code, unique within the same [GameSpec], e.g. "B", "P", "T", "D".
  final String code;

  /// UI copy (in-bead circle text, stats panel row name).
  final String label;

  /// Color lookup key: points to existing keys in Palette ("banker"/"player"/"tie"/"red"/"blue").
  final String paletteKey;

  /// In bead plate number mode, which field from [GenericResult.extras] this result displays; defaults to fallback display [label].
  final String? beadTextField;

  const OutcomeDef({
    required this.code,
    required this.label,
    required this.paletteKey,
    this.beadTextField,
  });
}

/// Corner position for dot-shaped marker.
enum MarkerPosition { topLeft, topRight, bottomLeft, bottomRight }

/// Boolean marker shape: "dot" corner (pair) | "innerDot" inner filled circle (natural).
enum MarkerShape { dot, innerDot }

/// Boolean marker definition (generalizes banker pair/player pair/natural).
class MarkerDef {
  /// Marker code, corresponds to key in [GenericResult.marks], e.g. "bankerPair".
  final String code;

  /// UI copy (stats panel/tooltip).
  final String label;

  /// Presentation shape.
  final MarkerShape shape;

  /// Corner position for dot shape, defaults to topLeft.
  final MarkerPosition position;

  /// Color lookup key, same as [OutcomeDef.paletteKey].
  final String paletteKey;

  const MarkerDef({
    required this.code,
    required this.label,
    required this.shape,
    this.position = MarkerPosition.topLeft,
    required this.paletteKey,
  });
}

/// Declarative stream selector (sealed class, exhaustive switch matching).
sealed class StreamSelector {
  const StreamSelector();
}

/// Directly use outcome code as token (baccarat mainstream, dragon-tiger mainstream).
final class OutcomeSelector extends StreamSelector {
  /// Binary token list for road, exactly 2, determines the two hypothesis values for predict.
  final (String, String) tokens;

  const OutcomeSelector(this.tokens);
}

/// Bucket definition (closed interval).
class RangeBucket {
  final String token;
  final double min;
  final double max;

  const RangeBucket({required this.token, required this.min, required this.max});
}

/// Bucket by numeric field (sicbo size: extras.total 4-10 → "S", 11-17 → "B").
final class RangeSelector extends StreamSelector {
  /// Field name in [GenericResult.extras].
  final String field;

  /// Bucket definitions, exactly 2.
  final (RangeBucket, RangeBucket) buckets;

  /// Result codes to skip the entire round if hit (sicbo triple takes all).
  final List<String>? skipOutcomes;

  const RangeSelector({required this.field, required this.buckets, this.skipOutcomes});
}

/// Road by boolean mark (single/double roads, etc.).
final class MarkSelector extends StreamSelector {
  /// Key in [GenericResult.marks].
  final String code;

  /// (token for true, token for false).
  final (String, String) tokens;

  const MarkSelector({required this.code, required this.tokens});
}

/// Road stream definition: declare how to derive road token from a round result.
class StreamDef {
  /// Stream ID, each [GameSpec] must have a main stream with ID "main".
  final String id;

  /// UI name (for multi-stream switching in panel).
  final String label;

  /// Selector.
  final StreamSelector selector;

  /// List of result codes that do not occupy cells (baccarat "T").
  final List<String>? skipOutcomes;

  const StreamDef({required this.id, required this.label, required this.selector, this.skipOutcomes});
}

/// Game specification: all declarations for a game.
///
/// ```dart
/// final spec = GameSpec(
///   id: 'custom',
///   label: 'Custom',
///   outcomes: [
///     OutcomeDef(code: 'A', label: 'Alpha', paletteKey: 'banker'),
///     OutcomeDef(code: 'B', label: 'Beta', paletteKey: 'player'),
///   ],
///   streams: [
///     StreamDef(id: 'main', label: 'Main', selector: OutcomeSelector(('A', 'B'))),
///   ],
/// );
/// ```
class GameSpec {
  /// Spec ID: "baccarat" | "dragonTiger" | "sicbo" | custom.
  final String id;

  /// Game name (panel title, etc.).
  final String label;

  /// All possible outcomes.
  final List<OutcomeDef> outcomes;

  /// List of road streams, must include id="main".
  final List<StreamDef> streams;

  /// Marker markers (nullable).
  final List<MarkerDef>? markers;

  const GameSpec({
    required this.id,
    required this.label,
    required this.outcomes,
    required this.streams,
    this.markers,
  });
}

/// Generalized single round result, internal format within core. External API retains [RawResult] (see `types.dart`),
/// converted by adapter layer.
class GenericResult {
  /// Round number, monotonically increasing from 1.
  final int no;

  /// Result code, must be ∈ `spec.outcomes[].code`.
  final String outcome;

  /// Boolean markers, keys ∈ `spec.markers[].code`; missing keys are treated as false.
  final Map<String, bool>? marks;

  /// Numeric additional fields (sicbo total/die1-3, baccarat points, etc.), used by range selector and tooltip.
  final Map<String, num>? extras;

  const GenericResult({required this.no, required this.outcome, this.marks, this.extras});
}

/// Return value of [validateGameSpec] (sealed class).
sealed class ValidateResult {
  const ValidateResult();
}

/// Validation passed.
final class ValidateOk extends ValidateResult {
  final GameSpec spec;
  const ValidateOk(this.spec);
}

/// Validation failed.
final class ValidateError extends ValidateResult {
  final List<String> errors;
  const ValidateError(this.errors);
}

const _validPaletteKeys = ['banker', 'player', 'tie', 'red', 'blue'];

/// Validate whether an arbitrary value (usually from JSON-deserialized `Map<String, dynamic>`) is a valid [GameSpec].
///
/// Hand-written validation (no third-party schema library), checks structure field by field, for runtime
/// "custom game spec" input scenarios. Still returns the original `Map` on successful validation (caller converts to [GameSpec] themselves), because
/// strong-typed conversion on the Dart side requires the caller to decide field defaults, this is only responsible for error reporting.
///
/// ```dart
/// final result = validateGameSpecJson(jsonDecode(userInput) as Map<String, dynamic>);
/// switch (result) {
///   case ValidateError(:final errors): print(errors);
///   case ValidateOkJson(:final json): // convert to GameSpec
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
      // Custom keys beyond the built-in five are allowed (at runtime falls back via colorForPaletteKey to
      // theme.palette.outcomes[key]), here only validates it must be a non-empty string.
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

/// Return value of [validateGameSpecJson].
sealed class ValidateJsonResult {
  const ValidateJsonResult();
}

/// Validation passed, returns the original (confirmed structurally valid) JSON Map.
final class ValidateJsonOk extends ValidateJsonResult {
  final Map json;
  const ValidateJsonOk(this.json);
}

/// Validation failed.
final class ValidateJsonError extends ValidateJsonResult {
  final List<String> errors;
  const ValidateJsonError(this.errors);
}
