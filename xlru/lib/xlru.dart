/// A strict least-recently-used cache with pinning and removal notifications.
///
/// ```dart
/// import 'package:xlru/xlru.dart';
///
/// final cache = LruCache<String, int>(maxSize: 2);
/// cache.set('one', 1);
/// cache.pin('one');
/// cache.set('two', 2);
/// cache.set('three', 3); // Evicts 'two'.
/// ```
library;

import 'dart:collection';
import 'dart:typed_data';

/// The reason an entry was removed from a [LruCache].
enum RemovalCause {
  /// Capacity enforcement removed an unpinned entry.
  evicted,

  /// [LruCache.set] replaced a value with a non-identical value.
  replaced,

  /// [LruCache.remove] explicitly removed an entry.
  removed,

  /// [LruCache.clear] removed an entry.
  cleared,
}

/// Receives the removed [key], its previous [value], and the removal [cause].
///
/// Notifications run synchronously after the operation has restored a consistent
/// cache state. Reentrant cache calls are allowed. If a listener throws, remaining
/// notifications in that batch still run, then the first error is rethrown with
/// its original stack trace. A replacement notification does not imply that the
/// key is absent: it describes the old value.
typedef RemovalListener<K, V> = void Function(
    K key, V value, RemovalCause cause);

/// Slot index meaning "no slot" in the recency and free lists.
const int _none = -1;

/// Upper bound for the number of slots allocated up front.
const int _initialSlots = 16;

/// Keeps hashes to 30 bits, small integers on every platform.
const int _hashBits = 0x3fffffff;

/// A hash-based cache ordered from most recently to least recently used.
///
/// [get], [set], and a successful [putIfAbsent] promote entries. [peek],
/// [containsKey], pinning, and iteration do not affect recency. Pinned entries
/// remain in the same recency list but cannot be evicted for capacity reasons.
/// Explicit [remove] and [clear] ignore pins. Replacing a value preserves pins.
///
/// Hash lookups and list updates take expected O(1) time. Each eviction takes
/// O(1 + the number of consecutive pinned entries at the list's oldest end).
/// Capacity enforcement may perform multiple evictions. If no entry is eligible,
/// the cache may temporarily exceed [maxSize]; [set], [unpin], and [resize]
/// enforce capacity again. By default the entry written by the current [set] or
/// [putIfAbsent] is not eligible during that call (see [allowSelfEviction]).
/// Use within a single isolate; no locking is performed.
///
/// Iterators throw [ConcurrentModificationError] after a successful mutation,
/// including pin changes, value replacement, resizing, or recency changes.
/// Reading an already newest entry does not change recency.
///
/// ```dart
/// final cache = LruCache<String, int>(maxSize: 2);
/// cache.set('a', 1);
/// cache.set('b', 2);
/// cache.get('a');
/// assert(cache.keys.join(',') == 'a,b');
/// ```
class LruCache<K, V> {
  /// Creates an empty cache with capacity [maxSize], which must be at least one.
  ///
  /// [onRemove] receives removal notifications after each operation completes.
  /// Optional [equals] and [hashCode] configure key equality as in [HashMap];
  /// equal keys must have equal, stable hash codes. Defaults use `==` and the
  /// key's `hashCode`. [allowSelfEviction] is described at [allowSelfEviction].
  /// Throws [ArgumentError] for an invalid capacity.
  LruCache({
    required int maxSize,
    RemovalListener<K, V>? onRemove,
    bool Function(K, K)? equals,
    int Function(K)? hashCode,
    this.allowSelfEviction = false,
  })  : _maxSize = _validateSize(maxSize),
        _onRemove = onRemove,
        _equals = equals,
        _hashCode = hashCode,
        _keys = List<Object?>.filled(_initialCount(maxSize), null),
        _values = List<V?>.filled(_initialCount(maxSize), null),
        _newer = Int32List(_initialCount(maxSize)),
        _older = Int32List(_initialCount(maxSize)),
        _pins = Int32List(_initialCount(maxSize)),
        _hashes = Int32List(_initialCount(maxSize)),
        _table = Int32List(_tableSize(_initialCount(maxSize)));

