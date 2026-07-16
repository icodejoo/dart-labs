# ffuzzy

English | [中文](README.zh-CN.md)

Fast fuzzy search for Flutter, powered by a compact **C** engine.

`ffuzzy` is a byte-for-byte reimplementation of [`nucleo`](https://github.com/helix-editor/nucleo)
(the matcher behind the Helix editor) in portable C. No Rust toolchain, no
codegen — the engine is a few source files that every platform's SDK compiles
on its own. The native library is **~32 KB** stripped.

- **Fast** — meets or beats the Rust `nucleo` engine: faster in every
  multi-threaded configuration and on `substring` across the board, at parity on
  CJK and single-threaded `fuzzy`. ~100k-item corpus filters in ~1.4 ms.
- **Tiny** — ~32 KB native `.so` (arm64), pure C, zero third-party deps.
- **All platforms** — Android, iOS, macOS, Linux, Windows and **Web** (WASM).
- **Search any object** — `FuzzyCorpus<T>` searches a `List<T>`; hits carry the
  original object (`hit.raw`).
- **Match modes as methods** — `fuzzy` (fzf-style, with `! ^ ' $` operators),
  `substring`, `prefix`, `postfix`, `exact`, plus unified `search()` with
  `SearchStrategy` (fuzzy / approx / fallback / merge) and `dual()`.
- **Edit-distance search** — `approx()` uses Myers bit-parallel Levenshtein;
  tolerates typos, substitutions and transpositions (opt-in build flag).
- **Multi-threaded** and **async** scans for large corpora without UI jank.
- **Hit highlighting** with correct Unicode (codepoint → UTF-16) offsets.
- **Unicode / CJK** — diacritic + full simple case folding; CJK matched directly.
- **Multi-key search** — attach host-computed pinyin / romaji / initials so a
  CJK item is findable by typing latin.

## Install

```yaml
dependencies:
  ffuzzy: ^0.6.0

environment:
  sdk: ^3.6.0
  flutter: ">=3.24.0"
```

> **No native platform setup required** — the C sources are compiled and bundled
> automatically by each platform's SDK on `flutter build`.

## Web support

On web, `ffuzzy` uses a WASM build of the same C engine. Call `ffuzzyInit` once
at app startup — it's a no-op on native, so it's safe to call unconditionally:

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Load the WASM engine from the published npm package:
  await ffuzzyInit(
    webUrl: 'https://cdn.jsdelivr.net/npm/@codejoo/ffuzzy@0.8.1/dist/ffuzzy.mjs',
  );
  // Or self-host: await ffuzzyInit(webAssetsUrl: '/assets/ffuzzy.mjs');
  runApp(const MyApp());
}
```

After `ffuzzyInit` returns, the full `FuzzyCorpus` API works identically on all
platforms.

> **Web note** — WASM runs synchronously on the main thread. For large corpora,
> `asyncFuzzy` yields to the event loop via a microtask but the WASM computation
> still runs on the main thread (no Web Worker). Keep corpora under ~50k items
> or use `fuzzy` synchronously with `limit` to stay within a frame budget.

**Lazy init (corpus created before `ffuzzyInit`):** If a `FuzzyCorpus` is
constructed before `ffuzzyInit` completes, it operates in *deferred* mode —
sync search methods return `[]` immediately, while `async*` methods (`asyncFuzzy`,
`asyncSearch`, `asyncApprox`, `asyncDual`, etc.) automatically await WASM
initialisation before executing and return real results. All strategies —
`fuzzy`, `approx`, `fallback`, `merge`, and `dual` — behave consistently in
both sync and async variants once WASM is ready.

**Parameters:**
- `webUrl` — CDN or self-hosted URL to `ffuzzy.mjs`. No Flutter asset needed.
- `webAssetsUrl` — local Flutter asset path (e.g. `/assets/ffuzzy.mjs`). Requires
  declaring the file in `pubspec.yaml` under `assets:`. Offline-capable.
- Both can be provided; `webAssetsUrl` takes priority.

## Quick start

```dart
import 'package:ffuzzy/ffuzzy.dart';

