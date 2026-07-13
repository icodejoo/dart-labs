// Shared behavioural spec — Dart runner.
// Loads test/shared/spec.json and asserts that the native FFI implementation
// produces identical results to the JS/WASM implementation.
//
//   flutter test test/shared_spec_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ffuzzy/ffuzzy.dart';

String _libPath() {
  final root = Directory.current.path;
  if (Platform.isWindows) return '$root\\libffz.dll';
  if (Platform.isMacOS)   return '$root/libffz.dylib';
  return '$root/build_x86_64/libffuzzy.so';
}

// ── Options merge ──────────────────────────────────────────────────────────────

FuzzyOptions _mergeOpts(FuzzyOptions base, Map<String, dynamic> ov) =>
    base.copyWith(
      limit: ov['limit'] as int?,
      highlight: ov['highlight'] as bool?,
      caseMatching: switch (ov['caseMatching']) {
        'respect' => FuzzyCase.respect,
        'ignore'  => FuzzyCase.ignore,
        _         => null,
      },
      scoring: switch (ov['scoring']) {
        'off'    => FuzzyScoring.off,
        'nucleo' => FuzzyScoring.nucleo,
        'fast'   => FuzzyScoring.fast,
        _        => null,
      },
    );

// ── Corpus builders ──────────────────────────────────────────────────────────

FuzzyCorpus<String> _buildStringCorpus(
    Map<String, dynamic> suite, String lib) {
  final corpus = FuzzyCorpus.strings(
    (suite['corpus'] as List? ?? []).cast<String>(),
    libraryPath: lib,
  );
  for (final entry in (suite['addKey'] as List? ?? [])) {
    final m = entry as Map<String, dynamic>;
    corpus.addKey(
      m['item'] as String,
      (m['keys'] as List).map((k) {
        final km = k as Map<String, dynamic>;
        return FuzzyKey(km['text'] as String, kind: km['kind'] as int);
      }).toList(),
    );
  }
  for (final op in (suite['mutations'] as List? ?? [])) {
    final m = op as Map<String, dynamic>;
    if (m['op'] == 'removeAt') corpus.removeAt(m['index'] as int);
    if (m['op'] == 'clear')    corpus.clear();
  }
  return corpus;
}

FuzzyCorpus<Map<String, dynamic>> _buildByKey(
    Map<String, dynamic> suite, String lib) {
  final bk = suite['byKey'] as Map<String, dynamic>;
  return FuzzyCorpus.byKey(
    (bk['items'] as List).cast<Map<String, dynamic>>(),
    bk['field'] as String,
    libraryPath: lib,
  );
}

FuzzyCorpus<Map<String, dynamic>> _buildByKeys(
    Map<String, dynamic> suite, String lib) {
  final bk = (suite['byKeys'] as Map<String, dynamic>);
  return FuzzyCorpus.byKeys(
    (bk['items'] as List).cast<Map<String, dynamic>>(),
    (bk['fields'] as List).cast<String>(),
    libraryPath: lib,
  );
}

// ── Search dispatcher ─────────────────────────────────────────────────────────

// Returns FuzzyHit<T> for both Hit and Raws modes (Raws wrapped with score=0)
List<FuzzyHit<T>> _searchHits<T>(
    FuzzyCorpus<T> c, String mode, String query, FuzzyOptions o) {
  final cm = o.caseMatching, lim = o.limit, sc = o.scoring, hl = o.highlight;
  switch (mode) {
    case 'fuzzy':         return c.fuzzy(query, caseMatching: cm, limit: lim, scoring: sc, highlight: hl);
    case 'prefix':        return c.prefix(query, caseMatching: cm, limit: lim);
    case 'postfix':
    case 'suffix':        return c.postfix(query, caseMatching: cm, limit: lim);
    case 'exact':         return c.exact(query, caseMatching: cm, limit: lim);
    case 'substring':     return c.substring(query, caseMatching: cm, limit: lim);
    // Raws — wrap raw items so assertions can reference .raw
    case 'fuzzyRaws':     return [for (final r in c.fuzzyRaws(query, caseMatching: cm, limit: lim, scoring: sc)) FuzzyHit(r, 0, 0, FuzzyKeyKind.original, 0, 0, const [])];
    case 'prefixRaws':    return [for (final r in c.prefixRaws(query, caseMatching: cm, limit: lim)) FuzzyHit(r, 0, 0, FuzzyKeyKind.original, 0, 0, const [])];
    case 'postfixRaws':
    case 'suffixRaws':    return [for (final r in c.postfixRaws(query, caseMatching: cm, limit: lim)) FuzzyHit(r, 0, 0, FuzzyKeyKind.original, 0, 0, const [])];
    case 'exactRaws':     return [for (final r in c.exactRaws(query, caseMatching: cm, limit: lim)) FuzzyHit(r, 0, 0, FuzzyKeyKind.original, 0, 0, const [])];
    case 'substringRaws': return [for (final r in c.substringRaws(query, caseMatching: cm, limit: lim)) FuzzyHit(r, 0, 0, FuzzyKeyKind.original, 0, 0, const [])];
    case 'length':        return List.generate(c.length, (i) => FuzzyHit(c.fuzzy('').firstOrNull?.raw ?? (null as T), i, 0, FuzzyKeyKind.original, 0, 0, const []));
    default: throw ArgumentError('unknown mode: $mode');
  }
}

