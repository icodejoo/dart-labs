// API surface parity test — JS side.
// Verifies that the JS package exports and instance methods match the Dart
// source of truth. Any method added or removed in Dart should be reflected
// here and in the TS corpus implementation.
import assert from 'node:assert/strict';
import { test, before } from 'node:test';

import * as Mod from '../dist/ffuzzy.mjs';
const {
  ffuzzyInitialize, ffuzzyReady, FuzzyCorpus, FuzzyKey, FuzzyOptions,
  FuzzyCase, FuzzyNorm, FuzzyMode, FuzzyScoring, FuzzyKeyKind,
  fuzzyCodepointToUtf16, highlightHtml,
} = Mod;

before(async () => { await ffuzzyInitialize(); });

// ── Module-level exports ──────────────────────────────────────────────────────

test('exports: required functions and classes', () => {
  const required = [
    'ffuzzyInitialize', 'ffuzzyReady',
    'FuzzyCorpus', 'FuzzyKey', 'FuzzyOptions',
    'FuzzyCase', 'FuzzyNorm', 'FuzzyMode', 'FuzzyScoring', 'FuzzyKeyKind',
    'fuzzyCodepointToUtf16', 'highlightHtml',
  ];
  for (const name of required) {
    assert.ok(name in Mod, `missing export: ${name}`);
  }
});

test('exports: enum values match Dart', () => {
  assert.equal(FuzzyCase.respect, 0);
  assert.equal(FuzzyCase.ignore,  1);
  assert.equal(FuzzyCase.smart,   2);

  assert.equal(FuzzyNorm.never, 0);
  assert.equal(FuzzyNorm.smart, 1);

  assert.equal(FuzzyScoring.fast,   0);
  assert.equal(FuzzyScoring.off,    1);
  assert.equal(FuzzyScoring.nucleo, 2);

  assert.equal(FuzzyKeyKind.original, 0);
  assert.equal(FuzzyKeyKind.pinyin,   1);
  assert.equal(FuzzyKeyKind.initials, 2);
  assert.equal(FuzzyKeyKind.romaji,   3);
  assert.equal(FuzzyKeyKind.custom,   100);
});

test('exports: FuzzyCorpus static factories', () => {
  assert.equal(typeof FuzzyCorpus.strings, 'function', 'FuzzyCorpus.strings');
  assert.equal(typeof FuzzyCorpus.byKey,   'function', 'FuzzyCorpus.byKey');
  assert.equal(typeof FuzzyCorpus.byKeys,  'function', 'FuzzyCorpus.byKeys');
});

// ── Instance methods ──────────────────────────────────────────────────────────

test('instance: all required methods present', () => {
  const c = FuzzyCorpus.strings(['a']);

  // Search methods — must match Dart FuzzyCorpus API
  const searchMethods = [
    'fuzzy',        'fuzzyRaws',
    'substring',    'substringRaws',
    'prefix',       'prefixRaws',
    'postfix',      'postfixRaws',
    'suffix',       'suffixRaws',
    'exact',        'exactRaws',
  ];
  for (const m of searchMethods) {
    assert.equal(typeof c[m], 'function', `missing method: ${m}`);
  }

  // Mutation methods
  const mutationMethods = [
    'add', 'addAll', 'addKey',
    'update', 'removeAt', 'removeWhere',
    'refresh', 'clear',
  ];
  for (const m of mutationMethods) {
    assert.equal(typeof c[m], 'function', `missing method: ${m}`);
  }

  // Lifecycle
  assert.equal(typeof c.dispose, 'function', 'dispose');
  assert.equal(typeof c.length,  'number',   'length getter');

  c.dispose();
});

// ── FuzzyHit shape ────────────────────────────────────────────────────────────

test('FuzzyHit: all fields present (mirrors Dart FuzzyHit)', () => {
  const c = FuzzyCorpus.strings(['src/main.dart']);
  const [hit] = c.fuzzy('main', { highlight: true });

  assert.ok(hit !== undefined, 'expected a hit');

  const requiredFields = [
    'raw',            // T
    'index',          // int
    'score',          // int
    'matchedKind',    // FuzzyKeyKind (as int in JS)
    'matchedKindCode', // int — matches Dart FuzzyHit.matchedKindCode
    'matchedKey',     // int
    'indices',        // number[]
  ];
  for (const f of requiredFields) {
    assert.ok(f in hit, `FuzzyHit missing field: ${f}`);
  }

  // Type checks
  assert.equal(typeof hit.raw,             'string',  'raw: string');
  assert.equal(typeof hit.index,           'number',  'index: number');
  assert.equal(typeof hit.score,           'number',  'score: number');
  assert.equal(typeof hit.matchedKind,     'number',  'matchedKind: number');
  assert.equal(typeof hit.matchedKindCode, 'number',  'matchedKindCode: number');
  assert.equal(typeof hit.matchedKey,      'number',  'matchedKey: number');
  assert.ok(Array.isArray(hit.indices),              'indices: Array');

  // matchedKind and matchedKindCode must be equal in JS
  assert.equal(hit.matchedKind, hit.matchedKindCode, 'matchedKind === matchedKindCode');

  c.dispose();
});

// ── FuzzyKey ──────────────────────────────────────────────────────────────────

test('FuzzyKey: constructor and static factory', () => {
  const k1 = new FuzzyKey('zhangsan', 1);
  assert.equal(k1.text, 'zhangsan');
  assert.equal(k1.kind, 1);

  const k2 = FuzzyKey.kind('zs', FuzzyKeyKind.initials);
  assert.equal(k2.text, 'zs');
  assert.equal(k2.kind, FuzzyKeyKind.initials);
});

// ── Utility functions ─────────────────────────────────────────────────────────

test('fuzzyCodepointToUtf16: BMP no-op, astral doubles', () => {
  assert.deepEqual(fuzzyCodepointToUtf16('abc', [0, 2]), [0, 2]);
  // emoji '😀' occupies 2 UTF-16 code units; offset[1] should be 2
  const offsets = fuzzyCodepointToUtf16('a😀b', [0, 1, 2]);
  assert.equal(offsets[0], 0);
  assert.equal(offsets[1], 1);  // 😀 starts at UTF-16 offset 1
  assert.equal(offsets[2], 3);  // 'b' starts at UTF-16 offset 3 (after 2-unit emoji)
});

test('highlightHtml: wraps matched chars, merges adjacent, escapes HTML', () => {
  assert.equal(highlightHtml('src/main.dart', [0, 1, 2]), '<mark>src</mark>/main.dart');
  assert.ok(highlightHtml('<b>item</b>', [0]).includes('&lt;'));
  assert.equal(highlightHtml('abc', [], { tag: 'em' }), 'abc');
  assert.equal(highlightHtml('abc', [1], { tag: 'b' }), 'a<b>b</b>c');
});
