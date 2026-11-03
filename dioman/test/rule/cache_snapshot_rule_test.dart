import 'package:dioman/dioman.dart';
import 'package:dioman/src/diagnostics.dart';
import 'package:dio/dio.dart';
import '../support/fake_clock.dart';
import '../support/auth_test_helpers.dart' show b3Finish;
import 'package:test/test.dart';
import '../support/helpers.dart';
import '../support/source_test_helpers.dart' show B4Persist;

/// 缓存用例的显式键、请求方法与凭证头。
const _key = 'native-cache', _method = 'GET', _authorization = 'Authorization';

/// 两次调用的路径与凭证。
const _first = '/first',
    _second = '/second',
    _firstSecret = 'first-secret',
    _secondSecret = 'second-secret';

/// 持久化格式的既有字段名。
const _expires = 'expiresAt', _data = 'data';

/// 快照不能持有前一个调用方的请求。
void main() {
  test(
      '[DiomanCache][DiomanResponse.request][DiomanResponseFactory.create] 内存命中经工厂绑定当前请求且不保留旧凭证或原生数据',
      () async {
    var creates = 0;
    DiomanRequest? current;
    final api = testClient(
        response: DiomanResponseFactory(create: (r) {
          creates++;
          return r;
        }),
        plugins: [
          const DiomanCache(),
          TestPlugin('current-request',
              stage: DiomanStage.source,
              enforce: DiomanEnforce.pre, handler: (ctx, next) async {
            current = ctx.request;
            return next();
          })
        ]);
    final first = await api.send<Object?>(_method, _first,
        call: DiomanCall(
            raw: true,
            key: _key,
            headers: {_authorization: _firstSecret},
            options: {DiomanCache.option: true}));
    final before = creates;
    final second = await api.send<Object?>(_method, _second,
        call: DiomanCall(
            raw: true,
            key: _key,
            headers: {_authorization: _secondSecret},
            options: {DiomanCache.option: true}));
    expect(creates, greaterThan(before));
    expect(second.request, same(current));
    expect(second.request.path, _second);
    expect(second.request.toRequestOptions().headers[_authorization],
        _secondSecret);
    expect(second.request, isNot(same(first.request)));
    expect(second.raw, isNull);
    expect(second.error, isNull);
    expect(first.raw, isNotNull);
  });
  for (final disk in [false, true]) {
    test(
        '[DiomanCache.shouldStore][DiomanResponseFactory.create] 快照生成前工厂 internal 不入缓存并保留原异常 disk=$disk',
        () async {
      final bug = StateError('snapshot-factory');
      final store = B4Persist()..values[_key] = {_expires: 60000, _data: 7};
      var creates = 0;
      final api = testClient(
          response: DiomanResponseFactory(create: (r) {
            creates++;
            if (creates == (disk ? 1 : 2)) throw bug;
            return r;
          }),
          plugins: [
            DiomanCache(
                persist: store,
                cachePolicy:
                    disk ? DiomanCachePolicy.both : DiomanCachePolicy.memo,
                clone: DiomanClonePolicy.shallow)
          ]);
      final call = DiomanCall(key: _key, options: {DiomanCache.option: true});
      await expectLater(
          api.send<Object?>(_method, _first, call: call), throwsA(same(bug)));
      expect(api.plugin<DiomanCacheApi>()!.entryCount, 0);
      expect(
          (await api.send<Object?>(_method, _second, call: call)).ok, isTrue);
    });
  }
  test(
      '[DiomanRetry.retryAfterMax][DiomanCache.shouldStore] 内存快照保留服务器超限退避且不读 raw',
      () async {
    final clock = FakeClock();
    var retries = 0;
    final api = testClient(clock: clock, plugins: [
      DiomanRetry(max: 1, onRetry: (_) => retries++),
      DiomanCache(shouldStore: (_) => true)
    ]);
    api.dio.interceptors.add(InterceptorsWrapper(onResponse: (r, h) {
      r.statusCode = 503;
      r.headers.set('retry-after', '61');
      h.next(r);
    }));
    await api.send<Object?>(_method, _first,
        call: DiomanCall(
            key: _key,
            options: {DiomanCache.option: true, DiomanRetry.option: false}));
    final result = await b3Finish(
        api.send<Object?>(_method, _second,
            call: DiomanCall(key: _key, options: {DiomanCache.option: true})),
        clock);
    expect(result.status, 503);
    expect(result.raw, isNull);
    expect(retries, 0);
  });
  for (final policy in DiomanCachePolicy.values) {
    test(
        '[DiomanParsed.code][DiomanCache.cachePolicy] 快照区分显式 null 业务码与缺省值 policy=$policy',
        () async {
      final api = testClient(
          response: DiomanResponseFactory(
              parse: (body, _) => DiomanParsed(code: null, data: body),
              isSuccess: (_) => true),
          plugins: [DiomanCache(cachePolicy: policy, persist: B4Persist())]);
      final call = DiomanCall(key: _key, options: {DiomanCache.option: true});
      final first = await api.send<Object?>(_method, _first, call: call);
      final second = await api.send<Object?>(_method, _second, call: call);
      expect(first.code, isNull);
      expect(second.code, isNull);
      expect(second.ok, isTrue);
      expect(second.data, first.data);
    });
  }
  test('[DiomanCachePersist.read][DiomanParsed.code] 旧持久化元信息缺业务码仍补零', () async {
    final store = B4Persist()
      ..values[_key] = {
        _expires: 60000,
        'result': {'ok': true, 'status': 200, 'message': '', _data: 7}
      };
    final api = testClient(plugins: [
      DiomanCache(persist: store, cachePolicy: DiomanCachePolicy.persist)
    ]);
    final result = await api.send<Object?>(_method, _second,
        call: DiomanCall(key: _key, options: {DiomanCache.option: true}));
    expect(result.code, 0);
    expect(result.data, 7);
  });
}
