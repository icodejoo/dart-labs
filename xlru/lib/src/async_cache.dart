import 'dart:async';
import 'dart:collection';

import '../xlru.dart';

/// Receives the removal of [key] from an [XlruAsyncCache].
///
/// Call [loadValue] to read the removed value from the store; it is only valid
/// while the callback runs, because the store entry is deleted right after the
/// callback completes. It completes with null if the value is gone. The cache
/// waits for the returned future before deleting the store entry.
///
/// For [XlruRemovalCause.replaced] the callback runs before the new value is
/// written, so [loadValue] yields the old value. Every `set` of an existing key
/// reports `replaced`, even when the new value equals the old one.
///
/// If the callback throws, the cache still finishes its own work and then
/// rethrows the error from the call that triggered the removal.
typedef XlruAsyncRemovalListener<K, V> = FutureOr<void> Function(
    K key, Future<V?> Function() loadValue, XlruRemovalCause cause);

/// Receives a store failure instead of letting it propagate; see
/// [XlruAsyncCache.new] for what each failed [operation] does to the cache.
///
/// [key] is null for [XlruStoreOperation.clear].
typedef XlruStoreErrorListener<K> = void Function(
    Object error, StackTrace stackTrace, XlruStoreOperation operation, K? key);

/// An LRU cache whose values live in an [XlruAsyncStore].
///
/// Keys, recency order, and pins stay in memory and behave exactly as in
/// [XlruCache]; only values go to the store. Use it for disks, databases, or
/// remote services. Without a store it keeps values in memory.
///
/// Operations on the same key run one after another in call order; different
/// keys run in parallel. Methods that never touch the store stay synchronous.
/// A store cannot hold null values: a missing value removes the entry with
/// [XlruRemovalCause.lost]. Use from one isolate.
///
/// ```dart
/// final cache = XlruAsyncCache<String, String>(maxSize: 100, store: myStore);
/// await cache.set('a', 'x');
/// final value = await cache.get('a');
/// final loaded = await cache.putIfAbsent('b', () async => fetchB());
/// ```
final class XlruAsyncCache<K, V> {
  /// Creates an empty cache with capacity [maxSize], at least one.
  ///
  /// [store] defaults to an in-memory store. It should be dedicated to this
  /// cache and empty; existing data in it is never read or cleared.
  /// [onRemove] and [equals]/[hashCode]/[allowSelfEviction] behave as in
  /// [XlruCache]. Throws [ArgumentError] for an invalid capacity.
  ///
  /// Without [onError], a store failure propagates from the call that caused it
  /// and the cache is left as it was before, except that a failed delete leaves
  /// stale data in the store. With [onError], the failure is reported and
  /// execution continues: a failed read counts as lost data, a failed write
  /// leaves the entry unchanged, and a failed delete or clear is only reported.
  XlruAsyncCache({
    required int maxSize,
    XlruAsyncStore<K, V>? store,
    this.onRemove,
    this.onError,
    bool Function(K, K)? equals,
    int Function(K)? hashCode,
    bool allowSelfEviction = false,
  })  : _store = store ??
            XlruMemoryStore<K, V>(equals: equals, hashCode: hashCode).asAsync(),
        _tails = HashMap<K, Future<void>>(equals: equals, hashCode: hashCode),
        _loads = HashMap<K, _Load<V>>(equals: equals, hashCode: hashCode),
        _equals = equals,
        _hashCode = hashCode {
    _index = XlruCache<K, bool>(
      maxSize: maxSize,
      equals: equals,
      hashCode: hashCode,
      allowSelfEviction: allowSelfEviction,
      onRemove: _onIndexRemoved,
    );
  }

  /// Called for every removal; see [XlruAsyncRemovalListener].
  final XlruAsyncRemovalListener<K, V>? onRemove;

  /// Called instead of throwing when the store fails; see [XlruAsyncCache.new].
  final XlruStoreErrorListener<K>? onError;

  final XlruAsyncStore<K, V> _store;
  final bool Function(K, K)? _equals;
  final int Function(K)? _hashCode;

  /// Keys, order, and pins; the values are just a marker.
  late final XlruCache<K, bool> _index;

  /// The latest queued task of every key with pending work.
  final HashMap<K, Future<void>> _tails;

  /// Loads started by [putIfAbsent] that have not finished.
  final HashMap<K, _Load<V>> _loads;

