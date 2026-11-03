import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mova/mova.dart';

import '../../support/fake_kernel.dart';

/// 启动本地服务器；每条测试结束强制关闭。
Future<HttpServer> _server(void Function(HttpRequest) serve) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen(serve);
  addTearDown(() => server.close(force: true));
  return server;
}

/// 本地测试服务器的请求地址。
Uri _url(HttpServer server) => Uri.parse('http://127.0.0.1:${server.port}/a');

/// 模拟原生 seek 无法确认的抽帧器。
class _UnconfirmedPuller implements MovaFramePuller {
  /// 截图调用次数；未落地时必须为零。
  int captures = 0;

  /// 使用生产落地确认与截图管线，模拟落地超时。
  @override
  Future<Uint8List?> extract(String uri, Duration at, {required int width, required bool hwdec}) =>
      movaCapturePreviewFrame(
        landed: () => movaWaitForPreviewFrame(() async => false,
          timeout: const Duration(milliseconds: 20), pollInterval: const Duration(milliseconds: 5)),
        capture: () async { captures++; return Uint8List.fromList([1]); },
      );

  /// 无原生资源需要回收。
  @override
  Future<void> release() async {}

  /// 无原生资源需要销毁。
  @override
  Future<void> dispose() async {}
}

/// B07 的总期限、取消、销毁及抽帧回归。
void main() {
  test('404 响应体不结束也立即返回 null', () async {
    final server = await _server((req) {
      req.response.statusCode = 404;
      req.response.write('unending');
      unawaited(req.response.flush());
    });
    final fetcher = MovaIoHttpFetcher(timeout: const Duration(seconds: 3));
    addTearDown(fetcher.close);
    expect(await fetcher.get(_url(server)).timeout(const Duration(seconds: 1)), isNull);
  });

  test('200 响应体不结束时 close 主动取消，不等网络期限', () async {
    final headers = Completer<void>();
    final server = await _server((req) {
      req.response.write('unending');
      unawaited(req.response.flush().then((_) => headers.complete()));
    });
    final fetcher = MovaIoHttpFetcher(timeout: const Duration(seconds: 30));
    final pending = fetcher.get(_url(server));
    await headers.future;
    await fetcher.close();
    expect(await pending.timeout(const Duration(seconds: 1)), isNull);
    expect(await fetcher.get(_url(server)), isNull);
    await fetcher.close();
  });

  test('响应头与响应体共享一个总期限，不能各自获得完整 timeout', () async {
    final releaseBody = Completer<void>();
    final headers = Completer<void>();
    final server = await _server((req) {
      unawaited(Future<void>(() async {
        await Future<void>.delayed(const Duration(milliseconds: 160));
        req.response.write('a');
        await req.response.flush();
        headers.complete();
        await releaseBody.future;
        await req.response.close();
      }));
    });
    final fetcher = MovaIoHttpFetcher(timeout: const Duration(milliseconds: 300));
    addTearDown(fetcher.close);
    final pending = fetcher.get(_url(server));
    await headers.future;
    // 在总期限后、第二阶段的独立期限之前结束，旧实现会返回成功。
    final answer = await pending.timeout(const Duration(milliseconds: 260));
    expect(answer, isNull);
    releaseBody.complete();
  });

  test('预览 404 body 悬挂时引擎 dispose 在期限内完成并释放主内核', () async {
    final headers = Completer<void>();
    final server = await _server((req) {
      req.response.statusCode = 404;
      req.response.write('unending');
      unawaited(req.response.flush().then((_) => headers.complete()));
    });
    final k = FakeKernel();
    final engine = createMovaEngine(kernel: k, ownsKernel: true,
      pip: MovaNoopPipPort(), orientation: MovaNoopOrientationPort(), brightness: MovaFallbackBrightnessPort(),
      fetcher: MovaIoHttpFetcher(timeout: const Duration(seconds: 30)),
      options: MovaOpts(preview: MovaPreviewConfig(enabled: true, debounce: Duration.zero,
        cache: MovaMemoryThumbCache(), network: MovaPreviewNet.always)));
    await engine.open(MovaSource(_url(server).toString()));
    engine.preview.requestAt(Duration.zero);
    await headers.future;
    await engine.dispose().timeout(const Duration(seconds: 1));
    expect(k.isDisposed, isTrue);
  });

  test('落地轮询超时返回 null，不截图也不缓存；确认后才允许截图', () async {
    final puller = _UnconfirmedPuller();
    final service = MovaPreviewService(
      config: const MovaPreviewConfig(enabled: true, debounce: Duration.zero, network: MovaPreviewNet.always),
      cache: MovaMemoryThumbCache(), probe: MovaAlwaysAllowNetProbe(),
      sources: [MovaPullerThumbSource(extractor: puller)],
    )..attach(const MovaSource('https://host/a.mp4'));
    service.requestAt(Duration.zero);
    await service.drain();
    expect(puller.captures, 0);
    expect(service.peekAt(Duration.zero), isNull);
    final hung = Completer<bool>();
    expect(await movaWaitForPreviewFrame(() => hung.future,
      timeout: const Duration(milliseconds: 10)), isFalse);
    expect(await movaCapturePreviewFrame(landed: () async => true,
      capture: () async => Uint8List.fromList([2])), [2]);
    await service.dispose();
  });
}
