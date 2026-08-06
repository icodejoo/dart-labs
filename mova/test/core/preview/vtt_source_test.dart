import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mova/src/core/model/source.dart';
import 'package:mova/src/core/preview/fetcher.dart';
import 'package:mova/src/core/preview/models.dart';
import 'package:mova/src/core/preview/vtt_source.dart';

/// A [MovaHttpFetch] serving canned responses and recording every URL asked.
///
/// 返回预置响应并记录每次请求 URL 的 [MovaHttpFetch]。
class _FakeFetcher implements MovaHttpFetch {
  /// Canned responses, keyed by URL.
  ///
  /// 按 URL 存放的预置响应。
  final Map<String, Uint8List> responses = <String, Uint8List>{};

  /// Every URL requested, in order.
  ///
  /// 按顺序记录的每个被请求 URL。
  final List<String> requested = <String>[];

  /// Registers [body] as the response for [url].
  ///
  /// 把 [body] 注册为 [url] 的响应。
  ///
  /// - [url]: the URL to serve / 要服务的 URL
  /// - [body]: response body as text / 文本形式的响应体
  void serveText(String url, String body) =>
      responses[url] = Uint8List.fromList(utf8.encode(body));

  /// Registers [bytes] as the response for [url].
  ///
  /// 把 [bytes] 注册为 [url] 的响应。
  ///
  /// - [url]: the URL to serve / 要服务的 URL
  /// - [bytes]: raw response body / 原始响应体
  void serveBytes(String url, List<int> bytes) =>
      responses[url] = Uint8List.fromList(bytes);

  @override
  Future<Uint8List?> get(Uri url) async {
    requested.add(url.toString());
    return responses[url.toString()];
  }

  @override
  Future<void> close() async {}
}

/// The VTT fixture used across these tests.
///
/// 本组测试共用的 VTT 样例。
const String _vtt = 'WEBVTT\n'
    '\n'
    '00:00:00.000 --> 00:00:10.000\n'
    'sprite-0.jpg#xywh=0,0,160,90\n'
    '\n'
    '00:00:10.000 --> 00:00:20.000\n'
    'sprite-0.jpg#xywh=160,0,160,90\n';

void main() {
  const src = MovaSource('https://host/media/a.mp4');

  test('defaultVttUrl appends .vtt to the media path', () {
    expect(defaultVttUrl(src), Uri.parse('https://host/media/a.mp4.vtt'));
    expect(
      defaultVttUrl(const MovaSource('https://host/l.m3u8?token=1')),
      Uri.parse('https://host/l.m3u8.vtt?token=1'),
    );
    expect(defaultVttUrl(const MovaSource('')), isNull);
  });

  test('fetches the vtt once, then serves thumbs with the right crop', () async {
    final f = _FakeFetcher()
      ..serveText('https://host/media/a.mp4.vtt', _vtt)
      ..serveBytes('https://host/media/sprite-0.jpg', [1, 2, 3]);
    final s = MovaVttThumbSource(fetcher: f);

    final t0 = await s.thumbAt(src, const Duration(seconds: 0));
    final t1 = await s.thumbAt(src, const Duration(seconds: 10));

    expect(t0!.crop, const MovaThumbCrop(x: 0, y: 0, w: 160, h: 90));
    expect(t0.at, Duration.zero);
    expect(t0.bytes, [1, 2, 3]);
    expect(t1!.crop, const MovaThumbCrop(x: 160, y: 0, w: 160, h: 90));
    expect(
      f.requested.where((u) => u.endsWith('.vtt')).length,
      1,
      reason: 'vtt should be fetched exactly once',
    );
    expect(
      f.requested.where((u) => u.endsWith('sprite-0.jpg')).length,
      1,
      reason: 'the sprite sheet should be fetched exactly once',
    );
    await s.dispose();
  });

  test('a missing vtt makes the source permanently unavailable for that media', () async {
    final f = _FakeFetcher();
    final s = MovaVttThumbSource(fetcher: f);
    expect(await s.thumbAt(src, Duration.zero), isNull);
    expect(await s.thumbAt(src, const Duration(seconds: 10)), isNull);
    expect(f.requested.length, 1, reason: 'a failed vtt fetch must not be retried per scrub');
    await s.dispose();
  });

  test('an empty vtt is treated as unavailable', () async {
    final f = _FakeFetcher()..serveText('https://host/media/a.mp4.vtt', 'WEBVTT\n');
    final s = MovaVttThumbSource(fetcher: f);
    expect(await s.thumbAt(src, Duration.zero), isNull);
    await s.dispose();
  });

  test('a missing sprite yields null without poisoning the index', () async {
    final f = _FakeFetcher()..serveText('https://host/media/a.mp4.vtt', _vtt);
    final s = MovaVttThumbSource(fetcher: f);
    expect(await s.thumbAt(src, Duration.zero), isNull);
    f.serveBytes('https://host/media/sprite-0.jpg', [9]);
    expect((await s.thumbAt(src, Duration.zero))!.bytes, [9]);
    await s.dispose();
  });

  test('a custom resolver overrides the .vtt convention', () async {
    final f = _FakeFetcher()
      ..serveText('https://cdn/thumbs.vtt', _vtt)
      ..serveBytes('https://cdn/sprite-0.jpg', [7]);
    final s = MovaVttThumbSource(
      fetcher: f,
      resolveUrl: (_) => Uri.parse('https://cdn/thumbs.vtt'),
    );
    expect((await s.thumbAt(src, Duration.zero))!.bytes, [7]);
    await s.dispose();
  });

  test('a resolver returning null disables the source', () async {
    final f = _FakeFetcher();
    final s = MovaVttThumbSource(fetcher: f, resolveUrl: (_) => null);
    expect(await s.thumbAt(src, Duration.zero), isNull);
    expect(f.requested, isEmpty);
    await s.dispose();
  });

  test('reset drops the cached index so a new media re-fetches', () async {
    final f = _FakeFetcher()
      ..serveText('https://host/media/a.mp4.vtt', _vtt)
      ..serveBytes('https://host/media/sprite-0.jpg', [1]);
    final s = MovaVttThumbSource(fetcher: f);
    await s.thumbAt(src, Duration.zero);
    await s.reset();
    await s.thumbAt(src, Duration.zero);
    expect(f.requested.where((u) => u.endsWith('.vtt')).length, 2);
    await s.dispose();
  });

  test('sprite memoisation is bounded by maxSprites', () async {
    const many = 'WEBVTT\n'
        '\n'
        '00:00:00.000 --> 00:00:10.000\n'
        's0.jpg\n'
        '\n'
        '00:00:10.000 --> 00:00:20.000\n'
        's1.jpg\n';
    final f = _FakeFetcher()
      ..serveText('https://host/media/a.mp4.vtt', many)
      ..serveBytes('https://host/media/s0.jpg', [0])
      ..serveBytes('https://host/media/s1.jpg', [1]);
    final s = MovaVttThumbSource(fetcher: f, maxSprites: 1);
    await s.thumbAt(src, Duration.zero);
    await s.thumbAt(src, const Duration(seconds: 10));
    await s.thumbAt(src, Duration.zero);
    expect(f.requested.where((u) => u.endsWith('s0.jpg')).length, 2);
    await s.dispose();
  });

  test('the source reports a stable name for diagnostics', () {
    expect(MovaVttThumbSource(fetcher: _FakeFetcher()).name, 'vtt');
  });
}
