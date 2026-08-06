import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mova/src/core/preview/dir_provider.dart';
import 'package:mova/src/core/preview/disk_cache.dart';

/// Builds [n] filler bytes so tests can tell payloads apart by length.
///
/// 造 [n] 个填充字节，让测试可以按长度区分不同负载。
Uint8List _bytes(int n) => Uint8List.fromList(List<int>.filled(n, n & 0xFF));

void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('vm_thumbs_test'));
  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  /// Builds a disk cache rooted at the per-test temp directory.
  ///
  /// 构造一个以本用例临时目录为根的磁盘缓存。
  MovaDiskThumbCache cache({int maxBytes = 1 << 20}) => MovaDiskThumbCache(
        dir: FixedThumbDirProvider(tmp.path),
        maxBytes: maxBytes,
      );

  test('write then read round-trips the bytes', () async {
    final c = cache();
    await c.write('k', _bytes(64));
    expect(await c.read('k'), _bytes(64));
    await c.dispose();
  });

  test('read misses return null and never throw', () async {
    final c = cache();
    expect(await c.read('missing'), isNull);
    await c.dispose();
  });

  test('peek is always null because disk reads cannot be synchronous', () async {
    final c = cache();
    await c.write('k', _bytes(8));
    expect(c.peek('k'), isNull);
    await c.dispose();
  });

  test('totalBytes reports the sum of stored entries', () async {
    final c = cache();
    await c.write('a', _bytes(100));
    await c.write('b', _bytes(50));
    expect(await c.totalBytes(), 150);
    await c.dispose();
  });

  test('evict deletes oldest-touched files until the byte budget is met', () async {
    final big = cache();
    await big.write('a', _bytes(100));
    await big.write('b', _bytes(100));
    await big.write('c', _bytes(100));
    await big.dispose();

    final now = DateTime.now();
    File('${tmp.path}/a.thumb').setLastModifiedSync(now.subtract(const Duration(hours: 3)));
    File('${tmp.path}/b.thumb').setLastModifiedSync(now.subtract(const Duration(hours: 2)));
    File('${tmp.path}/c.thumb').setLastModifiedSync(now.subtract(const Duration(hours: 1)));

    final small = cache(maxBytes: 250);
    await small.evict();
    expect(await small.read('a'), isNull);
    expect(await small.read('b'), _bytes(100));
    expect(await small.read('c'), _bytes(100));
    await small.dispose();
  });

  test('read touches the file so a re-read entry survives the next eviction', () async {
    final big = cache();
    await big.write('a', _bytes(100));
    await big.write('b', _bytes(100));
    await big.write('c', _bytes(100));
    await big.dispose();

    final now = DateTime.now();
    File('${tmp.path}/a.thumb').setLastModifiedSync(now.subtract(const Duration(hours: 3)));
    File('${tmp.path}/b.thumb').setLastModifiedSync(now.subtract(const Duration(hours: 2)));
    File('${tmp.path}/c.thumb').setLastModifiedSync(now.subtract(const Duration(hours: 1)));

    final small = cache(maxBytes: 250);
    await small.read('a');
    await small.evict();
    expect(await small.read('a'), _bytes(100));
    expect(await small.read('b'), isNull);
    await small.dispose();
  });

  test('write evicts inline so the budget is never exceeded after a write', () async {
    final c = cache(maxBytes: 150);
    await c.write('a', _bytes(100));
    await c.write('b', _bytes(100));
    expect(await c.totalBytes(), lessThanOrEqualTo(150));
    await c.dispose();
  });

  test('clear removes every stored entry but keeps the directory usable', () async {
    final c = cache();
    await c.write('a', _bytes(10));
    await c.clear();
    expect(await c.totalBytes(), 0);
    await c.write('b', _bytes(10));
    expect(await c.read('b'), _bytes(10));
    await c.dispose();
  });

  test('an unusable directory degrades to a silent no-op cache', () async {
    final blocker = File('${tmp.path}/blocker')..writeAsStringSync('x');
    final c = MovaDiskThumbCache(
      dir: FixedThumbDirProvider('${blocker.path}/nested'),
      maxBytes: 1 << 20,
    );
    await c.write('k', _bytes(4));
    expect(await c.read('k'), isNull);
    expect(await c.totalBytes(), 0);
    await c.clear();
    await c.dispose();
  });
}
