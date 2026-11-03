import '../support/b2_constants.dart';
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:dioman/dioman.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';

/// 请求短超时，明显小于服务端停顿。
const _short = Duration(milliseconds: 150);

/// 请求长超时，覆盖正常分块或延迟响应。
const _long = Duration(milliseconds: 1200);

/// 底层宽松超时。
const _base = Duration(seconds: 10);

/// 测试路径。
const _path = '/timeout';

/// 请求方法。
const _get = b2Get;

/// 服务端响应文本。
const _payload = 'ok';

/// 大上传的一块大小。
const _chunkSize = 64 * 1024;

/// 大上传块数，足够阻塞回环缓冲区。
const _chunks = 1024;

/// 一次真实回环请求的资源与结果。
class _Loop {
  /// 绑定 Dio 和服务器资源。
  _Loop(this.server, this.release, this.api);

  /// 真实监听套接字。
  final HttpServer server;

  /// 释放挂起处理器。
  final Completer<void> release;

  /// 新管线客户端。
  final Dioman<DiomanResponse<dynamic>> api;

  /// 创建服务器，错误只隔离客户端关闭导致的服务端写失败。
  static Future<_Loop> start(String mode, DiomanTimeouts tier) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final release = Completer<void>();
    server.listen((request) async {
      try {
        if (mode == b2HeadersMode) {
          request.response.bufferOutput = false;
          request.response.write(_payload);
          await request.response.flush();
          await release.future;
        } else if (mode == b2StallMode) {
          await release.future;
        } else if (mode == b2ChunksMode) {
          request.response.bufferOutput = false;
          for (var i = 0; i < 4; i++) {
            request.response.write(_payload);
            await request.response.flush();
            await Future<void>.delayed(const Duration(milliseconds: 100));
          }
          await request.response.close();
        } else {
          if (mode == b2DelayMode) {
            await Future<void>.delayed(const Duration(milliseconds: 400));
          } else {
            await request.drain<void>();
          }
          request.response.write(_payload);
          await request.response.close();
        }
      } on IOException {
        // 超时后客户端关闭套接字属于预期。
      }
    });
    final dio = Dio(BaseOptions(
        baseUrl: 'http://127.0.0.1:${server.port}',
        connectTimeout: _base,
        receiveTimeout: _base,
        sendTimeout: _base,
        responseType: ResponseType.plain));
    final api = Dioman(dio: dio, plugins: [
      DiomanTimeout(
          probe: () => NetworkQuality.poor,
          timeouts: {NetworkQuality.poor: tier})
    ]);
    final loop = _Loop(server, release, api);
    addTearDown(loop.close);
    return loop;
  }

  /// 释放全部真实 IO。
  Future<void> close() async {
    release.complete();
    api.dispose();
    api.dio.close(force: true);
    await server.close(force: true);
  }
}

/// 断言超时分类和实际经过的时长，排除即时失败冒充超时。
void _expectTimeout(
    DiomanResponse<dynamic> r, Stopwatch watch, Duration timeout) {
  expect(r.kind, DiomanKind.timeout);
  expect(watch.elapsed,
      greaterThanOrEqualTo(timeout - const Duration(milliseconds: 20)));
  expect(watch.elapsed, lessThan(timeout + const Duration(seconds: 2)));
}

/// 占满监听队列所需的最大连接尝试数。
const _maxFillAttempts = 512;

/// 探测队列是否已满的单次连接时限。
const _fillProbe = Duration(milliseconds: 300);

/// 握手完成前不返回的本地端点：监听但从不 accept，把队列占满后新的 SYN 会被丢弃。
class _SynBlackhole {
  /// 绑定监听套接字与已占位的连接。
  _SynBlackhole(this.server, this.held);

  /// 只监听不 accept 的套接字。
  final ServerSocket server;

  /// 用来占满队列的客户端连接。
  final List<Socket> held;

  /// 启动并占满队列；占不满（平台不丢 SYN）时返回 null。
  static Future<_SynBlackhole?> start() async {
    final server =
        await ServerSocket.bind(InternetAddress.loopbackIPv4, 0, backlog: 1);
    final held = <Socket>[];
    for (var i = 0; i < _maxFillAttempts; i++) {
      try {
        held.add(await Socket.connect(InternetAddress.loopbackIPv4, server.port,
            timeout: _fillProbe));
      } on SocketException {
        return _SynBlackhole(server, held);
      }
    }
    for (final s in held) {
      s.destroy();
    }
    await server.close();
    return null;
  }

  /// 释放全部套接字。
  Future<void> close() async {
    for (final s in held) {
      s.destroy();
    }
    await server.close();
  }
}

