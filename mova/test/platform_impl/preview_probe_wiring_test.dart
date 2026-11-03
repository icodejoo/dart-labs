import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mova/mova.dart';
import '../support/fake_kernel.dart';

/// 不触网的 HTTP 端口，记录预览是否实际拉取资源。
class _Fetch implements MovaHttpFetch {
  int gets = 0;
  @override
  Future<Uint8List?> get(Uri url) async { gets++; return null; }
  @override
  Future<void> close() async {}
}

Future<void> _request(MovaEngine engine, String uri) async {
  await engine.open(MovaSource(uri));
  engine.preview.requestAt(const Duration(seconds: 12));
  for (var i = 0; i < 10; i++) { await Future<void>.delayed(Duration.zero); }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dev.fluttercommunity.plus/connectivity');
  var queries = 0;
  var connection = 'mobile';
  setUp(() {
    queries = 0;
    connection = 'mobile';
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (_) async {
      queries++;
      return [connection];
    });
  });
  tearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));
  MovaEngine make(_Fetch fetch, [MovaPreviewConfig config = const MovaPreviewConfig(debounce: Duration.zero)]) {
    final engine = createMovaEngine(kernel: FakeKernel(), fetcher: fetch,
      thumbDir: null,
      options: MovaOpts(preview: config.copyWith(cache: MovaMemoryThumbCache()),
        controls: const MovaCtrlsConfig(autoHide: false), abr: const MovaAbrConfig(probeVariants: false)));
    addTearDown(engine.dispose);
    return engine;
  }
  test('C12 default wifiOnly consults connectivity lazily and blocks mobile', () async {
    final fetch = _Fetch();
    final engine = make(fetch);
    expect(queries, 0);
    await _request(engine, 'https://host/a.mp4');
    expect(queries, 1);
    expect(fetch.gets, 0);
  });
  test('C12 default wifiOnly allows remote preview on wifi', () async {
    connection = 'wifi';
    final fetch = _Fetch();
    await _request(make(fetch), 'https://host/a.mp4');
    expect(queries, 1);
    expect(fetch.gets, 1);
  });
  test('C12 no-work policies local URLs cooldown and cache avoid probe queries', () async {
    var created = 0;
    final unused = MovaEngine(kernel: FakeKernel(), fetcher: _Fetch(),
      previewProbeFactory: () { created++; return MovaAlwaysAllowNetProbe(); });
    await unused.dispose();
    expect(created, 0, reason: 'disposing an unused engine must not create a probe');
    final fetch = _Fetch();
    for (final config in [
      const MovaPreviewConfig(enabled: false, debounce: Duration.zero),
      const MovaPreviewConfig(sources: [], debounce: Duration.zero),
      const MovaPreviewConfig(network: MovaPreviewNet.always, debounce: Duration.zero),
      const MovaPreviewConfig(network: MovaPreviewNet.never, debounce: Duration.zero),
      MovaPreviewConfig(vttUrlResolver: (_) => null, debounce: Duration.zero),
    ]) { await _request(make(fetch, config), 'https://host/a.mp4'); }
    await _request(make(fetch), 'file:///host/a.mp4');
    expect(queries, 0);
    connection = 'wifi';
    final cache = MovaMemoryThumbCache();
    final engine = createMovaEngine(kernel: FakeKernel(), fetcher: fetch,
      options: MovaOpts(preview: MovaPreviewConfig(cache: cache, debounce: Duration.zero),
        controls: const MovaCtrlsConfig(autoHide: false), abr: const MovaAbrConfig(probeVariants: false)));
    addTearDown(engine.dispose);
    await engine.open(const MovaSource('https://host/b.mp4'));
    engine.preview.requestAt(const Duration(seconds: 12));
    for (var i = 0; i < 10; i++) { await Future<void>.delayed(Duration.zero); }
    expect(queries, 1);
    engine.preview.requestAt(const Duration(seconds: 14));
    for (var i = 0; i < 10; i++) { await Future<void>.delayed(Duration.zero); }
    expect(queries, 1, reason: 'VTT failure cooldown does not fetch again');
    await cache.write(defaultCacheKey('https://host/b.mp4', 16, 160), Uint8List(1));
    engine.preview.requestAt(const Duration(seconds: 16));
    for (var i = 0; i < 10; i++) { await Future<void>.delayed(Duration.zero); }
    expect(queries, 1);
  });
}
