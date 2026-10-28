import 'dart:async';
import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';
import 'package:test/test.dart';
import '../../test/support/fake_cache_persist.dart';
import '../../test/support/fixtures.dart';

/// 缓存配置用例的请求路径。
const _path = '/cache-options';

/// 默认有效期（毫秒）。
const _ttl = 1000;

/// 持久化条目里记录到期时间的字段名。
const _expiryField = 'expiresAt';

/// 构造仅缓存插件所需的请求，不依赖 key 插件。
RequestOptions _request([DiomanCacheOptions? override]) => RequestOptions(
    path: _path, extra: {kKey: _path, DiomanCache.pluginName: override});

/// 等待缓存请求回调完成并返回其出口。
Future<dynamic> _read(DiomanCache cache, RequestOptions options) async {
  final handler = RequestInterceptorHandler();
  cache.onRequest(options, handler);
  return handlerCompletion(handler);
}

/// 为放行的请求写入成功响应。
Future<void> _write(
    DiomanCache cache, RequestOptions options, Object data) async {
  final handler = ResponseInterceptorHandler();
  cache.onResponse(
      Response<dynamic>(requestOptions: options, statusCode: 200, data: data),
      handler);
  await handlerCompletion(handler);
}

/// 注册缓存时钟、有效期和声明规则测试。
void main() {
  test(
      '[DiomanCache.name][DiomanCache.pluginName][DiomanCache.ordering] 固定名称用于查找，声明在 offline 之前',
      () {
    final cache = DiomanCache(persist: FakeCachePersist());
    expect(cache.name, 'dioman:cache');
    expect(cache.name, DiomanCache.pluginName);
    expect(cache.ordering.before, {DiomanOffline.pluginName});
    expect(cache.ordering.after, isEmpty);
    expect(cache.ordering.requires, isEmpty);
    final dio = Dio();
    final handle = Dioman.install(dio, cache: cache);
    expect(handle.plugins.singleWhere((p) => p.name == DiomanCache.pluginName),
        same(cache));
    handle.dispose();
    dio.close(force: true);
  });

  for (final ttl in [-1, 0, _ttl]) {
    test(
        '[DiomanCacheOptions.expires][DiomanCacheOptions.now] 请求级 TTL=$ttl 不钳制，时钟同时用于写入和到期读取，空值继承',
        () async {
      var now = DateTime.utc(2026);
      final pluginNow = now.add(const Duration(days: 1));
      final persist = FakeCachePersist();
      final cache = DiomanCache(
          persist: persist,
          cachePolicy: DiomanCachePolicy.both,
          expires: _ttl,
          now: () => pluginNow);
      const defaults = DiomanCacheOptions();
      final override = DiomanCacheOptions(expires: ttl, now: () => now);
      expect(defaults.expires, isNull);
      expect(defaults.now, isNull);
      expect(override.expires, ttl);
      expect(override.now!(), now);
      final first = _request(override);
      await _read(cache, first);
      await _write(cache, first, _path);
      expect((persist.store[_path] as Map)[_expiryField],
          now.millisecondsSinceEpoch + ttl);
      final result = await _read(cache, _request(override));
      expect(result.data is Response, ttl > 0, reason: '零和负 TTL 立即过期');
      now = now.add(const Duration(milliseconds: _ttl));
      final expired = await _read(cache, _request(override));
      expect(expired.data, isA<RequestOptions>(), reason: '恰好到期时不命中');
      final inherited = _request(defaults);
      await _read(cache, inherited);
      await _write(cache, inherited, _path);
      expect((persist.store[_path] as Map)[_expiryField],
          pluginNow.millisecondsSinceEpoch + _ttl);
      expect((await _read(cache, _request(defaults))).data, isA<Response>());
      cache.dispose();
    });
  }

  test('[DiomanCachePersist.remove] 删除操作串行等待先前写入完成', () async {
    final persist = ControlledPersist()..writeGate = Completer<void>();
    final cache =
        DiomanCache(persist: persist, cachePolicy: DiomanCachePolicy.persist);
    final options = _request();
    await _read(cache, options);
    final writing = _write(cache, options, _path);
    await pumpEvents();
    var removed = false;
    final removing = cache.remove(_path).then((_) => removed = true);
    await pumpEvents();
    expect(persist.operations, [writeOperation]);
    expect(removed, isFalse);
    persist.writeGate!.complete();
    await Future.wait([writing, removing]);
    expect(persist.operations, [writeOperation, 'remove']);
    expect(persist.store, isEmpty);
    cache.dispose();
  });
}
