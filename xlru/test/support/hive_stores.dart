import 'dart:async';

import 'package:hive_ce/hive.dart';
import 'package:xlru/xlru.dart';

/// A synchronous store over a Hive [Box]: reads hit memory, writes are flushed
/// to disk in the background.
class HiveBoxStore<V> implements XlruStore<String, V> {
  HiveBoxStore(this.box);

  final Box<V> box;

  @override
  V? read(String key) => box.get(key);

  @override
  void write(String key, V value) => unawaited(box.put(key, value));

  @override
  void delete(String key) => unawaited(box.delete(key));

  /// [Box.clear] only reaches memory after its future completes, so a
  /// synchronous store deletes key by key, which is visible immediately.
  @override
  void clear() {
    for (final key in box.keys.toList()) {
      unawaited(box.delete(key));
    }
  }
}

/// An asynchronous store over a Hive [LazyBox]: every read goes to disk.
class HiveLazyBoxStore<V> implements XlruAsyncStore<String, V> {
  HiveLazyBoxStore(this.box);

  final LazyBox<V> box;

  @override
  Future<V?> read(String key) => box.get(key);

  @override
  Future<void> write(String key, V value) => box.put(key, value);

  @override
  Future<void> delete(String key) => box.delete(key);

  @override
  Future<void> clear() async {
    await box.clear();
  }
}
