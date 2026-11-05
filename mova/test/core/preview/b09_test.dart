import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:mova/src/core/preview/cache.dart';
import 'package:mova/src/core/preview/disk_cache.dart';
import 'package:mova/src/core/preview/dir_provider.dart';
import 'package:mova/src/platform_impl/thumb_dir_impl.dart';

/// 为独占目录测试提供工作区内的根路径。
class _Paths extends PathProviderPlatform {
  /// 创建路径替身，[path] 是临时目录。
  _Paths(this.path);

  /// 测试根目录。
  final String path;
  @override
  Future<String?> getTemporaryPath() async => path;
}

/// B09 字节预算、异步索引与目录隔离回归。
void main() {
  test('字节预算按 LRU 淘汰且 peek 刷新顺序', () async {
    final c = MovaMemoryThumbCache(maxBytes: 6);
    await c.write('a', Uint8List(3));
    await c.write('b', Uint8List(3));
    c.peek('a');
    await c.write('c', Uint8List(3));
    expect(c.peek('b'), isNull);
    expect(c.peek('a'), isNotNull);
    expect(c.totalBytes, 6);
  });
  test('覆盖同键按字节差额结算，超大值不驻留', () async {
    final c = MovaMemoryThumbCache(maxBytes: 6);
    await c.write('a', Uint8List(3));
    await c.write('a', Uint8List(5));
    expect(c.totalBytes, 5);
    await c.write('a', Uint8List(7));
    expect(c.totalBytes, 0);
    expect(c.peek('a'), isNull);
  });
  test('零字节预算禁用缓存', () async {
    final c = MovaMemoryThumbCache(maxBytes: 0);
    await c.write('a', Uint8List(1));
    expect(c.length, 0);
  });
  test('clear 同时清零字节和条目数', () async {
    final c = MovaMemoryThumbCache(maxBytes: 6);
    await c.write('a', Uint8List(3));
    await c.clear();
    expect(c.totalBytes, 0);
    expect(c.length, 0);
  });

  late Directory root;
  setUp(() async {
    root = await Directory('.dart_tool/b09').createTemp('cache_');
  });
  tearDown(() async => root.delete(recursive: true));

  test('磁盘只首次扫描，后续写入增量维护索引', () async {
    final c = MovaDiskThumbCache(dir: MovaFixedThumbDirProvider(root.path));
    await c.write('a', Uint8List(3));
    await File('${root.path}/external.thumb').writeAsBytes(Uint8List(9));
    await c.write('b', Uint8List(4));
    expect(await c.totalBytes(), 7);
    final reopened = MovaDiskThumbCache(
      dir: MovaFixedThumbDirProvider(root.path),
    );
    expect(await reopened.totalBytes(), 16);
  });
  test('并发磁盘写入后预算有界且覆盖大小正确', () async {
    final c = MovaDiskThumbCache(
      dir: MovaFixedThumbDirProvider(root.path),
      maxBytes: 10,
    );
    await Future.wait(List.generate(12, (i) => c.write('$i', Uint8List(4))));
    expect(await c.totalBytes(), 8);
    await c.write('11', Uint8List(2));
    expect(await c.totalBytes(), 6);
    await c.clear();
    expect(await c.totalBytes(), 0);
  });
  test('默认目录每实例独占，回收一个缓存不清理另一个', () async {
    final old = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Paths(root.absolute.path);
    addTearDown(() => PathProviderPlatform.instance = old);
    final first = MovaTempThumbDirProvider();
    final second = MovaTempThumbDirProvider();
    final paths = await Future.wait([
      first.resolve(),
      first.resolve(),
      second.resolve(),
    ]);
    expect(paths[0], paths[1]);
    expect(paths[0], isNot(paths[2]));
    final a = MovaDiskThumbCache(dir: first);
    final b = MovaDiskThumbCache(dir: second);
    await a.write('a', Uint8List(2));
    await b.write('b', Uint8List(3));
    await a.clear();
    await a.dispose();
    expect(await b.read('b'), hasLength(3));
  });
}
