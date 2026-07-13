// API surface parity test — Dart side (source of truth).
// Verifies that every public method of FuzzyCorpus<T> can be called without
// error with valid inputs, and that return types carry the expected fields.
// Any method added here must also appear in wasm/test/api_parity.test.mjs.
//
//   flutter test test/api_parity_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ffuzzy/ffuzzy.dart';

String _libPath() {
  final root = Directory.current.path;
  if (Platform.isWindows) return '$root\\libffz.dll';
  if (Platform.isMacOS)   return '$root/libffz.dylib';
  return '$root/build_x86_64/libffuzzy.so';
}

void main() {
  late String lib;
  setUpAll(() { lib = _libPath(); });

  // ── Static constructors ──────────────────────────────────────────────────────

  group('FuzzyCorpus static constructors', () {
    test('strings', () {
      final c = FuzzyCorpus.strings(['a', 'b'], libraryPath: lib);
      expect(c.length, 2);
      c.dispose();
    });

    test('byKey', () {
      final c = FuzzyCorpus.byKey(
        [{'name': 'Alice'}, {'name': 'Bob'}], 'name', libraryPath: lib,
      );
      expect(c.length, 2);
      c.dispose();
    });

    test('byKeys', () {
      final c = FuzzyCorpus.byKeys(
        [{'name': 'Alice', 'city': 'Boston'}], ['name', 'city'], libraryPath: lib,
      );
      expect(c.length, 1);
      c.dispose();
    });

    test('asyncBuild', () async {
      final c = await FuzzyCorpus.asyncBuild(
        ['alpha', 'beta'], stringOf: (s) => s, libraryPath: lib,
      );
      expect(c.length, 2);
      c.dispose();
    });
  });

  // ── Search methods ───────────────────────────────────────────────────────────

  group('FuzzyCorpus search methods', () {
    late FuzzyCorpus<String> c;
    setUp(() => c = FuzzyCorpus.strings(
      ['src/main.dart', 'lib/widget.dart', 'README.md'], libraryPath: lib,
    ));
    tearDown(() => c.dispose());

    test('fuzzy',         () { final h = c.fuzzy('main');        expect(h, isNotEmpty); });
    test('asyncFuzzy',    () async { final h = await c.asyncFuzzy('main'); expect(h, isNotEmpty); });
    test('fuzzyRaws',     () { final r = c.fuzzyRaws('main');     expect(r, isNotEmpty); });
    test('asyncFuzzyRaws',() async { final r = await c.asyncFuzzyRaws('main'); expect(r, isNotEmpty); });

    test('prefix',         () { expect(c.prefix('src'),      isNotEmpty); });
    test('asyncPrefix',    () async { expect(await c.asyncPrefix('src'), isNotEmpty); });
    test('prefixRaws',     () { expect(c.prefixRaws('src'),   isNotEmpty); });
    test('asyncPrefixRaws',() async { expect(await c.asyncPrefixRaws('src'), isNotEmpty); });

    test('postfix',         () { expect(c.postfix('.dart'),    isNotEmpty); });
    test('asyncPostfix',    () async { expect(await c.asyncPostfix('.dart'), isNotEmpty); });
    test('postfixRaws',     () { expect(c.postfixRaws('.dart'), isNotEmpty); });
    test('asyncPostfixRaws',() async { expect(await c.asyncPostfixRaws('.dart'), isNotEmpty); });

    test('suffix',          () { expect(c.suffix('.dart'),     isNotEmpty); });
    test('asyncSuffix',     () async { expect(await c.asyncSuffix('.dart'), isNotEmpty); });
    test('suffixRaws',      () { expect(c.suffixRaws('.dart'),  isNotEmpty); });
    test('asyncSuffixRaws', () async { expect(await c.asyncSuffixRaws('.dart'), isNotEmpty); });

    test('exact',          () { expect(c.exact('README.md'),   isNotEmpty); });
    test('asyncExact',     () async { expect(await c.asyncExact('README.md'), isNotEmpty); });
    test('exactRaws',      () { expect(c.exactRaws('README.md'), isNotEmpty); });
    test('asyncExactRaws', () async { expect(await c.asyncExactRaws('README.md'), isNotEmpty); });

    test('substring',         () { expect(c.substring('widget'),    isNotEmpty); });
    test('asyncSubstring',    () async { expect(await c.asyncSubstring('widget'), isNotEmpty); });
    test('substringRaws',     () { expect(c.substringRaws('widget'),  isNotEmpty); });
    test('asyncSubstringRaws',() async { expect(await c.asyncSubstringRaws('widget'), isNotEmpty); });
  });

  // ── FuzzyHit fields ──────────────────────────────────────────────────────────

  group('FuzzyHit fields', () {
    late FuzzyCorpus<String> c;
    setUp(() => c = FuzzyCorpus.strings(['src/main.dart'], libraryPath: lib));
    tearDown(() => c.dispose());

    test('all fields present', () {
      final hits = c.fuzzy('main', highlight: true);
      expect(hits, isNotEmpty);
      final h = hits.first;
      // These field names must match what JS exports in FuzzyHit
      expect(h.raw,             isA<String>());
      expect(h.index,           isA<int>());
      expect(h.score,           isA<int>());
      expect(h.matchedKind,     isA<FuzzyKeyKind>());
      expect(h.matchedKindCode, isA<int>());
      expect(h.matchedKey,      isA<int>());
      expect(h.indices,         isA<List<int>>());
      expect(h.indices, isNotEmpty); // highlight: true
    });

    test('matchedKindCode equals matchedKind.code', () {
      final h = c.fuzzy('main').first;
      expect(h.matchedKindCode, equals(h.matchedKind.code));
    });
  });

  // ── Mutation methods ─────────────────────────────────────────────────────────

  group('FuzzyCorpus mutation methods', () {
    late FuzzyCorpus<String> c;
    setUp(() => c = FuzzyCorpus.strings(['alpha', 'beta', 'gamma'], libraryPath: lib));
    tearDown(() => c.dispose());

    test('add',         () { c.add('delta'); expect(c.length, 4); });
    test('addAll',      () { c.addAll(['d', 'e']); expect(c.length, 5); });
    test('addKey',      () { c.addKey('zeta', [FuzzyKey.kind('z', FuzzyKeyKind.custom)]); expect(c.length, 4); });
    test('update',      () { c.update(0, 'ALPHA'); expect(c.fuzzy('ALPHA'), isNotEmpty); });
    test('removeAt',    () { c.removeAt(0); expect(c.length, 2); });
    test('removeWhere', () { final n = c.removeWhere((s) => s.startsWith('a')); expect(n, greaterThan(0)); });
    test('refresh',     () { c.refresh(['x', 'y']); expect(c.length, 2); });
    test('clear',       () { c.clear(); expect(c.length, 0); });
    test('asyncAddAll', () async { await c.asyncAddAll(['p', 'q']); expect(c.length, 5); });
  });

  // ── Lifecycle ────────────────────────────────────────────────────────────────

  group('FuzzyCorpus lifecycle', () {
    test('dispose is idempotent', () {
      final c = FuzzyCorpus.strings(['x'], libraryPath: lib);
      c.dispose(); c.dispose(); // should not throw
    });
    test('use after dispose throws', () {
      final c = FuzzyCorpus.strings(['x'], libraryPath: lib);
      c.dispose();
      expect(() => c.fuzzy('x'), throwsStateError);
    });
    test('asyncDispose', () async {
      final c = FuzzyCorpus.strings(['x'], libraryPath: lib);
      await c.asyncDispose();
    });
  });

  // ── Utility functions ─────────────────────────────────────────────────────────

  group('Utility functions', () {
    test('fuzzyCodepointToUtf16: BMP no-op', () {
      expect(fuzzyCodepointToUtf16('abc', [0, 2]), equals([0, 2]));
    });
    test('fuzzyCodepointToUtf16: astral doubles', () {
      // 'a😀b' → codepoints [a, 😀, b], UTF-16 offsets [0, 1, 3]
      final offsets = fuzzyCodepointToUtf16('a😀b', [0, 1, 2]);
      expect(offsets, equals([0, 1, 3]));
    });
  });

  // ── Enums ────────────────────────────────────────────────────────────────────

  group('Enum values match JS side', () {
    test('FuzzyCase codes', () {
      expect(FuzzyCase.respect.index, 0); // code = 0
      expect(FuzzyCase.ignore.index,  1);
      expect(FuzzyCase.smart.index,   2);
    });
    test('FuzzyKeyKind codes', () {
      expect(FuzzyKeyKind.original.code, 0);
      expect(FuzzyKeyKind.pinyin.code,   1);
      expect(FuzzyKeyKind.initials.code, 2);
      expect(FuzzyKeyKind.romaji.code,   3);
      expect(FuzzyKeyKind.custom.code,   100);
    });
    test('FuzzyScoring codes', () {
      expect(FuzzyScoring.fast.index,   0);
      expect(FuzzyScoring.off.index,    1);
      expect(FuzzyScoring.nucleo.index, 2);
    });
  });
}
