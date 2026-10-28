// ignore_for_file: avoid_print
// 边界层：timeout 真正生效（真实回环 HTTP：真实 Dio IO 适配器 + 真实 socket）
//
// 不用 test/support/test_server.dart（它强制短连接、写法固定），这里自建
// HttpServer，服务端可以在响应头之后停顿、或干脆不读请求体。
//
// 依据（dio 5.11.1）：
// - receive：adapters/io_adapter.dart 的 request.close() 套 receiveTimeout（等响应头）；
//   response/response_stream_handler.dart 在响应体阶段按「块间空闲」计时，每来一块重置。
// - send：adapters/io_adapter.dart 只给 request.addStream(...) 套 sendTimeout，
//   所以只有 body 写不进 socket（对端不读、缓冲塞满）时才会触发。
// - connect：见文件末尾注释，回环上无法造出连接超时，不在此写用例。
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';
import 'package:test/test.dart';

/// 被测的「短」超时：插件改写后应该真正生效的值。
const Duration _kShort = Duration(milliseconds: 150);

/// 请求级覆盖用的「长」超时，要明显大于服务端的拖延时间。
const Duration _kLong = Duration(milliseconds: 1200);

/// BaseOptions 里的宽松超时：若插件没改写成功，请求会一直等到它，用来证明生效的是改写值。
const Duration _kBase = Duration(seconds: 10);

/// 实际耗时允许超出超时值的余量（调度、建连、事件循环抖动）。
const Duration _kMargin = Duration(milliseconds: 1000);

/// 计时器可能比 Stopwatch 早触发的容差（Windows 定时器精度约 1ms 量级）。
const Duration _kEarlyTolerance = Duration(milliseconds: 20);

/// 每个场景的重复次数，取全部样本逐个断言。
const int _kSamples = 3;

/// 对照用例里分块写入的块数。
const int _kControlChunks = 4;

/// 对照用例里相邻两块之间的间隔：小于超时值，但总时长大于超时值。
const Duration _kControlGap = Duration(milliseconds: 100);

/// 对照用例用的接收超时：大于块间隔、小于总时长。
const Duration _kControlReceive = Duration(milliseconds: 250);

/// 发送场景每块字节数。
const int _kUploadChunkBytes = 64 * 1024;

/// 发送场景块数，总量 = 块数 × 块大小，要大到塞满回环 socket 的收发缓冲。
const int _kUploadChunks = 1024; // 64 MiB

/// 响应里一小段文本，便于断言 body 完整到达。
const String _kPayload = 'ok';

/// 请求路径。
const String _kPath = '/probe';

/// 一次请求的结果：成功时 [type] 为 null。
class _Outcome {
  /// 创建一次结果。
  const _Outcome(this.type, this.status, this.elapsed, this.received);

  /// 失败时的 Dio 异常类型，成功则为 null。
  final DioExceptionType? type;

  /// 成功时的 HTTP 状态码。
  final int? status;

  /// 从发起到结束的实际耗时。
  final Duration elapsed;

  /// 客户端经 onReceiveProgress 实际收到的响应体字节数，用来证明停顿发生在响应头之后。
  final int received;

  @override
  String toString() =>
      '${type ?? 'ok($status)'} @ ${elapsed.inMilliseconds}ms recv=${received}B';
}

/// 服务端处理器：[released] 在测试结束（服务端关闭）时完成，用于释放挂起的处理。
typedef _Handler = Future<void> Function(
    HttpRequest req, Future<void> released);

/// 自建的回环 HTTP 服务端，可让处理器任意停顿。
class _LoopbackServer {
  _LoopbackServer._(this._server);

  final HttpServer _server;
  final Completer<void> _released = Completer<void>();

  /// 服务端地址，形如 `http://127.0.0.1:port`。
  String get baseUrl => 'http://${_server.address.host}:${_server.port}';

  /// 绑定到 127.0.0.1 的随机端口并开始处理请求；处理器内部异常（客户端已断开）一律吞掉。
  static Future<_LoopbackServer> start(_Handler handler) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final s = _LoopbackServer._(server);
    server.listen((req) async {
      try {
        await handler(req, s._released.future);
      } catch (_) {
        // 客户端超时后会主动断连，服务端写入失败属于预期。
      }
    });
    return s;
  }

  /// 释放挂起的处理器并强制关闭所有连接。
  Future<void> close() async {
    if (!_released.isCompleted) _released.complete();
    await _server.close(force: true);
  }
}

/// 启动服务端并注册测试结束时的关闭。
Future<_LoopbackServer> _startServer(_Handler handler) async {
  final server = await _LoopbackServer.start(handler);
  addTearDown(server.close);
  return server;
}

/// 创建真实 Dio（默认 IO 适配器）：BaseOptions 带宽松超时，装 [DiomanTimeout]
/// 并让 poor 档改写为 [tier]；测试结束强制关闭。
Dio _buildDio(String baseUrl, DiomanTimeouts tier) {
  final dio = Dio(BaseOptions(
    baseUrl: baseUrl,
    connectTimeout: _kBase,
    receiveTimeout: _kBase,
    sendTimeout: _kBase,
    responseType: ResponseType.plain,
  ));
  dio.interceptors.add(DiomanTimeout(
    probe: () => NetworkQuality.poor,
    timeouts: {NetworkQuality.poor: tier},
  ));
  addTearDown(() => dio.close(force: true));
  return dio;
}