// ── Assertion helper ──────────────────────────────────────────────────────────

void _assertHits<T>(
    List<FuzzyHit<T>> hits, Map<String, dynamic> a, String id, [String Function(FuzzyHit<T>)? field]) {
  field ??= (h) => h.raw.toString();

  if (a.containsKey('count'))    expect(hits.length, a['count'],    reason: '$id: count');
  if (a.containsKey('maxCount')) expect(hits.length, lessThanOrEqualTo(a['maxCount'] as int), reason: '$id: maxCount');
  if (a.containsKey('minCount')) expect(hits.length, greaterThanOrEqualTo(a['minCount'] as int), reason: '$id: minCount');

  if (a.containsKey('top')) {
    expect(hits, isNotEmpty, reason: '$id: expected non-empty');
    expect(field(hits.first), a['top'], reason: '$id: top');
  }
  if (a.containsKey('hits')) {
    final expected = (a['hits'] as List).toSet();
    final actual   = hits.map(field).toSet();
    expect(actual, equals(expected), reason: '$id: hits set');
  }
  if (a.containsKey('contains')) {
    final raws = hits.map(field).toList();
    for (final s in (a['contains'] as List)) {
      expect(raws, contains(s), reason: '$id: contains "$s"');
    }
  }
  if (a.containsKey('excludes')) {
    final raws = hits.map(field).toSet();
    for (final s in (a['excludes'] as List)) {
      expect(raws, isNot(contains(s)), reason: '$id: excludes "$s"');
    }
  }
  if (a.containsKey('allScoreZero') && a['allScoreZero'] == true) {
    for (final h in hits) {
      expect(h.score, 0, reason: '$id: allScoreZero');
    }
  }
  if (a.containsKey('topHitFields') && hits.isNotEmpty) {
    final h = hits.first;
    final f = (a['topHitFields'] as Map<String, dynamic>);
    if (f.containsKey('index'))           expect(h.index, f['index'], reason: '$id: index');
    if (f.containsKey('scoreGt'))         expect(h.score, greaterThan(f['scoreGt'] as int), reason: '$id: score');
    if (f.containsKey('matchedKind'))     expect(h.matchedKind.code, f['matchedKind'], reason: '$id: matchedKind');
    if (f.containsKey('matchedKindCode')) expect(h.matchedKindCode, f['matchedKindCode'], reason: '$id: matchedKindCode');
    if (f['indicesEmpty'] == true)        expect(h.indices, isEmpty, reason: '$id: indices empty');
    if (f['indicesNotEmpty'] == true)     expect(h.indices, isNotEmpty, reason: '$id: indices not empty');
  }
}

// ── Main ──────────────────────────────────────────────────────────────────────

void main() {
  late String lib;
  setUpAll(() { lib = _libPath(); });

  final specFile = File('test/shared/spec.json');
  final spec = jsonDecode(specFile.readAsStringSync()) as Map<String, dynamic>;

  for (final suite in spec['suites'] as List) {
    final s     = suite as Map<String, dynamic>;
    final name  = s['name'] as String;
    final cases = (s['cases'] as List).cast<Map<String, dynamic>>();

    group(name, () {
      FuzzyCorpus<String>? corpus;
      FuzzyCorpus<Map<String, dynamic>>? mapCorpus;

      setUp(() {
        corpus = mapCorpus = null;
        if (s.containsKey('byKey'))  { mapCorpus = _buildByKey(s, lib); }
        else if (s.containsKey('byKeys')) { mapCorpus = _buildByKeys(s, lib); }
        else                          { corpus    = _buildStringCorpus(s, lib); }
      });
      tearDown(() { corpus?.dispose(); mapCorpus?.dispose(); });

      for (final c in cases) {
        final id   = c['id']   as String;
        final desc = (c['desc'] ?? id) as String;
        final mode = c['mode'] as String? ?? 'fuzzy';
        final q    = c['query'] as String? ?? '';
        final opts = _mergeOpts(const FuzzyOptions(),
            (c['opts'] as Map?)?.cast<String, dynamic>() ?? {});
        final a = (c['assert'] as Map).cast<String, dynamic>();

        test('$id: $desc', () {
          if (mapCorpus != null) {
            final hits = _searchHits(mapCorpus!, mode, q, opts);
            final bk = s['byKey'] ?? s['byKeys'];
            final topField = bk is Map
                ? (bk['field'] as String? ?? (bk['fields'] as List).first as String)
                : 'name';
            _assertHits(hits, a, id, (h) => (h.raw)[topField]?.toString() ?? '');
            if (a.containsKey('topField')) {
              expect(hits, isNotEmpty, reason: '$id: expected non-empty');
              expect((hits.first.raw as Map)[a['topField']], a['topValue'], reason: '$id: topField');
            }
            if (a.containsKey('contains_field')) {
              final cf = a['contains_field'] as Map;
              expect(hits.any((h) => (h.raw as Map)[cf['field']] == cf['value']), isTrue, reason: '$id: contains_field');
            }
          } else {
            final hits = _searchHits(corpus!, mode, q, opts);
            _assertHits(hits, a, id);
          }
        });
      }
    });
  }
}
