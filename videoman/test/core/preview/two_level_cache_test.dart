import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:videoman/src/core/preview/cache.dart';
import 'package:videoman/src/core/preview/two_level_cache.dart';

/// Builds [n] filler bytes so tests can tell payloads apart by length.
///
/// 造 [n] 个填充字节，让测试可以按长度区分不同负载。
Uint8List _bytes(int n) => Uint8List.fromList(List<int>.filled(n, n & 0xFF));

/// A recording [VmThumbCache] standing in for the slow (disk) level.
///
/// 记录调用的 [VmThumbCache]，用于替身"慢速（磁盘）"层。
class _RecordingCache implements VmThumbCache {
  /// Stored entries.
  ///
  /// 已存储的条目。
  final Map<String, Uint8List> store = <String, Uint8List>{};

  /// Ordered method names invoked on this fake.
  ///
  /// 在该替身上被调用的方法名有序列表。
  final List<String> calls = <String>[];

  @override
  Uint8List? peek(String key) {
    calls.add('peek:$key');
    return null;
  }

  @override
  Future<Uint8List?> read(String key) async {
    calls.add('read:$key');
    return store[key];
  }

  @override
  Future<void> write(String key, Uint8List bytes) async {
    calls.add('write:$key');
    store[key] = bytes;
  }

  @override
  Future<void> clear() async {
    calls.add('clear');
    store.clear();
  }

  @override
  Future<void> dispose() async => calls.add('dispose');
}

void main() {
  late VmMemoryThumbCache memory;
  late _RecordingCache disk;
  late VmTwoLevelCache cache;

  setUp(() {
    memory = VmMemoryThumbCache(maxEntries: 2);
    disk = _RecordingCache();
    cache = VmTwoLevelCache(memory: memory, disk: disk);
  });

  test('write goes into both levels', () async {
    await cache.write('k', _bytes(4));
    expect(memory.peek('k'), _bytes(4));
    expect(disk.store['k'], _bytes(4));
  });

  test('peek answers from memory without touching disk', () async {
    await cache.write('k', _bytes(4));
    disk.calls.clear();
    expect(cache.peek('k'), _bytes(4));
    expect(disk.calls, isEmpty);
  });

  test('peek misses when only disk holds the entry', () async {
    await disk.write('k', _bytes(4));
    disk.calls.clear();
    expect(cache.peek('k'), isNull);
    expect(disk.calls, isEmpty);
  });

  test('read falls through to disk and back-fills memory', () async {
    await disk.write('k', _bytes(4));
    expect(await cache.read('k'), _bytes(4));
    expect(memory.peek('k'), _bytes(4));
  });

  test('read does not hit disk again once memory holds the entry', () async {
    await disk.write('k', _bytes(4));
    await cache.read('k');
    disk.calls.clear();
    expect(await cache.read('k'), _bytes(4));
    expect(disk.calls, isEmpty);
  });

  test('read returns null when neither level has the key', () async {
    expect(await cache.read('nope'), isNull);
    expect(disk.calls, contains('read:nope'));
  });

  test('clear and dispose cascade to both levels', () async {
    await cache.write('k', _bytes(4));
    await cache.clear();
    expect(memory.peek('k'), isNull);
    expect(disk.store, isEmpty);
    await cache.dispose();
    expect(disk.calls, contains('dispose'));
  });
}
