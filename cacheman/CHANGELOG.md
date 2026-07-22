## 0.5.0

**Breaking:**

- Removed `Cacheman.create()`. `Cacheman` now has a plain, synchronous constructor
  (`Cacheman({container, path, options})`) plus an instance method `ensureInitialized()` that
  must be called and awaited once before any read/write — the only `Future` boundary in the API,
  same role `create()` used to play. This lets external code `extend Cacheman` and forward
  constructor params via `super(...)` without any factory boilerplate (Dart constructors can't be
  `async`, which is why `create()` — a static factory — couldn't be subclassed cleanly).

  Migration: `final cache = await Cacheman.create(options: opts);` →
  `final cache = Cacheman(options: opts); await cache.ensureInitialized();`

## 0.4.0

- Added `Cacheman.container` — exposes the underlying `get_storage` `GetStorage` instance, for
  interop that needs the raw container (e.g. `listenKey` for external change notifications, such
  as wiring up a GetX `Rx` for reactive reads).
- Added `Cacheman.storageKey(key)` — returns the actual key `key` is persisted under
  (namespace-prefixed, and `enckey`-encoded when enabled). Needed alongside `container` since the
  real storage key is otherwise opaque once `enckey`'s pluggable codec is involved.

## 0.3.0

**Breaking:**

- Removed the `Store` and `MemoCache` abstraction layers. `Engine` now talks directly to a
  `GetStorage` container and a plain `Map` read cache instead of going through an injected
  backend/memo-cache interface — both only ever had one real implementation
  (`GetStorageAdapter`/`Memo`), so the seam was pure indirection. `GetStorageAdapter` and
  `Memo` (and their files `lib/src/get_storage_adapter.dart`/`lib/src/memo.dart`) are deleted.
  `Store`/`MemoCache`/`Memo` were previously part of the public export surface
  (`package:cacheman/cacheman.dart`) — any code importing them directly will no longer
  compile. This is an internal simplification with no behavioral change to `Cacheman`'s
  public API (`read`/`write`/`remove`/`erase`/... are unaffected).
- Removed the in-process memo read-cache layer entirely. Every `read` now goes straight to
  `get_storage`; every `write` persists straight to `get_storage`, with no intermediate cache.
  `CachemanOptions.memoized`, `CacheOptions.memoized`, `CachemanOptions.cloned`, and
  `CachemanOptions.deepCloned` are all removed (there is no longer a shared memo reference for
  `cloned`/`deepCloned` to protect against — every `read()` already returns a value freshly
  deserialized from JSON, never aliased to anything the engine holds onto). `Engine.destroy()`
  and `Cacheman.destroy()` are removed — with no memo cache, `destroy()` had nothing left to do.
- Merged the `Engine` class directly into `Cacheman` — `Cacheman` was already a pure
  forwarding wrapper around `Engine` with no other consumers, so the two are now one class
  (`lib/src/cacheman.dart`); `lib/src/engine.dart` is deleted, and `CacheOptions`/
  `CachemanOptions` moved to `lib/src/options.dart`. This is an internal simplification with
  no behavioral change to `Cacheman`'s public API, but it **is breaking** for anyone who
  imported the `Engine` type directly (it was previously exported from
  `package:cacheman/cacheman.dart`) — that export is removed, since nothing outside the
  package ever constructed an `Engine` on its own.

## 0.2.0

**Breaking:**

- `ss` in-memory tier removed; only the persistent `ls` tier remains. `Cacheman.create()` no
  longer accepts a `cap` parameter, and `Cacheman.ss`/`Memory` no longer exist.
- `Engine`'s core CRUD methods renamed: `get`/`getAll` → `read`/`readAll`, `set`/`setAll` →
  `write`/`writeAll`, `clear` → `erase`. `remove`/`removeAll` are unchanged.
- `Cacheman.ls` removed. `Cacheman` now exposes `Engine`'s whole public API directly at the top
  level (`read`/`readAll`, `write`/`writeAll`, `remove`/`removeAll`, `erase`, `key`/`keys`/`length`/
  `purge`/`namespace`) — call `cache.write(...)`/`cache.read(...)` etc. instead of
  `cache.ls.write(...)`/`cache.ls.read(...)`. `fast`/`lazy`/`batchFast`/`debug()` now take a
  `Cacheman` instead of an `Engine` (`fast<String>(cache, 'token')`, `debug(cache)`).

## 0.1.0

Initial version — a `get_storage`-backed persistent tier (`ls`) plus a pure in-memory tier (`ss`),
sharing one engine: TTL & absolute expiry, sliding renewal, namespaces, pluggable serialization, an
optional `Codec` hook (no implementation shipped), batch get/set/remove, `raw`/`readonly` modes,
`fast`/`lazy`/`batchFast` key-bound accessors, a `debug()` snapshot helper, an optional `ss` capacity cap
(`cap`, FIFO eviction), and a generic `Jsonx` serializer round-tripping `DateTime`/`Duration`/`Set`/
`BigInt`/`Uri`/`RegExp`. The Dart/Flutter sibling of `@codejoo/storage`.
