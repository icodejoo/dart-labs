# xlru

[中文](README.zh.md)

Zero-dependency LRU cache for Dart and Flutter (VM and web, Dart 3.5+) with
removal callbacks, pinning, and lookups that don't change recency.

```yaml
dependencies:
  xlru: ^0.1.0
```

## Quick start

```dart
import 'package:xlru/xlru.dart';

void main() {
  final cache = XlruCache<String, int>(
    maxSize: 2,
    onRemove: (key, value, cause) => print('$key=$value: ${cause.name}'),
  );
  cache.set('a', 1);
  cache.set('b', 2);
  cache.get('a'); // Marks a as most recently used.
  cache.set('c', 3); // Evicts b (prints "b=2: evicted").
  print(cache.keys.toList()); // [c, a]
  print(cache.peek('a')); // 1, without changing the order.
}
```

`maxSize` counts entries. All public types start with `Xlru`.

## Pin a value while you use it

A pinned entry is never evicted to make room. Use it for resources that must
stay alive while in use:

```dart
final feeds = XlruCache<String, Feed>(
  maxSize: 10,
  onRemove: (key, feed, cause) => feed.dispose(),
);

final feed = feeds.putIfAbsent('forest', () => Feed('forest'));
feeds.pin('forest');
// ... use feed ...
feeds.unpin('forest');

// Or in one call; it always unpins, even if the action throws:
final name = feeds.usePinned('forest', (feed) => feed.name);
```

Every successful `pin` needs one `unpin`. Pins only block eviction: `set` with a
different value, `remove`, and `clear` still remove a pinned entry (and call
`onRemove`). When every remaining entry is pinned the cache may hold more than
`maxSize` entries until a later `set`, `unpin`, or `resize`.

## API

### `XlruCache<K, V>`

`final class`. Use it from one isolate; each isolate needs its own instance.

#### Constructor

```dart
XlruCache({
  required int maxSize,
  XlruRemovalListener<K, V>? onRemove,
  bool Function(K, K)? equals,
  int Function(K)? hashCode,
  bool allowSelfEviction = false,
  XlruStore<K, V>? store,
})
```

