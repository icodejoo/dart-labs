// ignore_for_file: avoid_relative_lib_imports
// 规则层：filter
import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';
import 'package:dioman/src/filter_plugin.dart';
import 'package:test/test.dart';
import '../../accept/lib/literals.dart';
import '../support/fixtures.dart';
import '../support/test_server.dart';

/// 注册本文件的规则层用例。
void main() {
  group(tkDiomanFilter, () {
    test(
        '[DiomanFilter.predicate][DiomanFilterOptions.predicate] the default predicate also drops empty/whitespace-only strings, '
        'and filters the data map the same way it filters queryParameters',
        () async {
      Map<String, dynamic>? seenQuery;
      Object? seenBody;
      final server = await TestServer.start((req) async {
        seenQuery = req.uri.queryParameters;
        await respondJson(req, {tkV: 1}, 200);
      });
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      dio.interceptors.add(const DiomanFilter());
      dio.interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
        seenBody = o.data;
        h.next(o);
      }));

      await dio.get<void>(tkData2, queryParameters: {
        tkKeep: tkX2,
        tkBlank: '   ',
        tkEmpty6: tkEmpty,
      });
      expect(seenQuery, {tkKeep: tkX2});

      await dio.post<void>(tkData2, data: {
        tkKeep: 1,
        'dropMe': null,
        tkBlank: tkJsonIndent,
      });
      expect(seenBody, {tkKeep: 1});
    });
  });

  group(tkPerRequestOptionsOverrides, () {
    test(
        '[DiomanFilter.ignoreKeys][DiomanFilterOptions.ignoreKeys] DiomanFilterOptions ignoreKeys override keeps a field the plugin '
        'default would otherwise strip', () async {
      final server = await TestServer.start((req) => respondJson(req, {}, 200));
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      Map<String, dynamic>? seenParams;
      dio.interceptors.add(const DiomanFilter()); // default: drops null/empty
      dio.interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
        seenParams = o.queryParameters;
        h.next(o);
      }));

      await dio.get<void>(
        tkX,
        queryParameters: {tkPage: null},
        options: Options(
          extra: {
            tkDiomanFilter2: const DiomanFilterOptions(ignoreKeys: [tkPage])
          },
        ),
      );

      expect(seenParams, containsPair(tkPage, null),
          reason:
              'per-request ignoreKeys must override the plugin default predicate');
    });
  });

  group(tkConstructorLevelEnabledFlag, () {
    test(
        '[DiomanFilter.enabled][DiomanFilterOptions.enabled] DiomanFilter(enabled: false) leaves every request untouched',
        () async {
      final server = await TestServer.start((req) => respondJson(req, {}, 200));
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      Map<String, dynamic>? seenParams;
      dio.interceptors.add(const DiomanFilter(enabled: false));
      dio.interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
        seenParams = o.queryParameters;
        h.next(o);
      }));

      await dio.get<void>(tkX, queryParameters: {tkPage: null});

      expect(seenParams, containsPair(tkPage, null),
          reason: 'a disabled plugin must never filter anything');
    });
  });

  group(tkOptionsMergeSemanticsNotOverride, () {
    test(
        '[DiomanFilter.ignoreKeys][DiomanFilterOptions.ignoreKeys] DiomanFilterOptions.ignoreKeys UNIONS with the plugin default '
        'instead of replacing it', () async {
      final server = await TestServer.start((req) => respondJson(req, {}, 200));
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      Map<String, dynamic>? seenParams;
      dio.interceptors.add(const DiomanFilter(ignoreKeys: [tkA2]));
      dio.interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
        seenParams = o.queryParameters;
        h.next(o);
      }));

      await dio.get<void>(
        tkX,
        queryParameters: {tkA2: null, tkB2: null},
        options: Options(
          extra: {
            tkDiomanFilter2: const DiomanFilterOptions(ignoreKeys: [tkB2])
          },
        ),
      );

      expect(
          seenParams, allOf(containsPair(tkA2, null), containsPair(tkB2, null)),
          reason: "plugin default 'a' must survive alongside per-request 'b', "
              'not be replaced by it');
    });
  });

  test(
      '[DiomanFilter.ignoreValues][DiomanFilterOptions.ignoreValues] filter 单请求保留值与实例保留值合并',
      () {
    final plugin = DiomanFilter(ignoreValues: [null]);
    final options = RequestOptions(path: replayPath, queryParameters: {
      replayField: tkEmpty
    }, extra: {
      DiomanFilter.pluginName:
          const DiomanFilterOptions(ignoreValues: [tkEmpty]),
    });
    plugin.onRequest(options, RequestInterceptorHandler());
    expect(options.queryParameters, {replayField: tkEmpty});
  });
}
