// ignore_for_file: avoid_relative_lib_imports
// 边界层：share
import 'dart:async';
import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';
import 'package:dioman/src/request_claims.dart';
import 'package:test/test.dart';
import '../../test/accept/lib/literals.dart';
import '../../test/support/fixtures.dart';
import '../../test/support/test_server.dart';

/// 注册本文件的边界层用例。
void main() {
  test('[DiomanShare.onRequest] share 首发取消后由存活跟随者接手', () async {
    final entered = Completer<void>();
    final server = await TestServer.start((r) async {
      if (!entered.isCompleted) entered.complete();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await respondJson(
          r,
          {
            tkCode: 0,
            tkData: {tkOk: true}
          },
          200);
    });
    final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
    final handle = Dioman.install(dio,
        key: const DiomanKey(),
        share: DiomanShare(),
        normalize: const DiomanNormalize());
    addTearDown(() async {
      handle.dispose();
      dio.close(force: true);
      await server.close();
    });
    final token = CancelToken();
    final leader = dio.get<dynamic>(tkShared, cancelToken: token);
    final leaderCheck = expectLater(leader, throwsA(isA<DioException>()));
    await entered.future;
    final follower = dio.get<dynamic>(tkShared);
    await Future<void>.delayed(const Duration(milliseconds: 15));
    token.cancel();
    await leaderCheck;
    expect((await follower).data, {tkOk: true});
  });

  const timeout = Duration(seconds: 3);

  group(tkEndRace5, () {
    for (final policy in [DiomanSharePolicy.end, DiomanSharePolicy.race]) {
      test(
          '[DiomanShare.policy][DiomanShareOptions.policy] policy=${policy.name}：所有请求都失败时每个调用方都拿到 DioException，'
          '不抛 NoSuchMethodError，registry 归零', () async {
        final gates = <Completer<void>>[];
        var fail = true;
        final adapter = RecordingAdapter((o, n) async {
          if (!fail) return jsonBody({tkV: n}, 200);
          final g = Completer<void>();
          gates.add(g);
          await g.future;
          return jsonBody({tkE: n}, 500);
        });
        final dio = fakeDio(adapter);
        Dioman.install(dio,
            key: const DiomanKey(), share: DiomanShare(policy: policy));

        final a = dio.get<dynamic>(tkX);
        final b = dio.get<dynamic>(tkX);
        final ra = a.then<Object>((_) => tkOk, onError: (Object e) => e);
        final rb = b.then<Object>((_) => tkOk, onError: (Object e) => e);
        await settleAsync();
        expect(adapter.calls, 2);
        gates[0].complete(); // 先失败的是旧请求/先到的竞争者，需等最终结果
        await settleAsync();
        gates[1].complete();

        final results = await Future.wait([ra, rb]).timeout(timeout);
        for (final r in results) {
          expect(r, isA<DioException>());
          expect((r as DioException).response?.statusCode, 500);
        }
        fail = false;
        final c = await dio.get<dynamic>(tkX).timeout(timeout);
        expect(c.data, isNotNull, reason: 'registry 已归零，新请求是全新请求');
      });
    }
  });

  group(
      'DiomanShare: none policy, own-failure settlement, dispose, '
      'hasMultipleDownstreamSettlers', () {
    test(
        '[DiomanShare.policy][DiomanShareOptions.policy][DiomanShare.dispose] dispose() completes a pending follower with an error instead of '
        'leaving it hanging (documented previously as NOT doing this — '
        'confirmed fixed)', () async {
      final started = Completer<void>();
      final server = await TestServer.start((req) async {
        started.complete();
        await Completer<void>().future; // hangs
      });
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      dio.interceptors.add(const DiomanKey());
      final share = DiomanShare(policy: DiomanSharePolicy.start);
      dio.interceptors.add(share);

      final leader = dio.get<void>(tkData2);
      leader.ignore();
      await started.future;
      final follower = dio.get<void>(tkData2);
      share.dispose();
      await expectLater(follower, throwsA(isA<DioException>()));
    });
  });

  group(tkDiomanShare, () {
// SharePolicy.retry's internal re-issue deliberately uses a throwaway
// `Dio()` (see SKILL.md) so it never re-enters this chain. Against a
// real TestServer that throwaway Dio's `.fetch()` still lands on our
// test server (RequestOptions carries its own already-resolved
// baseUrl), so both the exhausted-retry give-up path AND the
// successful-retry path are now directly observable — see the two
// tests below.
//
// NOTE: the first test below only issues a solo request, not a
// concurrent leader+follower pair. While investigating this fix a
// SEPARATE, pre-existing issue surfaced (present in the original code
// too, verified via `git stash`): a concurrent follower attached via
// `_handleStart` (onRequest's `RequestInterceptorHandler.reject`) hangs
// forever when the shared request ultimately errors — the follower's
// own dio.get() never settles, even though the leader and the shared
// completer both settle correctly. That looks like a dio
// interceptor-zone interaction distinct from anything in this review;
// flagged separately, not fixed here.
    test(
        '[DiomanShare.policy][DiomanShare.retries] policy=retry: a solo request is settled with the error (no hang) '
        'once retries are exhausted, and the entry is cleared so a later '
        'request with the same key hits the network again', () async {
      var calls = 0;
      final server = await TestServer.start((req) async {
        calls++;
        await respondJson(req, {tkFail: true}, 500);
      });
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      dio.interceptors.addAll([
        const DiomanKey(),
        DiomanShare(policy: DiomanSharePolicy.retry, retries: 0),
      ]);

      await expectLater(
        dio.get<void>(tkShared).timeout(const Duration(seconds: 5)),
        throwsA(isA<DioException>()),
        reason: 'must settle with the error, not hang',
      );

      final callsBefore = calls;
      await expectLater(dio.get<void>(tkShared), throwsA(isA<DioException>()));
      expect(calls, greaterThan(callsBefore),
          reason: 'the settled entry must have been removed from `_active`; '
              'a dangling entry would silently reuse the old dead completer '
              'instead of ever hitting the network again');
    });
  });

  test('[DiomanShare.policy][DiomanShare.retries] share 重放准备抛异常时首发与跟随者都结算',
      () async {
    final form = BrokenCloneForm();
    await form.finalize().drain<void>();
    final plugin = DiomanShare(policy: DiomanSharePolicy.retry, retries: 1);
    final leader =
        RequestOptions(path: replayPath, data: form, extra: {kKey: replayPath});
    final follower =
        RequestOptions(path: replayPath, extra: {kKey: replayPath});
    final joined = RequestInterceptorHandler();
    plugin.onRequest(leader, RequestInterceptorHandler());
    plugin.onRequest(follower, joined);
    handlerCompletion(joined).ignore();
    final handler = ErrorInterceptorHandler();
    final check = expectLater(handlerCompletion(handler), throwsA(anything));
    try {
      plugin.onError(
          DioException(
              requestOptions: leader, type: DioExceptionType.connectionError),
          handler);
      await check;
      expect(claimsOf(leader)!.isFinished, isTrue,
          reason: '首发失败也必须结算共享认领，不能把跟随者留在等待中');
      await expectLater(handlerCompletion(joined).timeout(replayTick),
          throwsA(predicate<Object>((error) => error is! TimeoutException)));
    } finally {
      plugin.dispose();
    }
  });

  test('[DiomanShare.onRequest] share 显式结算响应与无参数摘除都允许下一轮重新发起', () async {
    final plugin = DiomanShare();
    for (final resolve in [false, true]) {
      final leader =
          RequestOptions(path: replayPath, extra: {kKey: replayPath});
      final leaderHandler = RequestInterceptorHandler();
      plugin.onRequest(leader, leaderHandler);
      await handlerCompletion(leaderHandler);
      if (resolve) {
        final followerHandler = RequestInterceptorHandler();
        plugin.onRequest(
            RequestOptions(path: replayPath, extra: {kKey: replayPath}),
            followerHandler);
        plugin.settle(replayPath,
            response:
                Response<dynamic>(requestOptions: leader, data: replayField));
        expect(
            ((await handlerCompletion(followerHandler)).data as Response).data,
            replayField);
      } else {
        plugin.settle(replayPath);
      }
    }
    plugin.dispose();
  });

  test('[DiomanSharePolicy.race][DiomanShare.policy] share race 已胜出时认领预检返回胜出结果',
      () async {
    final plugin = DiomanShare(policy: DiomanSharePolicy.race);
    final first = RequestOptions(path: replayPath, extra: {kKey: replayPath});
    final last = RequestOptions(path: replayPath, extra: {kKey: replayPath});
    plugin.onRequest(first, RequestInterceptorHandler());
    plugin.onRequest(last, RequestInterceptorHandler());
    plugin.settle(replayPath,
        response: Response<dynamic>(requestOptions: first, data: replayField));
    final winner = await claimsOf(last)!.checkLoser!()!;
    expect(winner.data, replayField);
    expect(winner.requestOptions, same(last));
    plugin.dispose();
  });

  test('[DiomanShare.onRequest] share 认领登记被外部移除后仍能交付原始响应', () async {
    final plugin = DiomanShare();
    final options = RequestOptions(path: replayPath, extra: {kKey: replayPath});
    plugin.onRequest(options, RequestInterceptorHandler());
    options.extra.remove(kClaimsKey);
    final response =
        Response<dynamic>(requestOptions: options, data: replayField);
    final handler = ResponseInterceptorHandler();
    plugin.onResponse(response, handler);
    expect((await handlerCompletion(handler)).data, same(response));
    plugin.dispose();
  });

  test(
      '[DiomanSharePolicy.retry][DiomanShare.policy] share retry 在进入重放前已取消时停止并交付取消错误',
      () async {
    final plugin = DiomanShare(policy: DiomanSharePolicy.retry, retries: 1);
    final token = CancelToken();
    final options = RequestOptions(
        path: replayPath, cancelToken: token, extra: {kKey: replayPath});
    plugin.onRequest(options, RequestInterceptorHandler());
    token.cancel(replayFailure);
    final handler = ErrorInterceptorHandler();
    final check = expectLater(handlerCompletion(handler), throwsA(anything));
    plugin.onError(
        DioException(
            requestOptions: options, type: DioExceptionType.connectionError),
        handler);
    await check;
    plugin.dispose();
  });

  test('[DiomanShare.onRequest] share 接手的最后一个跟随者也取消后允许新请求', () async {
    var hits = 0;
    final leaderEntered = Completer<void>();
    final followerEntered = Completer<void>();
    final server = await TestServer.start((request) async {
      hits++;
      if (!leaderEntered.isCompleted) {
        leaderEntered.complete();
      } else if (!followerEntered.isCompleted) {
        followerEntered.complete();
      }
      await Future<void>.delayed(replayTick);
      await respondJson(request, {}, 200);
    });
    final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
    final handle =
        Dioman.install(dio, key: const DiomanKey(), share: DiomanShare());
    final firstToken = CancelToken();
    final lastToken = CancelToken();
    try {
      final firstCheck = expectLater(
          dio.get<dynamic>(replayPath, cancelToken: firstToken),
          throwsA(isA<DioException>()));
      await leaderEntered.future;
      final lastCheck = expectLater(
          dio.get<dynamic>(replayPath, cancelToken: lastToken),
          throwsA(isA<DioException>()));
      await Future<void>.delayed(const Duration(milliseconds: 5));
      firstToken.cancel(replayFailure);
      await firstCheck;
      await followerEntered.future;
      lastToken.cancel(replayFailure);
      await lastCheck;
      await Future<void>.delayed(replayTick);
      expect((await dio.get<dynamic>(replayPath)).statusCode, 200);
      expect(hits, 3);
    } finally {
      handle.dispose();
      dio.close(force: true);
      await server.close();
    }
  });
}
