import 'dart:math';

import 'package:test/test.dart';
import 'package:xlru/xlru.dart';

void main() {
  test('validates constructor and resize without changing state', () {
    for (final size in [0, -1]) {
      expect(() => XlruCache<int, int>(maxSize: size), throwsArgumentError);
    }
    final cache = XlruCache<int, int>(maxSize: 2)..set(1, 1);
    expect(() => cache.resize(0), throwsArgumentError);
    expect(() => cache.resize(-1), throwsArgumentError);
    expect(cache.maxSize, 2);
    expect(cache.keys, [1]);
  });

  test('empty, missing keys, and nullable values', () {
    final cache = XlruCache<String?, int?>(maxSize: 2);
    expect(cache.isEmpty, isTrue);
    expect(cache.isNotEmpty, isFalse);
    expect(cache.get('x'), isNull);
    expect(cache.peek('x'), isNull);
    expect(cache.remove('x'), isNull);
    expect(cache.pin('x'), isFalse);
    expect(cache.unpin('x'), isFalse);
    expect(cache.isPinned('x'), isFalse);
    cache.set(null, null);
    expect(cache.isNotEmpty, isTrue);
    expect(cache.containsKey(null), isTrue);
    expect(cache.putIfAbsent(null, () => fail('must not create')), isNull);
    expect(cache.length, 1);
  });

  test('get promotes while peek, containsKey, and iteration do not', () {
    final cache = XlruCache<int, int>(maxSize: 3)
      ..set(1, 10)
      ..set(2, 20)
      ..set(3, 30);
    expect(cache.peek(1), 10);
    expect(cache.containsKey(1), isTrue);
    expect(cache.keys, [3, 2, 1]);
    expect(cache.values, [30, 20, 10]);
    expect(cache.entries.map((e) => e.key), [3, 2, 1]);
    expect(cache.get(1), 10);
    expect(cache.keys, [1, 3, 2]);
    cache.set(4, 40);
    expect(cache.keys, [4, 1, 3]);
  });

  test('all four causes, old values, and identical replacement', () {
    final events = <(String, Object, XlruRemovalCause)>[];
    final a = Object();
    final b = Object();
    final cache = XlruCache<String, Object>(
      maxSize: 2,
      onRemove: (k, v, c) => events.add((k, v, c)),
    )
      ..set('a', a)
      ..set('b', b)
      ..set('a', a);
    expect(events, isEmpty);
    expect(cache.keys, ['a', 'b']);
    cache.set('a', b);
    cache.set('c', a);
    expect(cache.remove('a'), same(b));
    cache.remove('absent');
    cache.clear();
    cache.clear();
    expect(events, [
      ('a', a, XlruRemovalCause.replaced),
      ('b', b, XlruRemovalCause.evicted),
      ('a', b, XlruRemovalCause.removed),
      ('c', a, XlruRemovalCause.cleared),
    ]);
  });

  test('pin counts survive replacement and do not promote', () {
    final cache = XlruCache<int, int>(maxSize: 2)
      ..set(1, 1)
      ..set(2, 2);
    expect(cache.pin(1), isTrue);
    expect(cache.pin(1), isTrue);
    expect(cache.keys, [2, 1]);
    cache.set(1, 10);
    expect(cache.unpin(1), isTrue);
    expect(cache.isPinned(1), isTrue);
    cache.set(3, 3);
    expect(cache.keys, [3, 1]);
    expect(cache.unpin(1), isTrue);
    expect(cache.isPinned(1), isFalse);
    expect(cache.unpin(1), isFalse);
    cache.set(4, 4);
    expect(cache.keys, [4, 3]);
  });

  test('eviction skips consecutive pinned entries in the recency list', () {
    final removed = <int>[];
    final cache = XlruCache<int, int>(
      maxSize: 4,
      onRemove: (k, v, c) => removed.add(k),
    );
    for (var i = 1; i <= 4; i++) {
      cache.set(i, i);
    }
    cache.pin(1);
    cache.pin(2);
    cache.set(5, 5);
    expect(removed, [3]);
    expect(cache.keys, [5, 4, 2, 1]);
    cache.get(1);
    expect(cache.keys, [1, 5, 4, 2]);
  });

  test('strict mode: all pinned overflow converges after unpin, set, resize',
      () {
    final cache = XlruCache<int, int>(maxSize: 3, allowSelfEviction: true);
    for (var i = 1; i <= 3; i++) {
      cache.set(i, i);
      cache.pin(i);
    }
    cache.pin(1);
    cache.resize(1);
    expect(cache.length, 3);
    expect(cache.unpin(1), isTrue);
    expect(cache.length, 3);
    cache.set(4, 4); // The only unpinned entry evicts itself.
    expect(cache.containsKey(4), isFalse);
    cache.set(2, 20);
    expect(cache.isPinned(2), isTrue);
    cache.unpin(1);
    expect(cache.length, 2);
    cache.unpin(3);
    expect(cache.keys, [2]);
    cache.resize(4);
    cache.set(5, 5);
    expect(cache.keys, [5, 2]);
  });

  test('remove and clear ignore pins; clear notifies oldest first', () {
    final events = <int>[];
    final cache = XlruCache<int, int>(
      maxSize: 3,
      onRemove: (k, v, c) => events.add(k),
    )
      ..set(1, 1)
      ..set(2, 2)
      ..set(3, 3)
      ..pin(1)
      ..pin(2);
    expect(cache.remove(2), 2);
    cache.get(1);
    cache.clear();
    expect(events, [2, 3, 1]);
    expect(cache.length, 0);
  });

  test('resize finishes every eviction before any notification', () {
    final events = <int>[];
    late XlruCache<int, int> cache;
    cache = XlruCache<int, int>(
        maxSize: 4,
        onRemove: (k, v, c) {
          expect(cache.keys, [4]);
          expect(cache.maxSize, 1);
          expect(c, XlruRemovalCause.evicted);
          events.add(k);
        });
    for (var i = 1; i <= 4; i++) {
      cache.set(i, i);
    }
    cache.resize(1);
    expect(events, [1, 2, 3]);
  });

  test('putIfAbsent creates once and promotes hits', () {
    var calls = 0;
    final cache = XlruCache<int, int>(maxSize: 2)..set(1, 1);
    expect(cache.putIfAbsent(2, () => ++calls), 1);
    expect(cache.putIfAbsent(1, () => ++calls), 1);
    expect(calls, 1);
    expect(cache.keys, [1, 2]);
    expect(() => cache.putIfAbsent(3, () => throw StateError('creator')),
        throwsStateError);
    expect(cache.keys, [1, 2]);
  });

  test('strict mode: putIfAbsent reentrant creator and immediate eviction', () {
    final cache = XlruCache<int, int>(maxSize: 1, allowSelfEviction: true);
    expect(
        cache.putIfAbsent(1, () {
          cache.set(1, 10);
          return 20;
        }),
        20);
    expect(cache.peek(1), 20);
    cache.pin(1);
    expect(cache.putIfAbsent(2, () => 30), 30);
    expect(cache.keys, [1]);
    expect(
        () => cache.putIfAbsent(3, () {
              cache.remove(1);
              throw StateError('creator');
            }),
        throwsStateError);
    expect(cache.isEmpty, isTrue);
  });

  test('eviction listener can get, insert, remove, and resize reentrantly', () {
    final events = <int>[];
    late XlruCache<int, int> cache;
    cache = XlruCache<int, int>(
        maxSize: 2,
        onRemove: (k, v, c) {
          events.add(k);
          if (k == 1) {
            expect(cache.keys, [3, 2]);
            expect(cache.get(2), 2);
            cache.set(4, 4);
            cache.remove(4);
            cache.resize(3);
          }
        });
    cache.set(1, 1);
    cache.set(2, 2);
    cache.set(3, 3);
    expect(events, [1, 3, 4]);
    expect(cache.keys, [2]);
  });

  test('clear listener inserts remain while original batch is delivered', () {
    final events = <int>[];
    late XlruCache<int, int> cache;
    cache = XlruCache<int, int>(
        maxSize: 3,
        onRemove: (k, v, c) {
          events.add(k);
          if (k == 1) {
            expect(cache.isEmpty, isTrue);
            cache.set(9, 9);
          } else {
            expect(cache.keys, [9]);
          }
        })
      ..set(1, 1)
      ..set(2, 2)
      ..set(3, 3);
    cache.clear();
    expect(events, [1, 2, 3]);
    expect(cache.keys, [9]);
  });

  for (final operation in ['clear', 'resize']) {
    test('$operation delivers batch after errors and preserves first stack',
        () {
      final events = <int>[];
      final first = StateError('first');
      final originalStack = StackTrace.fromString('original listener stack');
      final cache = XlruCache<int, int>(
          maxSize: 4,
          onRemove: (k, v, c) {
            events.add(k);
            if (k == 1) Error.throwWithStackTrace(first, originalStack);
            if (k == 2) throw ArgumentError('second');
          });
      for (var i = 1; i <= 4; i++) {
        cache.set(i, i);
      }
      Object? caught;
      StackTrace? caughtStack;
      try {
        operation == 'clear' ? cache.clear() : cache.resize(1);
      } catch (error, stack) {
        caught = error;
        caughtStack = stack;
      }
      expect(caught, same(first));
      expect(caughtStack.toString(), contains('original listener stack'));
      expect(events, operation == 'clear' ? [1, 2, 3, 4] : [1, 2, 3]);
      expect(cache.length, operation == 'clear' ? 0 : 1);
    });
  }

  test('strict mode: replacement errors keep pins; new entries self-evict', () {
    final causes = <XlruRemovalCause>[];
    late XlruCache<int, int> cache;
    cache = XlruCache<int, int>(
        maxSize: 2,
        allowSelfEviction: true,
        onRemove: (k, v, c) {
          causes.add(c);
          expect(cache.length, 2);
          if (c == XlruRemovalCause.replaced) throw StateError('replaced');
        })
      ..set(1, 1)
      ..set(2, 2)
      ..pin(1)
      ..pin(2)
      ..resize(1);
    expect(() => cache.set(1, 10), throwsStateError);
    expect(cache.peek(1), 10);
    cache.set(3, 3);
    expect(causes, [XlruRemovalCause.replaced, XlruRemovalCause.evicted]);
  });

  test('custom equality, canonical keys, and ordered independent toMap', () {
    final keys = <String>[];
    final cache = XlruCache<String, int>(
      maxSize: 3,
      equals: (a, b) => a.toLowerCase() == b.toLowerCase(),
      hashCode: (key) => key.toLowerCase().hashCode,
      onRemove: (k, v, c) => keys.add(k),
    )
      ..set('One', 1)
      ..pin('ONE')
      ..set('Two', 2)
      ..set('ONE', 10);
    expect(cache.length, 2);
    expect(cache.isPinned('one'), isTrue);
    expect(cache.get('oNe'), 10);
    final copy = cache.toMap();
    expect(copy.keys, ['One', 'Two']);
    expect(copy['ONE'], 10);
    copy['three'] = 3;
    cache.remove('one');
    expect(copy['one'], 10);
    expect(cache.containsKey('three'), isFalse);
    expect(keys, ['One', 'One']);
  });

  for (final kind in ['keys', 'values', 'entries']) {
    for (final mutation in [
      'set',
      'replace',
      'get',
      'remove',
      'clear',
      'pin',
      'unpin',
      'resize'
    ]) {
      test('$kind detects $mutation after iterator creation', () {
        final cache = XlruCache<int, int>(maxSize: 3)
          ..set(1, 1)
          ..set(2, 2)
          ..pin(1);
        final Iterator<Object?> iterator = switch (kind) {
          'keys' => cache.keys.iterator,
          'values' => cache.values.iterator,
          _ => cache.entries.iterator,
        };
        expect(iterator.moveNext(), isTrue);
        switch (mutation) {
          case 'set':
            cache.set(3, 3);
          case 'replace':
            cache.set(2, 20);
          case 'get':
            cache.get(1);
          case 'remove':
            cache.remove(1);
          case 'clear':
            cache.clear();
          case 'pin':
            cache.pin(2);
          case 'unpin':
            cache.unpin(1);
          case 'resize':
            cache.resize(1);
        }
        expect(iterator.moveNext, throwsConcurrentModificationError);
      });
    }
  }

  test('iterator captures version before first move and after exhaustion', () {
    final cache = XlruCache<int, int>(maxSize: 2);
    final before = cache.keys.iterator;
    cache.set(1, 1);
    expect(before.moveNext, throwsConcurrentModificationError);
    final after = cache.keys.iterator;
    expect(after.moveNext(), isTrue);
    expect(after.moveNext(), isFalse);
    cache.set(2, 2);
    expect(after.moveNext, throwsConcurrentModificationError);
  });

  test('non-mutating operations keep iterators valid; iterable stays live', () {
    final cache = XlruCache<int, int>(maxSize: 2)..set(1, 1);
    final keys = cache.keys;
    final iterator = keys.iterator;
    cache.get(1);
    cache.set(1, 1);
    cache.peek(1);
    cache.toMap();
    cache.containsKey(1);
    cache.pin(9);
    cache.unpin(1);
    cache.remove(9);
    expect(iterator.moveNext(), isTrue);
    expect(iterator.current, 1);
    cache.set(2, 2);
    expect(keys, [2, 1]);
  });

  test('default: the written entry survives when older entries are pinned', () {
    final events = <(int, XlruRemovalCause)>[];
    final cache = XlruCache<int, int>(
        maxSize: 2, onRemove: (k, v, c) => events.add((k, c)))
      ..set(1, 1)
      ..set(2, 2)
      ..pin(1)
      ..pin(2);
    expect(cache.allowSelfEviction, isFalse);
    expect(cache.putIfAbsent(3, () => 3), 3);
    expect(cache.pin(3), isTrue); // Still resident, so it can be pinned.
    expect(cache.length, 3);
    expect(events, isEmpty);
    cache.set(4, 4); // Older entries are pinned and 4 is protected.
    expect(cache.keys, [4, 3, 2, 1]);
    cache.set(5, 5); // 4 lost its protection and is the oldest unpinned.
    expect(cache.keys, [5, 3, 2, 1]);
    expect(events, [(4, XlruRemovalCause.evicted)]);
    cache.unpin(1); // Converges: evicts 1, then 5.
    expect(cache.keys, [3, 2]);
    expect(events, [
      (4, XlruRemovalCause.evicted),
      (1, XlruRemovalCause.evicted),
      (5, XlruRemovalCause.evicted),
    ]);
  });

  test('without a listener, eviction, replacement, remove, clear still work',
      () {
    final cache = XlruCache<int, int>(maxSize: 2)
      ..set(1, 1)
      ..set(2, 2)
      ..set(1, 10)
      ..set(3, 3);
    expect(cache.keys, [3, 1]);
    expect(cache.remove(1), 10);
    cache
      ..set(4, 4)
      ..clear();
    expect(cache.isEmpty, isTrue);
  });

  for (final strict in [false, true]) {
    test('random operations match a reference model (strict: $strict)', () {
      final random = Random(974);
      final order = <int>[];
      final data = <int, int>{};
      final pins = <int, int>{};
      final actualEvents = <(int, int, XlruRemovalCause)>[];
      final expectedEvents = <(int, int, XlruRemovalCause)>[];
      var maxSize = 5;
      final cache = XlruCache<int, int>(
          maxSize: maxSize,
          allowSelfEviction: strict,
          onRemove: (k, v, c) => actualEvents.add((k, v, c)));
      void drop(int key, XlruRemovalCause cause) {
        expectedEvents.add((key, data.remove(key)!, cause));
        order.remove(key);
        pins.remove(key);
      }

      // [keep] is the key written by the current set; it is never eligible.
      void trim([int? keep]) {
        while (data.length > maxSize) {
          final eligible =
              order.reversed.where((k) => (pins[k] ?? 0) == 0 && k != keep);
          if (eligible.isEmpty) break;
          drop(eligible.first, XlruRemovalCause.evicted);
        }
      }

      for (var step = 0; step < 3000; step++) {
        final key = random.nextInt(12);
        switch (random.nextInt(8)) {
          case 0:
            final value = step;
            if (data.containsKey(key)) {
              expectedEvents.add((key, data[key]!, XlruRemovalCause.replaced));
            }
            data[key] = value;
            order.remove(key);
            order.insert(0, key);
            trim(strict ? null : key);
            cache.set(key, value);
          case 1:
            expect(cache.get(key), data[key]);
            if (data.containsKey(key)) {
              order.remove(key);
              order.insert(0, key);
            }
          case 2:
            expect(cache.pin(key), data.containsKey(key));
            if (data.containsKey(key)) pins[key] = (pins[key] ?? 0) + 1;
          case 3:
            final success = (pins[key] ?? 0) > 0;
            if (success) {
              pins[key] = pins[key]! - 1;
              trim();
            }
            expect(cache.unpin(key), success);
          case 4:
            expect(cache.remove(key), data[key]);
            if (data.containsKey(key)) drop(key, XlruRemovalCause.removed);
          case 5:
            maxSize = random.nextInt(6) + 1;
            trim();
            cache.resize(maxSize);
          case 6:
            expect(cache.peek(key), data[key]);
          case 7:
            for (final key in order.reversed.toList()) {
              drop(key, XlruRemovalCause.cleared);
            }
            cache.clear();
        }
        expect(cache.keys, order, reason: 'step $step');
        expect(cache.values, order.map((k) => data[k]), reason: 'step $step');
        expect(actualEvents, expectedEvents, reason: 'step $step');
      }
    });
  }

  // Large caches with sequential, colliding, constant, and strided hashes
  // exercise index growth, wraparound, and deletion shifting.
  final hashes = <String, int Function(int)?>{
    'default': null,
    'colliding': (k) => k % 13,
    'constant': (k) => 7,
    'strided': (k) => k * 1024,
  };
  for (final MapEntry(key: name, value: hash) in hashes.entries) {
    test('large random workload matches a reference model ($name hash)', () {
      final random = Random(name.length);
      final order = <int>[]; // Newest first.
      final data = <int, int>{};
      var maxSize = 150;
      final cache = XlruCache<int, int>(
          maxSize: maxSize,
          equals: hash == null ? null : (a, b) => a == b,
          hashCode: hash);
      void trim() {
        while (data.length > maxSize) {
          data.remove(order.removeLast());
        }
      }

      for (var step = 0; step < 8000; step++) {
        final key = random.nextInt(500) - 50;
        switch (random.nextInt(10)) {
          case 0 || 1 || 2 || 3:
            data[key] = step;
            order
              ..remove(key)
              ..insert(0, key);
            trim();
            cache.set(key, step);
          case 4 || 5:
            expect(cache.get(key), data[key]);
            if (data.containsKey(key)) {
              order
                ..remove(key)
                ..insert(0, key);
            }
          case 6:
            expect(cache.remove(key), data.remove(key));
            order.remove(key);
          case 7:
            expect(cache.containsKey(key), data.containsKey(key));
            expect(cache.peek(key), data[key]);
          case 8:
            if (random.nextInt(40) == 0) {
              maxSize = 1 + random.nextInt(400);
              trim();
              cache.resize(maxSize);
            }
          case 9:
            if (random.nextInt(300) == 0) {
              data.clear();
              order.clear();
              cache.clear();
            }
        }
        expect(cache.length, data.length, reason: 'step $step');
        if (step % 97 == 0) expect(cache.keys, order, reason: 'step $step');
      }
      expect(cache.keys, order);
      expect(cache.values, order.map((k) => data[k]));
    });
  }
  group('usePinned', () {
    test('returns null and skips the action for a missing key', () {
      final cache = XlruCache<int, int>(maxSize: 2);
      var called = false;
      expect(cache.usePinned(1, (v) => called = true), isNull);
      expect(called, isFalse);
    });

    test('pins during the action and unpins after', () {
      final removed = <int>[];
      final cache =
          XlruCache<int, int>(maxSize: 1, onRemove: (k, v, c) => removed.add(k))
            ..set(1, 10);
      final result = cache.usePinned(1, (v) {
        expect(cache.isPinned(1), isTrue);
        cache.set(2, 20); // Cannot evict 1 while pinned.
        expect(cache.containsKey(1), isTrue);
        return v + 1;
      });
      expect(result, 11);
      expect(cache.isPinned(1), isFalse);
      expect(cache.keys, [2]); // Unpin converged on capacity.
      expect(removed, [1]);
    });

    test('unpins when the action throws', () {
      final cache = XlruCache<int, int>(maxSize: 2)..set(1, 1);
      expect(() => cache.usePinned(1, (v) => throw StateError('x')),
          throwsStateError);
      expect(cache.isPinned(1), isFalse);
    });
  });

  test('removal causes are exhaustively switchable, including lost', () {
    String name(XlruRemovalCause cause) => switch (cause) {
          XlruRemovalCause.evicted => 'e',
          XlruRemovalCause.replaced => 'p',
          XlruRemovalCause.removed => 'r',
          XlruRemovalCause.cleared => 'c',
          XlruRemovalCause.lost => 'l',
        };
    expect(XlruRemovalCause.values.map(name).join(), 'eprcl');
  });
}
