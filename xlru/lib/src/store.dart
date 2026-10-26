import 'dart:collection';

/// A synchronous storage backend that only stores and fetches values by key.
///
/// The cache owns eviction order, pins, and removal callbacks; the store owns
/// where values live.
///
/// Contract:
/// - Serialization is the store's business; the cache never inspects values.
/// - [read] returns null when the store has no data for a key. The cache treats
///   that as lost data (`XlruRemovalCause.lost`), so a cache with a store cannot
///   hold null values.
/// - Pass a dedicated store that is empty when the cache is created. The cache
///   never reads or clears data that already exists in it.
///
/// ```dart
/// final cache = XlruCache<String, int>(
///   maxSize: 100,
///   store: XlruMemoryStore<String, int>(),
/// );
/// ```
abstract interface class XlruStore<K, V> {
  /// Returns the value stored for [key], or null if there is none.
  V? read(K key);

  /// Stores [value] for [key], replacing any previous value.
  void write(K key, V value);

  /// Deletes the data for [key]; does nothing if there is none.
  void delete(K key);

  /// Deletes all data in the store.
  void clear();
}

/// An asynchronous storage backend; same contract as [XlruStore], but every
/// operation returns a [Future].
///
/// Disks, databases, and remote services usually implement this interface.
///
/// ```dart
/// final cache = XlruAsyncCache<String, String>(
///   maxSize: 100,
///   store: myDiskStore,
/// );
/// ```
abstract interface class XlruAsyncStore<K, V> {
  /// Completes with the value stored for [key], or null if there is none.
  Future<V?> read(K key);

  /// Stores [value] for [key], replacing any previous value.
  Future<void> write(K key, V value);

  /// Deletes the data for [key]; does nothing if there is none.
  Future<void> delete(K key);

  /// Deletes all data in the store.
  Future<void> clear();
}

/// The store operation that failed, passed to an `onError` callback.
enum XlruStoreOperation {
  /// Reading a value.
  read,

  /// Writing a value.
  write,

  /// Deleting one key's data.
  delete,

  /// Clearing the whole store.
  clear,
}

/// The default in-memory store; values live in a [HashMap].
///
/// Pass [equals] and [hashCode] for custom key equality, with the same rules as
/// [HashMap]. Use [XlruStoreAsAsync.asAsync] to get an asynchronous store.
///
/// ```dart
/// final store = XlruMemoryStore<String, int>();
/// store.write('a', 1);
/// print(store.read('a')); // 1
/// ```
final class XlruMemoryStore<K, V> implements XlruStore<K, V> {
  /// Creates an empty in-memory store.
  XlruMemoryStore({bool Function(K, K)? equals, int Function(K)? hashCode})
      : _data = HashMap<K, V>(equals: equals, hashCode: hashCode);

  /// All stored data.
  final HashMap<K, V> _data;

  /// The number of stored values.
  int get length => _data.length;

  /// The stored keys, in no particular order.
  Iterable<K> get keys => _data.keys;

  @override
  V? read(K key) => _data[key];

  @override
  void write(K key, V value) => _data[key] = value;

  @override
  void delete(K key) => _data.remove(key);

  @override
  void clear() => _data.clear();
}

/// Wraps a synchronous store as an asynchronous one.
final class _SyncAsAsyncStore<K, V> implements XlruAsyncStore<K, V> {
  /// Wraps [_store].
  _SyncAsAsyncStore(this._store);

  /// The wrapped synchronous store.
  final XlruStore<K, V> _store;

  @override
  Future<V?> read(K key) async => _store.read(key);

  @override
  Future<void> write(K key, V value) async => _store.write(key, value);

  @override
  Future<void> delete(K key) async => _store.delete(key);

  @override
  Future<void> clear() async => _store.clear();
}

/// Converts a synchronous store into an asynchronous one.
extension XlruStoreAsAsync<K, V> on XlruStore<K, V> {
  /// Returns an [XlruAsyncStore] backed by this store, so one synchronous store
  /// can serve both cache types.
  ///
  /// Exceptions thrown by this store become errors of the returned futures.
  ///
  /// ```dart
  /// final cache = XlruAsyncCache<String, int>(
  ///   maxSize: 10,
  ///   store: XlruMemoryStore<String, int>().asAsync(),
  /// );
  /// ```
  XlruAsyncStore<K, V> asAsync() => _SyncAsAsyncStore<K, V>(this);
}
