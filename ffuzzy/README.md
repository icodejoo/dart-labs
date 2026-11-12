# ffuzzy

English | [中文](README.zh-CN.md)

Fuzzy search for Flutter, built on a small C engine.

`ffuzzy` is a byte-for-byte port of [`nucleo`](https://github.com/helix-editor/nucleo)
(the matcher used by the Helix editor) to portable C. You don't need a Rust
toolchain or code generation. The engine is a few C source files, and each
platform's SDK compiles them itself. The stripped native library is about
**32 KB**.

- **Fast** — as fast as or faster than the Rust `nucleo` engine: faster in every
  multi-threaded setup and on `substring`, equal on CJK and single-threaded
  `fuzzy`. Filtering a 100k-item corpus takes about 1.4 ms.
- **Small** — about 32 KB native `.so` (arm64), pure C, no third-party dependencies.
- **All platforms** — Android, iOS, macOS, Linux, Windows and **Web** (WASM).
- **Search any object** — `FuzzyCorpus<T>` searches a `List<T>`, and each hit
  carries the original object (`hit.raw`).
- **One method per match mode** — `fuzzy` (fzf-style, with `! ^ ' $` operators),
  `substring`, `prefix`, `postfix` and `exact`. `search()` picks the algorithm
  through `SearchStrategy` (fuzzy / approx / fallback / merge), and `dual()`
  returns both result lists.
- **Edit-distance search** — `approx()` uses Myers bit-parallel Levenshtein
  distance and tolerates typos, substitutions and transpositions.
- **Multi-threaded** and **async** scans, so large corpora don't freeze the UI.
- **Hit highlighting** with correct Unicode offsets (codepoint to UTF-16).
- **Unicode / CJK** — folds diacritics and simple case; CJK is matched directly.
- **Multi-key search** — attach pinyin / romaji / initials that you compute
  yourself, so a CJK item can be found by typing Latin letters.

## Install

```yaml
dependencies:
  ffuzzy: ^0.6.2

environment:
  sdk: ^3.6.0
  flutter: ">=3.24.0"
```

> **No native platform setup required.** Each platform's SDK compiles and bundles
> the C sources during `flutter build`.

## Web support

On web, `ffuzzy` uses a WASM build of the same C engine. Call `ffuzzyInit` once
at app startup. It does nothing on native, so you can call it unconditionally:

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

After `ffuzzyInit` returns, the whole `FuzzyCorpus` API behaves the same on every
platform.

> **Web note** — WASM runs synchronously on the main thread. `asyncFuzzy` yields
> to the event loop through a microtask, but the WASM computation itself still
> blocks the main thread (there is no Web Worker). For large corpora, keep them
> under ~50k items, or call `fuzzy` synchronously with `limit` to stay within a
> frame.

**Lazy init (corpus created before `ffuzzyInit`):** If a `FuzzyCorpus` is created
before `ffuzzyInit` completes, it runs in *deferred* mode. Sync search methods
return `[]` immediately, while `async*` methods (`asyncFuzzy`, `asyncSearch`,
`asyncApprox`, `asyncDual`, etc.) wait for WASM to initialize and then return
real results. Once WASM is ready, all strategies (`fuzzy`, `approx`, `fallback`,
`merge` and `dual`) behave the same in sync and async variants.

**Parameters:**
- `webUrl` — URL of `ffuzzy.mjs` on a CDN or your own server. No Flutter asset needed.
- `webAssetsUrl` — path of a local Flutter asset (e.g. `/assets/ffuzzy.mjs`). Declare
  the file under `assets:` in `pubspec.yaml`. Works offline.
- If you pass both, `webAssetsUrl` wins.

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
> created it. The mode methods run synchronously on the calling isolate. For a
> large corpus, use the `async*` twins (e.g. [`asyncFuzzy`](#search-modes)) or run
> the corpus on a background isolate so searching doesn't jank the UI.

## Use cases

Search-as-you-type over file paths, command palettes, contact or song lists, log
lines, or any in-memory list where you want fzf-quality ranking at native speed.
It fits large lists (tens of thousands of items) and CJK text best.

---

# API

Everything is exported from `package:ffuzzy/ffuzzy.dart`.

## `ffuzzyInit`

```dart
Future<void> ffuzzyInit({String? webUrl, String? webAssetsUrl})
```

Initializes the WASM engine on **web**. Does nothing on native. Call it once before
creating any `FuzzyCorpus`; calling it again is safe.

## `FuzzyCorpus<T>`

Holds `T` items in memory. Build it once, search it many times.

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
- **`buildAsync`** — builds the corpus on a background isolate, so a large dataset
  doesn't block the UI. On web it yields through a microtask instead.

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
> `refresh` rebuild it in O(n). That is cheap for occasional edits. If you change
> items often, batch the changes.

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

- **`fuzzy`** splits the query into space-separated terms and understands fzf-style
  operators (`!` negate, `^` prefix, `'` substring, `$` suffix). Other modes treat
  the whole query as one literal string.
- **Overrides** (`{FuzzyCase? caseMatching, FuzzyNorm? normalization, bool? parallel,
  int? threads, int? limit, bool? highlight, FuzzyScoring? scoring}`): each
  non-null argument replaces the matching field of the corpus's
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

`maxDistance` is chosen from the query length when omitted (≤2 chars → 0; 3–5 → 1; 6+ → 2).
Also: `approxRaws()`, `asyncApprox()`, `asyncApproxRaws()`.

#### Dual result: `dual()`

Runs both algorithms in one pass over the corpus and returns two separate lists:

```dart
FuzzyDualResult<T> result = corpus.dual('iphoen');
result.fuzzy   // List<FuzzyHit<T>> — subsequence hits
result.approx  // List<FuzzyHit<T>> — edit-distance hits
```

Also: `asyncDual()`.

`async*` calls (`asyncFuzzy`, `asyncSearch`, `asyncApprox`, `asyncDual`, …)
can safely run at the same time. On web, a call made before `ffuzzyInit` finishes
waits for WASM and then returns results. Changing the corpus while a search is
running throws [`StateError`](#errors).

### Lifecycle

| Member | Description |
|---|---|
| `void dispose()` | Safe to call more than once; waits for running async work to finish. Safe to call from `State.dispose()`. |
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

Pass `highlight: true` to fill `FuzzyHit.indices`. Dart strings are UTF-16, so
convert the codepoint positions before building a `TextSpan`:

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

Attach alternate keys that you compute yourself (pinyin, initials, …), so a CJK
item can be found by typing Latin letters:

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

> A `FuzzyCorpus` can't be sent between isolates. Build it inside the isolate and
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

Both algorithms (subsequence and edit distance) are always compiled in. Before
0.6.2, edit distance was behind the `FFZ_EDIT_DISTANCE` build flag; now there is
only one build.

### Native (Android / iOS / macOS / Linux / Windows)

Nothing to configure. The plugin's CMake build always compiles both algorithms.

### Web (WASM)

One prebuilt engine module, both algorithms included:

```dart
await ffuzzyInit(webUrl: 'https://cdn.jsdelivr.net/npm/@codejoo/ffuzzy@0.8.1/dist/ffuzzy.mjs');
```

To build your own:
```bash
# In wasm/:
bash build-engine.sh   # → src/ffz.mjs (WASM inlined as base64, self-contained)
npm run build          # → dist/ffuzzy.mjs
```

---

## Errors

- **Recoverable**: library/symbol load failure → `FuzzyException`; misuse (use
  after `dispose`, mutate during async search) → `StateError`.
- **Hard native faults**: not catchable — see [`FuzzyCrash`](#fuzzycrash-native-only).

### `FuzzyCrash` (native only)

Optional handler for native faults you can't recover from. It prints a backtrace
to stderr before the process exits, and can also write it to a file.

```dart
final report = FuzzyCrash.lastReport();
if (report != null) log('ffuzzy last crash:\n$report');
FuzzyCrash.install(breadcrumbPath: '${dir.path}/ffuzzy_crash.log');
```

---

## High-frequency & large-corpus search

To keep only the result of the latest query while the user types:

```dart
int _gen = 0;
Future<void> onQueryChanged(String q) async {
  final gen = ++_gen;
  final hits = await corpus.asyncFuzzy(q, limit: 50);
  if (gen != _gen) return;           // superseded by newer keystroke
  setState(() => _hits = hits);
}
```

**Concurrent searches** — several `async*` searches can run at the same time (each
gets its own native scratch memory). Changing the corpus while a search is running
throws `StateError`, so await the search or call `asyncDispose` first.

## Platforms

| Platform | Engine | Async search |
|---|---|---|
| Android / iOS / macOS / Linux / Windows | C via `dart:ffi` | `Isolate.run` (true background thread) |
| Web | C via WASM (`dart:js_interop`) | Microtask yield (main thread) |

On native, each platform builds the C sources itself (NDK / CMake / podspec).
You don't need to install an extra toolchain.

## Performance

Real-device (Flutter Windows, profile mode, 100k items):

| | C (ffuzzy) | Rust (nucleo) |
|---|---|---|
| Resident corpus memory | 15.25 MB | 16.54 MB |
| Filter (fuzzy, top-50) | 1.36 ms | 1.65 ms |

Methodology, the differential test (6210/6210 results byte-identical to nucleo),
Unicode coverage and engine design are in [`docs/INTERNALS.md`](docs/INTERNALS.md).

## npm / JavaScript

The same C engine is published as [`@codejoo/ffuzzy`](https://www.npmjs.com/package/@codejoo/ffuzzy)
for browsers and Node, with the same API. Both algorithms are in the one bundle:

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
