## 0.8.0

**Breaking:**

- `Cacheman()` now uses pure Dart memory storage. Data is lost on restart. Same-name
  containers still share memory and a Hub within one isolate; `ensureInitialized()`
  remains required. The default constructor no longer accepts `path`.
- `container` now returns `MemoryStorage`, not `GetStorage`. Custom backends should
  expose their own typed handle. `Cacheman.custom` and `AsyncCacheman` retain their
  existing primitive contracts.
- Removed the get_storage dependency and its transitive get/path_provider packages
  from the main package. Apps using GetX must depend on `get` directly.

Migration for persistent caches:

1. Add `get_storage: ^2.1.1` to the consuming app's dependencies.
2. Copy `example/lib/get_storage_cache.dart` into the app. This app-owned adapter
   includes initialization, synchronous CRUD, shared notifications and deferred saves.
3. Replace `Cacheman(...)` with `GetStorageCache(...)`, keeping the previous container
   name, path (if set) and options. Existing storage keys and serialized values are
   unchanged. Replace raw get_storage access through `container` with `box`.

```dart
import 'package:cacheman/cacheman.dart';
import 'get_storage_cache.dart'; // copied from example/lib/

final cache = GetStorageCache(
  container: 'cacheman', // keep the previous name; pass the previous path if set
  options: const CachemanOptions(namespace: 'account'),
);
await cache.ensureInitialized();
cache.write('token', 'abc'); // app-owned persistence
```

The adapter is only in the example and is not exported by the main library. Apps
that choose get_storage retain its platform restrictions. The demo keeps persistence
and displays 0.8.0. Package tests use memory/custom backends; real get_storage
integration tests now live in the example.

## 0.7.3

- Shorten the pubspec description to meet the pub.dev length limit.

## 0.7.2

- Docs only: rewrote README wording in plain language.

## 0.7.1

- Docs only: README install snippet and migration chapter now describe the released 0.7.0 API (`Cacheman.custom`, `AsyncCacheman`, subclass changes); example app gains a `Cacheman.custom` demo and a real README; removed stale "planned" wording.

## 0.7.0

Highlights: layered storage (synchronous `Cacheman` + abstract `AsyncCacheman`, `Cacheman.custom`
for custom synchronous backends), structured `CachemanError` reporting, `ValueAdapter`, a
non-throwing `read`, narrowed `force`, and the shared Hub with `watch`/`flush`/`flushDelay`/
`purgeOnInit`. See the Breaking list and the README migration chapter before upgrading from 0.6.

**Fixes (full review):**

- Default listenRaw no longer throws StateError during get_storage initialization;
  table replacements notify all watchers and empty-string key writes no longer report clear.
- Sliding renewal requires createdAt, preserving foreign expireAt/ttl-shaped data.
- Jsonx DateTime stores epoch microseconds and UTC/local mode for timezone-safe round trips;
  legacy string data remains readable.
- Jsonx preserves NoSuchMethodError from toJson as JsonUnsupportedObjectError.cause;
  correct Enum documentation to explain encoding errors and explicit conversion.

**Breaking:**

- `onError` always receives a `CachemanError` subclass; inspect `cause` for the original
  exception. Migrate `error is FormatException` to
  `error is CorruptEntryError && error.cause is FormatException`.
- `read<T>` type mismatches now return the default and report `TypeMismatchError`, retaining
  data. Replace TypeError catches with onError handling; use ValueAdapter for typed collections
  or custom classes. int/double are not coerced; use num or an adapter.
- `force` remains supported and defaults to true, but only retries backend write failures.
  Encoding/serialization/adapter failures report SerializeError without purge/retry; fix the
  converter instead of relying on repeated serialization. Final backend failures are WriteError;
  background persistence failures are FlushError; watch callback failures are WatchError.
- Removed unused deprecated `CacheOptions`; pass ttl/expireAt directly to write/writeAll.
- Deprecated O(index) `key(index)`; replace repeated indexed calls with one keys() snapshot.

**Added (stage 2):**

- Source-compatible read(key, [default]) plus readWith(key, {defaultValue, adapter}); Dart
  cannot mix optional positional and named parameters in one signature.
- Shared typed value checks and ValueAdapter with eager listOf/mapOf conversion; typed
  fast/lazy/batchFast accessors support adapters and a default millisecond ttl.

**Added (stage 1b):**

- Private per-identity Hub with one backend listener, self-healing owned-key indexes,
  typed synchronous watch/cancel, own-write suppression and namespace migration.
- Opt-in flushDelay (shared earliest deadline), void flush(), pending-write lifecycle
  saves and nonblocking purgeOnInit. Defaults preserve existing persistence behavior.
- `Cacheman.custom(...)` constructor for subclasses that bring their own primitives; plain
  forwarding subclasses keep full get_storage behavior (shared Hub, watch, flushDelay).
- Protected notification/deferred-flush/identity hooks with conservative defaults for
  custom subclasses; lazy memoized CacheContext.key plus actual storageKey.
- Bilingual examples/docs and full acceptance matrix, zero-dependency coverage and
  test-name gates; regression coverage for stages 0/1a and legacy functionality.

**Added (stage 1a):**

- Protected synchronous storage primitives and CacheContext/CacheOp for user subclasses;
  the default GetStorage container is lazy and still receives the supplied path on first use.
- Abstract AsyncCacheman with awaited CRUD, TTL/absolute/sliding expiry, namespace/enckey,
  codecs, raw/readonly/force, ownership-aware enumeration and scoped erase. No built-in
  asynchronous backend or extra dependency; no read-value or owned-key set cache.
