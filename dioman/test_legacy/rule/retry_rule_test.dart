// ignore_for_file: avoid_relative_lib_imports
// 规则层：retry
import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';
import 'package:test/test.dart';
import '../../test/accept/lib/literals.dart';
import '../../test/support/fixtures.dart';
import '../../test/support/test_server.dart';

/// 注册本文件的规则层用例。
void main() {
  const timeout = Duration(seconds: 3);

  group(tk9, () {
    test('[DiomanRetry.onRequest] retry 的重试走宿主的 adapter 和 transformer',
        () async {
      final transformer = CountingTransformer();
      final adapter = RecordingAdapter(
          (o, n) async => n == 1 ? jsonBody({}, 500) : jsonBody({tkV: n}, 200));
      final dio = fakeDio(adapter, transformer: transformer);
      Dioman.install(dio, retry: testRetry());

      final r = await dio.get<dynamic>(tkX).timeout(timeout);
      expect(r.data, {tkV: 2});
      expect(adapter.calls, 2);
      expect(transformer.responses, 2);
    });
  });

  group('DiomanRetry: business-failure loop exhaustion and error-path gates',
      () {
    test(
        '[DiomanRetry.delay][DiomanRetry.max] when every retry attempt still looks like a business failure, '
        'the retry loop exhausts and propagates the LAST attempt as-is',
        () async {
      var attempts = 0;
      final server = await TestServer.start((req) async {
        attempts++;
        return respondJson(req, {tkCode: 1, tkAttempt: attempts}, 200);
      });
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      dio.interceptors.add(DiomanRetry(
        max: 2,
        delay: (_, __, ___, ____) => Duration.zero,
        shouldRetry: (err, response) => (response?.data as Map)[tkCode] != 0,
      ));

      final r = await dio.get<Map<String, dynamic>>(tkData2);
      expect(attempts, 3, reason: 'original + 2 retries, all exhausted');
      expect(r.data![tkCode], 1,
          reason: 'gives up and returns the last (still-failing) attempt '
              'rather than throwing');
    });
    test(
        '[DiomanRetry.delay][DiomanRetry.enabled] a constructor-disabled DiomanRetry never intercepts a network '
        'error at all', () async {
      var attempts = 0;
      final server = await TestServer.start((req) async {
        attempts++;
        return respondJson(req, {tkFail: true}, 500);
      });
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      dio.interceptors.add(DiomanRetry(
          max: 2, delay: (_, __, ___, ____) => Duration.zero, enabled: false));

      await expectLater(
        dio.get<void>(tkData2),
        throwsA(isA<DioException>()),
      );
      expect(attempts, 1, reason: 'disabled ⇒ no retry attempted');
    });
    test(
        '[DiomanRetry.shouldRetry][DiomanRetryOptions.shouldRetry] an error shouldRetry rejects (e.g. a plain 404) is passed straight '
        'through without retrying', () async {
      var attempts = 0;
      final server = await TestServer.start((req) async {
        attempts++;
        return respondJson(req, {tkFail: true}, 404);
      });
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      dio.interceptors
          .add(DiomanRetry(max: 2, delay: (_, __, ___, ____) => Duration.zero));

      await expectLater(
        dio.get<void>(tkData2),
        throwsA(isA<DioException>()
            .having((e) => e.response?.statusCode, 'statusCode', 404)),
      );
      expect(attempts, 1,
          reason: '404 is not >=500 (and not a timeout/connectionError) — '
              "the default shouldRetry doesn't match it");
    });
  });

  group(tkDiomanRetry, () {
    test(
        '[DiomanRetry.enabled][DiomanRetryOptions.enabled] DiomanRetryOptions(enabled: false) is honoured on the business-retry '
        '(onResponse) path, not just the network-error path', () async {
      var calls = 0;
      final server = await TestServer.start((req) async {
        calls++;
        await respondJson(req, {tkCode: 1}, 200);
      });
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      dio.interceptors.add(DiomanRetry(
        max: 3,
        shouldRetry: (err, response) => (response?.data as Map)[tkCode] != 0,
      ));

      final res = await dio.get<Map<String, dynamic>>(
        tkData2,
        options: Options(
            extra: {tkDiomanRetry2: const DiomanRetryOptions(enabled: false)}),
      );

      expect(res.data![tkCode], 1);
      expect(calls, 1,
          reason:
              'enabled:false must skip business-level retry, not just network retry');
    });
  });

  group(tkNewlyWiredOptionsFieldsFullConstructorOptionsParity, () {
    test(
        '[DiomanRetry.shouldRetry][DiomanRetryOptions.shouldRetry] DiomanRetryOptions.shouldRetry overrides the plugin default network '
        'retry check for a single call', () async {
      var calls = 0;
      final server = await TestServer.start((req) async {
        calls++;
        // Not in [200,300) → dio's default validateStatus rejects it and
        // synthesizes a DioException(type: badResponse) for onError.
        await respondJson(req, {}, 418);
      });
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      dio.interceptors.add(DiomanRetry(
        max: 2,
        delay: (_, __, ___, ____) => Duration.zero,
      )); // default shouldRetry ignores 418

      await expectLater(
        dio.get<void>(
          tkX,
          options: Options(
            extra: {
              tkDiomanRetry2:
                  DiomanRetryOptions(shouldRetry: (err, response) => true)
            },
          ),
        ),
        throwsA(isA<DioException>()),
      );

      expect(calls, 3,
          reason: 'a per-request shouldRetry that accepts 418 must '
              'drive max+1 attempts, even though the plugin default would not '
              'retry a 418 at all');
    });
  });

  test(
      '[DiomanRetry.jitter][DiomanRetryOptions.jitter] retry Retry-After 数字、日期、非法日期及 jitter 各自生效',
      () async {
    for (final header in [
      '0',
      '-1',
      'Wed, 21 Oct 2026 07:28:00 GMT',
      'Wed, 21 Xxx 2026 07:28:00 GMT',
      'invalid'
    ]) {
      var hits = 0;
      final server = await TestServer.start((request) async {
        request.response.headers.set('Retry-After', header);
        await respondJson(request, {}, ++hits == 1 ? 500 : 200);
      });
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      final handle = Dioman.install(dio,
          retry: DiomanRetry(
              max: 1,
              afterStatusCodes: [500],
              delayMax: Duration.zero,
              retryAfterMax: Duration.zero));
      try {
        expect((await dio.get<dynamic>(replayPath)).statusCode, 200);
        expect(hits, 2);
      } finally {
        handle.dispose();
        dio.close(force: true);
        await server.close();
      }
    }
    for (final jitter in <Object>[
      true,
      (Duration raw) => const Duration(milliseconds: -1),
      (Duration raw) => Duration.zero
    ]) {
      var hits = 0;
      final server = await TestServer.start(
          (request) async => respondJson(request, {}, ++hits == 1 ? 500 : 200));
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      final handle = Dioman.install(dio,
          retry: DiomanRetry(
              max: 1,
              delay: (_, __, ___, ____) => replayTick,
              jitter: jitter,
              delayMax: Duration.zero));
      try {
        expect((await dio.get<dynamic>(replayPath)).statusCode, 200);
        expect(hits, 2);
      } finally {
        handle.dispose();
        dio.close(force: true);
        await server.close();
      }
    }
  });
}
