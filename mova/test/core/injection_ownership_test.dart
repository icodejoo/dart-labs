import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:mova/mova.dart';
import 'package:mova/testing.dart';
import 'package:mova/src/testing/hooks.dart';
import '../support/fake_kernel.dart';

class _Policy extends MovaBufferAbr {
  int resets = 0;
  @override
  void reset() { resets++; super.reset(); }
}
class _Cache extends MovaMemoryThumbCache {
  int disposals = 0;
  @override
  Future<void> dispose() async { disposals++; await super.dispose(); }
}
class _Probe extends MovaAlwaysAllowNetProbe {
  int disposals = 0;
  @override
  Future<void> dispose() async { disposals++; }
}
class _Source implements MovaThumbSource {
  int disposals = 0;
  @override
  String get name => 'host';
  @override
  Future<MovaThumb?> thumbAt(MovaSource source, Duration bucket) async => null;
  @override
  Future<void> reset() async {}
  @override
  Future<void> dispose() async { disposals++; }
}
class _Puller implements MovaFramePuller {
  int disposals = 0;
  @override
  Future<Uint8List?> extract(String uri, Duration at, {required int width, required bool hwdec}) async => null;
  @override
  Future<void> release() async {}
  @override
  Future<void> dispose() async { disposals++; }
}
class _Stt extends MovaNoopSttEngine {
  int starts = 0;
  int disposals = 0;
  @override
  Future<void> start(Duration atPosition) async { if (++starts == 1) throw StateError('recognizer'); }
  @override
  Future<void> dispose() async { disposals++; }
}
MovaEngine _engine({MovaPreviewConfig preview = const MovaPreviewConfig(), MovaAbrConfig abr = const MovaAbrConfig()}) =>
    MovaEngine(kernel: FakeKernel(), fetcher: const MovaTestHttpFetch(), options: MovaOpts(
      controls: const MovaCtrlsConfig(autoHide: false), preview: preview, abr: abr));

void main() {
  test('C13 policy factory creates one independent policy per engine and wins over legacy instance', () async {
    final policies = <_Policy>[];
    final legacy = _Policy();
    final abr = MovaAbrConfig(policy: legacy, policyFactory: () { final p = _Policy(); policies.add(p); return p; });
    final a = _engine(abr: abr), b = _engine(abr: abr);
    expect(policies, hasLength(2));
    await a.open(const MovaSource('file:///a.mp4'));
    expect(policies.first.resets, greaterThan(0));
    expect(policies.last.resets, 0);
    expect(legacy.resets, 0);
    expect(abr, isNot(MovaAbrConfig(policy: legacy)));
    await a.dispose(); await b.dispose();
  });
  test('C13 borrowed cache is neither cleared nor disposed', () async {
    final cache = _Cache();
    await cache.write('host', Uint8List.fromList([7]));
    final engine = _engine(preview: MovaPreviewConfig(cache: cache, clearOnDispose: true));
    await engine.dispose();
    expect(cache.disposals, 0);
    expect(cache.peek('host'), [7]);
    await cache.dispose();
  });
  test('C13 injected probe survives while lazy engine-created probe is disposed once', () async {
    final host = _Probe(), own = _Probe();
    final a = _engine(preview: MovaPreviewConfig(probe: host));
    final b = MovaEngine(kernel: FakeKernel(), fetcher: const MovaTestHttpFetch(), previewProbeFactory: () => own);
    await (b.preview as MovaPreviewService).probe.allowHeavy();
    await a.dispose(); await b.dispose(); await b.dispose();
    expect(host.disposals, 0);
    expect(own.disposals, 1);
    await host.dispose();
  });
  test('C13 injected source and extractor survive engine disposal', () async {
    final source = _Source(), puller = _Puller();
    final a = _engine(preview: MovaPreviewConfig(sources: [source]));
    final b = _engine(preview: MovaPreviewConfig(extractor: puller, extractPlatforms: MovaPlatformKind.values.toSet()));
    await a.dispose(); await b.dispose();
    expect(source.disposals, 0); expect(puller.disposals, 0);
    await source.dispose(); await puller.dispose();
  });
  test('C13 kernel borrowing ownership transfer and factory creation are explicit', () async {
    final host = FakeKernel(), transferred = FakeKernel();
    await MovaEngine(kernel: host).dispose();
    expect(host.isDisposed, isFalse);
    await MovaEngine(kernel: transferred, ownsKernel: true).dispose();
    expect(transferred.isDisposed, isTrue);
    MovaTesting.useTestKernels();
    try {
      final engine = createMovaEngine();
      final kernel = MovaTesting.lastKernel!;
      await engine.dispose();
      expect(kernel.calls.where((c) => c == 'dispose'), hasLength(1));
    } finally { MovaTesting.reset(); }
    await host.dispose();
  });
  test('C13 STT failures roll back and retry without disposing host recognizer', () async {
    final host = _Stt();
    final service = MovaSttService(config: MovaSttConfig(enabled: true, engine: host))..attach(const MovaSource('file:///a'));
    await service.start(); expect(service.isRunning, isFalse);
    await service.start(); expect(service.isRunning, isTrue);
    await service.dispose(); await service.dispose();
    expect(host.disposals, 0); expect(service.isRunning, isFalse);
    await host.dispose();
  });
}
