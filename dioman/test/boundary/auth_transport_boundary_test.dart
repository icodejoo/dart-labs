import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';
import 'package:test/test.dart';
import '../support/fixtures.dart';
import '../support/test_server.dart';

/// 触发 401 后重放的请求路径。
const _path = '/replay-body';

/// 初始的旧访问令牌。
const _old = 'old';

/// 刷新后换上的新访问令牌。
const _fresh = 'fresh';

/// 表单与 JSON 请求体共用的字段名。
const _field = 'value';

/// 注册重放传输与生命周期边界测试。
void main() {
  for (final multipart in [false, true]) {
    test('[DiomanAuth.onError] multipart=$multipart 请求体在服务器消费后完整重放', () async {
      final bodies = <String>[];
      final headers = <String?>[];
      final server = await TestServer.start((r) async {
        bodies.add(await utf8.decoder.bind(r).join());
        headers.add(r.headers.value('authorization'));
        await respondJson(r, {}, bodies.length == 1 ? 401 : 200);
      });
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      final handle = Dioman.install(dio,
          auth: DiomanAuth(
            tokenManager: TestTokens(_old),
            onRefresh: (manager, _) async =>
                (manager as TestTokens).set(_fresh),
            onAccessExpired: (_, __) async {},
          ));
      addTearDown(() async {
        handle.dispose();
        dio.close(force: true);
        await server.close();
      });
      final form = FormData.fromMap({
        _field: _old,
        'file': MultipartFile.fromString(_fresh, filename: 'payload.txt')
      });
      final result = await dio.post<void>(_path,
          data: multipart
              ? form
              : {
                  _field: [_old, _fresh]
                });
      expect(result.statusCode, 200);
      expect(bodies.length, 2);
      expect(headers, ['Bearer $_old', 'Bearer $_fresh']);
      if (multipart) {
        expect(form.isFinalized, isTrue);
        for (final body in bodies) {
          expect(body, contains('name="$_field"'));
          expect(body, contains(_old));
          expect(body, contains(_fresh));
          expect(body, contains('filename="payload.txt"'));
        }
      } else {
        expect(
            bodies.map(jsonDecode),
            everyElement({
              _field: [_old, _fresh]
            }));
      }
    });
  }

  test('[DiomanAuth.dio][DiomanAuth.dispose] 重放借用宿主转换器，解绑和释放后走兜底且宿主仍可请求',
      () async {
    var hits = 0;
    final server = await TestServer.start(
        (r) => respondJson(r, {}, ++hits % 2 == 1 ? 401 : 200));
    final transformer = CountingTransformer();
    final dio = Dio(BaseOptions(baseUrl: server.baseUrl))
      ..transformer = transformer;
    final auth = DiomanAuth(
        tokenManager: TestTokens(_old),
        onRefresh: (_, __) async {},
        onAccessExpired: (_, __) async {});
    dio.interceptors.add(auth);
    addTearDown(() async {
      auth.dispose();
      dio.close(force: true);
      await server.close();
    });
    auth.dio = dio;
    await dio.get<void>(_path);
    expect(transformer.responses, 2, reason: '初次请求与重放共用转换器');
    auth.dispose();
    await dio.get<void>(_path);
    expect(transformer.responses, 3,
        reason: 'dispose 解绑重放客户端，但宿主 adapter 仍可请求');
    auth.dio = null;
    await dio.get<void>(_path);
    expect(transformer.responses, 4, reason: '解绑后仅初次请求经过宿主转换器');
    auth.dispose();
    await dio.get<void>(_path);
    expect(transformer.responses, 5, reason: '释放兜底客户端后可以重新创建');
    expect(hits, 8);
  });

  test('[DiomanAuth.dispose] 释放时清刷新窗口引用，后续请求能启动新的刷新', () async {
    final started = Completer<void>();
    final release = Completer<void>();
    var refreshes = 0;
    final tokens = TestTokens(_old);
    final instant = DateTime.utc(2026);
    final server = await TestServer.start((r) => respondJson(r, {}, 200));
    final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
    final auth = DiomanAuth(
      tokenManager: tokens,
      expiresAt: (token) => token == _old ? instant : null,
      now: () => instant,
      onRefresh: (_, __) async {
        if (++refreshes == 1) {
          started.complete();
          await release.future;
        }
        tokens.set(_fresh);
      },
      onAccessExpired: (_, __) async {},
    );
    dio.interceptors.add(auth);
    addTearDown(() async {
      if (!release.isCompleted) release.complete();
      auth.dispose();
      dio.close(force: true);
      await server.close();
    });
    final pending = dio.get<void>(_path);
    await started.future;
    auth.dispose();
    await dio.get<void>(_path).timeout(const Duration(seconds: 3));
    expect(refreshes, 2, reason: '未等待释放前尚未完成的刷新窗口');
    release.complete();
    expect((await pending).statusCode, 200);
  });
}