// Plain strings:
final corpus = FuzzyCorpus.strings(['src/main.dart', 'lib/widget.dart', '中文搜索']);
for (final h in corpus.fuzzy('srcmn', parallel: true, limit: 50)) {
  print('${h.raw}  score=${h.score}');   // h.raw is the matched String
}
corpus.dispose();                          // or let the NativeFinalizer reclaim it

// Any object — give a `stringOf` extractor; hits carry the object:
final files = FuzzyCorpus<File>(myFiles, stringOf: (f) => f.path);
final hit = files.prefix('lib/').firstOrNull;   // hit.raw is a File
```

> A `FuzzyCorpus` owns native memory and must be used only on the isolate that
> created it. The mode methods are synchronous on the calling isolate — for a
> large corpus use the `async*` twins (e.g. [`asyncFuzzy`](#search-modes)) or run
> the corpus on a background isolate so searching doesn't jank the UI.

## Use cases

Type-as-you-go search over file paths, command palettes, contact/song lists,
log lines, or any in-memory list where you want fzf-quality ranking at native
speed — especially large lists (tens of thousands of items) and CJK content.

---

# API

Everything is exported from `package:ffuzzy/ffuzzy.dart`.

## `ffuzzyInit`

```dart
Future<void> ffuzzyInit({String? webUrl, String? webAssetsUrl})
```

Initialize the WASM engine on **web**. No-op on native. Call once before
constructing any `FuzzyCorpus`. Idempotent.

## `FuzzyCorpus<T>`

A resident corpus of `T` items you build once and search many times.

### Constructors

```dart
FuzzyCorpus<T>(
  Iterable<T> items, {
  required String Function(T) stringOf, // searchable text for each item
  FuzzyOptions options = const FuzzyOptions(),
  bool matchPaths = false,   // tune delimiters for path-like text
  bool preferPrefix = false, // bias scoring toward matches near the start
  String? libraryPath,       // load a specific native lib (tests / non-bundled)
})

static FuzzyCorpus<String>              FuzzyCorpus.strings(Iterable<String> items, {…})
static FuzzyCorpus<Map<String,dynamic>> FuzzyCorpus.byKey(items, String field, {…})
static FuzzyCorpus<Map<String,dynamic>> FuzzyCorpus.byKeys(items, List<String> fields, {…})
static Future<FuzzyCorpus<T>>           FuzzyCorpus.buildAsync<T>(items, {required stringOf, …})
```

- **`byKey`** — search a `List<Map>` by one field; `hit.raw` is the whole map.
- **`byKeys`** — search across multiple fields; `hit.matchedKey` is the index
  into `fields` that produced the hit.
- **`buildAsync`** — builds the corpus on a background isolate (no UI jank for
  large datasets). On web, falls back to a microtask yield.

### Building & mutating

| Member | Description |
|---|---|
| `void add(T item)` | Append one item. |
| `void addAll(Iterable<T> items)` | Append many. |
| `Future<void> addAllAsync(Iterable<T> items)` | Append many on a background isolate (native) or microtask (web). Exclusive while running. |
| `void addKey(T item, List<FuzzyKey> keys)` | Append `item` with [alternate search keys](#multi-key--cjk-transliteration). |
| `void update(int index, T item)` | Replace item at `index` (drops alternate keys). |
| `void removeAt(int index)` | Remove item at `index`. |
| `int removeWhere(bool Function(T) test)` | Remove matching items; returns count removed. |
| `void refresh([Iterable<T>? source])` | Re-add current items, or replace entire dataset. |
| `void clear()` | Remove all items; corpus stays usable. |
| `int get length` | Number of items in the corpus. |

> The native corpus is append-only, so `update` / `removeAt` / `removeWhere` /
> `refresh` rebuild it in O(n) — cheap for occasional edits; batch heavy churn.

### Search modes

#### Classic modes

Each mode returns `List<FuzzyHit<T>>`:

```dart
List<FuzzyHit<T>> fuzzy(String q, {…overrides});
List<FuzzyHit<T>> substring(String q, {…overrides});
List<FuzzyHit<T>> prefix(String q, {…overrides});
List<FuzzyHit<T>> postfix(String q, {…overrides});  // suffix() is an alias
List<FuzzyHit<T>> exact(String q, {…overrides});
```

Each has `*Raws`, `async*`, and `async*Raws` variants:

```dart
corpus.asyncFuzzy(q)         // Future<List<FuzzyHit<T>>> — Isolate.run on native
corpus.fuzzyRaws(q)          // List<T> — skips FuzzyHit wrapper, faster
corpus.asyncFuzzyRaws(q)     // Future<List<T>>
```

- **`fuzzy`** parses the query into space-separated terms and fzf-style operators
  (`!` negate, `^` prefix, `'` substring, `$` suffix). Other modes treat the
  whole query as one literal atom.
