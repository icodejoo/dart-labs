import 'package:benchmark_harness/benchmark_harness.dart';
import 'package:quiver/collection.dart';
import 'package:xlru/xlru.dart';

import 'naive_lru.dart';

abstract class _Adapter<K> {
  int? get(K key);
  void set(K key, int value);
}

class _Xlru<K> implements _Adapter<K> {
  _Xlru(int capacity) : cache = XlruCache<K, int>(maxSize: capacity);
  final XlruCache<K, int> cache;
  @override
  int? get(K key) => cache.get(key);
  @override
  void set(K key, int value) => cache.set(key, value);
}

class _Naive<K> implements _Adapter<K> {
  _Naive(int capacity) : cache = NaiveLru<K, int>(capacity);
  final NaiveLru<K, int> cache;
  @override
  int? get(K key) => cache.get(key);
  @override
  void set(K key, int value) => cache.set(key, value);
}

class _Quiver<K> implements _Adapter<K> {
  _Quiver(int capacity) : cache = LruMap<K, int>(maximumSize: capacity);
  final LruMap<K, int> cache;
  @override
  int? get(K key) => cache[key];
  @override
  void set(K key, int value) => cache[key] = value;
}

class _Operation<K> {
  _Operation(this.key, this.write);
  final K key;
  final bool write;
}

class _LruBenchmark<K> extends BenchmarkBase {
  _LruBenchmark(this.implementation, this.capacity, this.keyType, this.scenario,
      this.makeKey)
      : super('$implementation/$capacity/$keyType/$scenario');
  final String implementation;
  final int capacity;
  final String keyType;
  final String scenario;
  final K Function(int) makeKey;
  late _Adapter<K> cache;
  late List<_Operation<K>> operations;
  int checksum = 0;

  @override
  void setup() {
    cache = switch (implementation) {
      'xlru' => _Xlru<K>(capacity),
      'naive' => _Naive<K>(capacity),
      _ => _Quiver<K>(capacity),
    };
    final keys = List.generate(capacity * 2, makeKey);
    for (var i = 0; i < capacity; i++) {
      cache.set(keys[i], 1);
    }
    // Each trace inserts a multiple of 2*capacity distinct cycling keys, so
    // repeated traces remain in steady state. All reads target resident keys.
    final writeEvery = switch (scenario) {
      'read90' => 10,
      'mixed' => 2,
      _ => 1,
    };
    var cursor = capacity;
    var random = 17;
    operations = List.generate(capacity * 20, (i) {
      final write = i % writeEvery == 0;
      if (write) {
        final key = keys[cursor % keys.length];
        cursor++;
        return _Operation(key, true);
      }
      random = (random * 1664525 + 1013904223) & 0x7fffffff;
      // Restrict reads to the newest half of inserted keys. This guarantees
      // hits despite read promotions changing the eviction order.
      final offset = random % (capacity ~/ 2);
      final index = (cursor - 1 - offset) % keys.length;
      return _Operation(keys[index], false);
    });
    // Verify hit assumptions for two repetitions outside the timed section.
    for (var repeat = 0; repeat < 2; repeat++) {
      for (final operation in operations) {
        if (operation.write) {
          cache.set(operation.key, 1);
        } else if (cache.get(operation.key) != 1) {
          throw StateError('Unexpected miss: $name');
        }
      }
    }
  }

  @override
  void run() {
    var sum = 0;
    for (final operation in operations) {
      if (operation.write) {
        cache.set(operation.key, 1);
      } else {
        sum += cache.get(operation.key) ?? 0;
      }
    }
    checksum = sum;
  }

  // One exercise is one complete trace, rather than the default ten runs.
  @override
  void exercise() => run();

  @override
  void teardown() {
    final expected = operations.where((op) => !op.write).length;
    if (checksum != expected) throw StateError('Invalid checksum: $name');
  }

  /// Number of timed runs per benchmark; the median is reported.
  static const _runs = 5;

  /// Minimum duration of each timed run, in milliseconds.
  static const _runMillis = 500;

  void csvReport() {
    setup();
    BenchmarkBase.measureFor(warmup, 200);
    final samples = [
      for (var i = 0; i < _runs; i++)
        BenchmarkBase.measureFor(exercise, _runMillis),
    ]..sort();
    teardown();
    final micros = samples[_runs ~/ 2];
    final nanosPerOp = micros * 1000 / operations.length;
    print('$implementation,$capacity,$keyType,$scenario,'
        '${nanosPerOp.toStringAsFixed(2)}');
  }
}

/// Comma-separated implementations to run, e.g. `-Dimpls=xlru,naive`.
const _impls =
    String.fromEnvironment('impls', defaultValue: 'xlru,naive,quiver');

void main() {
  print('implementation,capacity,key,scenario,ns_per_op');
  for (final capacity in [100, 10000]) {
    for (final scenario in ['read90', 'write', 'mixed']) {
      for (final implementation in _impls.split(',')) {
        _LruBenchmark<int>(implementation, capacity, 'int', scenario, (i) => i)
            .csvReport();
        _LruBenchmark<String>(
                implementation, capacity, 'String', scenario, (i) => 'key-$i')
            .csvReport();
      }
    }
  }
}
