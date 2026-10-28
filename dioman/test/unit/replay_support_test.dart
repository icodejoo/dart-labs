// ignore_for_file: avoid_relative_lib_imports
// 单元层：replay_support
import 'dart:async';
import 'package:dio/dio.dart';
import 'package:dioman/src/replay_support.dart';
import 'package:dioman/src/request_claims.dart';
import 'package:test/test.dart';
import '../accept/lib/literals.dart';
import '../support/fixtures.dart';

/// 注册本文件的单元层用例。
void main() {
  group(tkCancelAll10, () {
    test('[cancellableDelay] cancellableDelay：取消时立刻结束；时间到自然结束', () async {
      final token = CancelToken();
      final sw = Stopwatch()..start();
      final f = cancellableDelay(const Duration(seconds: 30), token);
      token.cancel(tkX2);
      await f.timeout(const Duration(seconds: 1));
      expect(sw.elapsedMilliseconds, lessThan(1000));
      await cancellableDelay(const Duration(milliseconds: 10), CancelToken());
    });
  });

  test('[prepareForReplay] finalized FormData 拒绝克隆时不重放', () async {
    final form = UnclonableForm();
    await form.finalize().drain<void>();
    expect(prepareForReplay(RequestOptions(path: replayPath, data: form)),
        isFalse);
  });

  for (final success in [false, true]) {
    for (final mode in [0, 1, 2]) {
      test(
          '[ReplayClient.handOffResponse][ReplayClient.handOffResponseError] replay 仲裁出口 $mode 交付胜出方${success ? tkEmpty5 : tkFailed}',
          () async {
        final options = RequestOptions(path: replayPath);
        final response =
            Response<dynamic>(requestOptions: options, statusCode: 200);
        final owner = Interceptor();
        final winner = Completer<Response<dynamic>>();
        final claims = RequestClaims()..add(owner);
        claims.onFinal = (_, __) => winner.future;
        options.extra[kClaimsKey] = claims;
        final dynamic handler = mode == 2
            ? ErrorInterceptorHandler()
            : ResponseInterceptorHandler();
        final completed = handlerCompletion(handler);
        final check = success
            ? expectLater(completed,
                completion(predicate<dynamic>((s) => s.data == response)))
            : expectLater(completed, throwsA(anything));
        final error = DioException(requestOptions: options);
        if (mode == 0) {
          ReplayClient.handOffResponse(
              options, owner, response, handler as ResponseInterceptorHandler);
        } else if (mode == 1) {
          ReplayClient.handOffResponseError(
              options, owner, error, handler as ResponseInterceptorHandler);
        } else {
          ReplayClient().handOffError(
              owner, options, error, handler as ErrorInterceptorHandler);
        }
        if (success) {
          winner.complete(response);
        } else {
          winner.completeError(StateError(replayFailure));
        }
        await check;
        expect(claims.isFinished, isTrue);
      });
    }
  }

  for (final responsePhase in [false, true]) {
    test(
        '[ReplayClient.handOffResponseError][ReplayClient.handOffError] replay ${responsePhase ? '响应' : '错误'}出口取消时不等仲裁',
        () async {
      final options = RequestOptions(path: replayPath);
      final owner = Interceptor();
      final winner = Completer<Response<dynamic>>();
      final claims = RequestClaims()..add(owner);
      claims.onFinal = (_, __) => winner.future;
      options.extra[kClaimsKey] = claims;
      final dynamic handler = responsePhase
          ? ResponseInterceptorHandler()
          : ErrorInterceptorHandler();
      final check = expectLater(handlerCompletion(handler), throwsA(anything));
      final error = DioException.requestCancelled(
          requestOptions: options, reason: replayFailure);
      if (responsePhase) {
        ReplayClient.handOffResponseError(
            options, owner, error, handler as ResponseInterceptorHandler);
      } else {
        ReplayClient().handOffError(
            owner, options, error, handler as ErrorInterceptorHandler);
      }
      await check;
      winner.completeError(StateError(replayFailure));
    });
  }

  test('[ReplayClient.finishRecovered] 恢复成功前发现胜出方失败时清理认领并传播胜出错误', () async {
    final options = RequestOptions(path: replayPath);
    final owner = Interceptor();
    final claims = RequestClaims()..add(owner);
    claims.checkLoser =
        () => Future<Response<dynamic>>.error(StateError(replayFailure));
    options.extra[kClaimsKey] = claims;
    final handler = ErrorInterceptorHandler();
    final check = expectLater(handlerCompletion(handler), throwsA(anything));
    await ReplayClient().finishRecovered(
        owner, options, Response<dynamic>(requestOptions: options), handler);
    await check;
    expect(claims.isFinished, isTrue);
  });

  for (final asynchronous in [false, true]) {
    test(
        '[ReplayClient.runDownstream] replay 下游${asynchronous ? '异步' : '同步'}异常保留继续错误语义',
        () async {
      final host = Dio();
      final self = Interceptor();
      host.interceptors.addAll([self, ThrowingStage(asynchronous)]);
      final replay = ReplayClient()..bind(host);
      expect(replay.host, same(host));
      await expectLater(
          replay.runDownstream(
              self, Response(requestOptions: RequestOptions(path: replayPath))),
          throwsA(isA<DownstreamReject>()
              .having((e) => e.callFollowing, replayFailure, isTrue)
              .having((e) => e.error.error, replayField, isA<StateError>())));
      replay.dispose();
      host.close();
    });
  }
}
