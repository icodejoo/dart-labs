@TestOn('vm')
library;

import 'dart:io';

import 'package:hive_ce/hive.dart';
import 'package:test/test.dart';
import 'package:xlru/xlru.dart';

import 'support/fakes.dart';
import 'support/hive_stores.dart';

/// A fresh, empty backend plus ways to inspect it and to make it forget data.
class _Fixture {
  _Fixture(this.store, this.keys, this.drop);

  final XlruAsyncStore<String, int> store;

  /// The keys the backend currently holds.
  final Future<Set<String>> Function() keys;

  /// Deletes a key behind the cache's back, as an external cleanup would.
  final Future<void> Function(String key) drop;
}

/// One backend under test.
class _Backend {
  _Backend(this.name, this.create);

  final String name;
  final Future<_Fixture> Function() create;
}

void main() {
  late Directory dir;

  setUpAll(() {
    dir = Directory.systemTemp.createTempSync('xlru_hive_');
    Hive.init(dir.path);
  });

  tearDownAll(() async {
    await Hive.close();
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {
      // Windows may still hold the files; the temp dir is disposable.
    }
  });

  var boxId = 0;
  final backends = <_Backend>[
    _Backend('memory (sync store via asAsync)', () async {
      final store = XlruMemoryStore<String, int>();
      return _Fixture(store.asAsync(), () async => store.keys.toSet(),
          (key) async => store.delete(key));
    }),
    _Backend('scripted async store', () async {
      final store = ScriptedAsyncStore<String, int>();
      return _Fixture(store, () async => store.data.keys.toSet(),
          (key) async => store.data.remove(key));
    }),
    _Backend('hive Box (sync store via asAsync)', () async {
      final box = await Hive.openBox<int>('box${boxId++}');
      return _Fixture(
          HiveBoxStore<int>(box).asAsync(),
          () async => box.keys.cast<String>().toSet(),
          (key) async => box.delete(key));
    }),
    _Backend('hive LazyBox (native async)', () async {
      final box = await Hive.openLazyBox<int>('lazy${boxId++}');
      return _Fixture(
          HiveLazyBoxStore<int>(box),
          () async => box.keys.cast<String>().toSet(),
          (key) async => box.delete(key));
    }),
  ];

  for (final backend in backends) {
    group('XlruAsyncCache over ${backend.name}', () {
      late XlruAsyncCache<String, int> cache;
      late _Fixture fixture;
      late Future<Set<String>> Function() stored;
      late List<String> events;

      setUp(() async {
        fixture = await backend.create();
        stored = fixture.keys;
        events = [];
        cache = XlruAsyncCache<String, int>(
          maxSize: 2,
          store: fixture.store,
          onRemove: (k, load, c) async =>
              events.add('$k=${await load()}:${c.name}'),
        );
      });

      test('stores values, evicts in LRU order and mirrors the keys', () async {
        await cache.set('a', 1);
        await cache.set('b', 2);
        expect(await cache.get('a'), 1);
        await cache.set('c', 3);
        expect(cache.keys, ['c', 'a']);
        expect(await stored(), {'a', 'c'});
        expect(await cache.get('b'), isNull);
        expect(events, ['b=2:evicted']);
      });

      test('replace, remove and clear', () async {
        await cache.set('a', 1);
        await cache.set('a', 2);
        expect(await cache.peek('a'), 2);
        expect(events, ['a=1:replaced']);
        expect(await cache.remove('a'), 2);
        expect(await stored(), isEmpty);
        await cache.set('x', 7);
        await cache.set('y', 8);
        events.clear();
        await cache.clear();
        expect(events, ['x=7:cleared', 'y=8:cleared']);
        expect(await stored(), isEmpty);
        expect(cache.length, 0);
      });

      test('pins keep an entry past capacity until unpinned', () async {
        await cache.set('a', 1);
        cache.pin('a');
        await cache.set('b', 2);
        await cache.set('c', 3);
        expect(cache.containsKey('a'), isTrue);
        expect(cache.length, 2);
        await cache.unpin('a');
        expect(await stored(), cache.keys.toSet());
      });

      test('putIfAbsent shares one load and caches it', () async {
        var loads = 0;
        Future<int> loader() async {
          loads++;
          await Future<void>.delayed(const Duration(milliseconds: 5));
          return 42;
        }

        final results = await Future.wait(
            [for (var i = 0; i < 4; i++) cache.putIfAbsent('k', loader)]);
        expect(results, [42, 42, 42, 42]);
        expect(loads, 1);
        expect(await cache.get('k'), 42);
        expect(await stored(), {'k'});
      });

      test('usePinned reads through the store and unpins', () async {
        await cache.set('a', 5);
        final result = await cache.usePinned('a', (v) async => v * 3);
        expect(result, 15);
        expect(cache.isPinned('a'), isFalse);
      });

      test('a value that vanished from the store is lost', () async {
        await cache.set('a', 1);
        await cache.set('b', 2);
        await fixture.drop('a');
        expect(await cache.get('a'), isNull);
        expect(cache.keys, ['b']);
        expect(events, ['a=null:lost']);
        expect(await cache.toMap(), {'b': 2});
      });
    });
  }

  group('XlruCache over a Hive Box', () {
    test('persists values through the sync store', () async {
      final box = await Hive.openBox<int>('syncbox');
      final events = <String>[];
      final cache = XlruCache<String, int>(
        maxSize: 2,
        store: HiveBoxStore<int>(box),
        onRemove: (k, v, c) => events.add('$k=$v:${c.name}'),
      );
      cache.set('a', 1);
      cache.set('b', 2);
      cache.get('a');
      cache.set('c', 3);
      expect(cache.keys, ['c', 'a']);
      expect(box.keys.toSet(), {'a', 'c'});
      expect(events, ['b=2:evicted']);
      expect(cache.usePinned('a', (v) => v + 1), 2);
      cache.clear();
      expect(box.isEmpty, isTrue);
      await box.close();
    });
  });
}
