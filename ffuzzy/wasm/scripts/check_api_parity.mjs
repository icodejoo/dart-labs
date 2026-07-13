#!/usr/bin/env node
// API surface parity check — run in CI or before publish.
// Reads the canonical API from test/shared/api_surface.json and verifies:
//   • JS dist/ffuzzy.d.mts   exports everything required
//   • JS FuzzyCorpus class   has all required instance methods
//
// When Dart API changes, update test/shared/api_surface.json — this script
// and both language test runners (api_parity_test.dart, api_parity.test.mjs)
// will catch anything missing on either side.
//
//   node wasm/scripts/check_api_parity.mjs
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { join, dirname } from 'node:path';

const root = join(dirname(fileURLToPath(import.meta.url)), '../..');
const api  = JSON.parse(readFileSync(join(root, 'test/shared/api_surface.json'), 'utf8'));
const dts  = readFileSync(join(root, 'wasm/dist/ffuzzy.d.mts'), 'utf8');

// ── Extract JS exports ────────────────────────────────────────────────────────
// tsdown generates a single `export { A, B, C };` line at the bottom of .d.mts

const exportLine = dts.match(/^export \{([^}]+)\};/m)?.[1] ?? '';
const jsExports  = new Set(exportLine.split(',').map(s => s.trim()).filter(Boolean));

// ── Extract FuzzyCorpus instance methods from .d.mts ─────────────────────────

const classBlock = dts.match(/declare class FuzzyCorpus[\s\S]*?^}/m)?.[0] ?? '';
const jsMethods  = new Set(
  [...classBlock.matchAll(/^\s{2}(?:static\s+)?(\w+)\s*[<(]/gm)]
    .map(m => m[1])
    .filter(n => n !== 'FuzzyCorpus' && n !== 'constructor'),
);
const jsStatics = new Set(
  [...classBlock.matchAll(/^\s{2}static\s+(\w+)\s*[<(]/gm)].map(m => m[1]),
);

// ── Check ─────────────────────────────────────────────────────────────────────

let errors = 0;

function check(label, required, actual) {
  const missing = required.filter(n => !actual.has(n));
  const ok = missing.length === 0;
  if (ok) {
    console.log(`  ✔  ${label}`);
  } else {
    console.error(`  ✖  ${label} — missing: ${missing.join(', ')}`);
    errors++;
  }
}

console.log('\n── API parity check (source: test/shared/api_surface.json) ──────');
check('module exports',               api.module_exports,          jsExports);
check('FuzzyCorpus instance methods', api.corpus_instance_methods, jsMethods);
check('FuzzyCorpus static factories', api.corpus_static_methods,   jsStatics);
console.log('─────────────────────────────────────────────────────────────────\n');

process.exit(errors > 0 ? 1 : 0);
