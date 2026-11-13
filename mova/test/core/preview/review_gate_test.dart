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

class _Fetch implements IMovaHttpFetch {
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

class _Fallback implements IMovaThumbSource {
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

Mova _mova(_Probe probe, _Fetch fetch, List<MovaPreviewBlockReason> blocks,
    {String? vttUrl}) {
  final mova = Mova(kernel: FakeKernel(), fetcher: fetch,
    options: MovaOpts(
      controls: const MovaCtrlsOpts(autoHide: false),
      abr: const MovaAbrOpts(probeVariants: false),
      preview: MovaPreviewOpts(probe: probe, cache: MovaMemoryThumbCache(),
        debounce: Duration.zero, vttUrl: vttUrl, onBlocked: blocks.add),
    ));
  addTearDown(mova.dispose);
  return mova;
}

Future<void> _request(Mova mova) async {
  mova.preview.requestAt(const Duration(seconds: 12));
  await (mova.preview as MovaPreviewService).drain();
}

void main() {
  test('review P2 policy denial does not cool down VTT before wifi returns', () async {
    final probe = _Probe();
    final fetch = _Fetch();
    final blocks = <MovaPreviewBlockReason>[];
    final mova = _mova(probe, fetch, blocks);
    await mova.open(const MovaSource('https://host/a.mp4'));
    await _request(mova);
    expect(fetch.urls, isEmpty);
    expect(blocks, [MovaPreviewBlockReason.network]);
    probe.allowed = true;
    await _request(mova);
    expect(mova.preview.current, isNotNull);
    expect(fetch.urls.map((u) => u.path), ['/a.mp4.vtt', '/sprite.jpg']);
    expect(blocks, hasLength(1));
  });

  test('review P2 sprite policy denial reaches service and retries immediately', () async {
    final probe = _Probe();
    final fetch = _Fetch();
    final blocks = <MovaPreviewBlockReason>[];
    final mova = _mova(probe, fetch, blocks, vttUrl: 'file:///local.vtt');
    final fallback = _Fallback();
    (mova.preview as MovaPreviewService).sources.add(fallback);
    await mova.open(const MovaSource('https://host/a.mp4'));
    // 本地轨指向远程雪碧图，门控必须使用资源地址。
    // 显式远程图片使轨缓存命中后仍能单独识别策略拒绝。
    await _request(mova);
    expect(mova.preview.current, isNull);
    expect(fetch.urls.map((u) => u.path), ['/local.vtt']);
    expect(blocks, [MovaPreviewBlockReason.network]);
    expect(fallback.calls, 0, reason: '策略拒绝由服务结算，不能当普通失败继续兜底');
    probe.allowed = true;
    await _request(mova);
    expect(mova.preview.current, isNotNull);
    expect(fetch.urls.map((u) => u.path), ['/local.vtt', '/sprite.jpg']);
    expect(blocks, hasLength(1));
  });
}
