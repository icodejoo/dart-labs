# Changelog

## 0.6.2

Five-way parallel code review + two targeted expert passes across the whole
stack (C core, FFI bridge, Dart, WASM/TS), fixing correctness/memory-safety
bugs found since 0.6.0 shipped — no public API changes.

- **Fix: FAST-mode fuzzy scoring silently dropped valid long-range matches.**
  `ffz_fuzzy.c`'s default scoring mode used `0` as both "gap score is
  legitimately zero" and "no gap path exists" — a match whose accumulated
  gap penalties decayed to exactly 0 was treated as no-match. Now tracked via
  a separate validity flag.
- **Fix: 7 bugs in the edit-distance substring engine** (`ffz_edit.c` /
  `ffz_edit_window`) — `malloc(0)` misread as OOM (dropping genuine
  degenerate-window hits), a 32-bit `size_t` overflow guard on the reversed-hay
  scratch buffer, uninitialized `*out_start`/`*out_end` on some early-return
  paths, and a `finalise_results` dispatch that inferred "is this an
  edit-distance result" from the score's sign / a nullable pointer — both
  unreliable signals that misfired for exact matches and for `merge`'s mixed
  seq+edit arrays under allocation OOM. Replaced with an explicit `edit_all`
  flag.
- **Fix: OOM/null-pointer paths in the corpus filter engine** — missing
  NULL/query guard in `_corpus_filter_impl` (inconsistent with every sibling
  filter function), `finalise_results` breaking the "at most `limit` hits"
  contract on OOM, and a matcher-allocation OOM in `merge`/`dual` scans that
  dropped edit-distance-only hits that don't even need a matcher. Added
  overflow guards to array-growth doubling and arena alignment throughout.
- **Fix: a deferred (lazy-init) web corpus permanently returned empty
  results from `fallback`/`merge`/`dual()`** unless a plain `fuzzy`/`approx`
  search had already been called first to trigger WASM init — those three
  entry points checked the deferred flag but never actually triggered
  readiness. Also: their `async*` counterparts ran the search synchronously
  instead of awaiting WASM the way `asyncFuzzy` already did.
- **Fix: native (FFI) `search()` bypassed the C engine for 4 of 5 strategies**
  (`substring`/`prefix`/`postfix`/`exact`), silently dropping alt-key
  matching, normalization, and highlight indices on native for those modes —
  all 5 now route through the C engine consistently.
- **Fix: `toUtf8('')` produced a 1-byte NUL buffer instead of a true empty
  array**, breaking "empty query matches everything" semantics on native.
- **Fix: an FFI ABI typedef mismatch** for `filter_merge`/`filter_fallback`/
  `filter_dual` (parameter types copy-pasted from an unrelated function
  shape).
- **Fix: `asyncSearch`/`asyncApprox`/`asyncDual` on native didn't actually
  offload to a worker isolate** — they wrapped the synchronous call in an
  `async` function, which still runs on the calling isolate. Added 4 new
  async bridge methods so these genuinely run off the main isolate.
- **Fix: memory leaks on the WASM/web path** — `approx()`/`approxRaws()`
  were missing the disposed-check every other search entry point has
  (post-dispose use-after-free); a scratch-buffer free wasn't wrapped in
  try/finally and leaked on throw; OOM checks added to the write/allocate
  paths; an in-flight guard against concurrent double-init.
- **Fix: `update()` forked behavior between debug and release builds** — a
  debug-only `assert` was gating a mutation that must always happen.
- **Build:** `FFZ_SUBSEQUENCE`/`FFZ_EDIT_DISTANCE` CMake toggles removed —
  both search algorithms are now unconditionally compiled in (they always
  shipped together in practice; the toggles only added untested
  configurations). If you were building with one of these OFF, drop the flag.

Verified: 186 C unit tests + 310 leak/OOM checks, 118 Dart tests (`flutter
test`), 69 WASM/TS tests + API parity — all green.

## 0.6.1

Docs only. README (EN/ZH) corrected to match the shipped 0.6.0 API: version
pin, `search()`/`approx()`/`dual()` coverage, single-bundle WASM build (no
more `ffz-{fzf,approx,full}` variants), `matchedKindCode`. No code changes.

## 0.6.0

