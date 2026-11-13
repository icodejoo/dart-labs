import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mova/mova.dart';
import '../support/fake_kernel.dart';

/// 不触网的 HTTP 端口，记录预览是否实际拉取资源。
class _Fetch implements IMovaHttpFetch {
  int gets = 0;
  @override
  Future<Uint8List?> get(Uri url) async { gets++; return null; }
  @override
  Future<void> close() async {}
}

class _MemorySource implements IMovaThumbSource {
  int requests = 0;
  @override
  String get name => 'memory';
  @override
  Future<MovaThumb?> thumbAt(MovaSource source, Duration bucket) async {
    requests++;
    return MovaThumb(at: bucket, bytes: Uint8List(1));
  }
  @override
  Future<void> reset() async {}
  @override
  Future<void> dispose() async {}
}
class _DenyProbe extends MovaAlwaysAllowNetProbe {
  int queries = 0;
  @override
  Future<bool> allowHeavy() async { queries++; return false; }
}

Future<void> _request(Mova mova, String uri) async {
  await mova.open(MovaSource(uri));
  mova.preview.requestAt(const Duration(seconds: 12));
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
  Mova make(_Fetch fetch, [MovaPreviewOpts opts = const MovaPreviewOpts(debounce: Duration.zero)]) {
    final mova = createMova(kernel: FakeKernel(), fetcher: fetch,
      thumbDir: null,
      options: MovaOpts(preview: opts.copyWith(cache: MovaMemoryThumbCache()),
        controls: const MovaCtrlsOpts(autoHide: false), abr: const MovaAbrOpts(probeVariants: false)));
    addTearDown(mova.dispose);
    return mova;
  }
  test('C12 opaque memory sources skip default connectivity but honor an explicit probe', () async {
    final memory = _MemorySource();
    final fetch = _Fetch();
    final mova = make(fetch, MovaPreviewOpts(sources: [memory], debounce: Duration.zero));
    await _request(mova, 'https://host/a.mp4');
    expect(queries, 0, reason: 'a remote media URL does not mean this source fetches remote thumbnails');
    expect(memory.requests, 1);
    expect(mova.preview.current, isNotNull);
    expect(fetch.gets, 0);
    final guarded = _MemorySource();
    final probe = _DenyProbe();
    await _request(make(fetch, MovaPreviewOpts(sources: [guarded], probe: probe, debounce: Duration.zero)), 'https://host/b.mp4');
    expect(probe.queries, 1);
    expect(guarded.requests, 0);
    expect(queries, 0);
  });
  test('C12 default wifiOnly consults connectivity lazily and blocks mobile', () async {
    final fetch = _Fetch();
    final mova = make(fetch);
    expect(queries, 0);
    await _request(mova, 'https://host/a.mp4');
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
    final unused = Mova(kernel: FakeKernel(), fetcher: _Fetch(),
      previewProbeFactory: () { created++; return MovaAlwaysAllowNetProbe(); });
    await unused.dispose();
    expect(created, 0, reason: 'disposing an unused player must not create a probe');
    final fetch = _Fetch();
    for (final opts in [
      const MovaPreviewOpts(enabled: false, debounce: Duration.zero),
      const MovaPreviewOpts(sources: [], debounce: Duration.zero),
      const MovaPreviewOpts(network: MovaPreviewNet.always, debounce: Duration.zero),
      const MovaPreviewOpts(network: MovaPreviewNet.never, debounce: Duration.zero),
      MovaPreviewOpts(vttUrlResolver: (_) => null, debounce: Duration.zero),
    ]) { await _request(make(fetch, opts), 'https://host/a.mp4'); }
    await _request(make(fetch), 'file:///host/a.mp4');
    expect(queries, 0);
    connection = 'wifi';
    final cache = MovaMemoryThumbCache();
    final mova = createMova(kernel: FakeKernel(), fetcher: fetch,
      options: MovaOpts(preview: MovaPreviewOpts(cache: cache, debounce: Duration.zero),
        controls: const MovaCtrlsOpts(autoHide: false), abr: const MovaAbrOpts(probeVariants: false)));
    addTearDown(mova.dispose);
    await mova.open(const MovaSource('https://host/b.mp4'));
    mova.preview.requestAt(const Duration(seconds: 12));
    for (var i = 0; i < 10; i++) { await Future<void>.delayed(Duration.zero); }
    expect(queries, 1);
    mova.preview.requestAt(const Duration(seconds: 14));
    for (var i = 0; i < 10; i++) { await Future<void>.delayed(Duration.zero); }
    expect(queries, 1, reason: 'VTT failure cooldown does not fetch again');
    await cache.write(defaultCacheKey('https://host/b.mp4', 16, 160), Uint8List(1));
    mova.preview.requestAt(const Duration(seconds: 16));
    for (var i = 0; i < 10; i++) { await Future<void>.delayed(Duration.zero); }
    expect(queries, 1);
  });
}
