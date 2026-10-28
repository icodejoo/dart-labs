// 规则层：breaker 不经拦截链的逐次尝试记账（admit / recordResponse / recordError）
import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';
import 'package:test/test.dart';

/// 用例共用的请求路径。
const _path = '/accounting';

/// 构造一个待记账的请求。
RequestOptions _options() => RequestOptions(path: _path, method: 'GET');

/// 构造 [options] 的一次 HTTP 响应。
Response<dynamic> _response(RequestOptions options, int status) =>
    Response<dynamic>(requestOptions: options, statusCode: status);

/// 构造 [options] 的一次传输错误。
DioException _error(RequestOptions options, DioExceptionType type) =>
    DioException(requestOptions: options, type: type);

/// 先 admit 再按 [record] 报告结果，模拟一次重发尝试；返回 admit 的结果。
bool _attempt(DiomanBreaker breaker, void Function(RequestOptions) record) {
  final options = _options();
  final admitted = breaker.admit(options);
  if (admitted) record(options);
  return admitted;
}

/// 注册本文件的规则层用例。
void main() {
  test(
      '[DiomanBreaker.admit][DiomanBreaker.recordError] 连续失败达到阈值后熔断，admit 随即拒绝',
      () {
    final breaker = DiomanBreaker(failureThreshold: 2);
    for (var i = 0; i < 2; i++) {
      expect(
          _attempt(
              breaker,
              (o) => breaker
                  .recordError(_error(o, DioExceptionType.connectionError))),
          isTrue);
    }
    expect(breaker.isOpen(_options()), isTrue);
    expect(breaker.admit(_options()), isFalse, reason: '熔断打开时不再放行');
  });

  test('[DiomanBreaker.recordResponse] 5xx 与 429 计失败，成功响应清零连续失败计数', () {
    final breaker = DiomanBreaker(failureThreshold: 2);
    _attempt(breaker, (o) => breaker.recordResponse(_response(o, 503)));
    _attempt(breaker, (o) => breaker.recordResponse(_response(o, 200)));
    _attempt(breaker, (o) => breaker.recordResponse(_response(o, 429)));
    expect(breaker.isOpen(_options()), isFalse, reason: '中间的成功把计数清零了');
    _attempt(breaker, (o) => breaker.recordResponse(_response(o, 500)));
    expect(breaker.isOpen(_options()), isTrue);
  });

  test(
      '[DiomanBreaker.recordResponse][DiomanBreaker.recordError] 没有凭据的结果不记账，避免重复计数',
      () {
    final breaker = DiomanBreaker(failureThreshold: 1);
    breaker.recordResponse(_response(_options(), 500));
    breaker.recordError(_error(_options(), DioExceptionType.connectionError));
    expect(breaker.isOpen(_options()), isFalse);

    final options = _options();
    expect(breaker.admit(options), isTrue);
    breaker.recordResponse(_response(options, 200));
    // 同一次尝试的凭据已归还，再报一次失败不应计入。
    breaker.recordResponse(_response(options, 500));
    expect(breaker.isOpen(_options()), isFalse);
  });

  test('[DiomanBreaker.recordError] 取消只归还凭据、不计成败；熔断器自己的拒绝不计失败', () {
    final breaker = DiomanBreaker(failureThreshold: 2);
    _attempt(
        breaker,
        (o) =>
            breaker.recordError(_error(o, DioExceptionType.connectionError)));
    for (var i = 0; i < 3; i++) {
      _attempt(breaker,
          (o) => breaker.recordError(_error(o, DioExceptionType.cancel)));
    }
    expect(breaker.isOpen(_options()), isFalse, reason: '取消不算失败');

    final rejected = _options();
    breaker.admit(rejected);
    breaker.recordError(DioException(
        requestOptions: rejected,
        error: const DiomanBreakerOpenException(bucketKey: _path)));
    expect(breaker.isOpen(_options()), isFalse, reason: '自身的快速拒绝不算依赖失败');

    _attempt(
        breaker,
        (o) =>
            breaker.recordError(_error(o, DioExceptionType.connectionError)));
    expect(breaker.isOpen(_options()), isTrue,
        reason: '取消没有把前面那次失败清零，第二次失败即熔断');
  });
}
