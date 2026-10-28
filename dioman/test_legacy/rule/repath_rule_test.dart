// ignore_for_file: avoid_relative_lib_imports
// 规则层：repath
import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';
import 'package:dioman/src/repath_plugin.dart';
import 'package:test/test.dart';
import '../../test/accept/lib/literals.dart';
import '../../test/support/test_server.dart';

/// 注册本文件的规则层用例。
void main() {
  group(tkDiomanRepath, () {
    test(
        '[DiomanRepath.onRequest] {id}/:id placeholders are substituted from queryParameters, and '
        'removed from it by default', () async {
      String? seenPath;
      final server = await TestServer.start((req) async {
        seenPath = req.uri.path;
        await respondJson(req, {tkV: 1}, 200);
      });
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      dio.interceptors.add(DiomanRepath());

      final r = await dio.get<void>('/user/{id}/posts/:postId',
          queryParameters: {tkId: 42, tkPostId: 7, tkPage: 1});

      expect(seenPath, '/user/42/posts/7');
      expect(r.requestOptions.queryParameters.containsKey(tkId), isFalse,
          reason: 'removeKey defaults to true — substituted keys are '
              'removed from the source map');
      expect(r.requestOptions.queryParameters.containsKey(tkPostId), isFalse);
      expect(r.requestOptions.queryParameters[tkPage], 1,
          reason: 'an untouched param stays');
    });
    test(
        '[DiomanRepath.removeKey][DiomanRepathOptions.removeKey] falls back to the data map when a placeholder is not in '
        'queryParameters, and removeKey:false keeps the source key', () async {
      String? seenPath;
      final server = await TestServer.start((req) async {
        seenPath = req.uri.path;
        await respondJson(req, {tkV: 1}, 200);
      });
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      dio.interceptors.add(DiomanRepath(removeKey: false));

      final r = await dio.post<void>(tkUserId, data: {tkId: 99});

      expect(seenPath, tkUser99);
      expect(r.requestOptions.data[tkId], 99,
          reason: 'removeKey:false leaves the source key in place');
    });
    test(
        '[DiomanRepath.removeKey][DiomanRepathOptions.removeKey] the default removeKey:true also removes a data-map substitution '
        '(not just a queryParameters one)', () async {
      String? seenPath;
      final server = await TestServer.start((req) async {
        seenPath = req.uri.path;
        await respondJson(req, {tkV: 1}, 200);
      });
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      dio.interceptors.add(DiomanRepath()); // removeKey defaults to true

      final r = await dio.post<void>(tkUserId, data: {tkId: 99});

      expect(seenPath, tkUser99);
      expect(r.requestOptions.data.containsKey(tkId), isFalse,
          reason: 'removeKey defaults to true for the data-map branch too');
    });
    test(
        '[DiomanRepath.enabled][DiomanRepathOptions.enabled] a constructor-level disabled DiomanRepath never substitutes',
        () async {
      String? seenPath;
      final server = await TestServer.start((req) async {
        seenPath = req.uri.path;
        await respondJson(req, {tkV: 1}, 200);
      });
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      dio.interceptors.add(DiomanRepath(enabled: false));

      await dio.get<void>(tkUserId, queryParameters: {tkId: 42});
      expect(Uri.decodeComponent(seenPath!), tkUserId);
    });
    test(
        '[DiomanRepath.removeKey][DiomanRepathOptions.removeKey] a per-request DiomanRepathOptions can disable substitution or '
        'override removeKey for a single call', () async {
      String? seenPath;
      final server = await TestServer.start((req) async {
        seenPath = req.uri.path;
        await respondJson(req, {tkV: 1}, 200);
      });
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      dio.interceptors.add(DiomanRepath());

      await dio.get<void>(tkUserId,
          queryParameters: {tkId: 42},
          options: Options(extra: {
            tkDiomanRepath2: const DiomanRepathOptions(enabled: false)
          }));
      expect(Uri.decodeComponent(seenPath!), tkUserId,
          reason: 'per-request override disabled substitution for this call');

      final r = await dio.get<void>(tkUserId,
          queryParameters: {tkId: 7},
          options: Options(extra: {
            tkDiomanRepath2: const DiomanRepathOptions(removeKey: false)
          }));
      expect(seenPath, '/user/7');
      expect(r.requestOptions.queryParameters[tkId], 7,
          reason: 'per-request removeKey:false keeps the source query param');
    });
  });
}