- Private composed core shared by both facades for key spaces, envelopes, validation,
  renewal decisions and original-error reporting. Existing synchronous APIs stay intact.
- Bilingual layered-storage docs with app-side SharedPreferencesWithCache, Hive CE LazyBox
  and dart:io examples, an interactive parallel-cache demo and primitive/async regression tests.
- Document preserved enckey-only erase protection, sync versus awaited force failures,
  backend lifecycle/concurrency boundaries and lazy container first-access path precedence.

**Fixes:**

- R1: Guard incremental owned-key updates with index identity and scope generation during
  reentrant namespace changes. / 重入切域时校验索引身份与作用域代数，防止跨域误删。
- R2: Use lowercase UTF-8 hex filenames in both directory-backend examples to avoid
  case-insensitive filesystem collisions. / 双语目录后端示例改用小写 UTF-8 十六进制，避免大小写碰撞。
- R3: Track onError exceptions by identity instead of a shared failure counter, so caught
  unrelated errors cannot interrupt watch dispatch. / 按异常身份识别 onError 传播，避免已处理的无关异常打断 watch。
- R4: Preserve handler exceptions and stacks through mutation Futures and Zone propagation
  instead of wrapping them as FlushError. / 变更 Future 中的处理器异常保留身份和堆栈，按 Zone 传播。
- R5: Skip migrated watchers in keyed notification snapshots while retaining clear delivery.
  / 键通知快照跳过已迁移 watcher，clear 仍通知所有活跃订阅。
- R6: Register delayed flush before memory notifications so reentrant writers retain latest
  error ownership. / 延迟落盘在内存通知前登记，保留重入写入者的最新错误归属。
- Align architecture, bilingual READMEs and contributor skill with the actual synchronous API,
  sliding renewal after at least 10% of TTL elapsed, and get_storage's transitive `get` dependency;
  remove the obsolete architecture SVG and correct example verification paths.
- Guard the GetX interop example against collection/object feedback loops; document synchronous
  listeners, whole-container erase notifications and isolate-local storage maps.
- Cache decoded logical keys for `enckey` enumeration (bounded to 1024 entries); invalidate key
  caches on namespace changes.
- Report read-time decode/deserialization failures via `onError` or print while still deleting
  unreadable entries and returning the default value; keep purge scans quiet.
- Assert initialization before persistence in debug builds; release behavior is unchanged.
- Raise the Flutter minimum to 3.24.0 to match the Dart 3.5 SDK constraint.

**Performance:**

On-device profile benchmark against 0.6.0 (Android 12, arm64 profile build, real get_storage,
shared API only; medians of 7 rounds, 3 alternating launches per version). Hot paths are at
parity; the shared Hub, type checks and structured errors cost well under 1 µs per call.
/ 真机 profile 基准（对比 0.6.0）：热路径持平，Hub、类型校验与结构化错误的单次开销远低于 1 µs。

| Case | 0.6.0 | 0.7.0 | new/old |
|---|---|---|---|
| read short string | 2.59 µs | 2.68 µs | 1.04 |
| read 1KB / 10KB map | 40.0 / 344.6 µs | 40.2 / 343.1 µs | 1.00 |
| read 1KB with ttl / sliding | 41.2 / 41.6 µs | 41.2 / 41.4 µs | 1.00 |
| write short string / 1KB map | 9.2 / 70.4 µs | 9.8 / 71.0 µs | 1.07 / 1.01 |
| writeAll / readAll 100 × 1KB | 6.78 / 3.69 ms | 6.94 / 3.71 ms | 1.02 / 1.01 |
| purge 2000 live entries | 8.06 ms | 6.80 ms | 0.84 |
| remove + write cycle | 13.6 µs | 18.8 µs | 1.38 |
| enckey write / read | 9.2 / 5.8 µs | 10.0 / 6.4 µs | 1.09 |

- The remove + write cycle pays about 5 µs for Hub version tracking and watch notification
  (noisy: best runs differ by 0.6 µs); cached `length` moves from 0.03 to 0.2 µs for the Hub
  version check. First-time `keys()` scans varied 2.5–6.7 ms within each version, so no
  difference is claimed.

## 0.6.0

**Breaking:**

- Namespace prefix is now unambiguous: `%` and `:` inside a namespace are escaped (`%25`/`%3A`),
  so `namespace: 'a'` + key `b:x` no longer collides with `namespace: 'a:b'` + key `x`, and
  `a.erase()` no longer wipes `a:b`'s data. Namespaces without `%`/`:` keep the same storage
  keys; for the rest, persisted entries under the old prefix are no longer visible (migrate or
  let them expire). `Cacheman.namespace` returns the escaped prefix.

**Fixes:**

- `write()` / sliding renewal: a throwing `serialize`/codec is now inside `_persist`'s
  try/catch, so it goes through `force` + `onError` instead of escaping.
- `purge()` skips `raw` mode (no envelope, no expiry); `readonly` checks real presence
  (a stored `null` counts, no sliding renewal side effect).
- `Jsonx`: falls back to `toJson()` for custom objects; a plain `Map` shaped like a type tag is
  escaped and round-trips unchanged.
- Docs: get_storage 2.1.1's write Future cannot carry flush errors, so `onError` is only
  guaranteed for synchronous failures; same-container instances share the first-seen `path`.

**Added / deprecated:**

- `CachemanOptions.keyCodec` — a deterministic codec for `enckey`, independent of the value
  `codec` (falls back to `codec`).
- `CacheOptions` is `@Deprecated` (no method ever accepted it); removed in the next breaking release.
- Internal: `length`/`key`/`keys` read the owned-key set directly; erase reuses `_del`.

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
