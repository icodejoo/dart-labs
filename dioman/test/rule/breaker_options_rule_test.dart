import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';
import 'package:test/test.dart';
import '../support/fixtures.dart';

/// 熔断配置用例的请求路径。
const _path = '/breaker-options';

/// 上面路径对应的熔断桶键（GET 方法）。
const _key = 'GET:$_path';

/// 自定义 keyBuilder 归入的业务桶名。
const _custom = 'custom';

/// 一秒，用作冷却时长与注入时钟的步长。
const _tick = Duration(seconds: 1);

/// 负一秒，用于验证负冷却不被钳制。
const _negativeTick = Duration(seconds: -1);

/// 构造带请求级覆盖的请求。
RequestOptions _request([DiomanBreakerOptions? override]) =>
    RequestOptions(path: _path, extra: {DiomanBreaker.pluginName: override});

/// 放行并报告一次连接失败。
void _fail(DiomanBreaker breaker, RequestOptions options) {
  expect(breaker.admit(options), isTrue);
  breaker.onError(
      DioException(
          requestOptions: options, type: DioExceptionType.connectionError),
      IgnoringErrorHandler());
}

/// 放行并报告一次成功。
void _succeed(DiomanBreaker breaker, RequestOptions options) {
  expect(breaker.admit(options), isTrue);
  breaker.onResponse(
      Response<dynamic>(requestOptions: options, statusCode: 200),
      RecordingResponseHandler());
}

