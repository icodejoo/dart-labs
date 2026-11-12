import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:mova/mova.dart';
import '../support/fake_kernel.dart';

class _Fetch implements MovaHeaderedHttpFetch {
  final seen = <Map<String, String>>[];
  @override
  Future<Uint8List?> get(Uri url) => getWithHeaders(url, const {});
  @override
  Future<Uint8List?> getWithHeaders(Uri url, Map<String, String> headers) async {
    seen.add(headers);
    return Uint8List.fromList(utf8.encode(url.path.endsWith('.vtt')
      ? 'WEBVTT\n\n00:00:00.000 --> 00:00:10.000\nsprite.jpg\n'
      : '#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1000\na.m3u8\n'));
  }
  @override
  Future<void> close() async {}
}
class _Legacy implements MovaHttpFetch {
  int count = 0;
  @override
  Future<Uint8List?> get(Uri url) async { count++; return Uint8List(1); }
  @override
  Future<void> close() async {}
}
class _Puller implements MovaHeaderedFramePuller {
  Map<String, String>? seen;
  @override
  Future<Uint8List?> extract(String uri, Duration at, {required int width, required bool hwdec}) async => null;
  @override
  Future<Uint8List?> extractWithHeaders(String uri, Duration at, {required int width, required bool hwdec, required Map<String, String> headers}) async { seen = headers; return Uint8List(1); }
  @override
  Future<void> release() async {}
  @override
  Future<void> dispose() async {}
}
void main() {
  const source = MovaSource('https://h/a.mp4', headers: {'Referer': 'https://h', 'user-agent': 'old'}, userAgent: 'new', start: Duration(seconds: 7));
  test('C07 UA 合并不重复且不修改原表', () {
    expect(source.requestHeaders, {'Referer': 'https://h', 'User-Agent': 'new'});
    expect(source.headers['user-agent'], 'old');
  });
  test('C07 播放选项编码分隔符并覆盖底层值', () {
    final options = const MovaSource('x', headers: {'X': '甲,乙'}, userAgent: 'ua', mpvOptions: {'user-agent': 'old'}).mpvOptionsFor('x');
    expect(options['user-agent'], 'ua');
    expect(options['http-header-fields'], contains('%10%X: 甲,乙'));
  });
  test('C07 sameAs 区分鉴权 UA 及起播位置', () {
    for (final other in [const MovaSource('x', headers: {'A':'b'}), const MovaSource('x', userAgent: 'u'), const MovaSource('x', start: Duration(seconds: 1))]) {
      expect(const MovaSource('x').sameAs(other), isFalse);
    }
  });
  test('C07 pick 保留新增源规格', () {
    final picked = MovaSource.pick(['', source.uri], headers: source.headers, userAgent: source.userAgent, start: source.start)!;
    expect(picked.sameAs(source), isTrue);
  });
  test('C07 旧 fetcher 无头退化且仅提示一次', () async {
    final messages = <String>[];
    final fetch = _Legacy();
    await runZoned(() async {
      for (var i = 0; i < 2; i++) {
        await movaFetchWithHeaders(fetch, Uri.parse(source.uri), source.requestHeaders);
      }
    }, zoneSpecification: ZoneSpecification(print: (_, _, _, line) => messages.add(line)));
    expect(fetch.count, 2);
    expect(messages, hasLength(1));
  });
  test('C07 IO 请求头不会泄漏至后续请求', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final seen = <String?>[];
    server.listen((r) { seen.add(r.headers.value('referer')); r.response.write('ok'); r.response.close(); });
    final fetch = MovaIoHttpFetcher();
    addTearDown(fetch.close);
    final url = Uri.parse('http://127.0.0.1:${server.port}/x');
    await fetch.getWithHeaders(url, {'Referer':'auth'});
    await fetch.get(url);
    expect(seen, ['auth', null]);
  });
  test('C07 VTT 与雪碧图均带源请求头', () async {
    final fetch = _Fetch();
    final vtt = MovaVttThumbSource(fetcher: fetch);
    addTearDown(vtt.dispose);
    expect(await vtt.thumbAt(source, Duration.zero), isNotNull);
    expect(fetch.seen, [{'Referer': 'https://h', 'User-Agent': 'new'}, {'Referer': 'https://h', 'User-Agent': 'new'}]);
  });
  test('C07 抽帧能力接收源请求头', () async {
    final puller = _Puller();
    await MovaPullerThumbSource(extractor: puller).thumbAt(source, Duration.zero);
    expect(puller.seen, {'Referer': 'https://h', 'User-Agent': 'new'});
  });
  test('C07 起播位置寄存至时长就绪后下发', () async {
    final kernel = FakeKernel();
    final engine = MovaEngine(kernel: kernel);
    addTearDown(engine.dispose);
    await engine.open(const MovaSource('https://h/live', type: MovaStreamType.live, start: Duration(seconds: 3)));
    expect(kernel.lastSeek, isNull);
    await engine.open(source);
    expect(kernel.lastSeek, isNull);
    kernel.emitDuration(const Duration(seconds: 60));
    await Future<void>.delayed(Duration.zero);
    expect(kernel.lastSeek, source.start);
  });
  test('C07 清晰度探测和 feed 预取带源请求头', () async {
    final fetch = _Fetch();
    final engine = MovaEngine(kernel: FakeKernel(), fetcher: fetch);
    addTearDown(engine.dispose);
    await engine.open(const MovaSource('https://h/a.m3u8', headers: {'Referer':'auth'}));
    await engine.loadQualities();
    expect(fetch.seen, isNotEmpty);
    expect(fetch.seen.every((h) => h['Referer'] == 'auth'), isTrue);
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    String? seen;
    server.listen((r) { seen = r.headers.value('referer'); r.response.close(); });
    await const MovaNetworkWarmFeedPrefetcher().prime(MovaSource('http://127.0.0.1:${server.port}/x', headers: const {'Referer':'auth'}));
    expect(seen, 'auth');
  });
}


