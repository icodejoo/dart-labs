import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:videoman/src/core/preview/cache.dart';

/// Builds [n] filler bytes so tests can tell payloads apart by length.
///
/// 造 [n] 个填充字节，让测试可以按长度区分不同负载。
Uint8List _bytes(int n) => Uint8List.fromList(List<int>.filled(n, n & 0xFF));

void main() {
  test('peek and read miss on an unknown key', () async {
    final c = VmMemoryThumbCache();
    expect(c.peek('nope'), isNull);
    expect(await c.read('nope'), isNull);
    await c.dispose();
  });

  test('write makes the entry available synchronously via peek', () async {
    final c = VmMemoryThumbCache();
    await c.write('k', _bytes(3));
    expect(c.peek('k'), _bytes(3));
    expect(await c.read('k'), _bytes(3));
    expect(c.length, 1);
    await c.dispose();
  });

  test('writing the same key twice replaces rather than duplicates', () async {
    final c = VmMemoryThumbCache();
    await c.write('k', _bytes(3));
    await c.write('k', _bytes(5));
    expect(c.length, 1);
    expect(c.peek('k'), _bytes(5));
    await c.dispose();
  });

  test('count LRU evicts the least recently used entry past maxEntries', () async {
    final c = VmMemoryThumbCache(maxEntries: 2);
    await c.write('a', _bytes(1));
    await c.write('b', _bytes(2));
    await c.write('c', _bytes(3));
    expect(c.length, 2);
    expect(c.peek('a'), isNull);
    expect(c.peek('b'), _bytes(2));
    expect(c.peek('c'), _bytes(3));
    await c.dispose();
  });

  test('peek refreshes recency so the touched entry survives eviction', () async {
    final c = VmMemoryThumbCache(maxEntries: 2);
    await c.write('a', _bytes(1));
    await c.write('b', _bytes(2));
    c.peek('a');
    await c.write('c', _bytes(3));
    expect(c.peek('a'), _bytes(1));
    expect(c.peek('b'), isNull);
    await c.dispose();
  });

  test('read refreshes recency the same way peek does', () async {
    final c = VmMemoryThumbCache(maxEntries: 2);
    await c.write('a', _bytes(1));
    await c.write('b', _bytes(2));
    await c.read('a');
    await c.write('c', _bytes(3));
    expect(c.peek('a'), _bytes(1));
    expect(c.peek('b'), isNull);
    await c.dispose();
  });

  test('maxEntries of zero disables caching entirely', () async {
    final c = VmMemoryThumbCache(maxEntries: 0);
    await c.write('a', _bytes(1));
    expect(c.length, 0);
    expect(c.peek('a'), isNull);
    await c.dispose();
  });

  test('clear empties the cache', () async {
    final c = VmMemoryThumbCache();
    await c.write('a', _bytes(1));
    await c.write('b', _bytes(2));
    await c.clear();
    expect(c.length, 0);
    expect(c.peek('a'), isNull);
    await c.dispose();
  });
}
