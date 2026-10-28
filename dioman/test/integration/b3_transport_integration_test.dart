import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dioman/pipeline.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';
import '../support/pipeline/b3_helpers.dart';
import '../support/pipeline/fake_clock.dart';
import '../support/pipeline/helpers.dart';

/// 真实回环服务收到的标量载荷。
const _payload = 'transport payload';

/// 回环测试响应的成功载荷。
const _response = '{"code":0,"data":"done"}';

/// multipart 测试的字段名。
const _field = 'upload';

/// 验证真实传输复用、载荷重发和管理 API 动态装配。
void main() {
  test('[DiomanAuth.setup] 同配置不同客户端刷新窗口隔离，dispose 后新客户端正常刷新', () async {
    final tm = TestTokens();
    final gates = List.generate(2, (_) => Completer<void>());
    final starts = List.generate(2, (_) => Completer<void>());
    var calls = 0;
    final auth = b3Auth(tm, refresh: (tokens, r) async {
      final index = calls++;
      starts[index].complete();
      await gates[index].future;
      tokens.setTokens(accessToken: b3Fresh);
    });
    final source = TestPlugin(b3ValueResult,
        stage: DiomanStage.source,
        handler: (ctx, next) async => ctx.request.headers[b3Header] ==
                'Bearer $b3Old'
            ? ctx.fail(const DiomanFailure(kind: DiomanKind.http, status: 401))
            : next());
    final a = testClient(plugins: [auth, source]);
    final b = testClient(plugins: [auth, source]);
    final first = a.send<Object?>(b3ValueGet, b3Path);
    await starts[0].future;
    final second = b.send<Object?>(b3ValueGet, b3Path);
    await starts[1].future;
    expect(calls, 2);
    a.dispose();
    expect((await first).kind, DiomanKind.cancel);
    await expectLater(a.send<Object?>(b3ValueGet, b3Path), throwsStateError);
    gates[0].complete();
    gates[1].complete();
    expect((await second).ok, isTrue);
    b.dispose();
  });
  test('[DiomanNext] JSON FormData Stream 重发复用宿主 adapter，不关闭宿主', () async {
    for (final auth in [false, true]) {
      for (final bodyKind in [b3ValueData, _field, b3ValueResult]) {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final bodies = <String>[];
        final headers = <String?>[];
        server.listen((request) async {
          bodies.add(await utf8.decoder.bind(request).join());
          headers.add(request.headers.value(HttpHeaders.authorizationHeader));
          request.response.statusCode = bodies.length == 1
              ? auth
                  ? 401
                  : 500
              : 200;
          request.response.headers.contentType = ContentType.json;
          request.response.write(_response);
          await request.response.close();
        });
        final clock = FakeClock();
        final logs = <String>[];
        final dio = Dio(BaseOptions(
            baseUrl: 'http://${server.address.address}:${server.port}'));
        final api =
            Dioman<Result>(dio: dio, clock: clock, debug: logs.add, plugins: [
          if (auth)
            b3Auth(TestTokens())
          else
            const DiomanRetry(max: 1, methods: [b3ValuePost5]),
        ]);
        Object data;
        if (bodyKind == _field) {
          data = FormData.fromMap(
              {_field: MultipartFile.fromString(_payload, filename: _field)});
        } else if (bodyKind == b3ValueResult) {
          data = Stream<List<int>>.multi((sink) {
            sink.add(utf8.encode(_payload));
            sink.close();
          });
        } else {
          data = {_field: _payload};
        }
        final pending = api.send<Object?>(b3ValuePost5, b3Path, data: data);
        if (!auth) {
          while (clock.pendingTimers == 0) {
            await b3Turn();
          }
          clock.elapse(const Duration(seconds: 3));
        }
        expect((await pending).ok, isTrue);
        expect(bodies, hasLength(2));
        expect(bodies.every((s) => s.contains(_payload)), isTrue);
        if (auth) expect(headers, ['Bearer $b3Old', 'Bearer $b3Fresh']);
        expect(logs.any((s) => s.contains('无法克隆')), bodyKind == b3ValueResult);
        expect((await dio.get<dynamic>(b3Path)).statusCode, 200);
        api.dispose();
        await server.close(force: true);
      }
    }
  });
  test('[DiomanRetry.respectRetryAfter] 真实 429 503 秒数与日期通过 DiomanClock 等待',
      () async {
    for (final date in [false, true]) {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      var sends = 0;
      server.listen((request) async {
        await request.drain<void>();
        sends++;
        if (sends == 1) {
          request.response.statusCode = date ? 503 : 429;
          request.response.headers.set(HttpHeaders.retryAfterHeader,
              date ? b3ValueThu01Jan1970000002Gmt : '2');
        }
        request.response.headers.contentType = ContentType.json;
        request.response.write(_response);
        await request.response.close();
      });
      final clock = FakeClock();
      final api = Dioman<Result>(
          dio: Dio(BaseOptions(
              baseUrl: 'http://${server.address.address}:${server.port}')),
          clock: clock,
          plugins: [const DiomanRetry(max: 1)]);
      final pending = api.send<Object?>(b3ValueGet, b3Path);
      while (clock.pendingTimers == 0) {
        await b3Turn();
      }
      expect(sends, 1);
      clock.elapse(b3Tick);
      await b3Turn();
      expect(sends, 1);
      clock.elapse(b3Tick);
      expect((await pending).ok, isTrue);
      expect(sends, 2);
      api.dispose();
      await server.close(force: true);
    }
  });
  test('[Dioman.use × DiomanBreakerApi.stateOf] 插入移除替换熔断器使用新实例，dispose 拒绝复活',
      () async {
    final clock = FakeClock();
    var sends = 0;
    final api = testClient(clock: clock, plugins: [
      const DiomanRetry(max: 2),
      TestPlugin(b3ValueResult, stage: DiomanStage.source,
          handler: (ctx, next) async {
        sends++;
        return ctx.fail(const DiomanFailure(kind: DiomanKind.network));
      })
    ]);
    api.use(const DiomanBreaker(failureThreshold: 1));
    final old = api.plugin<DiomanBreakerApi>()!;
    expect((await b3Finish(api.send<Object?>(b3ValueGet, b3Path), clock)).kind,
        DiomanKind.breaker);
    expect(sends, 1);
    expect(api.eject(DiomanBreaker.pluginName), isTrue);
    expect(old.bucketCount, 0);
    expect((await b3Finish(api.send<Object?>(b3ValueGet, b3Path), clock)).kind,
        DiomanKind.network);
    expect(sends, 4);
    api.use(const DiomanBreaker(failureThreshold: 2));
    expect(identical(api.plugin<DiomanBreakerApi>(), old), isFalse);
    expect((await b3Finish(api.send<Object?>(b3ValueGet, b3Path), clock)).kind,
        DiomanKind.breaker);
    expect(sends, 6);
    api.dispose();
    await expectLater(api.send<Object?>(b3ValueGet, b3Path), throwsStateError);
  });
}
