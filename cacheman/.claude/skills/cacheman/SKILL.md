---
name: cacheman
description: >-
  Work on cacheman — a type-safe wrapper over get_storage (persistent, `ls`), one class
  (`Cacheman`): TTL & absolute expiry, sliding renewal, namespaces, pluggable
  serialize/deserialize, an optional Codec hook (no implementation shipped), enckey key
  obfuscation, raw/readonly modes, batch ops, an owned-key cache, a Jsonx serializer, and
  fast/lazy/batchFast key-bound accessors, and a public container/storageKey escape hatch for
  external interop (e.g. GetX reactive wiring). Flutter-only (get_storage dependency),
  Dart/Flutter sibling of `@codejoo/storage` (TypeScript). Read BEFORE modifying anything
  under lib/src/ or changing CachemanOptions semantics. Covers Cacheman's internal
  invariants, the owned-key cache gotcha, sliding renewal after at least 10% of ttl elapsed, force's sync-only
  retry, and the verify workflow. Triggers on: Cacheman(), ensureInitialized, ls, CachemanOptions,
  CacheEntity, sliding, namespace, enckey, codeable, raw mode, readonly, force, onError,
  Jsonx, fast/lazy/batchFast, debug(), read/write/erase, container, storageKey, listenKey.
---

# cacheman

Flutter package (`get_storage: ^2.1.1` — the only runtime dependency besides `flutter`
itself). One `Cacheman` class (`lib/src/cacheman.dart`) implements the whole read/write/
expiry/namespace logic directly — no internal `Engine` indirection; `ls` is a `Cacheman`
instance talking directly to a `GetStorage` container (no backend abstraction seam — it
only ever had one real implementation, so it was removed; also no in-process read cache —
every `read` goes straight to `GetStorage`), wired up from one `CachemanOptions`. Entry point
`lib/cacheman.dart` re-exports everything callers need. Tests: `test/cacheman_test.dart`
(every case goes through a real `Cacheman()` + `await ensureInitialized()` backed by real
`get_storage`, since `Cacheman` no longer accepts an injected fake backend — a shared
`setUp`/`tearDown` builds a fresh temp dir + `FakePathProviderPlatform` per test, and each
test picks a fresh container name). `example/lib/` is a runnable Flutter app (`flutter run
example/lib/main.dart`) exercising every public feature — update it alongside the READMEs
on any public API change.