/// 通过新入口验证 Dio 实际执行补丁超时。
void main() {
  for (final mode in [b2HeadersMode, b2StallMode]) {
    test('[DiomanTimeouts.receive] $mode 停顿按插件值超时', () async {
      final loop =
          await _Loop.start(mode, const DiomanTimeouts(receive: _short));
      final watch = Stopwatch()..start();
      final r = await loop.api.send<Object?>(_get, _path);
      _expectTimeout(r, watch, _short);
      expect((r.error as DioException).type, DioExceptionType.receiveTimeout);
    });
  }
  test('[DiomanTimeouts.receive] 分块间隔小于超时即成功，总时长可超过超时', () async {
    const timeout = Duration(milliseconds: 250);
    final loop =
        await _Loop.start(b2ChunksMode, const DiomanTimeouts(receive: timeout));
    final watch = Stopwatch()..start();
    final r = await loop.api.send<String>(_get, _path);
    expect(r.data, _payload * 4);
    expect(r.ok, isTrue);
    expect(watch.elapsed, greaterThan(timeout));
  });
  test(
      '[DiomanCall.options][NetworkQuality.poor]'
      '[DiomanTimeoutOptions.timeouts] 请求级收紧接收时限实际生效', () async {
    final loop =
        await _Loop.start(b2HeadersMode, const DiomanTimeouts(receive: _base));
    final watch = Stopwatch()..start();
    final r = await loop.api.send<Object?>(_get, _path,
        call: DiomanCall(options: {
          DiomanTimeout.option: const DiomanTimeoutOptions(
              timeouts: {NetworkQuality.poor: DiomanTimeouts(receive: _short)})
        }));
    _expectTimeout(r, watch, _short);
  });
  test('[DiomanTimeoutOptions.timeouts] 请求级放宽接收时限实际生效', () async {
    final loop =
        await _Loop.start(b2DelayMode, const DiomanTimeouts(receive: _short));
    final failed = await loop.api.send<Object?>(_get, _path);
    expect(failed.kind, DiomanKind.timeout);
    final r = await loop.api.send<String>(_get, _path,
        call: DiomanCall(options: {
          DiomanTimeout.option: const DiomanTimeoutOptions(
              timeouts: {NetworkQuality.poor: DiomanTimeouts(receive: _long)})
        }));
    expect(r.ok, isTrue);
    expect(r.data, _payload);
  });
  test(
      '[DiomanCall.headers][DiomanCall.sendTimeout]'
      '[DiomanTimeouts.send] 发送缓冲阻塞时真实超时', () async {
    final loop =
        await _Loop.start(b2StallMode, const DiomanTimeouts(send: _short));
    final chunk = Uint8List(_chunkSize);
    final watch = Stopwatch()..start();
    final r = await loop.api.send<Object?>(b2Post, _path,
        data: Stream<List<int>>.fromIterable(
            Iterable.generate(_chunks, (_) => chunk)),
        call: const DiomanCall(
            headers: {Headers.contentLengthHeader: _chunkSize * _chunks}));
    _expectTimeout(r, watch, _short);
    expect((r.error as DioException).type, DioExceptionType.sendTimeout);
  });
  test('[DiomanTimeouts.send] 正常读取小请求体时成功', () async {
    final loop = await _Loop.start('read', const DiomanTimeouts(send: _short));
    final r = await loop.api.send<String>(b2Post, _path, data: [1, 2, 3]);
    expect(r.ok, isTrue);
    expect(r.data, _payload);
  });
  test('[DiomanTimeouts.connect] 握手不完成时按插件值报连接超时（底层 10s 被改写）', () async {
    final hole = await _SynBlackhole.start();
    if (hole == null) {
      markTestSkipped('本平台占满监听队列后仍不丢 SYN，无法构造握手不完成端点');
      return;
    }
    addTearDown(hole.close);
    final dio = Dio(BaseOptions(
        baseUrl: 'http://127.0.0.1:${hole.server.port}',
        connectTimeout: _base,
        receiveTimeout: _base,
        sendTimeout: _base));
    final api = Dioman(dio: dio, plugins: [
      DiomanTimeout(probe: () => NetworkQuality.poor, timeouts: {
        NetworkQuality.poor: const DiomanTimeouts(connect: _short)
      })
    ]);
    addTearDown(() {
      api.dispose();
      dio.close(force: true);
    });
    final watch = Stopwatch()..start();
    final r = await api.send<Object?>(_get, _path);
    _expectTimeout(r, watch, _short);
    expect((r.error as DioException).type, DioExceptionType.connectionTimeout);
  });
}
