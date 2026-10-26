import 'package:test/test.dart';
import 'package:xlru/xlru.dart';

import 'support/fakes.dart';

void main() {
  group('XlruMemoryStore', () {
    test('reads, writes, deletes and clears', () {
      final store = XlruMemoryStore<String, int>();
      expect(store.read('a'), isNull);
      store.write('a', 1);
      store.write('a', 2);
      expect(store.read('a'), 2);
      expect(store.length, 1);
      store.delete('a');
      store.delete('missing');
      expect(store.length, 0);
      store.write('b', 3);
      store.clear();
      expect(store.read('b'), isNull);
    });

    test('supports custom key equality', () {
      final store = XlruMemoryStore<String, int>(
        equals: (a, b) => a.toLowerCase() == b.toLowerCase(),
        hashCode: (k) => k.toLowerCase().hashCode,
      )..write('A', 1);
      expect(store.read('a'), 1);
    });

    test('asAsync wraps results and errors', () async {
      final sync = MapStore<String, int>();
      final async = sync.asAsync();
      await async.write('a', 1);
      expect(await async.read('a'), 1);
      await async.delete('a');
      expect(await async.read('a'), isNull);
      await async.write('b', 2);
      await async.clear();
      expect(sync.data, isEmpty);
      sync.failRead = true;
      await expectLater(async.read('a'), throwsStateError);
    });
  });

  group('XlruCache with a store', () {
    late MapStore<String, int> store;
    late List<String> events;

    XlruCache<String, int> make({int maxSize = 2}) => XlruCache<String, int>(
          maxSize: maxSize,
          store: store,
          onRemove: (k, v, c) => events.add('$k=$v:${c.name}'),
        );

    setUp(() {
      store = MapStore<String, int>();
      events = [];
    });

    test('keeps values in the store and mirrors the cache keys', () {
      final cache = make();
      cache.set('a', 1);
      cache.set('b', 2);
      cache.get('a');
      cache.set('c', 3);
      expect(cache.keys, ['c', 'a']);
      expect(store.data, {'a': 1, 'c': 3});
      expect(cache.peek('a'), 1);
      expect(cache.get('b'), isNull);
      expect(events, ['b=2:evicted']);
    });

    test('reads values from the store, not from memory', () {
      final cache = make();
      cache.set('a', 1);
      store.data['a'] = 99;
      expect(cache.get('a'), 99);
      expect(cache.values, [99]);
      expect(cache.entries.single.value, 99);
      expect(cache.toMap(), {'a': 99});
    });

    test('reports replaced with the old value and writes the new one', () {
      final cache = make()..set('a', 1);
      cache.set('a', 2);
      expect(events, ['a=1:replaced']);
      expect(store.data, {'a': 2});
      events.clear();
      cache.set('a', 2); // Same value read back: identical, so no notification.
      expect(events, isEmpty);
    });

    test('remove returns the value and deletes it from the store', () {
      final cache = make()..set('a', 1);
      expect(cache.remove('a'), 1);
      expect(store.data, isEmpty);
      expect(events, ['a=1:removed']);
      expect(cache.remove('a'), isNull);
    });

    test('remove ignores pins, as without a store', () {
      final cache = make()
        ..set('a', 1)
        ..pin('a');
      expect(cache.remove('a'), 1);
      expect(store.data, isEmpty);
    });

    test('clear notifies oldest first and clears the store once', () {
      final cache = make()
        ..set('a', 1)
        ..set('b', 2);
      cache.clear();
      expect(events, ['a=1:cleared', 'b=2:cleared']);
      expect(store.data, isEmpty);
      expect(store.log.where((e) => e == 'clear'), hasLength(1));
      expect(cache.length, 0);
    });

    test('pinned entries are not evicted and the store follows', () {
      final cache = make(maxSize: 1)
        ..set('a', 1)
        ..pin('a');
      cache.set('b', 2);
      expect(cache.keys, ['b', 'a']);
      expect(store.data, {'a': 1, 'b': 2});
      cache.unpin('a');
      expect(cache.keys, ['b']);
      expect(store.data, {'b': 2});
      expect(events, ['a=1:evicted']);
    });

    test('putIfAbsent returns the stored value or creates one', () {
      final cache = make();
      expect(cache.putIfAbsent('a', () => 1), 1);
      expect(cache.putIfAbsent('a', () => 2), 1);
      expect(store.data, {'a': 1});
    });

    test('usePinned reads from the store and unpins afterwards', () {
      final cache = make()..set('a', 1);
      store.data['a'] = 5;
      final result = cache.usePinned('a', (v) {
        expect(cache.isPinned('a'), isTrue);
        return v * 2;
      });
      expect(result, 10);
      expect(cache.isPinned('a'), isFalse);
    });

    test('a failing write leaves the cache and store unchanged', () {
      final cache = make()..set('a', 1);
      store.failWrite = true;
      expect(() => cache.set('b', 2), throwsStateError);
      expect(() => cache.set('a', 9), throwsStateError);
      expect(cache.keys, ['a']);
      expect(store.data, {'a': 1});
      expect(events, isEmpty);
    });

    test('a failing delete still updates the cache, then throws', () {
      final cache = make(maxSize: 1)..set('a', 1);
      store.failDelete = true;
      expect(() => cache.set('b', 2), throwsStateError);
      expect(cache.keys, ['b']);
      expect(events, ['a=1:evicted']);
    });

    test('a failing read propagates and keeps the entry', () {
      final cache = make()..set('a', 1);
      store.failRead = true;
      expect(() => cache.get('a'), throwsStateError);
      expect(cache.containsKey('a'), isTrue);
    });

    test('a failing clear leaves the cache untouched', () {
      final cache = make()..set('a', 1);
      store.failClear = true;
      expect(cache.clear, throwsStateError);
      expect(cache.keys, ['a']);
    });

    test('lost: get returns null, removes the entry and notifies', () {
      final nullable = MapStore<String, int?>();
      final causes = <String>[];
      final cache = XlruCache<String, int?>(
        maxSize: 3,
        store: nullable,
        onRemove: (k, v, c) => causes.add('$k=$v:${c.name}'),
      )..set('a', 1);
      nullable.data.remove('a');
      expect(cache.get('a'), isNull);
      expect(cache.containsKey('a'), isFalse);
      expect(causes, ['a=null:lost']);
      expect(cache.length, 0);
    });

    test('lost with a non-nullable V is removed without a notification', () {
      final cache = make()..set('a', 1);
      store.data.remove('a');
      expect(cache.peek('a'), isNull);
      expect(cache.containsKey('a'), isFalse);
      expect(events, isEmpty);
    });

    test('lost value during putIfAbsent is recreated', () {
      final cache = make()..set('a', 1);
      store.data.remove('a');
      expect(cache.putIfAbsent('a', () => 7), 7);
      expect(store.data, {'a': 7});
    });

    test('iterating a lost value throws StateError', () {
      final cache = make()..set('a', 1);
      store.data.remove('a');
      expect(() => cache.values.toList(), throwsStateError);
    });

    test('eviction without a listener still deletes from the store', () {
      final cache = XlruCache<String, int>(maxSize: 1, store: store)
        ..set('a', 1)
        ..set('b', 2);
      expect(store.data, {'b': 2});
      expect(cache.keys, ['b']);
    });

    test('resize evicts from the store too', () {
      final cache = make(maxSize: 3)
        ..set('a', 1)
        ..set('b', 2)
        ..set('c', 3);
      cache.resize(1);
      expect(store.data, {'c': 3});
    });

    test('a listener that re-stores a later key of the batch keeps its value',
        () {
      late XlruCache<String, int> cache;
      cache = XlruCache<String, int>(
        maxSize: 3,
        store: store,
        onRemove: (k, v, c) {
          if (k == 'a' && c == XlruRemovalCause.evicted) cache.set('b', 99);
        },
      )
        ..set('a', 1)
        ..set('b', 2)
        ..set('c', 3);
      cache.resize(1);
      expect(cache.keys, ['b']);
      expect(store.data, {'b': 99});
      expect(cache.get('b'), 99);
    });

    test('a throwing listener does not stop store deletes', () {
      final cache = XlruCache<String, int>(
        maxSize: 1,
        store: store,
        onRemove: (k, v, c) => throw StateError('listener'),
      )..set('a', 1);
      expect(() => cache.set('b', 2), throwsStateError);
      expect(store.data, {'b': 2});
    });
  });
}
