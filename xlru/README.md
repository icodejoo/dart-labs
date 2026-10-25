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
})
```

| Parameter | Description |
| --- | --- |
| `maxSize` | Capacity in entries, at least 1; otherwise throws `ArgumentError`. |
| `onRemove` | Called for every removed entry; see [Removal callbacks](#removal-callbacks). |
| `equals`, `hashCode` | Custom key equality, with the same rules as `HashMap`: equal keys must have equal, stable hash codes. Defaults to `==` and `hashCode`. |
| `allowSelfEviction` | `false` (default): the entry written by `set` or `putIfAbsent` is not evicted by that same call, so you can safely `pin` it right after. `true`: it can be evicted (and reported) immediately if all older entries are pinned. |

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

Expiry, size-based weights, async loading, and statistics are not provided.
Build them around the cache using `onRemove`.

## License

MIT; see [LICENSE](LICENSE). Benchmarks: [benchmark/README.md](benchmark/README.md).
