import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mova/mova.dart';

import '../../support/fake_kernel.dart';

/// 可挂起首个请求的来源，记录实际执行的桶。
class _Source implements IMovaThumbSource {
  /// 首次执行时通知测试。
  final started = Completer<void>();
  /// 首个请求的返回门闩。
  final gate = Completer<void>();
  /// 已经开始执行的桶。
  final asked = <Duration>[];
  /// 来源的诊断名称。
  @override
  String get name => 'test';
  /// 首个请求挂起，之后返回对应桶的图像。
  @override
  Future<MovaThumb?> thumbAt(MovaSource source, Duration bucket) async {
    asked.add(bucket);
    if (!started.isCompleted) {
      started.complete();
      await gate.future;
    }
    return MovaThumb(at: bucket, bytes: Uint8List.fromList([bucket.inSeconds]));
  }
  /// 测试来源无会话缓存。
  @override
  Future<void> reset() async {}
  /// 销毁时放行首个请求。
  @override
  Future<void> dispose() async { if (!gate.isCompleted) gate.complete(); }
}

/// 挂起网络判定并可模拟首次异常的探针。
class _Probe implements IMovaNetProbe {
  /// 测试控制的网络判定门闩。
  Completer<bool>? gate;
  /// 下一次判定是否抛出异常。
  bool throwNext = false;
  /// 首次进入判定的通知。
  final started = Completer<void>();
  /// 按测试配置回答或抛错。
  @override
  Future<bool> allowHeavy() async {
    if (!started.isCompleted) started.complete();
    if (throwNext) { throwNext = false; throw StateError('probe'); }
    return gate?.future ?? true;
  }
  /// 无连通性变化推送。
  @override
  Stream<bool> get changes => const Stream.empty();
  /// 测试探针无外部资源。
  @override
  Future<void> dispose() async {}
}

/// 可模拟首次读取失败的内存缓存。
class _Cache extends MovaMemoryThumbCache {
  /// 下一次读取是否抛错。
  bool throwNext = true;
  /// 抛错后下一次读取仍然可用。
  @override
  Future<Uint8List?> read(String key) async {
    if (throwNext) { throwNext = false; throw StateError('cache'); }
    return super.read(key);
  }
}

/// 返回可修改的预置字节并记录请求。
class _Fetcher implements IMovaHttpFetch {
  /// URL 到响应字节的映射。
  final responses = <String, Uint8List>{};
  /// 实际访问的 URL。
  final asked = <String>[];
  /// 按 URL 返回响应。
  @override
  Future<Uint8List?> get(Uri url) async { asked.add(url.toString()); return responses[url.toString()]; }
  /// 测试无真实网络资源。
  @override
  Future<void> close() async {}
}

/// 记录抽帧次数，直播时不应调用。
class _Puller implements IMovaFramePuller {
  /// 已调用的抽帧次数。
  int calls = 0;
  /// 返回预置帧。
  @override
  Future<Uint8List?> extract(String uri, Duration at, {required int width, required bool hwdec}) async {
    calls++; return Uint8List.fromList([9]);
  }
  /// 无解码资源需要释放。
  @override
  Future<void> release() async {}
  /// 无解码资源需要销毁。
  @override
  Future<void> dispose() async {}
}

/// 创建零防抖的服务，支持自定义探针和缓存。
MovaPreviewService _service(List<IMovaThumbSource> sources, {IMovaNetProbe? probe, IMovaThumbCache? cache}) =>
    MovaPreviewService(
      opts: const MovaPreviewOpts(enabled: true, debounce: Duration.zero),
      cache: cache ?? MovaMemoryThumbCache(), probe: probe ?? MovaAlwaysAllowNetProbe(), sources: sources,
    )..attach(const MovaSource('https://host/a.mp4'));

/// 有效 VTT：仅覆盖零到五秒，用于同时测试命中与回退。
final _vtt = Uint8List.fromList(utf8.encode('WEBVTT\n\n00:00:00.000 --> 00:00:05.000\ns.jpg#xywh=0,0,10,10\n'));

