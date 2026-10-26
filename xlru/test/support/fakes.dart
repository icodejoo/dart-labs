import 'dart:async';

import 'package:xlru/xlru.dart';

/// A synchronous map-backed store with failure switches and an operation log.
class MapStore<K, V> implements XlruStore<K, V> {
  final Map<K, V> data = {};
  final List<String> log = [];
  bool failRead = false;
  bool failWrite = false;
  bool failDelete = false;
  bool failClear = false;

  @override
  V? read(K key) {
    log.add('read $key');
    if (failRead) throw StateError('read failed');
    return data[key];
  }

  @override
  void write(K key, V value) {
    log.add('write $key');
    if (failWrite) throw StateError('write failed');
    data[key] = value;
  }

  @override
  void delete(K key) {
    log.add('delete $key');
    if (failDelete) throw StateError('delete failed');
    data.remove(key);
  }

  @override
  void clear() {
    log.add('clear');
    if (failClear) throw StateError('clear failed');
    data.clear();
  }
}

/// An asynchronous store whose operations can be held open and failed on cue.
class ScriptedAsyncStore<K, V> implements XlruAsyncStore<K, V> {
  final Map<K, V> data = {};
  final List<String> log = [];

  /// Operations whose name (for example `write a`) is in here wait for [release].
  final Set<String> hold = {};

  /// Operations whose name is in here throw after their delay.
  final Set<String> fail = {};

  /// Awaited before every operation when set, to shuffle interleavings.
  Future<void> Function()? jitter;

  final Map<String, Completer<void>> _starts = {};
  final Map<String, Completer<void>> _release = {};

  Completer<void> _startGate(String name) =>
      _starts.putIfAbsent(name, Completer<void>.new);

  /// Waits until the operation named [name] is blocked on [hold].
  Future<void> waitStarted(String name) => _startGate(name).future;

  /// Forgets that [name] started, so [waitStarted] waits for the next one.
  void resetStarted(String name) => _starts.remove(name);

  /// Lets a held operation continue.
  void release(String name) {
    hold.remove(name);
    final gate = _release[name];
    if (gate != null && !gate.isCompleted) gate.complete();
  }

  Future<void> _step(String name) async {
    log.add(name);
    final start = _startGate(name);
    if (!start.isCompleted) start.complete();
    final jitterFn = jitter;
    if (jitterFn != null) await jitterFn();
    if (hold.contains(name)) {
      await (_release[name] ??= Completer<void>()).future;
    }
    if (fail.contains(name)) throw StateError('$name failed');
  }

  @override
  Future<V?> read(K key) async {
    await _step('read $key');
    return data[key];
  }

  @override
  Future<void> write(K key, V value) async {
    await _step('write $key');
    data[key] = value;
  }

  @override
  Future<void> delete(K key) async {
    await _step('delete $key');
    data.remove(key);
  }

  @override
  Future<void> clear() async {
    await _step('clear');
    data.clear();
  }
}