- **Overrides** (`{FuzzyCase? caseMatching, FuzzyNorm? normalization, bool? parallel,
  int? threads, int? limit, bool? highlight, FuzzyScoring? scoring}`): each
  non-null argument overrides the corresponding field of the corpus's
  [`FuzzyOptions`](#fuzzyoptions) for that call only.

#### Unified entry point: `search()`

```dart
List<FuzzyHit<T>> search(String q, {
  SearchStrategy strategy = SearchStrategy.fuzzy,
  int? maxDistance,          // for approx/fallback/merge; auto-scaled when null
  FuzzyCase? caseMatching,
  FuzzyNorm? normalization,
  bool? parallel, int? threads, int? limit, bool? highlight, FuzzyScoring? scoring,
})
```

| `strategy` | Behaviour |
|---|---|
| `SearchStrategy.fuzzy` | fzf subsequence (default; same as `fuzzy()`) |
| `SearchStrategy.approx` | Edit-distance Levenshtein (same as `approx()`) |
| `SearchStrategy.fallback` | Subsequence first; if empty, fall back to edit-distance |
| `SearchStrategy.merge` | Both algorithms; subsequence hits first, then edit-only hits |

`search()` has `searchRaws()`, `asyncSearch()`, `asyncSearchRaws()` variants.

#### Edit-distance shorthand: `approx()`

```dart
List<FuzzyHit<T>> approx(String q, {int? maxDistance, …})
```

`maxDistance` auto-scales by query length when omitted (≤2 chars → 0; 3–5 → 1; 6+ → 2).
Also: `approxRaws()`, `asyncApprox()`, `asyncApproxRaws()`.

#### Dual result: `dual()`

Runs both algorithms independently in a single corpus scan and returns separate
buckets:

```dart
FuzzyDualResult<T> result = corpus.dual('iphoen');
result.fuzzy   // List<FuzzyHit<T>> — subsequence hits
result.approx  // List<FuzzyHit<T>> — edit-distance hits
```

Also: `asyncDual()`.

`async*` calls (`asyncFuzzy`, `asyncSearch`, `asyncApprox`, `asyncDual`, …)
may overlap safely. On web they also serve as the deferred-init path — a
call made before `ffuzzyInit` completes will await WASM before returning
results. Mutations while a search is in flight throw [`StateError`](#errors).

### Lifecycle

| Member | Description |
|---|---|
| `void dispose()` | Idempotent; waits for in-flight async work to complete. Safe to call from `State.dispose()`. |
| `Future<void> asyncDispose()` | Like `dispose` but awaitable. |

```dart
@override
void dispose() {
  unawaited(_corpus.asyncDispose());
  super.dispose();
}
```

## `FuzzyOptions`

| Field | Type | Default | Meaning |
|---|---|---|---|
| `caseMatching` | `FuzzyCase` | `smart` | Case handling |
| `normalization` | `FuzzyNorm` | `smart` | Diacritic normalization |
| `parallel` | `bool` | `false` | Multi-threaded scoring (native only) |
| `threads` | `int` | `0` | `0` = auto (half CPUs, capped at 8) |
| `limit` | `int` | `0` | Max hits (`0` = all) |
| `highlight` | `bool` | `false` | `true` populates `FuzzyHit.indices` for highlighting |
| `scoring` | `FuzzyScoring` | `fast` | `fast` (rolling DP), `off` (insertion order), `nucleo` (full-matrix DP) |

```dart
final corpus = FuzzyCorpus.strings(items,
    options: const FuzzyOptions(parallel: true, limit: 50));
corpus.fuzzy('foo');               // uses parallel + limit 50
corpus.fuzzy('bar', limit: 10);    // same defaults, but limit overridden
```

## `FuzzyHit<T>`

| Field | Type | Description |
|---|---|---|
| `raw` | `T` | The original item that matched. |
| `index` | `int` | Insertion order in the corpus. |
| `score` | `int` | Match score (higher = better; only comparable within one query). |
| `matchedKind` | `FuzzyKeyKind` | Which kind of key matched (original / pinyin / …). |
| `matchedKindCode` | `int` | Raw kind code. Same as `matchedKind.code` for built-in kinds; preserves host-defined values (≥ 100) for keys added via `addKey`. |
| `matchedKey` | `int` | Which key matched (`0` = original; `byKeys` → index into `fields`). |
| `indices` | `List<int>` | Matched **codepoint** positions. **Only populated when `highlight: true`**; empty otherwise. Convert with [`fuzzyCodepointToUtf16`](#highlighting). |

## Enums

### `FuzzyCase`

| Value | Meaning |
|---|---|
| `respect` | Case-sensitive. |
| `ignore` | Case-insensitive. |
| `smart` | Case-insensitive unless the query has uppercase (default). |

### `FuzzyNorm`

| Value | Meaning |
|---|---|
| `never` | No diacritic folding. |
| `smart` | Fold diacritics unless the query uses them (default). |

### `FuzzyKeyKind`

| Value | `.code` | Meaning |
|---|---|---|
| `original` | `0` | Item's own text (`stringOf`). |
| `pinyin` | `1` | Pinyin alternate key. |
| `initials` | `2` | Initials alternate key. |
| `romaji` | `3` | Romaji alternate key. |
| `custom` | `100` | Host-defined (any value ≥ 100). |

## `FuzzyKey`

```dart
FuzzyKey(String text, {int kind = 1})          // kind 1 = pinyin
FuzzyKey.kind(String text, FuzzyKeyKind kind)  // recommended
```

## Highlighting

```dart
List<int> fuzzyCodepointToUtf16(String text, List<int> codepointIndices)
```

Pass `highlight: true` to populate `FuzzyHit.indices`. Dart strings are UTF-16 —
convert codepoint positions before building a `TextSpan`:

```dart
final hit = corpus.fuzzy('src', highlight: true).first;
final text = hit.raw as String;
final marks = fuzzyCodepointToUtf16(text, hit.indices).toSet();
final spans = [
  for (var i = 0; i < text.length; i++)
    TextSpan(text: text[i], style: marks.contains(i) ? boldStyle : null),
];
```

## Multi-key / CJK transliteration

Attach host-computed alternate keys so a CJK item is findable by typing latin:

```dart
corpus.addKey(zhangsan, [
  FuzzyKey.kind('zhangsan', FuzzyKeyKind.pinyin),
  FuzzyKey.kind('zs', FuzzyKeyKind.initials),
]);

final h = corpus.fuzzy('zs').first;
// h.matchedKind == FuzzyKeyKind.initials
```

For large datasets, build in a background isolate:

```dart
final corpus = await Isolate.run(() {
  final c = FuzzyCorpus<Contact>(contacts, stringOf: (c) => c.name);
  for (final contact in contacts) {
    c.addKey(contact, [FuzzyKey(contact.pinyin, kind: FuzzyKeyKind.pinyin.code)]);
  }
  return c;
});
```

> `FuzzyCorpus` cannot be sent across isolates — build inside the isolate and
> keep it there, or use `buildAsync`.

## Edit-distance search (typo-tolerant)

`approx()` matches items whose best key is within `maxDistance` Levenshtein edits of the
query. Unlike `fuzzy` (subsequence), it tolerates substituted or extra characters.

```dart
// "iphoen" → finds "iPhone" (2 edits)
corpus.approx('iphoen')                        // maxDistance auto-scaled
corpus.approx('iphoen', maxDistance: 2)        // explicit
corpus.search('iphoen', strategy: SearchStrategy.fallback)  // seq first, then approx
corpus.search('iphoen', strategy: SearchStrategy.merge)     // both, merged
corpus.dual('iphoen')                          // both, separate buckets
```

Results are sorted closest-first (`score = −(distance+1)` for edit-only hits;
seq hits keep their fzf score). `FuzzyHit.indices` is always empty for edit-distance hits.

> **Opt-in feature** — requires the native library (or WASM module) to be
> compiled with `FFZ_EDIT_DISTANCE`. `FFZ_SUBSEQUENCE` (ON by default) controls
> the fzf algorithm independently.

### Enabling on native (Android / iOS / macOS / Linux / Windows)

Pass CMake flags when building. Both algorithms are ON by default for
`FFZ_SUBSEQUENCE`; `FFZ_EDIT_DISTANCE` is OFF by default:

```bash
cmake -DFFZ_SUBSEQUENCE=ON -DFFZ_EDIT_DISTANCE=ON ..   # both
cmake -DFFZ_SUBSEQUENCE=OFF -DFFZ_EDIT_DISTANCE=ON ..  # edit-distance only
```

Both flags require at least one to be ON (CMake will error otherwise).

### Enabling on web (WASM)

The published `ffuzzy.mjs` bundle ships with both algorithms compiled in — no
variant selection needed:

```dart
await ffuzzyInit(webUrl: 'https://cdn.jsdelivr.net/npm/@codejoo/ffuzzy@0.8.1/dist/ffuzzy.mjs');
```

Rebuilding the engine yourself:
```bash
# In wasm/:
npm run build:engine   # emcc → src/ffz.mjs (subsequence + edit-distance)
npm run build          # → dist/ffuzzy.mjs + dist/ffuzzy.d.mts
```

If the WASM module was not built with the required algorithm, affected methods
return `[]` silently on web and throw `FuzzyException` on native.

---

## Errors

- **Recoverable**: library/symbol load failure → `FuzzyException`; misuse (use
  after `dispose`, mutate during async search) → `StateError`.
- **Hard native faults**: not catchable — see [`FuzzyCrash`](#fuzzycrash).

### `FuzzyCrash` (native only)

Optional last-gasp handler for non-recoverable native faults. Prints a backtrace
to stderr before exit and optionally writes it to a breadcrumb file.

```dart
final report = FuzzyCrash.lastReport();
if (report != null) log('ffuzzy last crash:\n$report');
FuzzyCrash.install(breadcrumbPath: '${dir.path}/ffuzzy_crash.log');
```

---

## High-frequency & large-corpus search

**Latest query wins** pattern for type-as-you-go:

```dart
int _gen = 0;
Future<void> onQueryChanged(String q) async {
  final gen = ++_gen;
  final hits = await corpus.asyncFuzzy(q, limit: 50);
  if (gen != _gen) return;           // superseded by newer keystroke
  setState(() => _hits = hits);
}
```

**Data races** — multiple `…Async` searches may overlap safely (each gets its
own native matcher scratch). Mutations while a search is in flight throw
`StateError`; await or `asyncDispose` first.

## Platforms

| Platform | Engine | Async search |
|---|---|---|
| Android / iOS / macOS / Linux / Windows | C via `dart:ffi` | `Isolate.run` (true background thread) |
| Web | C via WASM (`dart:js_interop`) | Microtask yield (main thread) |

On native, the C sources are compiled and bundled per-platform (NDK / CMake /
podspec). Consumers need no extra toolchain.

## Performance

Real-device (Flutter Windows, profile mode, 100k items):

| | C (ffuzzy) | Rust (nucleo) |
|---|---|---|
| Resident corpus memory | 15.25 MB | 16.54 MB |
| Filter (fuzzy, top-50) | 1.36 ms | 1.65 ms |

The full methodology, differential-test guarantee (6210/6210 byte-identical to
nucleo), Unicode coverage, and engine design live in
[`docs/INTERNALS.md`](docs/INTERNALS.md).

## npm / JavaScript

The same C engine is published as [`@codejoo/ffuzzy`](https://www.npmjs.com/package/@codejoo/ffuzzy)
for browser and Node projects, with a matching API (both algorithms compiled
into the one bundle):

```ts
import { ffuzzyInitialize, FuzzyCorpus } from '@codejoo/ffuzzy';

await ffuzzyInitialize();
const corpus = FuzzyCorpus.strings(['src/main.rs', 'README.md']);
corpus.fuzzy('src', { highlight: true });
corpus.approx('srcc');                  // edit-distance, maxDistance auto-scaled
corpus.search('src', { strategy: 'fallback' });
corpus.dual('src');                     // { fuzzy: [...], approx: [...] }
corpus.dispose();
```

## License

MIT — see [LICENSE](LICENSE).
