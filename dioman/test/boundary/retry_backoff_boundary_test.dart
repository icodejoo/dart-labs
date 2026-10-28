// 边界层：retry 错误阶段的退避等待与取消
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';
import 'package:dioman/src/request_claims.dart';
import 'package:test/test.dart';

import '../support/fixtures.dart';

/// 兜底超时：退避不可取消时会等一小时，靠它把用例判失败。
const _guard = Duration(seconds: 2);

/// 取消发生前先让重试进入退避等待的时间。
const _beforeCancel = Duration(milliseconds: 30);

/// 一小时的退避：只有取消能提前结束它。
const _hour = Duration(hours: 1);

/// 交接给下游的错误：排除兜底超时，避免把"等不到"误判成通过。
final _notTimeout =
    predicate<Object>((e) => e is! TimeoutException, 'not a timeout');

/// 注册本文件的边界层用例。
void main() {
  test('[DiomanRetry.onError] 退避等待期间取消：等待被打断，立刻以取消错误交接并注销认领，不触发重放', () async {
    var retried = 0;
    final plugin = DiomanRetry(
        max: 2, delay: (_, __, ___, ____) => _hour, onRetry: (_) => retried++);
    addTearDown(plugin.dispose);
    final token = CancelToken();
    final options = RequestOptions(path: replayPath, cancelToken: token);
    plugin.onRequest(options, RequestInterceptorHandler());
    final handler = ErrorInterceptorHandler();
    final done = expectLater(
        handlerCompletion(handler).timeout(_guard), throwsA(_notTimeout),
        reason: '退避不可取消的话这里会一直等到超时');

    plugin.onError(
        DioException(
            requestOptions: options, type: DioExceptionType.connectionError),
        handler);
    await Future<void>.delayed(_beforeCancel);
    expect(handler.isCompleted, isFalse, reason: '此时还在等退避');
    token.cancel(replayFailure);

    await done;
    expect(retried, 0, reason: '取消后没有进入重放');
    expect(claimsOf(options)!.isFinished, isTrue);
  });

  test('[DiomanRetry.onError] 取消类错误永不重试：直接原样交接，退避回调与重放都不触发', () async {
    var delayed = 0;
    var retried = 0;
    final plugin = DiomanRetry(
        max: 2,
        delay: (_, __, ___, ____) {
          delayed++;
          return Duration.zero;
        },
        onRetry: (_) => retried++);
    addTearDown(plugin.dispose);
    final options = RequestOptions(path: replayPath);
    plugin.onRequest(options, RequestInterceptorHandler());
    final handler = ErrorInterceptorHandler();
    final done = expectLater(
        handlerCompletion(handler).timeout(_guard), throwsA(_notTimeout));

    plugin.onError(
        DioException.requestCancelled(requestOptions: options, reason: 'user'),
        handler);

    await done;
    expect([delayed, retried], [0, 0]);
  });
}