/// 发一次请求并计时；Dio 异常转成 [_Outcome]，其它异常原样抛出。
Future<_Outcome> _run(Dio dio,
    {String method = 'GET', Object? data, Options? options}) async {
  var received = 0;
  final sw = Stopwatch()..start();
  try {
    final r = await dio.request<String>(
      _kPath,
      data: data,
      options: (options ?? Options()).copyWith(method: method),
      onReceiveProgress: (count, _) => received = count,
    );
    sw.stop();
    return _Outcome(null, r.statusCode, sw.elapsed, received);
  } on DioException catch (e) {
    sw.stop();
    return _Outcome(e.type, null, sw.elapsed, received);
  }
}

/// 重复 [_kSamples] 次 [body]，收集全部样本（断言失败时随原因一并输出）。
Future<List<_Outcome>> _sample(
    String label, Future<_Outcome> Function() body) async {
  final out = <_Outcome>[];
  for (var i = 0; i < _kSamples; i++) {
    out.add(await body());
  }
  return out;
}

/// 断言每个样本都以 [type] 失败，且耗时落在 [timeout - 容差, timeout + 余量]。
void _expectTimedOut(
    List<_Outcome> samples, DioExceptionType type, Duration timeout) {
  final lo = timeout - _kEarlyTolerance;
  final hi = timeout + _kMargin;
  for (final s in samples) {
    expect(s.type, type, reason: '全部样本: $samples');
    expect(s.elapsed, greaterThanOrEqualTo(lo),
        reason: '不应早于超时值 $timeout；全部样本: $samples');
    expect(s.elapsed, lessThanOrEqualTo(hi),
        reason: '不应晚于 $timeout + $_kMargin；全部样本: $samples');
  }
}

/// 服务端处理：写响应头和第一块并 flush，然后一直停顿（不结束）。
Future<void> _stallAfterHeaders(HttpRequest req, Future<void> released) async {
  await _writeNow(req.response, _kPayload);
  await released;
}

/// 写一块并立即送出：关掉 bufferOutput，否则 Dart 会攒着不发，响应头与数据都到不了客户端。
Future<void> _writeNow(HttpResponse res, String text) async {
  if (res.bufferOutput) res.bufferOutput = false; // 响应头发出后不能再改
  res.write(text);
  await res.flush();
}

/// 服务端处理：什么都不写，一直挂着（响应头都不发）。
Future<void> _stallBeforeHeaders(HttpRequest req, Future<void> released) =>
    released;

/// 服务端处理：先停顿 [delay]，再一次性写完响应。
_Handler _respondAfter(Duration delay) => (req, released) async {
      await Future.any<void>([Future<void>.delayed(delay), released]);
      req.response.write(_kPayload);
      await req.response.close();
    };

/// 生成惰性的大请求体流，不占内存，由背压驱动。
Stream<List<int>> _bigUpload() {
  final chunk = Uint8List(_kUploadChunkBytes);
  return Stream<List<int>>.fromIterable(
      Iterable<List<int>>.generate(_kUploadChunks, (_) => chunk));
}

/// 大请求体对应的请求选项：流式 body 必须显式给 content-length。
Options _bigUploadOptions() => Options(
      contentType: 'application/octet-stream',
      headers: {
        Headers.contentLengthHeader: _kUploadChunkBytes * _kUploadChunks
      },
    );

// ── connect 为什么不写用例 ────────────────────────────────────────────────────
// DiomanTimeouts.connect#effective 在本机回环上无法稳定核对：
// io_adapter.dart 的连接超时是给 httpClient.openUrl(...) 的 Future 套 .timeout，
// 只有「SYN 发出去却迟迟没有回应」才会触发（对端黑洞/丢包）。回环上要么连得上，
// 要么被立即拒绝（SocketException → connectionError，不是 connectionTimeout）。
// 外部黑洞地址（如 10.255.255.1）依赖网络环境，会抖，且违背本库「不用拍脑袋地址」的约定；
// 因此连接超时只能由验收层的 netem 丢包场景去核对。