| Parameter | Description |
| --- | --- |
| `maxSize` | Capacity in entries, at least 1; otherwise throws `ArgumentError`. |
| `onRemove` | Called for every removed entry; see [Removal callbacks](#removal-callbacks). |
| `equals`, `hashCode` | Custom key equality, with the same rules as `HashMap`: equal keys must have equal, stable hash codes. Defaults to `==` and `hashCode`. |
| `allowSelfEviction` | `false` (default): the entry written by `set` or `putIfAbsent` is not evicted by that same call, so you can safely `pin` it right after. `true`: it can be evicted (and reported) immediately if all older entries are pinned. |
| `store` | Where values live; see [Storage backends](#storage-backends). Default: in memory, inside the cache. |

```dart
final cache = XlruCache<String, int>(maxSize: 100);
final caseInsensitive = XlruCache<String, int>(
  maxSize: 100,
  equals: (a, b) => a.toLowerCase() == b.toLowerCase(),
  hashCode: (k) => k.toLowerCase().hashCode,
);
```

#### Properties

| Property | Type | Description |
| --- | --- | --- |
| `maxSize` | `int` | Current capacity. |
| `length` | `int` | Number of entries, pinned ones included. |
| `isEmpty` | `bool` | Whether there are no entries. |
| `isNotEmpty` | `bool` | Whether there is at least one entry. |
| `allowSelfEviction` | `bool` | The value given to the constructor. |
| `keys` | `Iterable<K>` | Keys, newest to oldest. Doesn't change recency. |
| `values` | `Iterable<V>` | Values, same order as `keys`. |
| `entries` | `Iterable<MapEntry<K, V>>` | Entries, same order as `keys`. |

`keys`, `values`, and `entries` are live views. Changing the cache while
iterating (including `get`, `pin`, `unpin`, and `set`) makes the next step throw
`ConcurrentModificationError`. Read with `peek`, or copy first:

```dart
for (final key in cache.keys.toList()) {
  print(cache.get(key));
}
```

They also don't support fast random access: `keys.length` and `keys.contains`
walk every entry. Use `length` and `containsKey` instead.

#### Methods

| Method | Returns | Description |
| --- | --- | --- |
| `get(K key)` | `V?` | The value, marking the entry most recently used. `null` if absent. |
| `peek(K key)` | `V?` | The value without changing recency. `null` if absent. |
| `containsKey(K key)` | `bool` | Whether the key exists. Doesn't change recency. |
| `set(K key, V value)` | `void` | Inserts or replaces, and marks the entry most recently used. May evict others. An existing entry keeps its key object and pins. |
| `putIfAbsent(K key, V Function() ifAbsent)` | `V` | The existing value (marked most recently used), or the value built by `ifAbsent` after inserting it. If `ifAbsent` throws, nothing is inserted. |
| `remove(K key)` | `V?` | Removes the entry even if pinned and returns its value; `null` if absent. |
| `clear()` | `void` | Removes all entries, even pinned ones. |
| `resize(int maxSize)` | `void` | Changes the capacity and evicts immediately if needed. Throws `ArgumentError` for values below 1, leaving the cache unchanged. |
| `pin(K key)` | `bool` | Adds one pin. `false` if the key is absent. Doesn't change recency. |
| `unpin(K key)` | `bool` | Removes one pin. `false` if the key is absent or not pinned. May evict the entry or others right away, running `onRemove`. |
| `isPinned(K key)` | `bool` | Whether the key exists and has at least one pin. |
| `usePinned<R>(K key, R Function(V value) action)` | `R?` | Pins the key, runs `action` with its value, and always unpins afterwards. `null` without calling `action` if the key is absent. |
| `toMap()` | `Map<K, V>` | An independent copy, newest to oldest, using the same key equality. |

`get`, `peek`, `remove`, and `usePinned` return `null` both for "absent" and for
a stored `null`; use `containsKey` to tell them apart.

```dart
cache.set('a', 1);
cache.get('a'); // 1
cache.peek('b'); // null
cache.putIfAbsent('b', () => 2); // 2
cache.pin('a'); // true
cache.remove('a'); // 1 (pins don't protect against remove)
cache.resize(50);
final copy = cache.toMap();
cache.clear();
```

### `XlruRemovalListener<K, V>`

```dart
typedef XlruRemovalListener<K, V> = void Function(
    K key, V value, XlruRemovalCause cause);
```

### `XlruRemovalCause`

| Value | When |
| --- | --- |
| `evicted` | An unpinned entry was removed to stay within `maxSize` (including by `unpin` and `resize`). |
| `replaced` | `set` stored a different (non-`identical`) value for an existing key; `value` is the old one. The key is still in the cache. Setting the identical value doesn't notify. |
| `removed` | `remove` deleted an existing entry. |
| `cleared` | `clear` deleted the entry (oldest first). |
| `lost` | A store no longer had the entry's value. Only caches with a `store` report it, but keep it in exhaustive `switch`es. With a store, `XlruCache` can only deliver it when `V` is nullable (the value passed is `null`); otherwise there is nothing to pass and the notification is skipped. |

## Storage backends

By default values live in memory. Pass a `store` to keep them elsewhere (a disk,
a database, Hive, a remote service); the cache still owns order, pins and
callbacks, and the store only saves and loads values.

```dart
// Synchronous store.
final cache = XlruCache<String, int>(maxSize: 100, store: XlruMemoryStore());

// Asynchronous store (disk, database, remote).
final async = XlruAsyncCache<String, String>(maxSize: 100, store: myStore);
await async.set('a', 'x');
final value = await async.get('a');
final user = await async.putIfAbsent('42', () => api.fetchUser(42));
```

Rules for every store:

- Give the cache its own store, empty at start. Existing data in it is never
  read, cleaned, or restored.
- Serialization is the store's job.
- A store cannot hold `null` values. If `read` returns `null` for a cached key,
  the entry is removed with `XlruRemovalCause.lost`.
- Hive: wrap a `Box` as an `XlruStore` and a `LazyBox` as an `XlruAsyncStore`;
  the adapters in `test/support/hive_stores.dart` are a starting point.

### `XlruStore<K, V>`

Synchronous store interface.

| Method | Description |
| --- | --- |
| `V? read(K key)` | The stored value, or `null` if none. |
| `void write(K key, V value)` | Stores or replaces the value. |
| `void delete(K key)` | Deletes the key's data; nothing happens if absent. |
| `void clear()` | Deletes all data. |

### `XlruAsyncStore<K, V>`

Asynchronous store interface; the same four methods returning `Future`:
`Future<V?> read(K)`, `Future<void> write(K, V)`, `Future<void> delete(K)`,
`Future<void> clear()`.

### `XlruMemoryStore<K, V>`

The in-memory store: `XlruMemoryStore({equals, hashCode})`, with `length`,
`keys`, and the four `XlruStore` methods. Custom `equals`/`hashCode` follow the
`HashMap` rules.

### `XlruStoreAsAsync.asAsync()`

`store.asAsync()` wraps any `XlruStore` as an `XlruAsyncStore`, so one
synchronous store can serve both cache types. Exceptions become future errors.

```dart
final async = XlruAsyncCache<String, int>(
  maxSize: 10,
  store: XlruMemoryStore<String, int>().asAsync(),
);
```

### `XlruStoreOperation`

`read`, `write`, `delete`, `clear`: which store operation failed, passed to
`onError`.

### Errors from a store

- `XlruCache` with a store: the exception propagates from the cache method. A
  failed write changes nothing. A failed delete (after an eviction or `remove`)
  still updates the cache and then throws.
- `XlruAsyncCache`: without `onError` the exception propagates from the call
  and the cache is as before (a failed delete still leaves the index updated and
  stale data in the store). With `onError`, the failure is reported and the call
  carries on: a failed read counts as lost data, a failed write leaves the entry
  unchanged, a failed delete or clear is only reported.

### `XlruAsyncCache<K, V>`

`final class`; an LRU cache whose values live in an `XlruAsyncStore`. Keys,
order and pins stay in memory and work as in `XlruCache`. Use it from one
isolate.

```dart
XlruAsyncCache({
  required int maxSize,
  XlruAsyncStore<K, V>? store,
  XlruAsyncRemovalListener<K, V>? onRemove,
  XlruStoreErrorListener<K>? onError,
  bool Function(K, K)? equals,
  int Function(K)? hashCode,
  bool allowSelfEviction = false,
})
```

| Parameter | Description |
| --- | --- |
| `maxSize` | Capacity in entries, at least 1; otherwise throws `ArgumentError`. |
| `store` | The values' home; defaults to in memory. |
| `onRemove` | Called for each removal, see `XlruAsyncRemovalListener` below. |
| `onError` | Called instead of throwing when the store fails. |
| `equals`, `hashCode`, `allowSelfEviction` | As in `XlruCache`. |

Operations on the **same key** run one after another in call order; different
keys run in parallel. Methods that don't touch the store are synchronous.

| Synchronous member | Description |
| --- | --- |
| `maxSize`, `length`, `isEmpty`, `isNotEmpty`, `allowSelfEviction` | As in `XlruCache`. |
| `keys` | Keys, newest to oldest; the same rules as `XlruCache.keys`. |
| `containsKey(key)` | Whether the key exists; no recency change. |
| `isPinned(key)` | Whether the key has at least one pin. |
| `pin(key)` | Adds a pin; `false` if absent. |

| Asynchronous method | Completes with | Description |
| --- | --- | --- |
| `get(key)` | `V?` | Value, marks most recently used. A value the store no longer has removes the entry as `lost` and gives `null`. |
| `peek(key)` | `V?` | Value without changing recency. |
| `set(key, value)` | `void` | Writes the value to the store first, then updates order and evicts. A running `putIfAbsent` load for the key is no longer cached. |
| `putIfAbsent(key, loader)` | `V` | Cached value, or the result of `loader`, cached. Concurrent calls for a key share one `loader` call; a failing `loader` caches nothing and fails all waiters; if the key is `set`, removed, or the cache cleared while loading, the value is returned but not cached. |
| `remove(key)` | `V?` | Removes even if pinned; returns the value. |
| `clear()` | `void` | Waits for pending work, reports `cleared` oldest first, clears the store. Work started meanwhile waits for it. |
| `resize(maxSize)` | `void` | Changes capacity and evicts at once; `ArgumentError` below 1. |
| `unpin(key)` | `bool` | Removes a pin; may evict, completing after removal callbacks and deletes. |
| `usePinned(key, action)` | `R?` | Pins, runs `action(value)` (may be async), always unpins; `null` if absent or lost. |
| `toMap()` | `Map<K, V>` | Copy, newest to oldest, reading every value. |

```dart
final length = await async.usePinned('a', (value) async => value.length);
```

### `XlruAsyncRemovalListener<K, V>`

```dart
typedef XlruAsyncRemovalListener<K, V> = FutureOr<void> Function(
    K key, Future<V?> Function() loadValue, XlruRemovalCause cause);
```

Call `loadValue()` to read the removed value from the store. It only works while
the callback runs: the store entry is deleted right after the callback finishes
(the cache waits for the future you return). For `replaced`, the callback runs
before the new value is written, so `loadValue` gives the old value; every
`set` of an existing key reports `replaced`. For `lost`, `loadValue` gives
`null`. An exception from the callback does not stop the cache's own work; the
first one is rethrown from the call that caused the removal.

### `XlruStoreErrorListener<K>`

```dart
typedef XlruStoreErrorListener<K> = void Function(Object error,
    StackTrace stackTrace, XlruStoreOperation operation, K? key);
```

`key` is `null` for `clear`.

## Removal callbacks

- Callbacks run synchronously, after the operation has finished changing the
  cache. They may call the cache again.
- One operation can produce several notifications: a `replaced` first, then any
  `evicted`.
- If a callback throws, the remaining callbacks of that operation still run,
  then the first exception is rethrown from the call that triggered them
  (`set`, `putIfAbsent`, `remove`, `clear`, `resize`, or `unpin`). Changes are
  not rolled back.
- Because the callback often disposes the value, a value returned by `remove`
  may already be disposed. If one resource is stored under several keys,
  coordinate its disposal yourself.

## Not included

Expiry, size-based weights, and statistics are not provided. Build them around
the cache using `onRemove`.

## License

MIT; see [LICENSE](LICENSE). Benchmarks: [benchmark/README.md](benchmark/README.md).
