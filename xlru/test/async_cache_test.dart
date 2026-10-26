import 'dart:async';
import 'dart:math';

import 'package:test/test.dart';
import 'package:xlru/xlru.dart';

import 'support/fakes.dart';

void main() {
  late ScriptedAsyncStore<String, int> store;
  late List<String> events;
  late List<String> errors;

  XlruAsyncCache<String, int> make({
    int maxSize = 2,
    bool withError = false,
    bool allowSelfEviction = false,
  }) =>
      XlruAsyncCache<String, int>(
        maxSize: maxSize,
        store: store,
        allowSelfEviction: allowSelfEviction,
        onRemove: (key, load, cause) async {
          final value = await load();
          events.add('$key=$value:${cause.name}');
        },
        onError: withError
            ? (error, stack, op, key) => errors.add('${op.name} $key')
            : null,
      );

  setUp(() {
    store = ScriptedAsyncStore<String, int>();
    events = [];
    errors = [];
  });

  test('validates the capacity', () {
    expect(() => XlruAsyncCache<String, int>(maxSize: 0), throwsArgumentError);
    final cache = XlruAsyncCache<String, int>(maxSize: 1);
    expect(cache.resize(0), throwsArgumentError);
  });

  group('with the default in-memory store', () {
    test('behaves like an LRU cache', () async {
      final cache = XlruAsyncCache<String, int>(maxSize: 2);
      await cache.set('a', 1);
      await cache.set('b', 2);
      expect(await cache.get('a'), 1);
      await cache.set('c', 3);
      expect(cache.keys, ['c', 'a']);
      expect(await cache.get('b'), isNull);
      expect(await cache.peek('a'), 1);
      expect(cache.length, 2);
      expect(cache.isEmpty, isFalse);
      expect(cache.isNotEmpty, isTrue);
      expect(cache.maxSize, 2);
      expect(cache.allowSelfEviction, isFalse);
      expect(cache.containsKey('c'), isTrue);
      expect(await cache.toMap(), {'c': 3, 'a': 1});
      expect((await cache.toMap()).keys, ['c', 'a']);
    });

    test('supports custom key equality', () async {
      final cache = XlruAsyncCache<String, int>(
        maxSize: 2,
        equals: (a, b) => a.toLowerCase() == b.toLowerCase(),
        hashCode: (k) => k.toLowerCase().hashCode,
      );
      await cache.set('A', 1);
      expect(await cache.get('a'), 1);
      expect(cache.length, 1);
    });
  });

  group('removal', () {
    test('evicted loads the value before deleting it', () async {
      final cache = make(maxSize: 1);
      await cache.set('a', 1);
      await cache.set('b', 2);
      expect(events, ['a=1:evicted']);
      expect(store.data, {'b': 2});
      expect(
          store.log.indexOf('read a'), lessThan(store.log.indexOf('delete a')));
    });

    test('replaced loads the old value before the new write', () async {
      final cache = make();
      await cache.set('a', 1);
      await cache.set('a', 2);
      expect(events, ['a=1:replaced']);
      expect(store.data, {'a': 2});
    });

    test('remove returns the value and reports removed', () async {
      final cache = make();
      await cache.set('a', 1);
      expect(await cache.remove('a'), 1);
      expect(await cache.remove('a'), isNull);
      expect(events, ['a=1:removed']);
      expect(store.data, isEmpty);
      expect(cache.length, 0);
    });

    test('remove ignores pins', () async {
      final cache = make();
      await cache.set('a', 1);
      cache.pin('a');
      expect(await cache.remove('a'), 1);
    });

    test('clear reports cleared oldest first, then clears the store', () async {
      final cache = make();
      await cache.set('a', 1);
      await cache.set('b', 2);
      await cache.clear();
      expect(events, ['a=1:cleared', 'b=2:cleared']);
      expect(store.data, isEmpty);
      expect(cache.length, 0);
    });

    test('a missing store value is lost', () async {
      final cache = make();
      await cache.set('a', 1);
      store.data.remove('a');
      expect(await cache.get('a'), isNull);
      expect(cache.containsKey('a'), isFalse);
      expect(events, ['a=null:lost']);
    });

    test('a throwing listener still deletes, then rethrows', () async {
      final cache = XlruAsyncCache<String, int>(
        maxSize: 1,
        store: store,
        onRemove: (k, load, c) => throw StateError('listener'),
      );
      await cache.set('a', 1);
      await expectLater(cache.set('b', 2), throwsStateError);
      expect(store.data, {'b': 2});
      expect(cache.keys, ['b']);
    });
  });

  group('pins', () {
    test('pinned entries survive eviction until unpinned', () async {
      final cache = make(maxSize: 1);
      await cache.set('a', 1);
      expect(cache.pin('a'), isTrue);
      expect(cache.pin('zz'), isFalse);
      await cache.set('b', 2);
      expect(cache.keys, ['b', 'a']);
      expect(cache.isPinned('a'), isTrue);
      expect(await cache.unpin('a'), isTrue);
      expect(await cache.unpin('a'), isFalse);
      expect(cache.keys, ['b']);
      expect(events, ['a=1:evicted']);
      expect(store.data, {'b': 2});
    });

    test('usePinned pins around the action and always unpins', () async {
      final cache = make();
      await cache.set('a', 1);
      final result = await cache.usePinned('a', (v) async {
        expect(cache.isPinned('a'), isTrue);
        return v + 1;
      });
      expect(result, 2);
      expect(cache.isPinned('a'), isFalse);
      expect(await cache.usePinned('zz', (v) => v), isNull);
      await expectLater(
          cache.usePinned('a', (v) => throw StateError('x')), throwsStateError);
      expect(cache.isPinned('a'), isFalse);
    });

    test('resize evicts and waits for the removals', () async {
      final cache = make(maxSize: 3);
      await cache.set('a', 1);
      await cache.set('b', 2);
      await cache.set('c', 3);
      await cache.resize(1);
      expect(cache.keys, ['c']);
      expect(store.data, {'c': 3});
      expect(events, ['a=1:evicted', 'b=2:evicted']);
    });
  });

  group('ordering and concurrency', () {
    test('operations on one key run in call order', () async {
      final cache = make();
      store.hold.add('write a');
      final set = cache.set('a', 1);
      await store.waitStarted('write a');
      final get = cache.get('a'); // Queued behind the write.
      await Future<void>.delayed(Duration.zero);
      expect(cache.containsKey('a'), isFalse);
      store.release('write a');
      await set;
      expect(await get, 1);
    });

    test('different keys do not wait for each other', () async {
      final cache = make();
      store.hold.add('write a');
      final slow = cache.set('a', 1);
      await store.waitStarted('write a');
      await cache.set('b', 2); // Completes while a's write is held.
      expect(cache.keys, ['b']);
      store.release('write a');
      await slow;
      expect(cache.keys, ['a', 'b']);
    });

    test('clear waits for pending work and blocks later work', () async {
      final cache = make();
      store.hold.add('write a');
      final set = cache.set('a', 1);
      await store.waitStarted('write a');
      final clear = cache.clear();
      final later = cache.set('b', 2);
      await Future<void>.delayed(Duration.zero);
      expect(store.log, isNot(contains('clear')));
      store.release('write a');
      await set;
      await clear;
      await later;
      expect(cache.keys, ['b']);
      expect(store.data, {'b': 2});
    });

    test('a key evicting itself does not deadlock', () async {
      final cache = make(maxSize: 1, allowSelfEviction: true);
      await cache.set('a', 1);
      cache.pin('a');
      await cache.set('b', 2).timeout(const Duration(seconds: 2));
      expect(cache.containsKey('b'), isFalse);
      expect(events, contains('b=2:evicted'));
    });

    test('two keys evicting each other do not deadlock', () async {
      final cache = make(maxSize: 1);
      store.hold.add('write a');
      final a = cache.set('a', 1);
      await store.waitStarted('write a');
      final b = cache.set('b', 2);
      store.release('write a');
      await Future.wait([a, b]).timeout(const Duration(seconds: 2));
      expect(cache.length, 1);
      expect(store.data.keys.toSet(), cache.keys.toSet());
    });

    test('a write in flight when its key is evicted wins over the eviction',
        () async {
      final cache = make(maxSize: 1);
      await cache.set('a', 1);
      store.resetStarted('write a');
      store.hold.add('write a');
      final rewrite = cache.set('a', 5);
      await store.waitStarted('write a');
      // Evicts a from the index while a is writing. It completes only after
      // a's eviction cleanup, which queues behind the held write.
      final other = cache.set('b', 2);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(cache.containsKey('a'), isFalse);
      store.release('write a');
      await Future.wait([rewrite, other]);
      expect(cache.keys, ['a']);
      expect(store.data, {'a': 5});
      expect(events, isNot(contains('a=5:evicted')));
    });

    for (final seed in [1, 2, 3, 7, 11, 13, 17, 19, 23, 29]) {
      test('random interleavings keep the store in step (seed $seed)',
          () async {
        final random = Random(seed);
        store.jitter = () async {
          for (var i = random.nextInt(3); i > 0; i--) {
            await Future<void>.delayed(Duration.zero);
          }
        };
        final cache = XlruAsyncCache<String, int>(maxSize: 4, store: store);
        final pending = <Future<Object?>>[];
        for (var i = 0; i < 400; i++) {
          final key = 'k${random.nextInt(8)}';
          switch (random.nextInt(9)) {
            case 0:
            case 1:
            case 2:
              pending.add(cache.set(key, i));
            case 3:
              pending.add(cache.get(key));
            case 4:
              pending.add(cache.peek(key));
            case 5:
              pending.add(cache.remove(key));
            case 6:
              pending.add(cache.putIfAbsent(key, () async => i));
            case 7:
              pending.add(cache.unpin(key));
              cache.pin(key);
            case 8:
              if (random.nextInt(25) == 0) pending.add(cache.clear());
          }
          if (random.nextInt(5) == 0) {
            await Future<void>.delayed(Duration.zero);
          }
        }
        await Future.wait(pending).timeout(const Duration(seconds: 20));
        for (final key in cache.keys.toList()) {
          while (cache.isPinned(key)) {
            await cache.unpin(key);
          }
        }
        expect(store.data.keys.toSet(), cache.keys.toSet());
        expect(cache.length, lessThanOrEqualTo(4));
      });
    }
  });

  group('putIfAbsent', () {
    test('returns the cached value without loading', () async {
      final cache = make();
      await cache.set('a', 1);
      var loads = 0;
      expect(await cache.putIfAbsent('a', () async => ++loads), 1);
      expect(loads, 0);
    });

    test('concurrent calls share one load', () async {
      final cache = make();
      var loads = 0;
      final gate = Completer<int>();
      Future<int> loader() {
        loads++;
        return gate.future;
      }

      final calls = [
        for (var i = 0; i < 3; i++) cache.putIfAbsent('a', loader)
      ];
      await Future<void>.delayed(Duration.zero);
      gate.complete(5);
      expect(await Future.wait(calls), [5, 5, 5]);
      expect(loads, 1);
      expect(await cache.get('a'), 5);
    });

    test('a failing load caches nothing and fails every waiter', () async {
      final cache = make();
      final gate = Completer<int>();
      final calls = [
        for (var i = 0; i < 2; i++) cache.putIfAbsent('a', () => gate.future)
      ];
      final results =
          calls.map((c) => c.then<Object?>((v) => v, onError: (e) => e));
      await Future<void>.delayed(Duration.zero);
      gate.completeError(StateError('load'));
      expect(await Future.wait(results), everyElement(isA<StateError>()));
      expect(cache.containsKey('a'), isFalse);
      expect(await cache.putIfAbsent('a', () async => 9), 9);
    });

    test('a set during the load wins; the load is returned but not cached',
        () async {
      final cache = make();
      final gate = Completer<int>();
      final load = cache.putIfAbsent('a', () => gate.future);
      await Future<void>.delayed(Duration.zero);
      await cache.set('a', 1);
      gate.complete(2);
      expect(await load, 2);
      expect(await cache.get('a'), 1);
    });

    test('a remove or clear during the load discards it', () async {
      final cache = make();
      final removeGate = Completer<int>();
      final removed = cache.putIfAbsent('a', () => removeGate.future);
      await Future<void>.delayed(Duration.zero);
      await cache.remove('a');
      removeGate.complete(1);
      await removed;
      expect(cache.containsKey('a'), isFalse);

      final clearGate = Completer<int>();
      final cleared = cache.putIfAbsent('b', () => clearGate.future);
      await Future<void>.delayed(Duration.zero);
      await cache.clear();
      clearGate.complete(2);
      await cleared;
      expect(cache.containsKey('b'), isFalse);
    });
  });

  group('store failures', () {
    test('without onError a failing write throws and changes nothing',
        () async {
      final cache = make();
      await cache.set('a', 1);
      store.fail.add('write b');
      await expectLater(cache.set('b', 2), throwsStateError);
      store.fail.add('write a');
      await expectLater(cache.set('a', 9), throwsStateError);
      expect(cache.keys, ['a']);
      expect(store.data, {'a': 1});
    });

    test('with onError a failing write is reported and skipped', () async {
      final cache = make(withError: true);
      store.fail.add('write a');
      await cache.set('a', 1);
      expect(errors, ['write a']);
      expect(cache.containsKey('a'), isFalse);
    });

    test('without onError a failing read throws and keeps the entry', () async {
      final cache = make();
      await cache.set('a', 1);
      store.fail.add('read a');
      await expectLater(cache.get('a'), throwsStateError);
      expect(cache.containsKey('a'), isTrue);
    });

    test('with onError a failing read counts as lost', () async {
      final cache = make(withError: true);
      await cache.set('a', 1);
      store.fail.add('read a');
      expect(await cache.get('a'), isNull);
      expect(errors, contains('read a'));
      expect(cache.containsKey('a'), isFalse);
    });

    test('a failing delete updates the index, then throws', () async {
      final cache = make(maxSize: 1);
      await cache.set('a', 1);
      store.fail.add('delete a');
      await expectLater(cache.set('b', 2), throwsStateError);
      expect(cache.keys, ['b']);
    });

    test('with onError a failing delete or clear is only reported', () async {
      final cache = make(maxSize: 1, withError: true);
      await cache.set('a', 1);
      store.fail.add('delete a');
      await cache.set('b', 2);
      expect(cache.keys, ['b']);
      store.fail.add('clear');
      await cache.clear();
      expect(errors, ['delete a', 'clear null']);
    });

    test('a failing clear without onError leaves the cache untouched',
        () async {
      final cache = make();
      await cache.set('a', 1);
      store.fail.add('clear');
      await expectLater(cache.clear(), throwsStateError);
      expect(cache.keys, ['a']);
      // The barrier is released, so the cache still works.
      store.fail.clear();
      await cache.set('b', 2);
      expect(cache.keys, ['b', 'a']);
    });
  });

  group('review regressions', () {
    test('a set right after putIfAbsent wins over the load', () async {
      final cache = make();
      final gate = Completer<int>();
      final load = cache.putIfAbsent('a', () => gate.future);
      final set = cache.set('a', 1); // Before the load's first lookup is done.
      await set;
      gate.complete(2);
      expect(await load, 2);
      expect(await cache.get('a'), 1);
    });

    test('a throwing replace listener still writes the new value', () async {
      final cache = XlruAsyncCache<String, int>(
        maxSize: 2,
        store: store,
        onRemove: (k, load, c) {
          if (c == XlruRemovalCause.replaced) throw StateError('listener');
        },
      );
      await cache.set('a', 1);
      await expectLater(cache.set('a', 2), throwsStateError);
      expect(store.data, {'a': 2});
      expect(cache.containsKey('a'), isTrue);
    });

    test('clear runs the cleanup of an eviction that started before it',
        () async {
      final cache = make(maxSize: 1);
      await cache.set('b', 2);
      store.resetStarted('write a');
      store.hold.add('write a');
      final setA = cache.set('a', 1);
      await store.waitStarted('write a');
      final clear = cache.clear();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      store.release('write a');
      await Future.wait([setA, clear]);
      // b is evicted with its value intact, before clear wipes the store.
      expect(events, ['b=2:evicted', 'a=1:cleared']);
      expect(cache.length, 0);
      expect(store.data, isEmpty);
    });

    test('operations started during clear run after it, in call order',
        () async {
      final cache = make();
      store.hold.add('clear');
      final clear = cache.clear();
      await store.waitStarted('clear');
      final first = cache.set('a', 1);
      final second = cache.set('a', 2);
      store.release('clear');
      await Future.wait([clear, first, second]);
      expect(await cache.get('a'), 2);
      expect(store.data, {'a': 2});
    });

    test('two clears in a row both complete', () async {
      final cache = make();
      await cache.set('a', 1);
      await Future.wait([cache.clear(), cache.clear()]);
      expect(cache.length, 0);
    });
  });
}