  /// Whether [set] and [putIfAbsent] may evict the entry they just wrote.
  ///
  /// When false (the default), the written entry is skipped during that call's
  /// capacity enforcement. If every other entry is pinned, the cache then
  /// temporarily exceeds [maxSize] and converges on a later write, [unpin], or
  /// [resize]. This keeps a freshly created value alive long enough to [pin]
  /// it. When true, eviction is strictly least-recently-used among unpinned
  /// entries, so a new entry can be evicted (and reported) immediately.
  ///
  /// ```dart
  /// final cache = LruCache<String, int>(maxSize: 1)..set('a', 1)..pin('a');
  /// cache.set('b', 2);
  /// assert(cache.containsKey('b')); // Kept; length is 2 until 'a' unpins.
  /// ```
  final bool allowSelfEviction;

  // Entries live in parallel slot arrays rather than per-entry objects, and
  // keys are found through an open-addressing table of slot numbers instead
  // of a HashMap, so inserts allocate nothing and eviction unindexes a slot
  // without rehashing or comparing its key. Evictions hand their slot to the
  // new entry, link updates need no type checks on any compiler, and hot
  // reads return the stored `V?` without casts.
  final RemovalListener<K, V>? _onRemove;
  final bool Function(K, K)? _equals;
  final int Function(K)? _hashCode;
  int _maxSize;
  int _version = 0;

  // Keys are only compared or handed back as `Object?`, so they are stored
  // untyped and writes need no covariance check.
  List<Object?> _keys;
  List<V?> _values;
  Int32List _newer;
  Int32List _older;
  Int32List _pins;

  /// Each slot's mixed key hash, so probing and rehashing skip `hashCode`.
  Int32List _hashes;

  /// Linear-probing table of `slot + 1` (0 is empty), at most half full.
  Int32List _table;

  /// The number of entries.
  int _count = 0;

  /// Slots handed out so far; slots at or above this index were never used.
  int _used = 0;

  /// Head of the free-slot list, chained through [_older].
  int _freeHead = _none;
  int _newest = _none;
  int _oldest = _none;

  static int _initialCount(int maxSize) =>
      maxSize < _initialSlots ? maxSize : _initialSlots;

  /// A power of two at least twice [slots].
  static int _tableSize(int slots) {
    var size = 2;
    while (size < slots * 2) {
      size *= 2;
    }
    return size;
  }

  static int _validateSize(int size) {
    if (size < 1) throw ArgumentError.value(size, 'maxSize', 'Must be >= 1');
    return size;
  }

  /// The target capacity; pinned entries may temporarily exceed this limit.
  int get maxSize => _maxSize;

  /// Changes the capacity to [maxSize] and immediately evicts eligible entries.
  ///
  /// Eviction visits unpinned entries from oldest to newest. Throws
  /// [ArgumentError] without changing the cache when [maxSize] is less than one.
  void resize(int maxSize) {
    _maxSize = _validateSize(maxSize);
    _version++;
    _notify(_trim(null, _none));
  }

  /// The number of entries, including pinned entries.
  int get length => _count;

  /// Whether the cache has no entries.
  bool get isEmpty => _count == 0;

  /// Whether the cache has at least one entry.
  bool get isNotEmpty => _count != 0;

  /// Returns the value for [key] and promotes it, or returns null if absent.
  ///
  /// For nullable values, use [containsKey] to distinguish null from absence.
  V? get(K key) {
    final slot = _find(key, _hash(key));
    if (slot == _none) return null;
    _promote(slot);
    return _values[slot];
  }

  /// Returns the value for [key], or null if absent, without changing recency.
  V? peek(K key) {
    final slot = _find(key, _hash(key));
    return slot == _none ? null : _values[slot];
  }

  /// Returns whether [key] exists, without changing recency.
  bool containsKey(K key) => _find(key, _hash(key)) != _none;