- **New: edit-distance search.** Myers bit-parallel Levenshtein
  (`src/ffz_edit.c`) alongside the existing subsequence engine. Both
  algorithms are independently modular via `FFZ_SUBSEQUENCE` /
  `FFZ_EDIT_DISTANCE` CMake flags (removed again in 0.6.2 — see above).
- **New: unified `search()` API.** `search(q, {strategy, maxDistance, …})`
  with `fuzzy` | `approx` | `fallback` | `merge` strategies, plus `approx()`
  (edit-distance shortcut, `maxDistance` auto-scales by query length when
  omitted) and `dual()` (single corpus scan, returns
  `FuzzyDualResult(fuzzy:, approx:)`). Each ships `…Raws` / `async…` /
  `async…Raws` variants.
- **BREAKING: async method renames.** `fuzzyAsync` → `asyncFuzzy`,
  `substringAsync` → `asyncSubstring`, … (all async variants now use the
  `async…` prefix); `disposeAndWait` → `asyncDispose`.
- **Build:** explicit source list in `CMakeLists.txt`, fatal error if both
  `FFZ_SUBSEQUENCE` and `FFZ_EDIT_DISTANCE` are OFF.

## 0.5.2

- **Repo move.** `homepage` / `repository` / `issue_tracker` now point at the
  `ffuzzy` subdirectory of the `dart-labs` monorepo instead of the old
  standalone `icodejoo/ffuzzy` repo. No code changes.

## 0.5.1

