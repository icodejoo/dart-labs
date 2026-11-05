# cacheman

> 简体中文: [README.zh-CN.md](./README.zh-CN.md)

[![pub](https://img.shields.io/pub/v/cacheman.svg)](https://pub.dev/packages/cacheman)

A tiny, type-safe wrapper over [`get_storage`](https://pub.dev/packages/get_storage) (persistent),
with one unified API: TTL & absolute expiry, sliding renewal, namespaces, pluggable
serialization, an optional codec hook, and a key-bound shortcut helper. The Dart/Flutter sibling of
`@codejoo/storage` (TypeScript).

Fully synchronous after a single `await cache.ensureInitialized()` call — see `Cacheman`'s class
doc for why.

## Install

```yaml
dependencies:
  cacheman:
    path: ../cacheman # or a git/pub dependency once published
```

## Quick start

```dart
import 'package:cacheman/cacheman.dart';

final cache = Cacheman();
await cache.ensureInitialized();

cache.write('token', 'abc');       // persists across restarts (get_storage)
cache.read<String>('token');       // 'abc' — synchronous
cache.write('session', 1, ttl: 60000); // expires in 60s
cache.remove('token');

cache.setNamespace('alice');        // per-account isolation, in place
```

## API

### `Cacheman({container, path, options})`

Constructs a `Cacheman` (persistent, `get_storage`-backed) exposing all CRUD methods directly — no
`.ls` indirection. Synchronous — call and `await` `ensureInitialized()` once before any read/write.

### `cache.ensureInitialized()`

The only `Future` boundary in the API. Awaits `get_storage`'s disk load for this instance's
container.

Subclassing: `Cacheman`'s constructor and `ensureInitialized()` are both plain, non-factory members,
so a subclass just forwards constructor params via `super(...)` — no factory boilerplate needed:

```dart
class MyCacheman extends Cacheman {
  MyCacheman({super.container, super.path, super.options});
  int extra = 0;
}

final cache = MyCacheman();
await cache.ensureInitialized();
```

### `Cacheman` methods

| Method | Description |
| --- | --- |
| `read<T>(key, [default])` | Read; missing/expired/unreadable → `default` (or `null`). |
| `write<T>(key, value, {ttl, expireAt})` | Write. `ttl` in ms. |
| `remove(key)` | Delete. |
| `readAll(keys, [defaults])` / `writeAll(keys, values, {...})` / `removeAll(keys)` | Batch, positional. |
| `keys()` / `key(index)` / `length` | Enumerate/count owned keys. |
| `purge()` | Proactively delete expired entries (otherwise lazy). |
| `erase()` | Erase owned keys (namespace/enckey-scoped) or everything. |
| `namespace` / `setNamespace([ns])` | Current prefix / switch it in place. |
| `container` | Underlying `get_storage` `GetStorage` instance — for interop needing the raw container (e.g. `listenKey` for external change notifications). |
| `storageKey(key)` | The actual key `key` is persisted under (namespace-prefixed, `enckey`-encoded when enabled) — pass this to `container.listenKey(...)`, not `key` itself. |

### `CachemanOptions`

`serialize`/`deserialize`, `codeable`/`codec`/`keyCodec`, `sliding`,
`namespace`, `raw`, `force`, `readonly`, `enckey`, `onError` — see each field's doc comment in
`lib/src/options.dart` for exact semantics.

Unreadable entries are deleted on read and reported via `onError(storageKey, error)` (or
print). The original decode/deserialization exception is preserved; a null codec result
uses `FormatException`. Purge/readonly probes do not report these failures; raw reads bypass decoding.

**No codec implementation ships with this package.** `Codec` is a plain `encode`/`decode` string
interface — bring your own (obfuscation, real encryption, compression, whatever fits).

### `fast<V>(cache, key)` / `lazy<V>(cache, key)` / `batchFast<V>(cache, keys)`

Key-bound shortcut accessors — see `lib/src/fast.dart`.

### GetX reactive interop (`container` + `storageKey`)

`get_storage` depends on `get`, so `get` is a transitive dependency of this package.
`container`/`storageKey` provide interop; this package ships no GetX binding. If you use GetX, they let you build a
VueUse-`useStorage`-style reactive wrapper yourself:

```dart
import 'dart:convert';
import 'package:cacheman/cacheman.dart';
import 'package:get/get.dart';

/// Compare JSON-compatible values. / 比较可 JSON 序列化的值。
bool sameValue(Object? a, Object? b) => a == b || jsonEncode(a) == jsonEncode(b);

/// Bind with a feedback guard. / 带回写守卫的绑定。
Rx<V?> reactive<V>(Cacheman cache, String key) {
  final rx = Rx<V?>(cache.read<V>(key));

  // Writes to this container in the same isolate update the Rx.
  cache.container.listenKey(cache.storageKey(key), (dynamic _) {
    final next = cache.read<V>(key);
    if (!sameValue(rx.value, next)) rx.value = next;
  });

  // Compare before writing: deserialized Maps/Lists/objects have fresh identities.
  ever(rx, (V? v) {
    if (sameValue(cache.read<V>(key), v)) return;
    v == null ? cache.remove(key) : cache.write<V>(key, v);
  });

  return rx;
}

final token = reactive<String>(cache, 'token');
Obx(() => Text(token.value ?? 'no token'));
token.value = 'abc123'; // updates the UI and persists
```

The comparison uses `==` first, then JSON content for collections and objects with `toJson()`.
For values JSON cannot encode, adapt `sameValue` to your value semantics. In production, keep
the cancellation function returned by `listenKey` and the `Worker` returned by `ever`, and
dispose both when the owner is disposed.

- `container.listenKey` callbacks are **synchronous**; a cache write can re-enter your listener
  before returning. The guard above prevents feedback writes for equal content.
- A whole-container `erase()` reports the changed key as `""`; a listener on a nonempty
  `storageKey(key)` receives no notification. Handle this separately (e.g. a container-level
  `listen` checking `container.changes` and resetting your Rx). `cache.erase()` takes this path
  without namespace/enckey; scoped erases remove owned keys individually and notify those keys.
- Each isolate has its own in-memory map and listeners. Writes in another isolate do not
  update or notify this binding; any cross-isolate synchronization must be arranged separately.

Use `cache.storageKey(key)`, not `cache.namespace + key`, whenever `enckey` might be in play —
the codec's encoding is a private, pluggable detail `storageKey` already accounts for.

### `debug(cache)`

Decrypted snapshot of every owned entry, `{ "namespace:key": value }` — see `lib/src/debug.dart`.

### `Jsonx`

`jsonEncode`/`jsonDecode`-compatible serializer that additionally round-trips `DateTime` / `Duration` /
`Set` / `BigInt` / `Uri` / `RegExp`. Pass `Jsonx.encode`/`Jsonx.decode<T>` (wrapped to the
`CacheEntity <-> String` shape) as `CachemanOptions.serialize`/`deserialize` — `decode<T>` casts the
result to `T` (e.g. `Jsonx.decode<Map<String, dynamic>>(s)`). Not round-trippable, by design: custom
`Enum`s and `Map`s with non-`String` keys — see `lib/src/jsonx.dart`'s doc comment.

## Example

A complete, runnable app exercising every feature above (persistent tier, ttl, sliding, namespace,
batch ops, `fast`/`lazy`/`batchFast`, `debug()`, `codeable`/`enckey`, `Jsonx`, `raw`/`readonly`)
is in [`example/`](./example/):

```bash
flutter run example/lib/main.dart
```

## Differences from `@codejoo/storage` (the TS sibling)

- **Fully synchronous** after `await cache.ensureInitialized()` — `get_storage` is sync-after-init, so there's no `db`/async
  tier the way the TS version has `ls`/`ss` (sync) vs `db` (async IndexedDB).
- **One tier, not three**: only the persistent tier — no in-memory `ss` tier and no IndexedDB
  equivalent needed.
- **No built-in codec.** The TS version ships obfuscation codecs; this package only exposes the
  `Codec` interface.
- **`force`'s retry only covers synchronous write failures** (e.g. a custom `serialize` throwing) —
  `get_storage`'s actual disk-flush failures are asynchronous and never retried; with 2.1.1 its write Future
  can't carry them, so `onError` is only guaranteed for synchronous failures (see `Cacheman`'s `_gs` doc comment in `lib/src/cacheman.dart`).
- No `crossTab` equivalent (a browser-tab concept with no Flutter analogue).

## License

MIT