  /// Inserts [value] at [key], or replaces its value, and makes it newest.
  ///
  /// Existing keys retain their original key object and pin count. A
  /// non-[identical] old value generates a [RemovalCause.replaced] notification
  /// before capacity eviction notifications. Identical replacement still
  /// promotes the entry. The written entry is protected from this call's
  /// capacity enforcement unless [allowSelfEviction] is true. Notifications run
  /// after all structural changes.
  void set(K key, V value) {
    List<_Removal>? removed;
    final hash = _hash(key);
    var slot = _find(key, hash);
    if (slot == _none) {
      // Evict before inserting and hand the victim's slot to the new entry.
      // The new entry is not linked yet, so it can never be this victim; any
      // further overflow is handled by the trim below, in the same order.
      if (_count >= _maxSize) {
        slot = _victim(_none);
        if (slot != _none) removed = _unlink(slot, removed);
      }
      if (slot == _none) slot = _takeSlot();
      _keys[slot] = key;
      _values[slot] = value;
      _pins[slot] = 0;
      _hashes[slot] = hash;
      _insert(slot, hash);
      _count++;
      _attach(slot);
      _version++;
    } else {
      final old = _values[slot];
      if (!identical(old, value)) {
        if (_onRemove != null) {
          removed = [_Removal(_keys[slot], old, RemovalCause.replaced)];
        }
        _values[slot] = value;
        _version++;
      }
      _promote(slot);
    }
    _notify(_trim(removed, allowSelfEviction ? _none : slot));
  }

  /// Returns and promotes the existing value at [key], otherwise creates it.
  ///
  /// Calls [ifAbsent] once on a miss and inserts its returned value with [set].
  /// If [ifAbsent] throws, this method does not insert anything; mutations made
  /// by the creator itself remain. If the creator inserts [key] reentrantly,
  /// [set] replaces that value. The created value stays cached when this call
  /// returns, unless [allowSelfEviction] is true and every older entry is
  /// pinned, in which case it may already have been evicted.
  V putIfAbsent(K key, V Function() ifAbsent) {
    final slot = _find(key, _hash(key));
    if (slot != _none) {
      _promote(slot);
      return _values[slot] as V;
    }
    final value = ifAbsent();
    set(key, value);
    return value;
  }

  /// Removes [key] regardless of pins and returns its value, or null if absent.
  ///
  /// An existing entry generates [RemovalCause.removed], including null values.
  V? remove(K key) {
    final slot = _find(key, _hash(key));
    if (slot == _none) return null;
    _unindex(slot);
    final storedKey = _keys[slot];
    final value = _values[slot];
    _detach(slot);
    _release(slot);
    _version++;
    if (_onRemove != null) {
      _notify([_Removal(storedKey, value, RemovalCause.removed)]);
    }
    return value;
  }

  /// Removes all entries regardless of pins, notifying oldest to newest.
  ///
  /// Each removed entry generates [RemovalCause.cleared]. The cache is empty
  /// before notifications begin; entries inserted by listeners remain present.
  void clear() {
    List<_Removal>? removed;
    if (_onRemove != null) {
      removed = [];
      for (var slot = _oldest; slot != _none; slot = _newer[slot]) {
        removed.add(_Removal(_keys[slot], _values[slot], RemovalCause.cleared));
      }
    }
    if (_count != 0) _version++;
    _allocate(_initialCount(_maxSize));
    _notify(removed);
  }

  /// Increments the pin count for [key] without promoting it.
  ///
  /// Returns false if absent, otherwise true. Each successful call requires a
  /// matching [unpin] before capacity eviction becomes possible.
  bool pin(K key) {
    final slot = _find(key, _hash(key));
    if (slot == _none) return false;
    _pins[slot]++;
    _version++;
    return true;
  }

  /// Decrements [key]'s pin count without promoting it or going below zero.
  ///
  /// Returns false if absent or not pinned. On success returns true and
  /// immediately enforces capacity; an entry whose count reaches zero may be
  /// evicted before this method returns.
  bool unpin(K key) {
    final slot = _find(key, _hash(key));
    if (slot == _none || _pins[slot] == 0) return false;
    _pins[slot]--;
    _version++;
    _notify(_trim(null, _none));
    return true;
  }

  /// Returns whether [key] exists with a positive pin count, without promotion.
  bool isPinned(K key) {
    final slot = _find(key, _hash(key));
    return slot != _none && _pins[slot] > 0;
  }

  /// Live keys in newest-to-oldest order, including pins, without promotion.
  ///
  /// Each iterator detects mutations after its creation.
  Iterable<K> get keys => _CacheIterable(this, (slot) => _keys[slot] as K);

