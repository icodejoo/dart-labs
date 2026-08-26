// Lifetime/bookkeeping tests for `RustSvgPictureCache`, added with the memory
// round: the async render path used to start a fresh parse + decode + record
// for every caller that arrived while one was already running, and each of
// those extra runs produced a `ui.Picture` (plus, for `<image>` sources, a
// decoded `ui.Image`) that was overwritten in the cache and left for the GC.
//
// Best-effort: skips itself if the native library isn't loadable under plain
// `flutter test` (host VM, no Flutter build step), same convention as
// `rust_image_smoke_test.dart`.
//
// `RustSvgPictureCache` 的生命周期/记账测试，随内存专项一起加入：异步渲染路径
// 过去对每一个在渲染进行中到达的调用方都会重开一趟解析 + 解码 + 录制，而每一趟
// 多出来的运行都会产生一个 `ui.Picture`（含 `<image>` 的源还多一个解码出的
// `ui.Image`），随后在缓存里被覆盖、丢给 GC。
//
// 尽力而为：若在纯 `flutter test`（host VM，未走 Flutter 构建）下原生库无法加载
// 则自行跳过，约定同 `rust_image_smoke_test.dart`。

import 'package:flutter_test/flutter_test.dart';
import 'package:svgx/svgx.dart';

const _svg = '''
<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24">
  <path d="M4 4 L20 4 L20 20 Z" fill="#123456"/>
</svg>
''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  var rustAvailable = true;

  setUpAll(() async {
    try {
      await RustLib.init();
    } catch (_) {
      rustAvailable = false;
    }
  });

  setUp(RustSvgPictureCache.instance.clear);
  tearDown(() {
    RustSvgPictureCache.instance
      ..onParseMiss = null
      ..clear();
  });

  test('concurrent getOrRenderAsync for one key renders exactly once', () async {
    if (!rustAvailable) return;
    final cache = RustSvgPictureCache.instance;
    var misses = 0;
    cache.onParseMiss = (_) => misses++;

    // Both calls happen before either can complete — the shape a rebuilding
    // FutureBuilder produces.
    final first = cache.getOrRenderAsync(_svg);
    final second = cache.getOrRenderAsync(_svg);
    final results = await Future.wait([first, second]);

    expect(misses, 1, reason: 'the second caller must join the first render');
    expect(identical(results[0], results[1]), isTrue);
    expect(identical(results[0].picture, results[1].picture), isTrue);
    expect(cache.length, 1);
  });

  test('a settled async render leaves no in-flight bookkeeping behind', () async {
    if (!rustAvailable) return;
    final cache = RustSvgPictureCache.instance;
    var misses = 0;
    cache.onParseMiss = (_) => misses++;

    await cache.getOrRenderAsync(_svg);
    cache.clear();
    // A second render after the first settled must actually run again: if the
    // finished future were still registered as in-flight, this would silently
    // hand back the stale entry.
    await cache.getOrRenderAsync(_svg);

    expect(misses, 2);
    expect(cache.length, 1);
  });

  test('length and approximateBytesUsed track the cached entries', () async {
    if (!rustAvailable) return;
    final cache = RustSvgPictureCache.instance;
    expect(cache.length, 0);
    expect(cache.approximateBytesUsed, 0);

    cache.getOrRender(_svg);
    expect(cache.length, 1);
    expect(cache.approximateBytesUsed, greaterThan(0));

    cache.clear();
    expect(cache.length, 0);
    expect(cache.approximateBytesUsed, 0);
  });

  test('the LRU evicts down to maximumSize', () async {
    if (!rustAvailable) return;
    final cache = RustSvgPictureCache.instance;
    final previousMax = cache.maximumSize;
    cache.maximumSize = 2;
    try {
      for (var i = 0; i < 5; i++) {
        cache.getOrRender(_svg.replaceFirst('#123456', '#12345$i'));
      }
      expect(cache.length, 2);
    } finally {
      cache.maximumSize = previousMax;
    }
  });
}