**`Cacheman()`'s constructor is plain and synchronous; `ensureInitialized()` (an instance
method, not a static factory) is the only `Future` boundary in the whole API** — every other
method is synchronous, because `get_storage` is sync-after-init (see `Cacheman`'s class doc
for the full "why" vs the TS sibling's async IndexedDB tier). Do not add async methods to
`Cacheman` without re-reading that design note — it's a deliberate constraint, not an
oversight. There used to be a static `Cacheman.create()` factory instead; it was removed in
favor of this plain-constructor + `ensureInitialized()` split specifically so external code
can `extend Cacheman` and forward constructor params via `super(...)` — a static factory
can't be subclassed that way, and Dart constructors can't be `async`.

`Cacheman`'s public CRUD surface is `read`/`readAll`, `write`/`writeAll`, `remove`/
`removeAll`, `erase` (plus `keys`/`key(index)`/`length`/`purge`/`setNamespace`,
unaffected by that rename). `Cacheman` holds its `GetStorage` (`_gs`) directly as a private
field — there is no `Store`/`MemoCache` contract to satisfy anymore and no memo read cache;
adding a second backend would mean giving `Cacheman` an internal branch, not resurrecting an
injected-interface seam. `Cacheman.destroy()` was removed along with the memo cache — there
was nothing left for it to release.

`Cacheman.container` (public `GetStorage` getter) and `Cacheman.storageKey(key)` (public
`_fullKey` wrapper — namespace-prefixed, `enckey`-encoded when enabled) exist purely for
external interop that needs the raw, real storage key — e.g. wiring `container.listenKey(
storageKey(key), ...)` up to a GetX `Rx` for a VueUse-`useStorage`-style reactive layer. Use
`storageKey(key)`, not `namespace + key`, whenever `enckey` might be involved — the codec's
encoding is a private, pluggable implementation detail that can't be reproduced externally.

The two READMEs (`README.md` EN, `README.zh-CN.md` ZH) are the canonical usage docs — keep
both in sync on any public API change. Every field in `lib/src/*.dart` already carries a
bilingual (EN + 中文) doc comment; match that convention for anything new.

## Architecture map

- **`lib/src/interface.dart`** — `Codec` (`encode`/`decode` string transform, no
  implementation shipped), `CachemanOnError` typedef. (The former `Store`/`MemoCache`
  backend contracts were removed — `Cacheman` now talks directly to `GetStorage`, see below.)
- **`lib/src/options.dart`** — `CacheOptions` (deprecated, unused — pass `ttl`/`expireAt` to `write` directly),
  `CachemanOptions` (instance-level configuration for `Cacheman`).
- **`lib/src/entity.dart`** — `CacheEntity` (the write envelope: `value`/`expireAt`/
  `createdAt`/`ttl`), `defaultSerialize`/`defaultDeserialize` (plain `jsonEncode`/
  `jsonDecode`). `createdAt` doubles as "this entry was written by this library" — never
  drop it when adding a new field, it's what stops a coincidentally-shaped foreign entry
  from being mistaken for an expired one.
- **`lib/src/cacheman.dart`** — the whole `Cacheman` class: the constructor (builds `_gs`
  directly from the `GetStorage` container and one `CachemanOptions`) plus `ensureInitialized()`
  (awaits `_gs`'s disk load), plus all the logic: `read`/`readAll`, `write`/`writeAll`,
  `remove`/`removeAll`, `erase`,
  `key`/`keys`/`length`/`purge`/`setNamespace`. `_gs` (the `GetStorage` container:
  `_gs.write`/`.remove`/`.erase` calls are fire-and-forget with best-effort `.catchError`
  handlers; get_storage 2.1.1 drops the actual flush Future, so real disk errors cannot
  reach `onError` through them). `_hydrate` deletes unreadable entries and reports the
  original exception (or FormatException for a null codec result); purge/readonly probes
  remain quiet.
  There is no in-process read cache — every `read` re-fetches from `_gs`.
- **`lib/src/fast.dart`** — `FastAccessor<V>`, `fast`/`lazy`/`batchFast` — key-bound
  accessor sugar over a `Cacheman` (its own `get`/`set`/`remove` methods forward to
  `Cacheman.read`/`Cacheman.write`/`Cacheman.remove` — the accessor's own method names were
  not part of the earlier `Engine`-CRUD rename).
- **`lib/src/debug.dart`** — `debug(Cacheman)`: decrypted snapshot, never writes the snapshot
  back (doesn't pollute `keys()`/`length`); ordinary read side effects still apply
  (lazy-expiry deletion, sliding renewal, unreadable-entry deletion/reporting).
- **`lib/src/jsonx.dart`** — `Jsonx.encode`/`Jsonx.decode<T>`: a `toEncodable`/`reviver` pair
  round-tripping `DateTime`/`Duration`/`Set`/`BigInt`/`Uri`/`RegExp` via a strict
  `{'#t': tag, 'value': ...}` tagged shape (`_isTagged` requires *exactly* those two keys,
  so it never collides with real user data that happens to carry a same-named field).

## `Cacheman` invariants (do NOT break)

- **`Cacheman()`'s constructor does NOT call `GetStorage.init(container)`.** That factory
  method internally caches instances by container name with `path` baked in as `null` on
  first call — passing `path:` later would silently be ignored on a cache hit. Instead, the
  constructor builds `GetStorage(container, path)` directly itself; `ensureInitialized()`
  then awaits that instance's own `initStorage` and calls
  `WidgetsFlutterBinding.ensureInitialized()` (normally `init()`'s job). Do not "simplify"
  this back to `GetStorage.init(...)`.
- **Writes assert explicit initialization in debug builds.** `_initialized` becomes true
  only after `ensureInitialized()` awaits `initStorage`; `_persist` asserts before its
  retry try/catch so misuse is not swallowed. Release behavior stays unchanged.
- **The owned-key cache (`_ownedKeysCache`) is per-`Cacheman`-instance, not per-backend.**
  It's lazily built via a full scan (`_gs.getKeys<Iterable<dynamic>>().where(_owns)`) on
  first access, then incrementally maintained by `_trackOwned`/`_untrackOwned` as *this*
  instance writes/deletes. **Two `Cacheman` instances sharing the same namespace on the
  same backend (e.g. two separate `Cacheman()` instances for the same
  container+namespace) can drift this cache stale** — a write through instance A is
  invisible to instance B's cache. Fine for the normal one-instance-per-namespace usage
  (per-account isolation); do not assume it's safe for concurrent same-namespace instances
  without addressing this first. `setNamespace` invalidates the cache wholesale (ownership
  predicate changed).
- **Sliding renewal only fires once at least 10% of the ttl has elapsed (at most 90%
  remains)** (`entity.expireAt! - now <= entity.ttl! * 0.9`) — reads while more than 90%
  remains do NOT trigger a write-back. Preserve this guard: it exists specifically to stop
  high-frequency reads from amplifying into high-frequency writes.
- **`force`'s retry only covers a *synchronous* write exception** (e.g. a custom
  `serialize` throwing) — `_persist` catches, purges expired entries, retries once, then
  reports via `onError`. Actual disk-flush failures are async and are *never* retried;
  get_storage 2.1.1's write Future cannot carry them, so `_reportFlushError` is best-effort
  only. Don't conflate `_reportError` (sync) with `_reportFlushError` (async). Note there's no real-backend way to force a
  *synchronous* `get_storage` write failure in tests anymore (the old `FakeStore.failNext`
  seam is gone) — `test/cacheman_test.dart`'s "force / onError" group instead verifies that
  flush failures do not throw synchronously out of an initialized `write()`; it does not
  guarantee `onError` for a real disk failure. Throwing serializers cover sync retries.
- **`raw: true` requires a `String` value** — anything else is warned and the write is
  skipped (`T value` checked `is! String` in `Cacheman.write`). This mirrors a fix in the TS
  sibling; don't silently coerce non-strings.
- **`readonly: true` short-circuits `write` before the raw/entity branch** — `_alive` checks
  presence without renewal/deletion/reporting; a stored null counts as present. A second
  `write` on a live key is a silent no-op; it fires again once the key expires.
- **`enckey` requires `keyCodec ?? codec`** — without one, the constructor prints a warning
  and keys stay plaintext (`_enckey` checks both the flag and `_keyCodec`). Same pattern for
  `codeable` without a value codec. `_ekCache` (encoded keys) and `_lkCache` (storage key →
  logical key) are each capped at `_keyCacheLimit` (1024), cleared wholesale on overflow
  and together on `setNamespace` — bounded maps, not LRUs. Null key decodes retain the
  original fallback behavior and are not memoized.
- **`_persist` calls `_trackOwned` on every successful write, including retries** — if you
  add a new write path, remember to call `_trackOwned`/`_untrackOwned` so the owned-key
  cache stays consistent; the cache is *not* self-healing except via a full rebuild
  triggered by `setNamespace`.

## Verify workflow

Run these commands at the package root（在包根目录执行）:

```bash
flutter analyze         # acceptance gate — must be clean
flutter test             # test/cacheman_test.dart — all groups run against a real get_storage backend
flutter analyze example   # independently analyze the example package (entry: example/lib/main.dart)
dart pub publish --dry-run   # release readiness check before bumping/publishing
```

The `Cacheman()` integration tests need a working `path_provider` platform channel
even though an explicit `path:` is passed (get_storage's io backend unconditionally calls
`getApplicationDocumentsDirectory()` first) — `test/cacheman_test.dart`'s
`FakePathProviderPlatform` satisfies that call; its returned path is never actually used.
On Windows, `get_storage` never closes its file handle, so the temp dir cleanup in
`tearDown` is best-effort only, not a correctness assertion — don't turn a cleanup failure
into a test failure.

Always update both READMEs for any public API or semantics change, and keep new
`CachemanOptions`/`CacheOptions` fields' doc comments bilingual (EN + 中文), matching every
existing field.
