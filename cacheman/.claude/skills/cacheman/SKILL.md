---
name: cacheman
description: >-
  Work on cacheman — a type-safe wrapper over get_storage (persistent, `ls`) and a pure
  in-memory store (`ss`) sharing one Engine: TTL & absolute expiry, sliding renewal,
  namespaces, pluggable serialize/deserialize, an optional Codec hook (no implementation
  shipped), enckey key obfuscation, raw/readonly modes, batch ops, an owned-key cache, a
  Jsonx serializer, and fast/lazy/batchFast key-bound accessors. Flutter-only (get_storage
  dependency), Dart/Flutter sibling of `@codejoo/storage` (TypeScript). Read BEFORE modifying
  anything under lib/src/ or changing CachemanOptions semantics. Covers Engine's internal
  invariants, the owned-key cache gotcha, sliding-renewal's 90% threshold, force's
  sync-only retry, and the verify workflow. Triggers on: Cacheman.create, Engine, ls, ss,
  CachemanOptions, CacheEntity, sliding, namespace, enckey, codeable, raw mode, readonly,
  memoized, cloned, deepCloned, force, onError, Jsonx, fast/lazy/batchFast, debug(), Memory
  cap, GetStorageAdapter.
---

# cacheman

Flutter package (`get_storage: ^2.1.1` — the only runtime dependency besides `flutter`
itself). One `Engine` class (`lib/src/engine.dart`) implements the whole read/write/expiry/
namespace logic; `ls` and `ss` are two `Engine` instances that share the same
`CachemanOptions` but differ only in backend (`Store` implementation) and `Memo` instance.
Entry point `lib/cacheman.dart` re-exports everything callers need. Tests:
`test/cacheman_test.dart` (unit tests against a `FakeStore`, plus a real-`get_storage`
integration group at the bottom). `example/cacheman_example.dart` is a single-file runnable
Flutter app (`flutter run example/cacheman_example.dart`) exercising every public feature —
update it alongside the READMEs on any public API change.

**`Cacheman.create()` is the only `Future` boundary in the whole API** — every `Engine`
method after that is synchronous, because `get_storage` is sync-after-init (see
`Cacheman`'s class doc for the full "why" vs the TS sibling's async IndexedDB tier). Do not
add async methods to `Engine` without re-reading that design note — it's a deliberate
constraint, not an oversight.

The two READMEs (`README.md` EN, `README.zh-CN.md` ZH) are the canonical usage docs — keep
both in sync on any public API change. Every field in `lib/src/*.dart` already carries a
bilingual (EN + 中文) doc comment; match that convention for anything new.

## Architecture map

- **`lib/src/interface.dart`** — the contracts: `Store` (string-keyed backend: `get`/`set`/
  `remove`/`clear`/`key(index)`/`keys()`/`length`), `MemoCache` (dynamic-valued read cache:
  `get`/`set`/`remove`/`clear`), `Codec` (`encode`/`decode` string transform, no
  implementation shipped), `CachemanOnError` typedef.
- **`lib/src/memory.dart`** — `Memory implements Store`, backs `ss`. `LinkedHashMap`-based,
  soft `cap` (total `key.length + value.length`), FIFO eviction by *insertion* order
  (overwriting an existing key does NOT reset its position — see the class doc's
  self-eviction gotcha: overwriting the oldest key with a bigger value can evict that very
  write).
- **`lib/src/get_storage_adapter.dart`** — `GetStorageAdapter implements Store`, backs `ls`.
  Wraps a `GetStorage` container. `set`/`remove`/`clear` are fire-and-forget
  (`.catchError` → `onError`) because get_storage's disk flush is async and debounced,
  decoupled from any single call.
- **`lib/src/memo.dart`** — `Memo implements MemoCache`, plain `Map`-backed. One instance per
  `Engine` (so per `ls`/`ss`), never shared across `Cacheman` instances.
- **`lib/src/entity.dart`** — `CacheEntity` (the write envelope: `value`/`expireAt`/
  `createdAt`/`ttl`), `defaultSerialize`/`defaultDeserialize` (plain `jsonEncode`/
  `jsonDecode`). `createdAt` doubles as "this entry was written by this library" — never
  drop it when adding a new field, it's what stops a coincidentally-shaped foreign entry
  from being mistaken for an expired one.
- **`lib/src/engine.dart`** — `CacheOptions` (per-`set` call: `ttl`/`expireAt`/`memoized`),
  `CachemanOptions` (instance-level, see below), `Engine` (all the logic).
- **`lib/src/cacheman.dart`** — `Cacheman.create()` wiring: builds `ls` (GetStorageAdapter +
  Memo) and `ss` (Memory + Memo) from one `CachemanOptions`, plus `setNamespace`/`destroy`.
- **`lib/src/fast.dart`** — `FastAccessor<V>`, `fast`/`lazy`/`batchFast` — key-bound
  accessor sugar over an `Engine`, no independent state.