  /// Live values in the same order as [keys], without promotion.
  Iterable<V> get values => _CacheIterable(this, (slot) => _values[slot] as V);

  /// Live entries in the same order as [keys], without promotion.
  ///
  /// Returned [MapEntry] objects are immutable snapshots of individual entries.
  Iterable<MapEntry<K, V>> get entries => _CacheIterable(
      this, (slot) => MapEntry(_keys[slot] as K, _values[slot] as V));

  /// Returns an independent ordered copy, newest to oldest, without promotion.
  ///
  /// The returned map preserves this cache's key equality and hash functions.
  /// Values are copied by reference.
  Map<K, V> toMap() {
    final result = LinkedHashMap<K, V>(equals: _equals, hashCode: _hashCode);
    for (final entry in entries) {
      result[entry.key] = entry.value;
    }
    return result;
  }

  /// Replaces all slot storage with [slots] empty slots.
  void _allocate(int slots) {
    _keys = List<Object?>.filled(slots, null);
    _values = List<V?>.filled(slots, null);
    _newer = Int32List(slots);
    _older = Int32List(slots);
    _pins = Int32List(slots);
    _hashes = Int32List(slots);
    _table = Int32List(_tableSize(slots));
    _count = 0;
    _used = 0;
    _freeHead = _newest = _oldest = _none;
  }

  /// Returns a free slot, reusing released slots before growing storage.
  int _takeSlot() {
    final free = _freeHead;
    if (free != _none) {
      _freeHead = _older[free];
      return free;
    }
    if (_used == _keys.length) _grow();
    return _used++;
  }

  /// Doubles slot storage, stopping exactly at [maxSize] on the way up.
  void _grow() {
    final slots = _keys.length;
    var next = slots * 2;
    if (slots < _maxSize && next > _maxSize) next = _maxSize;
    _keys = List<Object?>.filled(next, null)..setRange(0, slots, _keys);
    _values = List<V?>.filled(next, null)..setRange(0, slots, _values);
    _newer = Int32List(next)..setRange(0, slots, _newer);
    _older = Int32List(next)..setRange(0, slots, _older);
    _pins = Int32List(next)..setRange(0, slots, _pins);
    _hashes = Int32List(next)..setRange(0, slots, _hashes);
    _table = Int32List(_tableSize(next));
    for (var slot = _oldest; slot != _none; slot = _newer[slot]) {
      _insert(slot, _hashes[slot]);
    }
  }

  /// The mixed hash of [key], as stored in [_hashes].
  ///
  /// Web integers hash to themselves, and runs of consecutive keys would form
  /// one long probe cluster, so the hash is spread with a multiply whose
  /// product stays below 2^53 (exact on every platform) and a fold.
  int _hash(K key) {
    final custom = _hashCode;
    final h = (custom == null ? key.hashCode : custom(key)) & _hashBits;
    final p = (h * 0x5bd1e9) & _hashBits;
    return p ^ (p >> 15);
  }

  /// The slot holding [key], whose mixed hash is [hash], or [_none].
  int _find(K key, int hash) {
    final table = _table;
    final mask = table.length - 1;
    final equals = _equals;
    var i = hash & mask;
    for (;;) {
      final slot = table[i] - 1;
      if (slot < 0) return _none;
      if (_hashes[slot] == hash) {
        final stored = _keys[slot];
        if (equals == null ? stored == key : equals(stored as K, key)) {
          return slot;
        }
      }
      i = (i + 1) & mask;
    }
  }

  /// Records [slot] in the table at the first free position for [hash].
  void _insert(int slot, int hash) {
    final table = _table;
    final mask = table.length - 1;
    var i = hash & mask;
    while (table[i] != 0) {
      i = (i + 1) & mask;
    }
    table[i] = slot + 1;
  }

  /// Removes [slot] from the table, shifting later probe entries back.
  void _unindex(int slot) {
    final table = _table;
    final mask = table.length - 1;
    var i = _hashes[slot] & mask;
    while (table[i] != slot + 1) {
      i = (i + 1) & mask;
    }
    _count--;
    var j = i;
    for (;;) {
      j = (j + 1) & mask;
      final entry = table[j];
      if (entry == 0) break;
      // Move the entry back unless its home lies cyclically in (i, j].
      final home = _hashes[entry - 1] & mask;
      if (i <= j ? (home <= i || home > j) : (home <= i && home > j)) {
        table[i] = entry;
        i = j;
      }
    }
    table[i] = 0;
  }