/// 注册熔断配置与查询规则测试。
void main() {
  test(
      '[DiomanBreaker.name][DiomanBreaker.pluginName][DiomanBreaker.ordering] 固定名称与 retry 后置声明',
      () {
    final breaker = DiomanBreaker();
    expect(breaker.name, 'dioman:breaker');
    expect(breaker.name, DiomanBreaker.pluginName);
    expect(breaker.ordering.after, {DiomanRetry.pluginName});
    expect(breaker.ordering.before, isEmpty);
    expect(breaker.ordering.requires, isEmpty);
    final dio = Dio();
    final handle = Dioman.install(dio, breaker: breaker);
    expect(handle.plugins.singleWhere((p) => p.name == breaker.name),
        same(breaker));
    handle.dispose();
    dio.close(force: true);
  });

  test(
      '[DiomanBreaker.defaultIdleTtl][DiomanBreaker.bucketCount][DiomanBreaker.dispose] 默认一小时惰性回收，查询不回收，dispose 清全部桶',
      () {
    var now = DateTime.utc(2026);
    final breaker = DiomanBreaker(clock: () => now);
    expect(DiomanBreaker.defaultIdleTtl, const Duration(hours: 1));
    expect(breaker.idleTtl, DiomanBreaker.defaultIdleTtl);
    expect(DiomanBreaker(idleTtl: _tick).idleTtl, _tick);
    _succeed(breaker, _request());
    now = now.add(const Duration(hours: 1));
    _succeed(breaker, RequestOptions(path: _custom));
    expect(breaker.bucketCount, 2, reason: '等于 TTL 不回收');
    now = now.add(const Duration(milliseconds: 1));
    expect(breaker.bucketCount, 2, reason: 'getter 不主动回收');
    _succeed(breaker, RequestOptions(path: 'third'));
    expect(breaker.bucketCount, 2, reason: '创建新桶才回收第一桶');
    breaker.dispose();
    expect(breaker.bucketCount, 0);
    expect(breaker.isOpen(_request()), isFalse);
    expect(breaker.stateOf(_key), DiomanBreakerState.closed);
  });

  test('[DiomanBreaker.defaultMaxBuckets] 默认一千桶软上限用于实际淘汰', () {
    final breaker = DiomanBreaker();
    expect(DiomanBreaker.defaultMaxBuckets, 1000);
    expect(breaker.maxBuckets, DiomanBreaker.defaultMaxBuckets);
    expect(DiomanBreaker(maxBuckets: 2).maxBuckets, 2);
    for (var index = 0; index <= DiomanBreaker.defaultMaxBuckets; index++) {
      _succeed(breaker, RequestOptions(path: '/$index'));
    }
    expect(breaker.bucketCount, DiomanBreaker.defaultMaxBuckets);
  });

  test(
      '[DiomanBreaker.isOpen][DiomanBreaker.stateOf][DiomanBreaker.new(clock)] 未知桶只读、注入时钟冷却到点后仅查询不迁移',
      () {
    var now = DateTime.utc(2026);
    final breaker = DiomanBreaker(
        failureThreshold: 1, resetDuration: _tick, clock: () => now);
    expect(breaker.stateOf(_key), DiomanBreakerState.closed);
    expect(breaker.isOpen(_request()), isFalse);
    expect(breaker.bucketCount, 0);
    _fail(breaker, _request());
    expect(breaker.isOpen(_request()), isTrue);
    now = now.add(_tick);
    expect(breaker.isOpen(_request()), isFalse);
    expect(breaker.stateOf(_key), DiomanBreakerState.open);
    expect(breaker.bucketCount, 1);
    expect(breaker.admit(_request()), isTrue);
    expect(breaker.stateOf(_key), DiomanBreakerState.halfOpen);
    final defaultClock = DiomanBreaker(failureThreshold: 1);
    _fail(defaultClock, _request());
    expect(defaultClock.isOpen(_request()), isTrue);
  });

  test(
      '[DiomanBreaker.keyBuilder][DiomanBreakerOptions.keyBuilder] 默认 METHOD:path，自定义分桶与空请求覆盖继承',
      () {
    final defaults = DiomanBreaker();
    expect(defaults.keyBuilder, isNull);
    _succeed(defaults, _request());
    _succeed(defaults, RequestOptions(path: _path, method: 'POST'));
    expect(defaults.bucketCount, 2);

    /// 将不同请求归到同一个业务桶。
    String builder(RequestOptions _) => _custom;

    /// 将当前请求划入独立桶。
    String overrideBuilder(RequestOptions _) => _path;
    final breaker = DiomanBreaker(keyBuilder: builder, failureThreshold: 1);
    const inherited = DiomanBreakerOptions();
    final override = DiomanBreakerOptions(keyBuilder: overrideBuilder);
    expect(inherited.keyBuilder, isNull);
    expect(breaker.keyBuilder, same(builder));
    expect(override.keyBuilder, same(overrideBuilder));
    _fail(breaker, _request(inherited));
    expect(breaker.isOpen(RequestOptions(path: 'another')), isTrue);
    expect(breaker.stateOf(_custom), DiomanBreakerState.open);
    _succeed(breaker, _request(override));
    expect(breaker.stateOf(_path), DiomanBreakerState.closed);
    expect(breaker.bucketCount, 2);
  });

  test(
      '[DiomanBreakerOptions.failureThreshold][DiomanBreakerOptions.resetDuration][DiomanBreakerOptions.halfOpenMaxCalls] 覆盖值不钳制且空值继承插件配置',
      () {
    const defaults = DiomanBreakerOptions();
    const override = DiomanBreakerOptions(
        failureThreshold: -1,
        resetDuration: _negativeTick,
        halfOpenMaxCalls: -1);
    expect(defaults.failureThreshold, isNull);
    expect(defaults.resetDuration, isNull);
    expect(defaults.halfOpenMaxCalls, isNull);
    expect(override.failureThreshold, -1);
    expect(override.resetDuration, _negativeTick);
    expect(override.halfOpenMaxCalls, -1);
    final breaker = DiomanBreaker(
        failureThreshold: 3,
        resetDuration: const Duration(days: 1),
        halfOpenMaxCalls: 1);
    _fail(breaker, _request(defaults));
    expect(breaker.isOpen(_request()), isFalse, reason: '空阈值沿用三次');
    _fail(breaker, _request(override));
    expect(breaker.isOpen(_request()), isTrue, reason: '负阈值使本次失败立即熔断');
    final probe =
        _request(const DiomanBreakerOptions(resetDuration: _negativeTick));
    expect(breaker.admit(probe), isTrue, reason: '负冷却立即允许探测');
    expect(breaker.isOpen(_request()), isTrue, reason: '空并发覆盖沿用一个槽位');
    expect(breaker.admit(_request(override)), isFalse, reason: '负探测上限没有钳制为正数');
    expect(
        breaker
            .admit(_request(const DiomanBreakerOptions(halfOpenMaxCalls: 2))),
        isTrue);
  });

  test('[DiomanBreakerOpenException.retryableAt] 快速拒绝带冷却截止时间，手动构造可为空', () {
    var now = DateTime.utc(2026);
    final breaker = DiomanBreaker(
        failureThreshold: 1, resetDuration: _tick, clock: () => now);
    expect(
        const DiomanBreakerOpenException(bucketKey: _key).retryableAt, isNull);
    _fail(breaker, _request());
    final handler = RecordingRequestHandler();
    breaker.onRequest(_request(), handler);
    final error = handler.error!.error as DiomanBreakerOpenException;
    expect(error.retryableAt, now.add(_tick));
    expect(error.bucketKey, _key);
    now = error.retryableAt!;
    expect(breaker.admit(_request()), isTrue);
  });
}