/// B08 的队列合并、重试与媒体能力回归。
void main() {
  test('在途请求后只执行最新待处理桶，已支付的旧结果仍缓存', () async {
    final src = _Source();
    final s = _service([src]);
    s.requestAt(const Duration(seconds: 10));
    await src.started.future;
    s.requestAt(const Duration(seconds: 20));
    s.requestAt(const Duration(seconds: 30));
    src.gate.complete();
    await s.drain();
    expect(src.asked, [const Duration(seconds: 10), const Duration(seconds: 30)]);
    expect(s.current!.at, const Duration(seconds: 30));
    expect(s.peekAt(const Duration(seconds: 10)), isNotNull);
    expect(s.peekAt(const Duration(seconds: 20)), isNull);
    await s.dispose();
  });

  test('网络判定期间过期的请求在启动来源前丢弃，cancel 阻止迟到发布', () async {
    final p = _Probe()..gate = Completer<bool>();
    final src = _Source()..gate.complete();
    final s = _service([src], probe: p);
    s.requestAt(const Duration(seconds: 10));
    await p.started.future;
    s.requestAt(const Duration(seconds: 20));
    p.gate!.complete(true);
    await s.drain();
    expect(src.asked, [const Duration(seconds: 20)]);
    s.requestAt(const Duration(seconds: 30));
    s.cancel();
    await s.drain();
    expect(src.asked, [const Duration(seconds: 20)]);
    expect(s.current, isNull);
    await s.dispose();
  });

  test('探针与缓存异常不会使后续队列失效', () async {
    final p = _Probe()..throwNext = true;
    final src = _Source()..gate.complete();
    final s = _service([src], probe: p, cache: _Cache());
    for (final second in [10, 20, 30]) {
      s.requestAt(Duration(seconds: second));
      await s.drain();
    }
    expect(src.asked, [const Duration(seconds: 20), const Duration(seconds: 30)]);
    expect(s.current!.at, const Duration(seconds: 30));
    await s.dispose();
  });

  test('VTT 失败冷却后可重试，损坏内容不会永久封禁，成功后仍记忆', () async {
    var now = DateTime.utc(2026);
    final f = _Fetcher();
    final vtt = MovaVttThumbSource(fetcher: f, now: () => now);
    const src = MovaSource('https://host/a.mp4');
    expect(await vtt.thumbAt(src, Duration.zero), isNull);
    expect(await vtt.thumbAt(src, Duration.zero), isNull);
    expect(f.asked, hasLength(1));
    now = now.add(const Duration(seconds: 30));
    f.responses['https://host/a.mp4.vtt'] = Uint8List.fromList([0]);
    expect(await vtt.thumbAt(src, Duration.zero), isNull);
    now = now.add(const Duration(seconds: 30));
    f.responses['https://host/a.mp4.vtt'] = _vtt;
    f.responses['https://host/s.jpg'] = Uint8List.fromList([1]);
    expect(await vtt.thumbAt(src, Duration.zero), isNotNull);
    expect(await vtt.thumbAt(src, Duration.zero), isNotNull);
    expect(f.asked.where((url) => url.endsWith('.vtt')), hasLength(3));
    await vtt.dispose();
  });

  test('DVR 直播可用 VTT，未命中时也不启动独立抽帧器', () async {
    final f = _Fetcher();
    f.responses['https://host/a.mp4.vtt'] = _vtt;
    f.responses['https://host/s.jpg'] = Uint8List.fromList([1]);
    final puller = _Puller();
    final s = _service([MovaVttThumbSource(fetcher: f), MovaPullerThumbSource(extractor: puller)]);
    s.attach(const MovaSource('https://host/a.mp4', type: MovaStreamType.live));
    s.requestAt(Duration.zero);
    await s.drain();
    expect(s.current, isNotNull);
    s.requestAt(const Duration(seconds: 10));
    await s.drain();
    expect(puller.calls, 0);
    await s.dispose();
  });

  test('audioOnly 播放器即使开启预览也不探测 VTT', () async {
    final f = _Fetcher();
    final mova = createMova(kernel: FakeKernel.audioOnly(), audioOnly: true,
      pip: MovaNoopPip(), orient: MovaNoopOrient(), brightness: MovaFallbackBrightness(),
      fetcher: f, options: MovaOpts(preview: MovaPreviewOpts(enabled: true,
        debounce: Duration.zero, cache: MovaMemoryThumbCache(), network: MovaPreviewNet.always)));
    await mova.open(const MovaSource('https://host/a.mp4'));
    mova.preview.requestAt(Duration.zero);
    await (mova.preview as MovaPreviewService).drain();
    expect(f.asked, isEmpty);
    expect(mova.preview.current, isNull);
    await mova.dispose();
  });
}