  /// Clears [slot]'s references and pushes it onto the free list.
  void _release(int slot) {
    _keys[slot] = null;
    _values[slot] = null;
    _older[slot] = _freeHead;
    _freeHead = slot;
  }

  void _attach(int slot) {
    _newer[slot] = _none;
    _older[slot] = _newest;
    if (_newest == _none) {
      _oldest = slot;
    } else {
      _newer[_newest] = slot;
    }
    _newest = slot;
  }

  void _detach(int slot) {
    final newer = _newer[slot];
    final older = _older[slot];
    if (newer == _none) {
      _newest = older;
    } else {
      _older[newer] = older;
    }
    if (older == _none) {
      _oldest = newer;
    } else {
      _newer[older] = newer;
    }
  }

  void _promote(int slot) {
    if (slot == _newest) return;
    _detach(slot);
    _attach(slot);
    _version++;
  }

  /// The oldest unpinned slot other than [keep], or [_none].
  int _victim(int keep) {
    var slot = _oldest;
    while (slot != _none && (_pins[slot] > 0 || slot == keep)) {
      slot = _newer[slot];
    }
    return slot;
  }

  /// Evicts [slot] and frees it; see [_unlink].
  List<_Removal>? _evict(int slot, List<_Removal>? removed) {
    removed = _unlink(slot, removed);
    _release(slot);
    return removed;
  }

  /// Removes [slot]'s entry from the table and recency list, keeping the slot
  /// for the caller and recording a notification only when a listener exists.
  List<_Removal>? _unlink(int slot, List<_Removal>? removed) {
    if (_onRemove != null) {
      (removed ??= [])
          .add(_Removal(_keys[slot], _values[slot], RemovalCause.evicted));
    }
    _unindex(slot);
    _detach(slot);
    _version++;
    return removed;
  }

  /// Evicts unpinned entries other than [keep] until within capacity.
  ///
  /// Returns [removed] with eviction records appended; the list is only
  /// allocated when a listener exists and something was evicted.
  List<_Removal>? _trim(List<_Removal>? removed, int keep) {
    while (_count > _maxSize) {
      final victim = _victim(keep);
      if (victim == _none) break;
      removed = _evict(victim, removed);
    }
    return removed;
  }

  /// Delivers [removed] to the listener; see [RemovalListener] for semantics.
  void _notify(List<_Removal>? removed) {
    final listener = _onRemove;
    if (listener == null || removed == null) return;
    Object? firstError;
    StackTrace? firstStack;
    for (final item in removed) {
      try {
        listener(item.key as K, item.value as V, item.cause);
      } catch (error, stack) {
        firstError ??= error;
        firstStack ??= stack;
      }
    }
    if (firstError != null) {
      Error.throwWithStackTrace(firstError, firstStack!);
    }
  }
}

/// A pending removal notification, delivered after the operation completes.
class _Removal {
  _Removal(this.key, this.value, this.cause);
  final Object? key;
  final Object? value;
  final RemovalCause cause;
}

class _CacheIterable<K, V, T> extends IterableBase<T> {
  _CacheIterable(this.cache, this.select);
  final LruCache<K, V> cache;
  final T Function(int slot) select;

  @override
  Iterator<T> get iterator => _CacheIterator(cache, select);
}

class _CacheIterator<K, V, T> implements Iterator<T> {
  _CacheIterator(this.cache, this.select)
      : version = cache._version,
        next = cache._newest;
  final LruCache<K, V> cache;
  final T Function(int slot) select;
  final int version;
  int next;
  T? _current;

  @override
  T get current => _current as T;

  @override
  bool moveNext() {
    if (version != cache._version) throw ConcurrentModificationError(cache);
    final slot = next;
    if (slot == _none) {
      _current = null;
      return false;
    }
    _current = select(slot);
    next = cache._older[slot];
    return true;
  }
}