- **Fix: Windows debug build (`error D8016: '/O2' and '/RTC1' command-line
  options are incompatible`).** The root `CMakeLists.txt` selected `/Od` vs
  `/O2` by string-matching `CMAKE_BUILD_TYPE`, which is empty at configure
  time under multi-config generators (e.g. Ninja Multi-Config), so Debug
  builds silently got `/O2` and clashed with Flutter's Debug-only `/RTC1`.
  Now gated with `$<CONFIG:Debug>` generator expressions, which resolve
  correctly per-config regardless of generator. (#1)

## 0.5.0

- **New: raw-object search.** Every match mode gains a `…Raws` variant that
  returns the matched objects directly — no `FuzzyHit` wrapper — and an
  async/single-result family alongside:
  - `fuzzyRaws` / `substringRaws` / `prefixRaws` / `postfixRaws` / `suffixRaws`
    / `exactRaws` (lists), their `…RawsAsync` twins, and `fuzzyRaw` /
    `substringRaw` / `prefixRaw` / `postfixRaw` / `exactRaw` (+ `…RawAsync`) for
    the single best hit.
  - These skip Pass-2 highlight-index computation, so they're faster than the
    `FuzzyHit`-returning methods when you only need the items, not
    score/indices/metadata.
- **New: `suffix` / `suffixAsync` / `suffixRaws` / `suffixRawsAsync`** — aliases
  for the `postfix` family, matching the more idiomatic Dart naming.
- **Fix: literal queries keep their spaces.** In the non-fuzzy modes
  (`exact` / `prefix` / `postfix` / `substring`) the query is now treated as a
  single literal atom, so `exact("Super Gems 1000")` matches that exact string
  instead of being split into three space-separated terms. (Fuzzy mode still
  parses space-separated terms and `! ^ ' $` operators as before.)
- **C engine.** Added `ffz_corpus_filter_raws` (the skip-index scan behind the
  `…Raws` methods) and bulk result accessors (`ffz_ffi_results_bulk`,
  `ffz_ffi_results_items_bulk`) that fill caller arrays in one call — these cut
  the result-read boundary crossings to O(1), chiefly benefiting the WASM build.

## 0.4.0

- **New: scoring modes.** A `scoring:` parameter on `FuzzyOptions` and on every
  search method selects the ranking algorithm via the `FuzzyScoring` enum:
  - `fast` (default) — 2-row rolling DP, tuned for names / paths / symbols.
  - `off` — no ranking; results returned in insertion order (ID / unique-match).
  - `nucleo` — full-matrix DP, highest fidelity (~2× CPU).
- **Performance.** SIMD reverse scan (`ffz_rfind_ci`) speeds the prefilter tail
  window 20–30%; an ASCII fast path in the rolling preprocess loop adds ~5–10%
  on ASCII input.
- **Hardening** (from a multi-agent security / correctness review):
  - Cap the FAST rolling DP and the per-query atom count so hostile input can't
    drive a CPU hang.
  - Saturate the greedy scorer so a very long match can't wrap its 16-bit score
    and rank below a poor one.
  - `add` / `addAll` / `addKey` now perform the native insert *before* updating
    the Dart mirror, so a failed native add can't desync the corpus and return
    the wrong items afterwards.
  - Use `ptrdiff_t` for substring positions (correct on 64-bit Windows for
    >2 GB inputs); link `Threads::Threads` (musl / older glibc); NUL-terminate
    the Android crash log; honor `FFZ_NO_THREADS`; ship the Android `x86` ABI.

## 0.3.1

**The `ffuzzy` engine is now the compact C matcher** (previously a separate `ffz`
package). The original Rust + `flutter_rust_bridge` implementation is deprecated
and retained only for performance comparison under `benchmark/`.

- **Breaking — engine and API replaced.** The Rust-era API (the old
  `FuzzyMatcher`, `FuzzyStringMatcher`, `fuzzyMatch`, …) is gone. Use the
  C-engine API:
  - `FuzzyCorpus<T>` — generic object search via a `stringOf` extractor (or
    `FuzzyCorpus.strings(...)` for plain strings); hits carry the object as
    `FuzzyHit<T>.obj`.
  - **Match modes are methods**, not a flag: `fuzzy` / `substring` / `prefix` /
    `postfix` / `exact`, each with an `…Async` twin (background isolate).
  - **`FuzzyOptions`** bundles `caseMatching`/`normalization`/`parallel`/
    `threads`/`limit`/`highlight` as corpus-wide defaults (constructor),
    overridable field-by-field via each method's named params.
  - Mutation: `add`/`addAll`/`addKey`/`update`/`removeAt`/`removeWhere`/
    `refresh`/`clear` (append-only native corpus → edits rebuild in O(n)).
  - Plus `FuzzyHit`, `FuzzyKey`/`FuzzyKeyKind`, `fuzzyCodepointToUtf16`,
    `FuzzyException`, `FuzzyCrash`. See the README for the full surface.
- **No Rust toolchain required.** Native code is plain C, compiled and bundled
  per platform by the standard SDK; the previous precompiled-binary download
  step is gone.
- Smaller native library (~32 KB arm64) and equal-or-better performance vs the
  Rust engine (see README / `doc/INTERNALS.md`).
- Web is no longer offered (FFI is unavailable on web).

Functionally this is the former `ffz` 0.1.0 engine, published under the `ffuzzy`
name. Everything below describes that engine.

## 0.1.0 (as `ffz`)

Initial release of the standalone C reimplementation of
[`nucleo-matcher`](https://github.com/helix-editor/nucleo) 0.3.1 with an
idiomatic Dart/Flutter FFI binding. C-only; no Rust dependency.

### Matching
- Fuzzy / substring / prefix / postfix / exact modes; fuzzy parses fzf-style
  operators (`! ^ ' $`) and space-separated terms.
- Per-query case (`respect`/`ignore`/`smart`) and Unicode normalization.
- **Byte-identical to nucleo** (6210/6210 differential pairs, score + indices)
  in the exact build; CJK/Latin-fold/full-case-fold Unicode support.

### Corpus & API
- Resident `FuzzyCorpus` with `add`/`addAll`/`addKey`/`clear`/`filter`.
- `addKey` for host-computed alternate keys (pinyin/romaji/initials).
- `filterAsync` runs the scan on a background isolate (UI never janks);
  overlapping calls are safe (per-call native matcher). Mutating a corpus while
  a `filterAsync` is in flight throws `StateError` (would be a use-after-free).
- Optional multi-threaded scoring (off by default; auto = half the CPUs capped
  at 8; hard ceiling cpu-1). Results are deterministic and identical to serial.
- `fuzzyCodepointToUtf16` to map match indices to UTF-16 offsets for highlighting.

### Build & diagnostics
- Native debug/release split is automatic per Flutter mode: debug/profile keep
  symbols + an optional in-process crash handler (`FuzzyCrash`); release is
  stripped/small (~32 KB arm64) with a `.debug`/`.pdb`/`.dSYM` sidecar for
  offline symbolization. `FFZ_CRASH_IN_RELEASE` forces the handler into release.

### Memory safety
- Drop-on-OOM throughout (no crash on allocation failure); bounded scratch;
  invalid UTF-8 → U+FFFD. Verified by unit + leak + OOM-injection + libFuzzer
  (ASan/UBSan) + the differential test in CI across Linux/macOS/Windows/Android.
