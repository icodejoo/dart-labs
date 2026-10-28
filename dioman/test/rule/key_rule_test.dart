// ignore_for_file: avoid_relative_lib_imports
// 规则层：key
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';
import 'package:test/test.dart';
import '../../accept/lib/literals.dart';
import '../support/fake_cache_persist.dart';
import '../support/fixtures.dart';
import '../support/test_server.dart';

/// 注册本文件的规则层用例。
void main() {
  group(tkDiomanKey, () {
    test(
        '[DiomanKeyOptions.key] a String body is folded into the deep key as-is',
        () async {
      var calls = 0;
      final server = await TestServer.start((req) async {
        calls++;
        await respondJson(req, {tkV: 1}, 200);
      });
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      dio.interceptors.add(const DiomanKey());
      dio.interceptors.add(DiomanCache(
          persist: FakeCachePersist(),
          cachePolicy: DiomanCachePolicy.memo,
          shouldCache: (o) => true));

      await dio.post<void>(tkData2, data: tkRawBody);
      await dio.post<void>(tkData2, data: tkRawBody);
      expect(calls, 1);

      await dio.post<void>(tkData2, data: 'different-body');
      expect(calls, 2);
    });
  });

  group(tkPerRequestOptionsOverrides, () {
    test(
        '[DiomanKeyOptions.key][DiomanKey.onRequest] DiomanKeyOptions(key: ...) overrides the computed key',
        () async {
      final server = await TestServer.start((req) => respondJson(req, {}, 200));
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      dio.interceptors.add(const DiomanKey());

      final captured = <String?>[];
      dio.interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
        captured.add(o.extra[kKey] as String?);
        h.next(o);
      }));

      await dio.get<void>(
        tkA3,
        options: Options(
            extra: {tkDiomanQid: const DiomanKeyOptions(key: tkFixedKey)}),
      );

      expect(captured, [tkFixedKey]);
    });
  });

  group(tkOptionsMergeSemanticsNotOverride, () {
    test(
        '[DiomanKey.ignores][DiomanKey.onRequest] DiomanKeyOptions.ignoreKeys UNIONS with the plugin default',
        () async {
      final server = await TestServer.start((req) => respondJson(req, {}, 200));
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      final keys = <String>[];
      dio.interceptors.add(const DiomanKey(ignores: [tkA2]));
      dio.interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
        keys.add(o.extra[kKey] as String);
        h.next(o);
      }));

      final override = Options(
        extra: {
          tkDiomanQid: const DiomanKeyOptions(ignores: [tkB2])
        },
      );
      await dio.get<void>(tkX,
          queryParameters: {tkA2: tk1, tkB2: tk2}, options: override);
      await dio.get<void>(tkX,
          queryParameters: {tkA2: '99', tkB2: tk2}, options: override);

      expect(keys[0], keys[1],
          reason: "both 'a' and 'b' must be excluded from the key (union of "
              "plugin default 'a' and per-request 'b'), so varying only 'a' "
              'must not change the key when both calls carry the same '
              'per-request override');
    });
  });

  group(tkNewlyWiredOptionsFieldsFullConstructorOptionsParity, () {
    test(
        '[DiomanKey.builder][DiomanKeyOptions.builder] DiomanKeyOptions.builder overrides the computed key for a single '
        'call', () async {
      final server = await TestServer.start((req) => respondJson(req, {}, 200));
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      dio.interceptors.add(const DiomanKey());

      final captured = <String?>[];
      dio.interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
        captured.add(o.extra[kKey] as String?);
        h.next(o);
      }));

      await dio.get<void>(
        tkX,
        options: Options(extra: {
          tkDiomanQid: DiomanKeyOptions(builder: (o) => 'custom:${o.path}'),
        }),
      );

      expect(captured, ['custom:/x']);
    });
  });

  group(tkKeyNamespace, () {
    test(
        '[DiomanKey.namespace][DiomanKeyOptions.key] isolates every key source and evaluates namespace once per key',
        () {
      for (final fastMode in [false, true]) {
        for (final override in [
          null,
          const DiomanKeyOptions(key: cacheKey),
          DiomanKeyOptions(builder: (_) => cacheKey),
        ]) {
          var account = accountA;
          var calls = 0;
          final plugin = DiomanKey(
              fastMode: fastMode,
              namespace: () {
                calls++;
                return account;
              });
          final first = namespacedKey(plugin, override: override);
          expect(namespacedKey(plugin, override: override), first);
          account = accountB;
          expect(namespacedKey(plugin, override: override), isNot(first));
          expect(calls, 3);
        }
      }
      final first = namespacedKey(DiomanKey(namespace: () => accountA));
      expect(jsonDecode(first), [mockRoute, emptyQueryKey, null, accountA]);
      expect(namespacedKey(DiomanKey(namespace: () => '["$accountA",null]')),
          isNot(first));
    });
  });

  test(
      '[DiomanKeyOptions.key] key includes origin, URL query and separate query/body fields',
      () {
    /// 构造同一请求的不同字段。
    /// request 的测试辅助入口。
    RequestOptions request(String url,
            {Map<String, dynamic>? query, dynamic data}) =>
        RequestOptions(path: url, queryParameters: query, data: data);
    const url = 'https://a.example/leaf';
    expect(requestKey(request(url)),
        isNot(requestKey(request('https://b.example/leaf'))));
    expect(requestKey(request('$url?q=1')),
        isNot(requestKey(request('$url?q=2'))));
    expect(
        requestKey(request('$url?b=2&a=1')),
        requestKey(
            request(url, query: {firstField: queryValue, secondField: tk2})));
    expect(requestKey(request(url, query: {queryField: queryValue})),
        isNot(requestKey(request(url, data: {queryField: queryValue}))));
  });

  group(tkKeyNamespace, () {
    test(
        '[DiomanKey.namespace][DiomanKey.enabled] disabled requests do not evaluate namespace',
        () {
      final plugin = DiomanKey(namespace: () => throw StateError(accountA));
      final options = cacheOptions()
        ..extra[DiomanKey.pluginName] = const DiomanKeyOptions(enabled: false);
      final handler = RecordingRequestHandler();
      plugin.onRequest(options, handler);
      expect(handler.calls, 1);
      expect(handler.error, isNull);
    });
  });
}
