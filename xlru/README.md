# xlru

[中文](README.zh.md)

A zero-dependency, pure Dart LRU cache with reason-aware removal callbacks,
reference-counted pinning, and lookups that can leave recency unchanged.
Requires Dart 3.5 or later. Works on the Dart VM and the web, including Flutter.

## Install

```yaml
dependencies:
  xlru: ^0.1.0
```

## Quick start

```dart
import 'package:xlru/xlru.dart';

void main() {
  final cache = LruCache<String, int>(
    maxSize: 2,
    onRemove: (key, value, cause) => print('$key=$value: ${cause.name}'),
  );
  cache.set('a', 1);
  cache.set('b', 2);
  cache.get('a'); // Promotes a.
  cache.set('c', 3); // Evicts b.
  print(cache.keys.toList()); // [c, a]
  print(cache.peek('a')); // 1; leaves recency unchanged.
}
```

## API

| API | Behavior |
| --- | --- |
| `LruCache(maxSize: ..., onRemove: ..., equals: ..., hashCode: ..., allowSelfEviction: false)` | Creates an empty cache; capacity must be at least 1. Equality and hash callbacks are optional. See [pins](#protect-resources-with-pins) for `allowSelfEviction`. |
| `maxSize`, `resize(maxSize)` | Read/change capacity; shrinking immediately evicts eligible entries. |
| `length`, `isEmpty`, `isNotEmpty` | Include pinned entries. |
| `get(key)` | Returns a value and promotes the entry; null if absent. |
| `peek(key)`, `containsKey(key)` | Inspect without promotion. |
| `set(key, value)` | Inserts/replaces and promotes; retains existing pins and the original key object. |
| `putIfAbsent(key, creator)` | Promotes and returns an existing value, otherwise creates and inserts one. |
| `remove(key)` | Removes regardless of pins; returns the previous value or null. |
| `clear()` | Removes everything, notifying oldest to newest, regardless of pins. |
| `pin(key)`, `unpin(key)` | Increment/decrement a reference count; return false for a missing key or an unpin without a pin. |
| `isPinned(key)` | Tests whether the pin count is positive, without promotion. |
| `keys`, `values`, `entries` | Live iterables, newest to oldest, including pins, without promotion. |
| `toMap()` | An independent ordered map copy preserving custom key equality; values retain their identity. |

For nullable values, `get`, `peek`, and `remove` cannot distinguish a stored null
from absence; use `containsKey` when that distinction matters. A throwing
`putIfAbsent` creator causes no insertion by the method. Changes made inside the
creator remain. If it inserts the same key, its returned value replaces that
entry. By default the created value is still cached when the method returns.

Custom `equals` and `hashCode` follow `HashMap` rules: equality must be stable
and equal keys must have equal, stable hashes. Do not mutate key identity while
the key is stored. The optional callbacks themselves should not mutate the cache.

## Protect resources with pins

For a scene-feed registry, dispose resources on removal and pin the feed while
a drawer uses it:

```dart
final feeds = LruCache<String, SceneFeed>(
  maxSize: 10,
  onRemove: (key, feed, cause) => feed.dispose(),
);
final feed = feeds.putIfAbsent('forest', () => SceneFeed('forest'));
feeds.pin('forest');
// Use feed while the drawer is open.
feeds.unpin('forest');
```

`SceneFeed` is application-defined; see the runnable
[example](example/xlru_example.dart) for a pure Dart implementation.
Pin immediately after obtaining a resident entry and balance every successful
pin with an unpin. Pinning does not promote an entry. Pins stay in the same LRU
list, so iteration always reflects actual use order. Replacing a pinned value
preserves its pin count, but still notifies removal of the old value.

Eviction scans from the oldest end and skips pinned entries. If all remaining
entries are pinned, the cache may exceed its target capacity, for example after
shrinking. `set`, successful `unpin`, and `resize` enforce capacity again.
`remove` and `clear` explicitly override pins.

The entry written by `set` or `putIfAbsent` is never evicted by that same call,
so the get-then-pin pattern above is safe even when every older entry is pinned:
the cache temporarily grows and converges on a later write, `unpin`, or `resize`.
Pass `allowSelfEviction: true` for strict LRU instead; then a new entry written
into a cache full of pinned entries is evicted (and reported) immediately, and
`putIfAbsent` returns a value that is no longer cached.

## Removal notifications

`RemovalCause` has four values:

- `evicted`: an unpinned entry was removed to enforce capacity.
- `replaced`: a value was replaced with a non-identical value. The callback gets
  the old value; the key may still exist. Identical replacement does not notify.
- `removed`: an existing entry was explicitly removed.
- `cleared`: an entry was removed by `clear`, oldest to newest.

Each operation completes **all structural changes before any callback**. A batch
delivers replacement notifications before its capacity eviction notifications.
Callbacks are synchronous and may call cache methods reentrantly. Nested
operations deliver their own batches before the outer callback resumes. A clear
listener can insert new entries; those entries survive the original clear.

If callbacks throw, the rest of that batch still runs. The first exception is
then rethrown with its original stack via `Error.throwWithStackTrace`. Completed
mutations are retained. A callback may therefore observe changes made by earlier
callbacks in the same batch.

## Ordering and complexity

Entries live in parallel slot arrays rather than per-entry objects. A
linear-probing hash table maps keys to slots, and recency is a doubly linked
list of slot indices held in typed int arrays. An insertion at capacity reuses
the evicted entry's slot, so steady-state writes allocate nothing, and hot paths
need no runtime type checks under dart2js, dart2wasm, or the VM. Hash lookup
and recency updates take expected O(1), with O(n) storage. Each eviction costs
**O(1 + the number of consecutive pinned entries at the oldest end)**; enforcing
capacity may require multiple evictions. Scanning an entirely pinned cache is
O(n). `clear` and `toMap` take O(n).

Iterators throw `ConcurrentModificationError` after mutations, including value
replacement, recency changes, resizing, and pin-count changes. Non-promoting
reads and reading an already newest entry do not invalidate iterators. An
iterable is live; each iterator captures the cache version at its creation.
The cache is intended for one isolate and uses no locks.

## Validation and benchmarks

```sh
dart pub get
dart format --output=none --set-exit-if-changed .
dart analyze
dart test
dart test -p chrome
dart pub publish --dry-run
dart run benchmark/lru_benchmark.dart
dart compile exe benchmark/lru_benchmark.dart -o build/lru_benchmark.exe
dart compile js benchmark/lru_benchmark.dart -O4 -o build/lru_benchmark.js
node build/lru_benchmark.js
```

Create `build/` before compilation. See [benchmark methodology and results](benchmark/README.md)
for VM JIT, AOT, JavaScript (dart2js `-O4` and `-O1`), and WebAssembly comparisons
against a simple `LinkedHashMap` LRU and quiver's `LruMap`. The benchmark-only
dependencies are not runtime dependencies.

## License

MIT; see [LICENSE](LICENSE).
