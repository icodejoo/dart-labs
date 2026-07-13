// Shared behavioural spec — JS/WASM runner.
// Loads test/shared/spec.json and asserts the JS implementation produces the
// same results as the Dart native implementation (test/shared_spec_test.dart).
import assert from 'node:assert/strict';
import { test, describe, before, after } from 'node:test';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { join, dirname } from 'node:path';

import {
  ffuzzyInitialize, FuzzyCorpus, FuzzyKey,
} from '../dist/ffuzzy.mjs';

const __dir  = dirname(fileURLToPath(import.meta.url));
const spec   = JSON.parse(
  readFileSync(join(__dir, '../../test/shared/spec.json'), 'utf8'),
);

// ── options helper ────────────────────────────────────────────────────────────

function toOpts(overrides = {}) {
  return {
    limit:        overrides.limit        ?? 0,
    caseMatching: overrides.caseMatching === 'respect' ? 0
                : overrides.caseMatching === 'ignore'  ? 1
                : 2,
    scoring:      overrides.scoring      === 'off'    ? 1
                : overrides.scoring      === 'nucleo' ? 2
                : 0,
    highlight:    overrides.highlight ?? false,
  };
}

// ── search dispatcher ─────────────────────────────────────────────────────────

function search(corpus, mode, query, opts) {
  switch (mode) {
    case 'fuzzy':         return corpus.fuzzy(query, opts);
    case 'fuzzyRaws':     return corpus.fuzzyRaws(query, opts).map(raw => ({ raw }));
    case 'substring':     return corpus.substring(query, opts);
    case 'substringRaws': return corpus.substringRaws(query, opts).map(raw => ({ raw }));
    case 'prefix':        return corpus.prefix(query, opts);
    case 'prefixRaws':    return corpus.prefixRaws(query, opts).map(raw => ({ raw }));
    case 'postfix':       return corpus.postfix(query, opts);
    case 'postfixRaws':   return corpus.postfixRaws(query, opts).map(raw => ({ raw }));
    case 'suffix':        return corpus.suffix(query, opts);
    case 'suffixRaws':    return corpus.suffixRaws(query, opts).map(raw => ({ raw }));
    case 'exact':         return corpus.exact(query, opts);
    case 'exactRaws':     return corpus.exactRaws(query, opts).map(raw => ({ raw }));
    case 'length':        return Array(corpus.length).fill(null).map((_, i) => ({ raw: i }));
    default: throw new Error(`unknown mode: ${mode}`);
  }
}

// ── assertion helper ──────────────────────────────────────────────────────────

function assertHits(hits, a, id, getField = h => h.raw) {
  if ('count' in a)    assert.equal(hits.length, a.count, `${id}: count`);
  if ('maxCount' in a) assert.ok(hits.length <= a.maxCount, `${id}: maxCount`);
  if ('minCount' in a) assert.ok(hits.length >= a.minCount, `${id}: minCount`);
  if ('top' in a) {
    assert.ok(hits.length > 0, `${id}: expected non-empty`);
    assert.equal(getField(hits[0]), a.top, `${id}: top`);
  }
  if ('hits' in a) {
    const expected = new Set(a.hits), actual = new Set(hits.map(getField));
    assert.deepEqual(actual, expected, `${id}: hits set`);
  }
  if ('contains' in a) {
    const raws = hits.map(getField);
    for (const s of a.contains) assert.ok(raws.includes(s), `${id}: contains "${s}"`);
  }
  if ('excludes' in a) {
    const raws = new Set(hits.map(getField));
    for (const s of a.excludes) assert.ok(!raws.has(s), `${id}: excludes "${s}"`);
  }
  if ('allScoreZero' in a && a.allScoreZero) {
    for (const h of hits) assert.equal(h.score ?? 0, 0, `${id}: allScoreZero`);
  }
  if ('topHitFields' in a && hits.length > 0) {
    const h = hits[0], f = a.topHitFields;
    if ('index'          in f) assert.equal(h.index, f.index, `${id}: index`);
    if ('scoreGt'        in f) assert.ok(h.score > f.scoreGt, `${id}: score > ${f.scoreGt}`);
    if ('matchedKind'    in f) assert.equal(h.matchedKind, f.matchedKind, `${id}: matchedKind`);
    if ('matchedKindCode' in f) assert.equal(h.matchedKindCode, f.matchedKindCode, `${id}: matchedKindCode`);
    if ('indicesEmpty'   in f && f.indicesEmpty)   assert.equal(h.indices?.length ?? 0, 0, `${id}: indices empty`);
    if ('indicesNotEmpty' in f && f.indicesNotEmpty) assert.ok((h.indices?.length ?? 0) > 0, `${id}: indices not empty`);
  }
}

// ── build corpus ──────────────────────────────────────────────────────────────

function buildCorpus(suite) {
  if (suite.byKey) {
    const { items, field } = suite.byKey;
    return { corpus: FuzzyCorpus.byKey(items, field), items: items.map(m => m[field]) };
  }
  if (suite.byKeys) {
    const { items, fields } = suite.byKeys;
    return { corpus: FuzzyCorpus.byKeys(items, fields), items: items.map(m => m[fields[0]]) };
  }

  const strings = [...(suite.corpus || [])];
  const corpus  = FuzzyCorpus.strings(strings);

  for (const entry of suite.addKey || []) {
    corpus.addKey(entry.item, entry.keys.map(k => new FuzzyKey(k.text, k.kind)));
    strings.push(entry.item);
  }

  for (const op of suite.mutations || []) {
    if (op.op === 'removeAt') { corpus.removeAt(op.index); strings.splice(op.index, 1); }
    if (op.op === 'clear')    { corpus.clear(); strings.length = 0; }
  }

  return { corpus, items: strings };
}

// ── run suites ────────────────────────────────────────────────────────────────

before(async () => { await ffuzzyInitialize(); });

for (const suite of spec.suites) {
  describe(suite.name, () => {
    let corpus, items;
    before(() => ({ corpus, items } = buildCorpus(suite)));
    after(() => corpus?.dispose());

    for (const c of suite.cases) {
      const opts = toOpts(c.opts);
      test(`${c.id}: ${c.desc ?? c.id}`, () => {
        const hits = search(corpus, c.mode, c.query, opts);

        if (suite.byKey || suite.byKeys) {
          const fieldDef = suite.byKey ?? suite.byKeys;
          const fields = suite.byKeys ? suite.byKeys.fields : [suite.byKey.field];
          if ('topField' in c.assert) {
            assert.ok(hits.length > 0, `${c.id}: expected non-empty`);
            assert.equal(hits[0].raw[c.assert.topField], c.assert.topValue, `${c.id}: topField`);
          }
          if ('contains_field' in c.assert) {
            const { field: f, value: v } = c.assert.contains_field;
            assert.ok(hits.some(h => h.raw[f] === v), `${c.id}: contains_field ${f}=${v}`);
          }
          if ('minCount' in c.assert) assert.ok(hits.length >= c.assert.minCount, `${c.id}: minCount`);
          if ('count'    in c.assert) assert.equal(hits.length, c.assert.count, `${c.id}: count`);
        } else {
          assertHits(hits, c.assert, c.id);
        }
      });
    }
  });
}
