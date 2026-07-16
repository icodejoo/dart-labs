# @codejoo/ffuzzy

English | [中文](README.zh-CN.md)

Ranked fuzzy search for the web — a WASM port of the [ffuzzy](https://github.com/icodejoo/dart-labs/tree/main/ffuzzy) C engine.

Fuzzy + edit-distance search · TypeScript · browser + Node · ~36 KB gzip

## Install

```sh
npm install @codejoo/ffuzzy
```

## Quick start

The WASM module is managed internally — call `ffuzzyInitialize()` once at
startup, then use `FuzzyCorpus` synchronously, exactly like the Dart API (no
module handle to pass around).

```ts
import { ffuzzyInitialize, FuzzyCorpus } from '@codejoo/ffuzzy';

await ffuzzyInitialize();   // once at startup (WASM instantiation is async)

// Plain strings
const corpus = FuzzyCorpus.strings(['src/main.ts', 'README.md', 'package.json']);
corpus.fuzzy('src').forEach(h => console.log(h.raw, h.score));
corpus.dispose();

// Generic objects — hits carry the original object
const files = new FuzzyCorpus(myFiles, { stringOf: f => f.path });
const hit = files.fuzzy('src')[0];
hit.raw;  // original object
files.dispose();
```

> Why the one `await`? WASM is instantiated asynchronously on the main thread
> (browsers forbid synchronous compilation of modules >4 KB), so the engine must
> be readied once. After that, every call is synchronous.

## Search

`fuzzy` is the flagship mode — the one where WASM genuinely outperforms
native JS (8-55× faster than fuse.js). `substring` / `prefix` / `postfix`
(alias `suffix`) / `exact` run as native JS string ops (no WASM crossing) and
each has a `*Raws` variant that skips the `FuzzyHit` wrapper for speed:

```ts
corpus.fuzzy('gems', { limit: 50 })     // ranked, scored, multi-key
corpus.prefix('Super')
corpus.postfix('1000')                  // suffix() is an alias
corpus.exact('101024')
corpus.substring('ems')
corpus.fuzzyRaws('gems')                // T[] — skips FuzzyHit wrapper
```

`fuzzy` supports fzf-style operators: `!term` negate · `^term` prefix-force ·
`'term` substring-force · `term$` postfix-force.

### Edit-distance search — `approx()`

Tolerates typos, substitutions and transpositions via Myers bit-parallel
Levenshtein — unlike `fuzzy` (subsequence matching), it matches items within
`maxDistance` edits of the query:

```ts
corpus.approx('iphoen')                  // "iPhone" — maxDistance auto-scales by query length
corpus.approx('iphoen', 2)               // explicit maxDistance
corpus.approxRaws('iphoen')              // T[]
```

`maxDistance` auto-scales when omitted: ≤2 chars → 0, 3–5 → 1, 6+ → 2.

### Unified entry point — `search()`

```ts
corpus.search('iphoen', { strategy: 'fuzzy' })      // default, same as fuzzy()
corpus.search('iphoen', { strategy: 'approx' })     // same as approx()
corpus.search('iphoen', { strategy: 'fallback' })   // subsequence first, else edit-distance
corpus.search('iphoen', { strategy: 'merge' })       // both, subsequence hits first
corpus.searchRaws('iphoen', { strategy: 'merge' })  // T[]
```

### Dual result — `dual()`

Runs both algorithms in a single corpus scan, returned as separate buckets:

```ts
const { fuzzy, approx } = corpus.dual('iphoen');
```

## Options

```ts
import { FuzzyCorpus, FuzzyCase, FuzzyNorm } from '@codejoo/ffuzzy';

const corpus = new FuzzyCorpus(items, {
  stringOf: item => item.name,
  options: {
    caseMatching: FuzzyCase.smart,    // 0 respect · 1 ignore · 2 smart (default)
    normalization: FuzzyNorm.smart,   // 0 never · 1 smart/accent-strip (default)
    limit: 50,                        // max results (0 = unlimited)
    highlight: true,                  // populate FuzzyHit.indices
  },
  matchPaths: false,   // treat '/' as path separator
  preferPrefix: false, // bias toward prefix matches
});
```

Per-call overrides:

```ts
corpus.fuzzy('query', { limit: 10, caseMatching: FuzzyCase.respect });
```

## Typed object search — `byKey` / `byKeys`

`T` is inferred from the items array, so `hit.raw` is fully typed:

```ts
interface Game { gameId: string; gameName: string; platform: { id: string } }

// Single field — hit.raw is Game
const byName = FuzzyCorpus.byKey(games, 'gameName');
byName.fuzzy('gems')[0].raw.gameId;   // ✓ typed as string

// Multiple fields — matchedKey tells you which field matched
const corpus = FuzzyCorpus.byKeys(games, ['gameName', 'gameId']);
const hit = corpus.fuzzy('gems')[0];
hit.raw.gameName;    // ✓ Game
hit.matchedKey;      // 0 = gameName matched, 1 = gameId matched

// Dot-notation for nested fields (IDE autocomplete included)
const byPlatform = FuzzyCorpus.byKey(games, 'platform.id');
byPlatform.fuzzy('226')[0]?.raw.gameId;  // ✓
```

Missing or null fields are silently treated as `''` — no runtime errors.

## Multi-key search (pinyin / romaji)

```ts
import { FuzzyCorpus, FuzzyKey, FuzzyKeyKind } from '@codejoo/ffuzzy';

corpus.addKey(item, [
  FuzzyKey.kind('zhongguo', FuzzyKeyKind.pinyin),
  FuzzyKey.kind('zg',       FuzzyKeyKind.initials),
]);
```

Mutation: `add` / `addAll` / `addKey` / `update` / `removeAt` / `removeWhere` / `refresh` / `clear`.

## Hit highlighting

Pass `{ highlight: true }` on the search call — `FuzzyHit.indices` is empty by
default (`highlight: false`) for speed.

**Option A — `highlightHtml`** (convenience, XSS-safe):

```ts
import { highlightHtml } from '@codejoo/ffuzzy';

const [hit] = corpus.fuzzy('src', { highlight: true });
element.innerHTML = highlightHtml(hit.raw, hit.indices);
// → '<mark>src</mark>/main.dart'
// Custom tag: highlightHtml(hit.raw, hit.indices, { tag: 'b' })
```

**Option B — raw codepoint positions** (for Flutter / custom rendering):

```ts
import { fuzzyCodepointToUtf16 } from '@codejoo/ffuzzy';

const [hit] = corpus.fuzzy('src', { highlight: true });
const u16 = fuzzyCodepointToUtf16(hit.raw, hit.indices);
// apply u16 offsets to DOM Range / TextSpan / highlight API
```

## `using` statement

```ts
using corpus = FuzzyCorpus.strings(items); // auto-disposed at scope exit
```

## FuzzyHit shape

```ts
interface FuzzyHit<T> {
  raw:             T;        // original item
  index:           number;   // insertion index in corpus
  score:           number;   // higher = better; only comparable within one query
  matchedKind:     number;   // FuzzyKeyKind of the matched key
  matchedKindCode: number;   // raw kind code — same as matchedKind for built-ins, preserves custom kinds (>=100)
  matchedKey:      number;   // key index within the item
  indices:         number[]; // matched codepoint positions — populated only when highlight:true
}
```

## Performance

Benchmarked on a 4886-item game corpus (average 15-byte ASCII names, `limit: 50`).

### vs fuzzysort and fuse.js

| Items | ffuzzy | fuzzysort | fuse.js | vs fuzzysort | vs fuse.js |
|------:|-------:|----------:|--------:|:------------:|:----------:|
| 4 886 | 120-220 µs | **19-103 µs** | 1.8-6.7 ms | 0.13-0.48× | **8-56×** |
| 9 772 | 240-415 µs | **32-193 µs** | 3.6-13 ms | 0.13-0.47× | **9-55×** |
| 24 430 | 0.6-1.1 ms | **92-695 µs** | 12-35 ms | 0.14-0.64× | **11-56×** |
| 48 860 | 1.4-2.8 ms | **238-2440 µs** | 18-75 ms | 0.14-0.88× | **7-57×** |

Build time (one-off): ffuzzy **2-9 ms** · fuse.js 2-20 ms · fuzzysort 5-27 ms

> fuzzysort is a pure-JS library that operates directly on V8-native strings with
> no WASM boundary overhead — it wins on raw speed for ASCII-only text.
> ffuzzy closes the gap on high-density queries (`"sp"` at 48k items: 2.77 vs 2.44 ms)
> and wins decisively against fuse.js at all scales.

### Feature comparison

| | ffuzzy | fuzzysort | fuse.js |
|--|:------:|:---------:|:-------:|
| Speed (pure ASCII) | ★★★ | ★★★★★ | ★ |
| vs fuse.js | **7-57× faster** | ~10× faster | baseline |
| CJK / diacritic folding | ✅ | ❌ | △ |
| Multi-key (pinyin / romaji) | ✅ `byKeys` | ❌ | ❌ |
| Typed `byKey<T>` / dot-path | ✅ | ❌ | ❌ |
| Dart FFI (Flutter) | ✅ | ❌ | ❌ |
| Ranking quality | nucleo DP | prefix-biased | Bitap/Levenshtein |
| Edit-distance search | ✅ `approx` | ❌ | △ (Bitap) |
| Bundle size | ~36 KB gzip | ~8 KB | ~24 KB |

**When to choose ffuzzy over fuzzysort**: CJK content, pinyin/romaji transliteration,
multi-field search (`byKeys`), or when you also use the Flutter/Dart package.
For pure ASCII with no Unicode requirements, fuzzysort may be a lighter choice.

## Build from source

```sh
cd wasm
npm run build          # fast path: compile src/ffuzzy-corpus.ts → dist/ffuzzy.mjs + .d.mts

# Rebuild the WASM engine (requires Emscripten >=3.x):
npm run build:engine    # emcc compiles src/*.c → src/ffz.mjs, then npm run build
npm run build:all       # engine + build in one step
```

## Related

- [ffuzzy on pub.dev](https://pub.dev/packages/ffuzzy) — Flutter / Dart package
- [ffuzzy on GitHub](https://github.com/icodejoo/dart-labs/tree/main/ffuzzy)

## License

MIT