- **`lib/src/debug.dart`** — `debug(Engine)`: read-only decrypted snapshot, never writes
  back (doesn't pollute `keys()`/`length`).
- **`lib/src/jsonx.dart`** — `Jsonx.encode`/`Jsonx.decode<T>`: a `toEncodable`/`reviver` pair
  round-tripping `DateTime`/`Duration`/`Set`/`BigInt`/`Uri`/`RegExp` via a strict
  `{'#t': tag, 'value': ...}` tagged shape (`_isTagged` requires *exactly* those two keys,
  so it never collides with real user data that happens to carry a same-named field).

## `Engine` invariants (do NOT break)

- **`Cacheman.create()` does NOT call `GetStorage.init(container)`.** That factory method
  internally caches instances by container name with `path` baked in as `null` on first
  call — passing `path:` later would silently be ignored on a cache hit. Instead, `create()`
  constructs `GetStorage(container, path)` directly and awaits `initStorage` itself, plus
  calls `WidgetsFlutterBinding.ensureInitialized()` itself (normally `init()`'s job). Do not
  "simplify" this back to `GetStorage.init(...)`.
- **The owned-key cache (`_ownedKeysCache`) is per-`Engine`-instance, not per-backend.** It's
  lazily built via a full scan (`_store.keys().where(_owns)`) on first access, then
  incrementally maintained by `_trackOwned`/`_untrackOwned` as *this* instance writes/
  deletes. **Two `Engine` instances sharing the same namespace on the same backend (e.g. two
  separate `Cacheman.create()` calls for the same container+namespace) can drift this cache
  stale** — a write through instance A is invisible to instance B's cache. Fine for the
  normal one-instance-per-namespace usage (per-account isolation); do not assume it's safe
  for concurrent same-namespace instances without addressing this first. `setNamespace`
  invalidates the cache wholesale (ownership predicate changed).
- **Sliding renewal only fires past 90% of the ttl elapsed** (`entity.expireAt! - now <=
  entity.ttl! * 0.9`) — a hot read well within its ttl does NOT trigger a write-back. Don't
  lower this threshold casually; it exists specifically to stop high-frequency reads from
  amplifying into high-frequency writes.
- **`force`'s retry only covers a *synchronous* write exception** (e.g. a custom
  `serialize` throwing, or `FakeStore.failNext` in tests) — `_persist` catches, purges
  expired entries, retries once, then reports via `onError`. `GetStorageAdapter`'s actual
  disk-flush failures are async (`.catchError` on the `GetStorage.write` Future) and are
  *never* retried — they only ever reach `onError`. Don't conflate the two failure paths.
- **`raw: true` requires a `String` value** — anything else is warned and the write is
  skipped (`T value` checked `is! String` in `Engine.set`). This mirrors a fix in the TS
  sibling; don't silently coerce non-strings.
- **`readonly: true` short-circuits `set` before the raw/entity branch** — `write()` only
  runs if `get<dynamic>(key) == null`. A second `set` on a live key is a silent no-op; it
  fires again once the key expires.
- **`enckey` requires a `codec`** — without one, `Engine`'s constructor prints a warning and
  keys stay plaintext (`_enckey` getter is `_opts.enckey && _opts.codec != null`, so this is
  enforced structurally, not just documented). Same pattern for `codeable` without a codec.
  `_ekCache` (encrypted-key memoization) is capped at 1024 entries, cleared wholesale on
  overflow — a guard against unbounded growth under dynamic key names, not an LRU.
- **`cloned` cloning picks the concrete `Map` type before copying** (`value is Map<String,
  dynamic>` checked before the bare `value is Map` fallback) — a bare `value is Map` type
  test alone promotes to `Map<dynamic, dynamic>` regardless of the original's actual key
  type, which would break a caller's `get<Map<String, dynamic>>()` cast after a `Map.of`
  copy. Don't collapse these two branches.
- **`deepCloned` only applies when `cloned` is also `true`** — it changes shallow→deep, it
  is not an independent switch. Deep clone re-encodes/decodes through `jsonEncode`/
  `jsonDecode` (no generic Dart `structuredClone` primitive exists); a value that isn't
  JSON-encodable falls back to returning it unchanged (equivalent to sharing the reference,
  not an error).
- **`_persist` calls `_trackOwned` on every successful write, including retries** — if you
  add a new write path, remember to call `_trackOwned`/`_untrackOwned` so the owned-key
  cache stays consistent; the cache is *not* self-healing except via a full rebuild
  triggered by `setNamespace`.

## Verify workflow

```bash
cd D:/workspaces/dart-labs/cacheman
flutter analyze         # acceptance gate — must be clean
flutter test             # test/cacheman_test.dart — unit tests (FakeStore) + get_storage integration group
flutter analyze example/cacheman_example.dart   # example is analyzed separately, not part of the main lib scan
dart pub publish --dry-run   # release readiness check before bumping/publishing
```

The `Cacheman.create()` integration tests need a working `path_provider` platform channel
even though an explicit `path:` is passed (get_storage's io backend unconditionally calls
`getApplicationDocumentsDirectory()` first) — `test/cacheman_test.dart`'s
`FakePathProviderPlatform` satisfies that call; its returned path is never actually used.
On Windows, `get_storage` never closes its file handle, so the temp dir cleanup in
`tearDown` is best-effort only, not a correctness assertion — don't turn a cleanup failure
into a test failure.

Always update both READMEs for any public API or semantics change, and keep new
`CachemanOptions`/`CacheOptions` fields' doc comments bilingual (EN + 中文), matching every
existing field.