/// 注册本文件的边界层用例。
void main() {
  group('timeout 真正生效（真实回环 HTTP）', () {
    test(
        '[DiomanTimeouts.receive#effective] 响应头之后 body 停顿 → receiveTimeout，耗时贴近改写值',
        () async {
      final server = await _startServer(_stallAfterHeaders);
      final dio =
          _buildDio(server.baseUrl, const DiomanTimeouts(receive: _kShort));

      final samples = await _sample('receive/body停顿', () => _run(dio));

      _expectTimedOut(samples, DioExceptionType.receiveTimeout, _kShort);
      for (final s in samples) {
        expect(s.received, _kPayload.length,
            reason: '响应头与第一块已到达，停顿发生在响应体阶段；全部样本: $samples');
      }
    });

    test(
        '[DiomanTimeouts.receive#effective] 服务端一直不回响应头 → receiveTimeout，耗时贴近改写值',
        () async {
      final server = await _startServer(_stallBeforeHeaders);
      final dio =
          _buildDio(server.baseUrl, const DiomanTimeouts(receive: _kShort));

      final samples = await _sample('receive/不回响应头', () => _run(dio));

      _expectTimedOut(samples, DioExceptionType.receiveTimeout, _kShort);
      for (final s in samples) {
        expect(s.received, 0, reason: '响应头都没到；全部样本: $samples');
      }
    });

    test('[DiomanTimeouts.receive#effective] 对照：每块间隔都小于超时 → 成功（即便总时长超过超时值）',
        () async {
      final server = await _startServer((req, released) async {
        for (var i = 0; i < _kControlChunks; i++) {
          await _writeNow(req.response, _kPayload);
          await Future.any<void>(
              [Future<void>.delayed(_kControlGap), released]);
        }
        await req.response.close();
      });
      final dio = _buildDio(
          server.baseUrl, const DiomanTimeouts(receive: _kControlReceive));

      final samples = await _sample('receive/对照', () => _run(dio));

      for (final s in samples) {
        expect(s.type, isNull, reason: '全部样本: $samples');
        expect(s.status, 200, reason: '全部样本: $samples');
        expect(s.received, _kPayload.length * _kControlChunks,
            reason: '所有块都应收到；全部样本: $samples');
        expect(s.elapsed, greaterThan(_kControlReceive),
            reason: '总时长应超过超时值，才说明计时是块间空闲；全部样本: $samples');
      }
    });

    test(
        '[DiomanTimeouts.send#effective] 服务端不读请求体、body 塞满缓冲 → sendTimeout，耗时贴近改写值',
        () async {
      final server =
          await _startServer((req, released) => released); // 不读 body，也不响应
      final dio =
          _buildDio(server.baseUrl, const DiomanTimeouts(send: _kShort));

      final samples = await _sample(
          'send/不读body',
          () => _run(dio,
              method: 'POST',
              data: _bigUpload(),
              options: _bigUploadOptions()));

      _expectTimedOut(samples, DioExceptionType.sendTimeout, _kShort);
    });

    test('[DiomanTimeouts.send#effective] 对照：服务端正常读完小请求体 → 成功', () async {
      final server = await _startServer((req, released) async {
        await req.drain<void>();
        req.response.write(_kPayload);
        await req.response.close();
      });
      final dio =
          _buildDio(server.baseUrl, const DiomanTimeouts(send: _kShort));

      final samples = await _sample(
          'send/对照',
          () => _run(dio,
              method: 'POST', data: Uint8List(_kUploadChunkBytes).toList()));

      for (final s in samples) {
        expect(s.type, isNull, reason: '全部样本: $samples');
        expect(s.status, 200, reason: '全部样本: $samples');
      }
    });

    test(
        '[DiomanTimeouts.receive#effective][DiomanTimeoutOptions.timeouts] 请求级收紧插件级：生效的是请求级的 150ms，而不是插件级的 10s',
        () async {
      final server = await _startServer(_stallAfterHeaders);
      final dio =
          _buildDio(server.baseUrl, const DiomanTimeouts(receive: _kBase));
      final perRequest = Options(extra: {
        DiomanTimeout.pluginName: const DiomanTimeoutOptions(
          timeouts: {NetworkQuality.poor: DiomanTimeouts(receive: _kShort)},
        ),
      });

      final samples =
          await _sample('receive/请求级收紧', () => _run(dio, options: perRequest));

      _expectTimedOut(samples, DioExceptionType.receiveTimeout, _kShort);
    });

    test(
        '[DiomanTimeouts.receive#effective][DiomanTimeoutOptions.timeouts] 请求级放宽插件级：插件级 150ms 本会超时，请求级 1200ms 让它成功',
        () async {
      // 服务端拖 400ms 才响应：大于插件级 150ms、小于请求级 1200ms。
      final server =
          await _startServer(_respondAfter(const Duration(milliseconds: 400)));
      final dio =
          _buildDio(server.baseUrl, const DiomanTimeouts(receive: _kShort));

      // 先证明不带请求级覆盖时确实超时，排除「服务端其实够快」。
      final base = await _sample('receive/请求级放宽-无覆盖', () => _run(dio));
      _expectTimedOut(base, DioExceptionType.receiveTimeout, _kShort);

      final perRequest = Options(extra: {
        DiomanTimeout.pluginName: const DiomanTimeoutOptions(
          timeouts: {NetworkQuality.poor: DiomanTimeouts(receive: _kLong)},
        ),
      });
      final samples = await _sample(
          'receive/请求级放宽-有覆盖', () => _run(dio, options: perRequest));

      for (final s in samples) {
        expect(s.type, isNull, reason: '全部样本: $samples');
        expect(s.status, 200, reason: '全部样本: $samples');
      }
    });
  });
}
