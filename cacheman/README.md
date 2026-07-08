# cacheman

A tiny, type-safe wrapper over [`get_storage`](https://pub.dev/packages/get_storage) (persistent) and an
in-memory store, with one unified API: TTL & absolute expiry, sliding renewal, namespaces, pluggable
serialization, an optional codec hook, and a key-bound shortcut helper. The Dart/Flutter sibling of
`@codejoo/storage` (TypeScript).

Fully synchronous after a single async `create()` — see `Cacheman`'s class doc for why.

## Install

```yaml
dependencies:
  cacheman:
    path: ../cacheman # or a git/pub dependency once published
```

## Quick start

```dart
import 'package:cacheman/cacheman.dart';

final cache = await Cacheman.create();

cache.ls.set('token', 'abc');       // persists across restarts (get_storage)
cache.ls.get<String>('token');      // 'abc' — synchronous
cache.ls.set('session', 1, ttl: 60000); // expires in 60s
cache.ls.remove('token');

cache.ss.set('draft', {'id': 1});   // pure in-memory — gone on next process start

cache.setNamespace('alice');        // per-account isolation, in place
await cache.destroy();              // releases resources, keeps persisted data
```

## API

### `Cacheman.create({container, path, options, cap})`

The only `Future` boundary. Returns a `Cacheman` with `.ls` (persistent, `get_storage`-backed) and `.ss`
(pure in-memory) — both `Engine`s share the same option set and method surface. `cap` caps `.ss`
only (`ls` is disk-backed, no such cap): a soft limit on total `key.length + value.length` across all
entries; `null` (default) means unlimited. Once over cap, the oldest entries (by insertion order) are
evicted first (FIFO) — see `Memory.cap`'s doc comment for exact semantics.

### `Engine` methods (`ls` / `ss`)

| Method | Description |
| --- | --- |
| `get<T>(key, [default])` | Read; missing/expired → `default` (or `null`). |
| `set<T>(key, value, {ttl, expireAt, memoized})` | Write. `ttl` in ms. |
| `remove(key)` | Delete. |
| `getAll(keys, [defaults])` / `setAll(keys, values, {...})` / `removeAll(keys)` | Batch, positional. |
| `keys()` / `key(index)` / `length` | Enumerate/count owned keys. |
| `purge()` | Proactively delete expired entries (otherwise lazy). |
| `clear()` | Clear owned keys (namespace/enckey-scoped) or everything. |
| `namespace` / `setNamespace([ns])` | Current prefix / switch it in place. |
| `destroy()` | Clear the memo cache. Does not delete persisted data. |

### `CachemanOptions`

`memoized`, `cloned` (+`deepCloned`), `serialize`/`deserialize`, `codeable`/`codec`, `sliding`,
`namespace`, `raw`, `force`, `readonly`, `enckey`, `onError` — see each field's doc comment in
`lib/src/engine.dart` for exact semantics.

**No codec implementation ships with this package.** `Codec` is a plain `encode`/`decode` string
interface — bring your own (obfuscation, real encryption, compression, whatever fits).

### `fast<V>(engine, key)` / `lazy<V>(engine, key)` / `batchFast<V>(engine, keys)`

Key-bound shortcut accessors — see `lib/src/fast.dart`.

### `debug(engine)`

Decrypted snapshot of every owned entry, `{ "namespace:key": value }` — see `lib/src/debug.dart`.

### `Jsonx`

`jsonEncode`/`jsonDecode`-compatible serializer that additionally round-trips `DateTime` / `Duration` /
`Set` / `BigInt` / `Uri` / `RegExp`. Pass `Jsonx.encode`/`Jsonx.decode<T>` (wrapped to the
`CacheEntity <-> String` shape) as `CachemanOptions.serialize`/`deserialize` — `decode<T>` casts the
result to `T` (e.g. `Jsonx.decode<Map<String, dynamic>>(s)`). Not round-trippable, by design: custom
`Enum`s and `Map`s with non-`String` keys — see `lib/src/jsonx.dart`'s doc comment.

## Differences from `@codejoo/storage` (the TS sibling)

- **Fully synchronous** after `create()` — `get_storage` is sync-after-init, so there's no `db`/async
  tier the way the TS version has `ls`/`ss` (sync) vs `db` (async IndexedDB).
- **Two tiers, not three**: `ls` (persistent) / `ss` (in-memory) — no IndexedDB equivalent needed.
- **No built-in codec.** The TS version ships obfuscation codecs; this package only exposes the
  `Codec` interface.
- **`force`'s retry only covers synchronous write failures** (e.g. a custom `serialize` throwing) —
  `get_storage`'s actual disk-flush failures are asynchronous and reported via `onError` separately,
  not retried (see `GetStorageAdapter`'s doc comment).
- **`cloned` is shallow by default** (`Map.of`/`List.of`); set `deepCloned: true` too if you intend to
  mutate anything beyond the top-level container.
- No `crossTab` equivalent (a browser-tab concept with no Flutter analogue).

## License

MIT
