// ignore_for_file: avoid_relative_lib_imports
// 规则层：share
import 'dart:async';
import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';
import 'package:test/test.dart';
import '../../accept/lib/literals.dart';
import '../support/fixtures.dart';
import '../support/test_server.dart';

/// 注册本文件的规则层用例。
void main() {
  group('DiomanShare policy: end', () {
    test(
        '[DiomanShare.policy][DiomanShareOptions.policy] only the LATEST (highest-seq) response settles the shared '
        'promise — an earlier, superseded caller for the same key gets '
        'redirected to that result instead of its own', () async {
      final aStarted = Completer<void>();
      final releaseA = Completer<void>();
      var calls = 0;
      final server = await TestServer.start((req) async {
        calls++;
        if (calls == 1) {
          aStarted.complete();
          await releaseA.future;
          return respondJson(req, {tkV: 'a-stale'}, 200);
        }
        return respondJson(req, {tkV: tkBLatest}, 200);
      });
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      dio.interceptors.add(const DiomanKey());
      dio.interceptors.add(DiomanShare(policy: DiomanSharePolicy.end));

      final a = dio.get<Map<String, dynamic>>(tkData2);
      await aStarted.future;
      final b = await dio
          .get<Map<String, dynamic>>(tkData2)
          .timeout(const Duration(seconds: 3));
      releaseA.complete();
      final aResult = await a.timeout(const Duration(seconds: 3));

      expect(b.data, {tkV: tkBLatest});
      expect(aResult.data, {tkV: tkBLatest},
          reason: 'a is superseded by b (higher seq) — it gets redirected '
              "to b's result instead of its own stale one");
    });
    test(
        '[DiomanShare.policy][DiomanShareOptions.policy] a solo caller (no supersession) just settles with its own '
        'result', () async {
      final server =
          await TestServer.start((req) => respondJson(req, {tkV: 1}, 200));
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      dio.interceptors.add(const DiomanKey());
      dio.interceptors.add(DiomanShare(policy: DiomanSharePolicy.end));

      final r = await dio.get<Map<String, dynamic>>(tkData2);
      expect(r.data, {tkV: 1});
    });
  });

  group('DiomanShare policy: race', () {
    test(
        '[DiomanShare.policy][DiomanShareOptions.policy] the first attempt to SUCCEED wins for everyone, including a '
        "slower attempt that's still in flight", () async {
      final slowStarted = Completer<void>();
      final releaseSlow = Completer<void>();
      var calls = 0;
      final server = await TestServer.start((req) async {
        calls++;
        if (calls == 1) {
          slowStarted.complete();
          await releaseSlow.future;
          return respondJson(req, {tkV: 'slow'}, 200);
        }
        return respondJson(req, {tkV: tkFast}, 200);
      });
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      dio.interceptors.add(const DiomanKey());
      dio.interceptors.add(DiomanShare(policy: DiomanSharePolicy.race));

      final slow = dio.get<Map<String, dynamic>>(tkData2);
      await slowStarted.future;
      final fast = await dio
          .get<Map<String, dynamic>>(tkData2)
          .timeout(const Duration(seconds: 3));
      releaseSlow.complete();
      final slowResult = await slow.timeout(const Duration(seconds: 3));

      expect(fast.data, {tkV: tkFast});
      expect(slowResult.data, {tkV: tkFast},
          reason: "the slow attempt lost the race — it's redirected to the "
              "fast attempt's winning result");
    });
  });

  group(
      'DiomanShare: none policy, own-failure settlement, dispose, '
      'hasMultipleDownstreamSettlers', () {
    test(
        '[DiomanShare.policy][DiomanShareOptions.policy] without DiomanKey installed, share is a no-op — every call is '
        'independent', () async {
      var calls = 0;
      final server = await TestServer.start((req) async {
        calls++;
        await respondJson(req, {tkV: 1}, 200);
      });
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      dio.interceptors.add(DiomanShare(policy: DiomanSharePolicy.start));

      await Future.wait([dio.get<void>(tkData2), dio.get<void>(tkData2)]);
      expect(calls, 2, reason: 'no key ⇒ share never dedupes');
    });
    test(
        '[DiomanShare.policy][DiomanShare.onError] policy: none passes every request through independently — never '
        'shared, and errors reach onError with no entry attached', () async {
      var calls = 0;
      final server = await TestServer.start((req) async {
        calls++;
        return respondJson(req, {tkFail: true}, 500);
      });
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      dio.interceptors.add(const DiomanKey());
      dio.interceptors.add(DiomanShare(policy: DiomanSharePolicy.none));

      await expectLater(dio.get<void>(tkData2), throwsA(isA<DioException>()));
      await expectLater(dio.get<void>(tkData2), throwsA(isA<DioException>()));
      expect(calls, 2, reason: 'policy none never dedupes');
    });
    test(
        '[DiomanShare.policy][DiomanShareOptions.policy] policy: end — a SOLO caller (matching seq, not superseded) whose '
        'own request fails settles the entry with that failure', () async {
      final server = await TestServer.start(
          (req) => respondJson(req, {tkFail: true}, 500));
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      dio.interceptors.add(const DiomanKey());
      dio.interceptors.add(DiomanShare(policy: DiomanSharePolicy.end));

      await expectLater(
        dio.get<Map<String, dynamic>>(tkData2),
        throwsA(isA<DioException>()),
      );
    });
    test(
        '[DiomanShare.registerDownstreamSettler] registerDownstreamSettler(): a single registration is not '
        '"multiple"; a second one is', () {
      final share = DiomanShare();
      expect(share.hasMultipleDownstreamSettlers, isFalse);
      share.registerDownstreamSettler();
      expect(share.hasMultipleDownstreamSettlers, isFalse);
      share.registerDownstreamSettler();
      expect(share.hasMultipleDownstreamSettlers, isTrue);
    });
    test(
        '[DiomanShare.settle][DiomanShare.policy] settle() explicitly completes an entry with an error, and removes '
        'it so a later caller for the same key starts fresh', () async {
      final started = Completer<void>();
      var attempts = 0;
      final server = await TestServer.start((req) async {
        attempts++;
        if (attempts == 1) {
          started.complete();
          await Completer<void>().future; // leader hangs forever
        }
        await respondJson(req, {tkV: tkLater}, 200);
      });
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      dio.interceptors.add(const DiomanKey());
      final share = DiomanShare(policy: DiomanSharePolicy.start);
      dio.interceptors.add(share);

      final leader = dio.get<void>(tkData2);
      leader.ignore(); // never settles through the normal path in this test
      await started.future;
      final keyOptions = RequestOptions(path: tkData2, baseUrl: server.baseUrl);
      const DiomanKey().onRequest(keyOptions, RequestInterceptorHandler());
      share.settle(keyOptions.extra[kKey] as String,
          error: DioException(
              requestOptions: RequestOptions(path: tkData2),
              message: 'forced'));
      // A later, independent caller for the same key must not find a stale
      // entry — settle() removed it, so this is a genuinely fresh request.
      final r = await dio
          .get<Map<String, dynamic>>(tkData2)
          .timeout(const Duration(seconds: 3));
      expect(r.data, {tkV: tkLater});
    });
  });

  group(tkDiomanShare, () {
    test(
        '[DiomanShare.policy][DiomanShare.retries] policy=retry: with retries available, a successful retry resolves '
        "through the internal throwaway Dio hitting the real test server "
        '(this success path could only be exercised offline via a failure '
        'before — see note above)', () async {
      var attempt = 0;
      final server = await TestServer.start((req) async {
        attempt++;
        if (attempt == 1) {
          await respondJson(req, {tkFail: true}, 500);
        } else {
          await respondJson(req, {tkOk: true, tkAttempt: attempt}, 200);
        }
      });
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      dio.interceptors.addAll([
        const DiomanKey(),
        DiomanShare(policy: DiomanSharePolicy.retry, retries: 2),
      ]);

      final res = await dio
          .get<Map<String, dynamic>>('/shared-ok')
          .timeout(const Duration(seconds: 5));

      expect(res.data![tkOk], true,
          reason: 'the internal retry Dio must be able to reach the real '
              'server and deliver the eventual success to the caller');
      expect(attempt, 2,
          reason: 'one failed attempt, then one successful internal retry');
    });
    test(
        '[DiomanShare.policy][DiomanShareOptions.policy] policy=race: a caller whose own request failed still gets the '
        'winning sibling\'s successful result', () async {
      final loserStarted = Completer<void>();
      final server = await TestServer.start((req) async {
        final id = int.parse(req.headers.value('x-test-id')!);
        if (id == 1) {
          loserStarted.complete();
          // Let the winner (id 2) settle the shared completer first.
          await Future<void>.delayed(const Duration(milliseconds: 50));
          req.response.statusCode = 500;
          await req.response.close();
          return;
        }
        await loserStarted.future;
        await respondJson(req, {tkWinner: true}, 200);
      });
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      dio.interceptors.addAll([
        const DiomanKey(),
        DiomanShare(policy: DiomanSharePolicy.race),
      ]);

      final loser = dio.get<Map<String, dynamic>>(
        tkData2,
        options: Options(headers: {tkXTestId: tk1}),
      );
      final winner = dio.get<Map<String, dynamic>>(
        tkData2,
        options: Options(headers: {tkXTestId: tk2}),
      );

      final results = await Future.wait([loser, winner])
          .timeout(const Duration(seconds: 5));

      expect(results[0].data![tkWinner], true,
          reason: 'the caller whose own request errored must still receive '
              "the sibling's successful response, per SharePolicy.race");
      expect(results[1].data![tkWinner], true);
    });
  });

  group(tkPerRequestOptionsOverrides, () {
    test(
        '[DiomanShare.enabled][DiomanShareOptions.enabled] DiomanShareOptions(enabled: false) bypasses dedup for that request',
        () async {
      var calls = 0;
      final server = await TestServer.start((req) async {
        calls++;
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await respondJson(req, {}, 200);
      });
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      dio.interceptors.addAll([const DiomanKey(), DiomanShare()]);

      await Future.wait([
        dio.get<void>(tkX),
        dio.get<void>(
          tkX,
          options: Options(extra: {
            tkDiomanShare2: const DiomanShareOptions(enabled: false)
          }),
        ),
      ]);

      expect(calls, 2, reason: 'the opted-out call must issue its own request');
    });
  });

  test(
      '[DiomanSharePolicy.end][DiomanShare.policy] share end 的旧成功在最新调用失败时收到同一个失败',
      () async {
    final plugin = DiomanShare(policy: DiomanSharePolicy.end);
    final first = RequestOptions(path: replayPath, extra: {kKey: replayPath});
    final last = RequestOptions(path: replayPath, extra: {kKey: replayPath});
    plugin.onRequest(first, RequestInterceptorHandler());
    plugin.onRequest(last, RequestInterceptorHandler());
    final oldHandler = ResponseInterceptorHandler();
    final check = expectLater(handlerCompletion(oldHandler), throwsA(anything));
    plugin.onResponse(Response<dynamic>(requestOptions: first), oldHandler);
    plugin.settle(replayPath,
        error: DioException(requestOptions: last, message: replayFailure));
    await check;
    plugin.dispose();
  });

  group('DiomanShare', () {
    test(
        '[DiomanShare.policy][DiomanSharePolicy.end] '
        'policy=end: every caller — including superseded ones — receives '
        'the LAST request\'s result', () async {
      final server = await TestServer.start((req) async {
        final n = int.parse(req.headers.value('x-test-seq')!);
        await respondJson(req, {'seq': n}, 200);
      });
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      dio.interceptors.addAll([
        const DiomanKey(),
        DiomanShare(policy: DiomanSharePolicy.end),
      ]);

      final first = dio.get<Map<String, dynamic>>(
        tkData2,
        options: Options(headers: {'X-Test-Seq': tk1}),
      );
      final second = dio.get<Map<String, dynamic>>(
        tkData2,
        options: Options(headers: {'X-Test-Seq': tk2}),
      );

      final results = await Future.wait([first, second])
          .timeout(const Duration(seconds: 5));

      expect(results[0].data!['seq'], 2,
          reason: 'the superseded first caller must get the last response');
      expect(results[1].data!['seq'], 2);
    });
  });

  group('DiomanShare policy: race', () {
    test(
        '[DiomanShare.policy][DiomanSharePolicy.race] '
        'only once every in-flight attempt has failed does the race '
        'settle as a failure for everyone', () async {
      final server = await TestServer.start(
          (req) => respondJson(req, {tkFail: true}, 500));
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      dio.interceptors.add(const DiomanKey());
      dio.interceptors.add(DiomanShare(policy: DiomanSharePolicy.race));

      await expectLater(
        dio.get<Map<String, dynamic>>(tkData2),
        throwsA(isA<DioException>()),
      );
    });
  });
}