  /// Set while [clear] runs: new operations wait for it, while the removal
  /// cleanups of operations that started earlier keep running.
  Future<void>? _clearing;

  /// Collects the removal tasks created by the index operation in progress.
  List<Future<void>>? _batch;

  /// The target capacity; pinned entries may temporarily exceed this limit.
  int get maxSize => _index.maxSize;

  /// The number of entries, including pinned entries.
  int get length => _index.length;

  /// Whether the cache has no entries.
  bool get isEmpty => _index.isEmpty;

  /// Whether the cache has at least one entry.
  bool get isNotEmpty => _index.isNotEmpty;

  /// Whether [set] and [putIfAbsent] may evict the entry they just wrote.
  bool get allowSelfEviction => _index.allowSelfEviction;

  /// Live keys, newest to oldest, including pins, without promotion.
  ///
  /// The iterable follows [XlruCache.keys]: changing the cache while iterating
  /// invalidates the iterator, so copy with `keys.toList()` first.
  Iterable<K> get keys => _index.keys;

  /// Returns whether [key] exists, without changing recency.
  bool containsKey(K key) => _index.containsKey(key);

  /// Returns whether [key] exists with a positive pin count.
  bool isPinned(K key) => _index.isPinned(key);

  /// Increments the pin count for [key]; returns false if it is absent.
  ///
  /// Pins only block capacity eviction. Each successful call needs a matching
  /// [unpin].
  bool pin(K key) => _index.pin(key);

  /// Decrements [key]'s pin count; returns false if absent or not pinned.
  ///
  /// May evict entries right away, so the future completes after their removal
  /// callbacks and store deletes, and fails if one of them fails.
  Future<bool> unpin(K key) async {
    final batch = <Future<void>>[];
    final result = _collect(batch, () => _index.unpin(key));
    await _drain(batch);
    return result;
  }

  /// Returns the value for [key] and promotes it, or null if absent.
  ///
  /// If the store no longer has the value, the entry is removed as
  /// [XlruRemovalCause.lost] and null is returned.
  Future<V?> get(K key) => _exec<V?>(key, (batch) async {
        if (_index.get(key) == null) return null;
        return _fetch(key);
      });

  /// Returns the value for [key] without changing recency, or null if absent.
  Future<V?> peek(K key) => _exec<V?>(key, (batch) async {
        if (!_index.containsKey(key)) return null;
        return _fetch(key);
      });

  /// Stores [value] at [key] and makes it newest.
  ///
  /// The value is written to the store first; if that fails the entry is left
  /// as it was. May evict other entries; the future completes after their
  /// removal callbacks and store deletes. A load started by [putIfAbsent] for
  /// the same key that is still running will not be cached.
  Future<void> set(K key, V value) {
    _loads[key]?.stale = true;
    return _put(key, value);
  }

  /// Returns the cached value for [key], or loads and caches it with [loader].
  ///
  /// Concurrent calls for the same key share one [loader] call. A failing
  /// [loader] caches nothing and fails every waiting call. If the key is
  /// [set], removed, or the cache is cleared while loading, the loaded value
  /// is still returned but not cached.
  ///
  /// ```dart
  /// final user = await cache.putIfAbsent('42', () => api.fetchUser(42));
  /// ```
  Future<V> putIfAbsent(K key, Future<V> Function() loader) {
    final running = _loads[key];
    if (running != null) return running.future;
    final load = _Load<V>();
    _loads[key] = load;
    return load.future = _load(key, loader, load);
  }

  /// Removes [key] regardless of pins and returns its value, or null if absent.
  ///
  /// The value is read from the store before it is deleted.
  Future<V?> remove(K key) {
    _loads[key]?.stale = true;
    return _exec<V?>(key, (batch) async {
      if (!_index.containsKey(key)) return null;
      final read = await _read(key);
      // Evicted while reading: the eviction's own task reports and deletes it.
      if (!_index.containsKey(key)) return read.value;
      _index.remove(key);
      final value = read.value;
      await _finishRemoval(
        key,
        value == null ? XlruRemovalCause.lost : XlruRemovalCause.removed,
        () async => value,
      );
      return value;
    });
  }

