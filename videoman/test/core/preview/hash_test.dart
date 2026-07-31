import 'package:flutter_test/flutter_test.dart';
import 'package:videoman/src/core/preview/hash.dart';

void main() {
  test('fnv1a64 matches the reference vectors for the empty and short inputs', () {
    // Reference FNV-1a 64 vectors, masked to a non-negative Dart int.
    //
    // FNV-1a 64 的参考向量，掩码为非负 Dart int。
    expect(fnv1a64(''), 0xcbf29ce484222325 & 0x7FFFFFFFFFFFFFFF);
    expect(fnv1a64('a'), 0xaf63dc4c8601ec8c & 0x7FFFFFFFFFFFFFFF);
    expect(fnv1a64('foobar'), 0x85944171f73967e8 & 0x7FFFFFFFFFFFFFFF);
  });

  test('fnv1a64 is always non-negative', () {
    for (final s in ['', 'a', 'foobar', 'https://host/very/long/path.m3u8', '中文']) {
      expect(fnv1a64(s), greaterThanOrEqualTo(0), reason: s);
    }
  });

  test('defaultCacheKey is stable and filename-safe', () {
    final k = defaultCacheKey('https://host/a.mp4', 30, 160);
    expect(k, defaultCacheKey('https://host/a.mp4', 30, 160));
    expect(RegExp(r'^[0-9a-z_]+$').hasMatch(k), isTrue, reason: k);
  });

  test('defaultCacheKey separates buckets, widths and sources', () {
    expect(defaultCacheKey('a', 30, 160), isNot(defaultCacheKey('a', 40, 160)));
    expect(defaultCacheKey('a', 30, 160), isNot(defaultCacheKey('a', 30, 320)));
    expect(defaultCacheKey('a', 30, 160), isNot(defaultCacheKey('b', 30, 160)));
  });

  test('defaultCacheKey keeps bucket and width in clear text for debuggability', () {
    expect(defaultCacheKey('https://host/a.mp4', 30, 160), endsWith('_30_160'));
  });
}
