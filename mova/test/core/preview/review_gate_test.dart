import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mova/mova.dart';

import '../../support/fake_kernel.dart';

class _Probe extends MovaAlwaysAllowNetProbe {
  bool allowed = false;
  int queries = 0;
  @override
  Future<bool> allowHeavy() async { queries++; return allowed; }
}

class _Fetch implements MovaHttpFetch {
  final urls = <Uri>[];
  @override
  Future<Uint8List?> get(Uri url) async {
    urls.add(url);
    return url.path.endsWith('.vtt')
        ? Uint8List.fromList(utf8.encode('WEBVTT\n\n00:00.000 --> 01:00.000\nhttps://host/sprite.jpg#xywh=0,0,10,10\n'))
        : Uint8List.fromList([1, 2, 3]);
  }
  @override
  Future<void> close() async {}
}

class _Fallback implements MovaThumbSource {
  int calls = 0;
  @override
  String get name => 'fallback';
  @override
  Future<MovaThumb?> thumbAt(MovaSource source, Duration bucket) async {
    calls++;
    return null;
  }
  @override
  Future<void> reset() async {}
  @override
  Future<void> dispose() async {}
}

MovaEngine _engine(_Probe probe, _Fetch fetch, List<MovaPreviewBlockReason> blocks,
    {String? vttUrl}) {
  final engine = MovaEngine(kernel: FakeKernel(), fetcher: fetch,
    options: MovaOpts(
      controls: const MovaCtrlsConfig(autoHide: false),
      abr: const MovaAbrConfig(probeVariants: false),
      preview: MovaPreviewConfig(probe: probe, cache: MovaMemoryThumbCache(),
        debounce: Duration.zero, vttUrl: vttUrl, onBlocked: blocks.add),
    ));
  addTearDown(engine.dispose);
  return engine;
}

Future<void> _request(MovaEngine engine) async {
  engine.preview.requestAt(const Duration(seconds: 12));
  await (engine.preview as MovaPreviewService).drain();
}

void main() {
  test('review P2 policy denial does not cool down VTT before wifi returns', () async {
    final probe = _Probe();
    final fetch = _Fetch();
    final blocks = <MovaPreviewBlockReason>[];
    final engine = _engine(probe, fetch, blocks);
    await engine.open(const MovaSource('https://host/a.mp4'));
    await _request(engine);
    expect(fetch.urls, isEmpty);
    expect(blocks, [MovaPreviewBlockReason.network]);
    probe.allowed = true;
    await _request(engine);
    expect(engine.preview.current, isNotNull);
    expect(fetch.urls.map((u) => u.path), ['/a.mp4.vtt', '/sprite.jpg']);
    expect(blocks, hasLength(1));
  });

  test('review P2 sprite policy denial reaches service and retries immediately', () async {
    final probe = _Probe();
    final fetch = _Fetch();
    final blocks = <MovaPreviewBlockReason>[];
    final engine = _engine(probe, fetch, blocks, vttUrl: 'file:///local.vtt');
    final fallback = _Fallback();
    (engine.preview as MovaPreviewService).sources.add(fallback);
    await engine.open(const MovaSource('https://host/a.mp4'));
    // 本地轨指向远程雪碧图，门控必须使用资源地址。
    // 显式远程图片使轨缓存命中后仍能单独识别策略拒绝。
    await _request(engine);
    expect(engine.preview.current, isNull);
    expect(fetch.urls.map((u) => u.path), ['/local.vtt']);
    expect(blocks, [MovaPreviewBlockReason.network]);
    expect(fallback.calls, 0, reason: '策略拒绝由服务结算，不能当普通失败继续兜底');
    probe.allowed = true;
    await _request(engine);
    expect(engine.preview.current, isNotNull);
    expect(fetch.urls.map((u) => u.path), ['/local.vtt', '/sprite.jpg']);
    expect(blocks, hasLength(1));
  });
}