  /// Removes all entries regardless of pins.
  ///
  /// Waits for every pending operation first, and operations started meanwhile
  /// wait for it. Removal callbacks run oldest to newest, then the store is
  /// cleared. A load started by [putIfAbsent] that is still running will not
  /// be cached.
  Future<void> clear() async {
    for (final load in _loads.values) {
      load.stale = true;
    }
    while (_clearing != null) {
      await _clearing;
    }
    final gate = Completer<void>();
    _clearing = gate.future;
    Object? firstError;
    StackTrace? firstStack;
    try {
      // Removal cleanups spawned by pending operations join `_tails` while
      // they run, so loop until nothing is left.
      while (_tails.isNotEmpty) {
        await Future.wait(_tails.values.toList());
      }
      final listener = onRemove;
      if (listener != null) {
        for (final key in _index.keys.toList().reversed) {
          try {
            await listener(
                key, () => _store.read(key), XlruRemovalCause.cleared);
          } catch (error, stack) {
            firstError ??= error;
            firstStack ??= stack;
          }
        }
      }
      if (await _try(XlruStoreOperation.clear, null, _store.clear)) {
        _index.clear();
      }
    } finally {
      _clearing = null;
      gate.complete();
    }
    if (firstError != null) Error.throwWithStackTrace(firstError, firstStack!);
  }

  /// Changes the capacity and evicts immediately if needed.
  ///
  /// The future completes after the evicted entries' callbacks and store
  /// deletes. Fails with [ArgumentError] for a capacity below one.
  Future<void> resize(int maxSize) async {
    final batch = <Future<void>>[];
    _collect(batch, () => _index.resize(maxSize));
    await _drain(batch);
  }

  /// Pins [key], runs [action] with its value, then always unpins.
  ///
  /// Returns null without calling [action] if the key is absent or its value is
  /// lost. The pin is taken before the value is read, so the entry cannot be
  /// evicted while it is being loaded or used.
  ///
  /// ```dart
  /// final length = await cache.usePinned('a', (value) async => value.length);
  /// ```
  Future<R?> usePinned<R>(K key, FutureOr<R> Function(V value) action) async {
    if (!_index.pin(key)) return null;
    try {
      final value = await peek(key);
      if (value == null) return null;
      return await action(value);
    } finally {
      await unpin(key);
    }
  }

  /// Returns an independent copy, newest to oldest, reading every value.
  ///
  /// Entries whose value is lost are dropped from the copy and removed.
  Future<Map<K, V>> toMap() async {
    final result = LinkedHashMap<K, V>(equals: _equals, hashCode: _hashCode);
    for (final key in _index.keys.toList()) {
      final value = await peek(key);
      if (value != null) result[key] = value;
    }
    return result;
  }

  /// Writes [value] to [key] in the key's queue; the body of [set].
  Future<void> _put(K key, V value) => _exec<void>(key, (batch) async {
        final listener = onRemove;
        Object? listenerError;
        StackTrace? listenerStack;
        if (listener != null && _index.containsKey(key)) {
          try {
            await listener(
                key, () => _store.read(key), XlruRemovalCause.replaced);
          } catch (error, stack) {
            listenerError = error;
            listenerStack = stack;
          }
        }
        if (await _try(
            XlruStoreOperation.write, key, () => _store.write(key, value))) {
          _collect(batch, () => _index.set(key, true));
        }
        if (listenerError != null) {
          Error.throwWithStackTrace(listenerError, listenerStack!);
        }
      });

  /// Runs a [putIfAbsent] load and caches its result unless it went stale.
  Future<V> _load(K key, Future<V> Function() loader, _Load<V> load) async {
    try {
      final cached = await get(key);
      if (cached != null) return cached;
      final value = await loader();
      if (!load.stale) await _put(key, value);
      return value;
    } finally {
      if (identical(_loads[key], load)) _loads.remove(key);
    }
  }

  /// Reads [key]'s value from the store for an entry that is in the index.
  ///
  /// A missing value, or a failure reported to [onError], removes the entry as
  /// lost and yields null.
  Future<V?> _fetch(K key) async {
    final read = await _read(key);
    final value = read.value;
    if (value != null) return value;
    if (_index.containsKey(key)) {
      _index.remove(key);
      await _finishRemoval(key, XlruRemovalCause.lost, () async => null);
    }
    return null;
  }

  /// Reads from the store; [_Read.value] is null if missing or failed.
  Future<_Read<V>> _read(K key) async {
    V? value;
    final ok = await _try(XlruStoreOperation.read, key,
        () async => value = await _store.read(key));
    return _Read<V>(ok, value);
  }

