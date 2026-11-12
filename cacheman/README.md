# cacheman

> 简体中文: [README.zh-CN.md](./README.zh-CN.md)

[![pub](https://img.shields.io/pub/v/cacheman.svg)](https://pub.dev/packages/cacheman)

A tiny, type-safe wrapper over [`get_storage`](https://pub.dev/packages/get_storage) (persistent),
with one unified API: TTL & absolute expiry, sliding renewal, namespaces, pluggable
serialization, an optional codec hook, and a key-bound shortcut helper. The Dart/Flutter sibling of
`@codejoo/storage` (TypeScript).

`Cacheman` stays fully synchronous after a single `await cache.ensureInitialized()` call — see `Cacheman`'s class
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

The only `Future` boundary in Cacheman's CRUD API. Awaits `get_storage`'s disk load for this instance's
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
| `readWith<T>(key, {defaultValue, adapter})` | Read with typed JSON adaptation. |
| `write<T>(key, value, {ttl, expireAt, adapter})` | Write. `ttl` in ms. |
| `remove(key)` | Delete. |
| `readAll(keys, [defaults])` / `writeAll(keys, values, {...})` / `removeAll(keys)` | Batch, positional. |
| `keys()` / `key(index)` / `length` | Enumerate/count owned keys. |
| `purge()` | Proactively delete expired entries (otherwise lazy). |
| `erase()` | Erase owned keys (namespace/enckey-scoped) or everything. |
| `namespace` / `setNamespace([ns])` | Current prefix / switch it in place. |
| `container` | Underlying `get_storage` `GetStorage` instance — for interop needing the raw container (e.g. `listenKey` for external change notifications). |
| `storageKey(key)` | The actual key `key` is persisted under (namespace-prefixed, `enckey`-encoded when enabled) — pass this to `container.listenKey(...)`, not `key` itself. |
| `watch<T>(key, onChange, {includeOwnWrites = false})` | Watch decoded values; returns cancellation and follows namespace changes. |
| `flush()` | Queue a shared save immediately; returns void, errors use onError. |

### `CachemanOptions`

`serialize`/`deserialize`, `codeable`/`codec`/`keyCodec`, `sliding`,
`namespace`, `raw`, `force`, `readonly`, `enckey`, `onError`, `flushDelay`, `purgeOnInit` — see each field's doc comment in
`lib/src/options.dart` for exact semantics.

Unreadable entries are deleted on read and reported via `onError(storageKey, error)` (or
print). Errors are `CorruptEntryError(dropped: true)` with the original decode/deserialization
exception in `cause`; a null codec result uses a FormatException cause. Purge/readonly probes do not report these failures; raw reads bypass decoding.

**No codec implementation ships with this package.** `Codec` is a plain `encode`/`decode` string
interface — bring your own (obfuscation, real encryption, compression, whatever fits).

### `fast<V>(cache, key)` / `lazy<V>(cache, key)` / `batchFast<V>(cache, keys)`

Key-bound shortcut accessors — see `lib/src/fast.dart`.

### Shared Hub, `watch`, `flushDelay`, `flush` and `purgeOnInit`

Same-container Cacheman instances share one private Hub/listener. Owned-key indexes automatically
rebuild after peer or external container changes; local writes maintain a fresh index in O(1).
No read-value cache is added. Hub/watch/delayed flushing apply only to synchronous Cacheman.

```dart
final cache = Cacheman(options: const CachemanOptions(
  namespace: 'account',
  flushDelay: Duration(milliseconds: 200), // opt-in / 显式启用，default null
  purgeOnInit: true,                      // opt-in / 显式启用，default false
));
await cache.ensureInitialized();
final stop = cache.watch<Map<String, dynamic>>('profile', (value) {
  print(value); // peer/external changes / 其他实例或外部变更
});
cache.write('profile', {'name': 'Ada'}); // readable now / 立即可读，自身事件被忽略
cache.flush(); // queue save now / 立即排保存，没有 Future/持久化完成确认
stop();
```

`watch` reads through this instance's decoder/expiry rules; missing, deleted or cleared values
produce null. It includes whole-container erase events and follows `setNamespace`. Set
`includeOwnWrites: true` to also receive this instance's writes, renewal and lazy deletion.
Type/read/callback failures use `onError` without stopping other watchers; a throwing `onError`
still propagates as usual. Cancel subscriptions when their owner is disposed.

`flushDelay: null` preserves get_storage's default flush each event-loop turn containing writes.
Opting into 200ms coalesces writes/renewals using `writeInMemory` and a shared timer. The earliest
deadline wins: frequent writes never postpone a pending flush. A crash may lose writes within
that window. Deletes still call get_storage `remove` and immediately queue a flush (no public
memory-only remove exists); erase keeps its original behavior. `flush()` cancels the timer and
queues a save. Pending writes also flush on inactive/paused/hidden/detached lifecycle events.
These are best-effort saves, not synchronous disk-write guarantees; get_storage 2.1.1 still
drops its actual disk-flush Future. Observable hook failures go to the most recent delayed
writer's onError, or the explicit flush caller's onError.

`purgeOnInit: true` schedules one nonblocking `Timer.run` purge after initialization. Awaiting
init does not await the purge; raw mode skips it. AsyncCacheman ignores both new options.

Subclasses that bring their own primitives must call `super.custom(...)` (see
`PreferencesCache`). Such subclasses get an independent Hub identity (`this`) and no
notifications by default, so they never implicitly open GetStorage; they rescan owned keys on
every enumeration, and `watch` throws UnsupportedError. Plain subclasses that only forward
constructor params (like `MyCacheman` above) keep the default constructor and therefore the
full get_storage behavior: shared Hub, `watch`, `flushDelay` and the incremental key index. For shared notifications, override `hubIdentity`
with a stable backend handle and implement `listenRaw(ctx, onChange)` (return cancellation;
null key means clear), plus `syncNotificationsRaw`. All instances sharing an identity must use
the same notification/persistence contract. If notifications are asynchronous, indexes still
rescan each time and `includeOwnWrites: false` may receive own events: compare values yourself.
Override `setDeferredRaw`/`flushRaw` for true delayed persistence; otherwise they fall back to
`setRaw`/no-op.

### GetX reactive interop (`watch`)

`get_storage` depends on `get`, so `get` is a transitive dependency. The package ships no GetX
binding; use `watch` to build a VueUse-useStorage-style binding in your app:

```dart
import 'dart:convert';
import 'package:cacheman/cacheman.dart';
import 'package:get/get.dart';

/// Compare JSON-compatible values. / 比较可 JSON 序列化的值。
bool sameValue(Object? a, Object? b) => a == b || jsonEncode(a) == jsonEncode(b);

/// Own writes cannot feed back; dispose both subscriptions. / 忽略自身写入，释放两种订阅。
({Rx<V?> rx, void Function() dispose}) reactive<V>(Cacheman cache, String key) {
  final rx = Rx<V?>(cache.read<V>(key));
  final stop = cache.watch<V>(key, (next) {
    if (!sameValue(rx.value, next)) rx.value = next;
  }, includeOwnWrites: false);
  final worker = ever(rx, (V? value) {
    if (sameValue(cache.read<V>(key), value)) return;
    value == null ? cache.remove(key) : cache.write<V>(key, value);
  });
  return (rx: rx, dispose: () { stop(); worker.dispose(); });
}

final binding = reactive<String>(cache, 'token');
final token = binding.rx;
Obx(() => Text(token.value ?? 'no token'));
token.value = 'abc123';
// On owner disposal / 对象释放时：binding.dispose();
```

The comparison uses `==` then JSON content for collections and objects with `toJson()`. Adapt
`sameValue` for values JSON cannot encode. Keep the binding and dispose both subscriptions.

- Default notifications are synchronous. `watch` excludes own writes (including renewal/lazy
  deletion), breaking feedback for newly deserialized Map/List values.
- Raw `container.listenKey` still misses whole-container erase (changed key `""`); `watch`
  translates it for every watched key. Scoped erase removes owned keys individually.
- Each isolate has its own memory map/listeners; cross-isolate changes require your own synchronization.

For direct container interop, use `storageKey(key)` instead of `namespace + key` with enckey.

### `debug(cache)`

Decrypted snapshot of every owned entry, `{ "namespace:key": value }` — see `lib/src/debug.dart`.

### `Jsonx`

`jsonEncode`/`jsonDecode`-compatible serializer that additionally round-trips `DateTime` / `Duration` /
`Set` / `BigInt` / `Uri` / `RegExp`. Pass `Jsonx.encode`/`Jsonx.decode<T>` (wrapped to the
`CacheEntity <-> String` shape) as `CachemanOptions.serialize`/`deserialize` — `decode<T>` casts the
result to `T` (e.g. `Jsonx.decode<Map<String, dynamic>>(s)`). Enum encoding throws
`JsonUnsupportedObjectError`; define a custom `toJson` or use `ValueAdapter` to convert it to `name`.
Maps with non-String keys cannot be encoded. DateTime stores `[microsecondsSinceEpoch, isUtc]`
to preserve the instant across timezones; legacy ISO 8601 strings remain readable.

## Error handling

`CachemanOnError` keeps its `(String key, Object error)` signature, but every reported
object is now a `CachemanError`. `key` is the actual storage key (`*` for whole-backend
operations); `cause` retains the original exception and `stackTrace` the available trace.

| Error | Meaning / recovery |
| --- | --- |
| `SerializeError` | adapter.toJson, serialize or value-codec encoding failed; fix conversion, no purge/retry. |
| `WriteError` | Backend write failed after retry, or immediately with force:false. |
| `CorruptEntryError` | Decode failed; dropped:true confirms removal before reporting. Check cause before changing codecs. |
| `TypeMismatchError` | Requested type or adapter.fromJson failed; default returned and data retained. |
| `FlushError` | Observable background persistence failure; never force-retried. |
| `WatchError` | Watch callback or its backend/key lookup failed; other watchers continue. |

```dart
final cache = Cacheman(options: CachemanOptions(onError: (key, error) {
  if (error is CorruptEntryError && error.cause is FormatException) {
    print('Unreadable entry removed: $key');
  } else if (error is CachemanError) {
    print('$key: ${error.runtimeType}: ${error.cause}');
  }
}));
```

`read` never throws for type/adapter mismatches. Backend IO failures and exceptions thrown by
`onError` itself still propagate. Purge/readonly probes stay quiet. Real get_storage 2.1.1 disk
flush failures are not reliably observable because it drops the actual flush Future.

Web localStorage capacity/quota is controlled by the browser/backend; cacheman does not
increase it. Only observable write/flush failures can be classified. Multi-isolate/process
synchronization remains application-owned.

## Type safety and ValueAdapter

JSON decoding produces `List<dynamic>` and `Map<String, dynamic>`; requesting `List<String>`
or `Map<String, int>` directly can therefore mismatch. A mismatch returns the default,
reports `TypeMismatchError`, and keeps the stored value. `read<dynamic>` and `read<Object?>`
accept every value. There is no int/double coercion: JSON `1` is int, so `read<double>`
returns its default; use `num` or a ValueAdapter for numeric conversion.

`ValueAdapter<T>` converts business values to/from JSON-compatible data before/after envelope
serialization. `listOf<E>()` and `mapOf<V>()` eagerly copy and cast every element; custom classes
supply toJson/fromJson. Conversion failures become SerializeError on write and TypeMismatchError
on read (original exception in cause). Raw mode ignores adapters with a debug warning and only
stores String. Adapters do not change the stored envelope format or add a read cache.

Dart cannot combine an optional positional default with named parameters. Existing
`read(key, [default])` stays source-compatible; use `readWith(key, {defaultValue, adapter})`
for adapters. Both call the same core. Accessors accept adapter/default ttl on creation;
set uses that ttl when omitted. AsyncCacheman offers the same readWith/write adapters.

```dart
final names = ValueAdapter.listOf<String>();
cache.write('names', ['Ada'], adapter: names);
final list = cache.readWith<List<String>>('names', adapter: names);
final counts = cache.readWith<Map<String, int>>('counts',
  defaultValue: const {}, adapter: ValueAdapter.mapOf<int>());
final bound = fast<List<String>>(cache, 'names', adapter: names, ttl: 60000);
bound.set(['Ada']); // ttl=60000 unless set(..., ttl: ...) overrides it
final deferred = lazy<List<String>>(cache, 'names', adapter: names, ttl: 60000);
final group = batchFast<List<String>>(cache, ['names'], adapter: names, ttl: 60000);

/// Business value. / 业务值。
class Profile {
  const Profile(this.name);
  /// Display name. / 显示名称。
  final String name;
}
final profiles = ValueAdapter<Profile>(
  toJson: (p) => {'name': p.name},
  fromJson: (json) => Profile((json as Map<String, dynamic>)['name'] as String),
);
cache.write('profile', const Profile('Ada'), adapter: profiles);
final profile = cache.readWith<Profile>('profile', adapter: profiles);
// AsyncCacheman: await write / readWith with the same adapters.
// AsyncCacheman：同样的适配器，write / readWith 须 await。
```

## Migration from 0.6 to 0.7.0

- Change raw exception checks such as `error is FormatException` to
  `error is CorruptEntryError && error.cause is FormatException`; other failures also inspect cause.
- Replace TypeError catches around reads with onError handling and defaults; use a ValueAdapter
  for typed collections/custom classes. Existing stored data is kept on mismatch.
- `force` remains enabled by default and supported. It retries only backend writes, using one
  prebuilt string. Fix deterministic serialization/codec/adapter failures instead of expecting retry.
- Delete CacheOptions construction/imports; pass ttl/expireAt directly to write/writeAll.
- Replace key(index) loops (O(n²)) with one keys() snapshot. The deprecated method remains callable.
- Unscoped erase still clears the entire backend including foreign keys; namespace or enckey
  keeps ownership protection. The nullable read return type is unchanged.

## Layered storage / custom backends

Use multiple instances in parallel: small, frequently accessed data in synchronous `Cacheman`
(default `get_storage`, which loads the entire container into memory), large values in your
`AsyncCacheman` subclass backed by on-demand disk IO. The caches do not route or migrate data
automatically; choose the instance at the call site. Neither facade adds a read-value cache.
Cacheman owns namespace, TTL/absolute expiry, sliding renewal, envelopes, serialization/codecs,
raw/readonly, force and ownership semantics; subclasses implement only backend primitives.
No Hive, files, SharedPreferences backend or extra dependency ships in `lib/`.

### Synchronous primitives: SharedPreferencesWithCache

Override all six protected hooks: `initRaw`, `getRaw`, `keysRaw`, `setRaw`, `removeRaw`, `clearRaw`.
Getters/enumeration are synchronous. Mutations must finish the memory update **before returning**;
their `Future<void>` only reports background persistence errors. Those Future failures are reported,
never retried by `force`; only synchronous backend write throws may purge and retry once.
Serialization/adapter/value-codec failures report SerializeError without purging or retrying.
Keep your mutation overrides non-`async` and forward to the backend's immediate memory update.

Illustrative app-side adapter (add `shared_preferences` to your app, not this package):

```dart
import 'package:cacheman/cacheman.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// App-owned synchronous preferences adapter. / 应用自有的同步偏好适配器。
class PreferencesCache extends Cacheman {
  /// Builds without opening a backend. / 构造时不打开后端。
  PreferencesCache({super.options}) : super.custom();
  /// Backend initialized by ensureInitialized. / 由 ensureInitialized 初始化的后端。
  late final SharedPreferencesWithCache prefs;

  @override
  Future<void> initRaw(CacheContext ctx) async {
    prefs = await SharedPreferencesWithCache.create(
      cacheOptions: const SharedPreferencesWithCacheOptions(),
    );
  }

  @override
  Object? getRaw(CacheContext ctx, String k) => prefs.get(k);
  @override
  Iterable<String> keysRaw(CacheContext ctx) => prefs.keys;
  @override
  Future<void> setRaw(CacheContext ctx, String k, String v) => prefs.setString(k, v);
  @override
  Future<void> removeRaw(CacheContext ctx, String k) => prefs.remove(k);
  @override
  Future<void> clearRaw(CacheContext ctx) => prefs.clear();
}
```

[SharedPreferencesWithCache](https://pub.dev/packages/shared_preferences) supplies cached synchronous
reads. Its current [implementation](https://github.com/flutter/packages/blob/main/packages/shared_preferences/shared_preferences/lib/src/shared_preferences_async.dart)
updates its cache before returning the persistence Future. Verify that contract for your chosen
backend/version. `Cacheman.container` is still the default GetStorage escape hatch: even a fully
custom subclass creates that default container if it accesses the getter. Overriding all hooks
avoids it completely. The default `GetStorage(container, path)` is now lazy; initialization or first
container access still supplies the constructor's path. Same-name containers retain GetStorage's
first-construction-path-wins rule, now determined by first backend access rather than facade creation.
Sync owned-key snapshots now self-heal through Hub versions, or rescan on every query
when the subclass lacks synchronous notifications (as in this preferences example).

### Asynchronous primitives: Hive CE LazyBox

`AsyncCacheman({options})` is abstract and has no container/path parameters. Implement `getRaw`,
`setRaw`, `removeRaw`, `keysRaw`; `initRaw` optionally opens the backend (default no-op).
`clearRaw` optionally overrides the default enumerate-and-remove implementation, which clears every
key returned by `keysRaw`. All hooks receive actual storage keys; values written are strings.
[Hive CE LazyBox](https://pub.dev/documentation/hive_ce/latest/hive_ce/LazyBox-class.html) loads each
value from the backend on demand instead of keeping all values in memory (key metadata still lives
in the backend). Configure Hive in the app before initializing this adapter; use a dedicated
string-keyed LazyBox. Add `hive_ce` only to the consuming app.

```dart
import 'package:cacheman/cacheman.dart';
import 'package:hive_ce/hive.dart';

/// App-owned on-demand disk cache. / 应用自有的按需磁盘缓存。
class HiveCache extends AsyncCacheman {
  /// Opens the named box during initialization. / 初始化时打开指定 box。
  HiveCache(this.boxName, {super.options});
  /// Dedicated box name. / 专用 box 名称。
  final String boxName;
  /// Application owns closing this handle. / 应用负责关闭此句柄。
  late final LazyBox<String> box;

  @override
  Future<void> initRaw(CacheContext ctx) async {
    box = await Hive.openLazyBox<String>(boxName);
  }
  @override
  Future<Object?> getRaw(CacheContext ctx, String k) async => await box.get(k);
  @override
  Future<void> setRaw(CacheContext ctx, String k, String v) => box.put(k, v);
  @override
  Future<void> removeRaw(CacheContext ctx, String k) => box.delete(k);
  @override
  Future<Iterable<String>> keysRaw(CacheContext ctx) async => box.keys.cast<String>();
  @override
  Future<void> clearRaw(CacheContext ctx) async { await box.clear(); }
}

// First configure Hive's directory in your app: Hive.init(cacheDirectory).
// 先在应用内配置 Hive 目录：Hive.init(cacheDirectory)。
final small = Cacheman(options: const CachemanOptions(namespace: 'small'));
final large = HiveCache('large', options: const CachemanOptions(namespace: 'reports'));
await small.ensureInitialized();
await large.ensureInitialized();
small.write('report', 1000); // small summary / 小型摘要
await large.write('report', List.generate(1000, (i) => {'row': i}), ttl: 60000);
final report = await large.read<List<dynamic>>('report');
// The application owns box lifecycle: await large.box.close() when finished.
// 应用负责 box 生命周期：使用完毕后 await large.box.close()。
```

### Asynchronous primitives: one dart:io file per key

The filename encodes the **storageKey** with UTF-8 + lowercase hexadecimal, including its namespace/codec
transformation. Logical keys such as `report/2026` cannot introduce path separators.

```dart
import 'dart:convert' show utf8;
import 'dart:io';
import 'package:cacheman/cacheman.dart';

/// App-owned IO-only per-key file adapter. / 应用自有的每键文件适配器，仅限 IO 平台。
class DirectoryCache extends AsyncCacheman {
  /// Uses a dedicated directory. / 使用缓存专用目录。
  DirectoryCache(this.directory, {super.options});
  /// Backend directory. / 后端目录。
  final Directory directory;
  /// Recognized file suffix. / 可识别的文件后缀。
  static const suffix = '.cache';
  /// Hexadecimal radix. / 十六进制基数。
  static const _hexRadix = 16;
  /// Hex digits per UTF-8 byte. / 每个 UTF-8 字节的十六进制位数。
  static const _byteDigits = 2;

  /// Lowercase hex avoids base64 case collisions on case-insensitive filesystems.
  /// 小写十六进制避免 base64 在大小写不敏感文件系统上的文件名碰撞。
  static String _encodeKey(String key) => utf8.encode(key)
      .map((byte) => byte.toRadixString(_hexRadix).padLeft(_byteDigits, '0')).join();

  /// Decode only complete lowercase hex byte pairs. / 仅解码完整的小写十六进制字节对。
  static String _decodeKey(String name) {
    if (!RegExp(r'^(?:[0-9a-f]{2})*$').hasMatch(name)) {
      throw const FormatException('Invalid hex filename');
    }
    return utf8.decode([
      for (var i = 0; i < name.length; i += _byteDigits)
        int.parse(name.substring(i, i + _byteDigits), radix: _hexRadix),
    ]);
  }

  /// Maps storageKey to a safe filename. / 将 storageKey 映射为安全文件名。
  File fileFor(String k) => File(
    '${directory.path}${Platform.pathSeparator}${_encodeKey(k)}$suffix',
  );

  @override
  Future<void> initRaw(CacheContext ctx) async {
    await directory.create(recursive: true);
  }
  @override
  Future<Object?> getRaw(CacheContext ctx, String k) async {
    final file = fileFor(k);
    return await file.exists() ? await file.readAsString() : null;
  }
  @override
  Future<void> setRaw(CacheContext ctx, String k, String v) async {
    await fileFor(k).writeAsString(v, flush: true);
  }
  @override
  Future<void> removeRaw(CacheContext ctx, String k) async {
    final file = fileFor(k);
    if (await file.exists()) await file.delete();
  }
  @override
  Future<Iterable<String>> keysRaw(CacheContext ctx) async {
    final keys = <String>[];
    await for (final entry in directory.list(followLinks: false)) {
      if (entry is! File) continue;
      final name = entry.uri.pathSegments.last;
      if (!name.endsWith(suffix)) continue;
      try {
        keys.add(_decodeKey(name.substring(0, name.length - suffix.length)));
      } on FormatException { /* ignore foreign filenames / 忽略外部文件名 */ }
    }
    return keys;
  }
  // clearRaw defaults to keysRaw + removeRaw; no recursive directory deletion.
  // clearRaw 默认 keysRaw + removeRaw，不递归删除目录。
}

final large = DirectoryCache(Directory('cache-data'));
await large.ensureInitialized();
await large.write('report/2026', {'rows': 1000});
final report = await large.read<Map<String, dynamic>>('report/2026');
```

This minimal IO example uses a dedicated directory and assumes serialized access. File-name length
limits still apply; atomic replacement, locking and recovery belong in your backend. It is for IO
platforms, not web. Values are read on demand and not retained by cacheman.

### Context and async API contract

`CacheContext.storageKey` is the actual backend key. `key` resolves lazily once and retains
the captured namespace. Subscription uses init with a null key; flush uses write with a null key,
preserving the existing CacheOp enum.

`CacheContext` carries `key` (logical, before namespace/encoding), `namespace` (escaped prefix, same
as the getter) and `op` (`CacheOp.init/read/write/remove/keys/clear`). Init/enumeration/whole-backend
clear have a null key; batch CRUD invokes a primitive per key with its logical key. Internal lazy
deletes and renewals use remove/write contexts. Use it for logging or routing by logical key prefix;
if you route across boxes, `keysRaw` must enumerate their union and `clearRaw` must cover them all.

Await `ensureInitialized`, `read<T>`/`readAll`, `write`/`writeAll`, `remove`/`removeAll`, `erase`,
`keys()`, `length()`, `purge()` and `setNamespace()` on AsyncCacheman.
`namespace` and `storageKey()` stay synchronous (no backend IO). TTL/expireAt and default values match Cacheman.
There is no async `key(index)`, `fast`/`lazy`/`batchFast` or `debug()` in this stage.
Every async enumeration calls `keysRaw` and filters ownership; no owned-key set is cached.
Expired keys remain in enumeration/counts until read/purge, as in Cacheman.

- With namespace **or enckey**, `erase()` removes only owned keys; with neither, it calls
  `clearRaw` for the entire backend, including foreign keys. This preserves Cacheman's existing
  enckey-only protection too.
- `force` catches only awaited `setRaw` failures, purges expired entries and retries
  once, then calls `onError(storageKey, error)` or prints. Renewal awaits persistence; failed renewal
  still returns the previously read value. This differs from synchronous background flush Futures.
- Decode failures are deleted and reported before returning the default; purge/readonly probes stay
  quiet. Other backend IO failures propagate; an `onError` callback that throws also propagates.
- Await pending operations before switching namespace. Readonly and sliding are not transactions;
  arrange concurrent access, backend lifecycle and durability in your subclass/application.

## Example

A complete, runnable app exercising every feature above (persistent tier, ttl, sliding, namespace,
batch ops, `fast`/`lazy`/`batchFast`, `debug()`, `codeable`/`enckey`, `Jsonx`, `raw`/`readonly`, parallel sync/async caches)
is in [`example/`](./example/):

```bash
flutter run example/lib/main.dart
```

## Differences from `@codejoo/storage` (the TS sibling)

- **Synchronous Cacheman**, plus an abstract **AsyncCacheman** for user-provided backends.
  No built-in disk tier, memory `ss` tier or automatic routing; instances can run in parallel.
- **No built-in codec.** The TS version ships obfuscation codecs; this package only exposes the
  `Codec` interface.
- **Cacheman `force` retries only synchronous backend write failures** (`setRaw` throwing) —
  `get_storage`'s actual disk-flush failures are asynchronous and never retried; with 2.1.1 its write Future
  can't carry them, so `onError` is only guaranteed for synchronous failures (see `Cacheman`'s `_gs` doc comment in `lib/src/cacheman.dart`).
- No `crossTab` equivalent (a browser-tab concept with no Flutter analogue).

## License

MIT
