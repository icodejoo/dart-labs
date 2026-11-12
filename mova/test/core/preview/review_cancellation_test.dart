import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mova/mova.dart';
import 'package:mova/src/core/preview/request_context.dart';

import '../../support/fake_kernel.dart';

class _Probe extends MovaAlwaysAllowNetProbe {
  final started = Completer<void>();
  final gate = Completer<bool>();
  @override
  Future<bool> allowHeavy() async {
    if (started.isCompleted) return true;
    started.complete();
    return gate.future;
  }
}

class _Fetch implements MovaHttpFetch {
  final urls = <Uri>[];
  @override
  Future<Uint8List?> get(Uri url) async {
    urls.add(url);
    return url.path.endsWith('.vtt')
        ? Uint8List.fromList(utf8.encode('WEBVTT\n\n00:00.000 --> 01:00.000\nhttps://host/sprite.jpg#xywh=0,0,10,10\n'))
        : Uint8List.fromList([1]);
  }
  @override
  Future<void> close() async {}
}

class _Puller implements MovaFramePuller {
  final uris = <String>[];
  @override
  Future<Uint8List?> extract(String uri, Duration at, {required int width, required bool hwdec}) async {
    uris.add(uri);
    return Uint8List.fromList([1]);
  }
  @override
  Future<void> release() async {}
  @override
  Future<void> dispose() async {}
}

const _source = MovaSource('https://host/a.mp4');
Future<void> _turns() async {
  for (var i = 0; i < 10; i++) { await Future<void>.delayed(Duration.zero); }
}

MovaEngine _engine(String mode, _Probe probe, _Fetch fetch, _Puller puller) {
  final engine = MovaEngine(kernel: FakeKernel(), fetcher: fetch,
    options: MovaOpts(
      controls: const MovaCtrlsConfig(autoHide: false),
      abr: const MovaAbrConfig(probeVariants: false),
      preview: MovaPreviewConfig(probe: probe, cache: MovaMemoryThumbCache(),
        debounce: Duration.zero, vttEnabled: mode != 'extract',
        vttUrl: mode == 'sprite' ? 'file:///local.vtt' : null,
        extractor: mode == 'extract' ? puller : null,
        extractPlatforms: MovaPlatformKind.values.toSet()),
    ));
  addTearDown(engine.dispose);
  return engine;
}

void main() {
  for (final mode in ['track', 'sprite', 'extract']) {
    for (final action in ['cancel', 'attach', 'dispose']) {
      test('review P2 pending $mode probe cannot start old work after $action', () async {
        final probe = _Probe();
        final fetch = _Fetch();
        final puller = _Puller();
        final engine = _engine(mode, probe, fetch, puller);
        final service = engine.preview as MovaPreviewService;
        await engine.open(_source);
        engine.preview.requestAt(const Duration(seconds: 12));
        await probe.started.future;
        Future<void>? closing;
        var closedBeforeProbe = false;
        if (action == 'cancel') {
          engine.preview.cancel();
        } else if (action == 'attach') {
          await engine.open(const MovaSource('https://host/b.mp4'));
        } else {
          closing = service.dispose().then((_) { closedBeforeProbe = true; });
        }
        await _turns();
        final didClose = closedBeforeProbe;
        probe.gate.complete(true);
        await service.drain();
        await closing;
        expect(fetch.urls.map((u) => u.path), mode == 'sprite' ? ['/local.vtt'] : isEmpty);
        expect(puller.uris, isEmpty);
        expect(engine.preview.current, isNull);
        if (action == 'dispose') expect(didClose, isTrue, reason: 'dispose 不等待探针');
      });
    }
  }

  test('review P2 same bucket replacement progresses while old probe is pending', () async {
    final probe = _Probe();
    final fetch = _Fetch();
    final engine = _engine('track', probe, fetch, _Puller());
    await engine.open(_source);
    engine.preview.requestAt(const Duration(seconds: 12));
    await probe.started.future;
    engine.preview.requestAt(const Duration(seconds: 12));
    await _turns();
    final replacement = engine.preview.current;
    probe.gate.complete(true);
    await (engine.preview as MovaPreviewService).drain();
    expect(replacement, isNotNull, reason: '新代际无需等旧探针返回');
    expect(fetch.urls.map((u) => u.path), ['/a.mp4.vtt', '/sprite.jpg']);
  });

  for (final mode in ['track', 'extract']) {
    test('review P2 $mode wrapper disposal invalidates direct pending calls', () async {
      final probe = _Probe();
      final fetch = _Fetch();
      final puller = _Puller();
      final engine = _engine(mode, probe, fetch, puller);
      await engine.open(_source);
      final source = (engine.preview as MovaPreviewService).sources.single;
      final result = expectLater(source.thumbAt(_source, const Duration(seconds: 12)),
        throwsA(isA<PreviewRequestCancelled>()));
      await probe.started.future;
      await source.dispose();
      probe.gate.complete(true);
      await result;
      expect(fetch.urls, isEmpty);
      expect(puller.uris, isEmpty);
    });
  }
}