  /// Runs a store [operation]; returns false after reporting a failure to
  /// [onError], and rethrows when there is no [onError].
  Future<bool> _try(XlruStoreOperation operation, K? key,
      Future<void> Function() action) async {
    try {
      await action();
      return true;
    } catch (error, stack) {
      final handler = onError;
      if (handler == null) rethrow;
      handler(error, stack, operation, key);
      return false;
    }
  }

  /// Calls [onRemove] for [key] and then deletes its store entry.
  ///
  /// The delete runs even if the callback throws; the first error is rethrown.
  Future<void> _finishRemoval(
      K key, XlruRemovalCause cause, Future<V?> Function() loadValue) async {
    Object? firstError;
    StackTrace? firstStack;
    try {
      await onRemove?.call(key, loadValue, cause);
    } catch (error, stack) {
      firstError = error;
      firstStack = stack;
    }
    try {
      await _try(XlruStoreOperation.delete, key, () => _store.delete(key));
    } catch (error, stack) {
      firstError ??= error;
      firstStack ??= stack;
    }
    if (firstError != null) Error.throwWithStackTrace(firstError, firstStack!);
  }

  /// Handles the index evicting [key]: finish its removal in the key's queue.
  void _onIndexRemoved(K key, bool _, XlruRemovalCause cause) {
    if (cause != XlruRemovalCause.evicted) return;
    final task = _enqueue<void>(key, cleanup: true, () async {
      // A write that was already running when the key was evicted puts it back
      // in the index and has reported the old value as replaced, so the stale
      // eviction must not delete the new data or report it again.
      if (_index.containsKey(key)) return;
      await _finishRemoval(
          key, XlruRemovalCause.evicted, () => _store.read(key));
    });
    _batch!.add(task);
  }

  /// Runs [action] with removal tasks created by the index added to [batch].
  R _collect<R>(List<Future<void>> batch, R Function() action) {
    final previous = _batch;
    _batch = batch;
    try {
      return action();
    } finally {
      _batch = previous;
    }
  }

  /// Runs [body] in [key]'s queue, then waits for the removals it triggered.
  ///
  /// The removals run outside the queue slot, so two keys evicting each other
  /// cannot deadlock. If both [body] and a removal fail, [body]'s error wins.
  Future<T> _exec<T>(
      K key, Future<T> Function(List<Future<void>> batch) body) async {
    final batch = <Future<void>>[];
    T? result;
    Object? error;
    StackTrace? stack;
    try {
      result = await _enqueue<T>(key, () => body(batch));
    } catch (e, s) {
      error = e;
      stack = s;
    }
    try {
      await _drain(batch);
    } catch (e, s) {
      if (error == null) {
        error = e;
        stack = s;
      }
    }
    if (error != null) Error.throwWithStackTrace(error, stack!);
    return result as T;
  }

  /// Waits for every task in [batch] and rethrows the first failure.
  Future<void> _drain(List<Future<void>> batch) async {
    Object? error;
    StackTrace? stack;
    for (final task in batch) {
      try {
        await task;
      } catch (e, s) {
        error ??= e;
        stack ??= s;
      }
    }
    if (error != null) Error.throwWithStackTrace(error, stack!);
  }

  /// Queues [task] behind earlier tasks of [key].
  ///
  /// While [clear] runs, other new tasks are held back until it finishes, but a
  /// [cleanup] (the removal of an entry an earlier operation evicted) is queued
  /// at once so [clear] can wait for it.
  Future<T> _enqueue<T>(K key, Future<T> Function() task,
      {bool cleanup = false}) {
    final gate = _clearing;
    if (gate != null && !cleanup) {
      return gate.then((_) => _enqueue<T>(key, task));
    }
    final previous = _tails[key];
    Future<T> run() async {
      if (previous != null) await previous;
      return task();
    }

    final result = run();
    final tail = result.then<void>((_) {}, onError: (Object _) {});
    _tails[key] = tail;
    tail.then((_) {
      if (identical(_tails[key], tail)) _tails.remove(key);
    });
    return result;
  }
}

/// A running [XlruAsyncCache.putIfAbsent] load.
class _Load<V> {
  /// Whether a [set], remove, or clear happened while it was loading.
  bool stale = false;

  /// Completes with the loaded value.
  late Future<V> future;
}

/// The outcome of a store read: whether it succeeded and what it returned.
class _Read<V> {
  _Read(this.ok, this.value);
  final bool ok;
  final V? value;
}
