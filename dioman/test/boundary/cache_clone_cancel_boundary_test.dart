import '../support/response_contract.dart';
import 'dart:async';
import 'package:dioman/dioman.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';
import '../support/source_test_helpers.dart';
import '../support/fake_network.dart';
import '../support/helpers.dart';

const _path = '/b8';
const _get = 'GET';

/// 验证对应主题的行为与边界。
void main() {
  for (final disk in [false, true]) {
    test('[DiomanCache.clone] B8 命中返回边界重查取消 disk=$disk', () async {
      final token = CancelToken();
      var cancelOnClone = false;
      final ctx = testContext(token: token);
      final persist = B4Persist();
      final plugin = DiomanCache<Result>(
          persist: persist,
          cachePolicy:
              disk ? DiomanCachePolicy.persist : DiomanCachePolicy.memo,
          clone: (Object? data) {
            if (cancelOnClone) token.cancel();
            return data;
          }).setup(ctx.client);
      final request = DiomanRequest(RequestOptions(path: _path),
          call: DiomanCall(options: {DiomanCache.option: true}));
      final cached = testContext(token: token, request: request);
      Future<Result> next([RequestPatch? patch]) async =>
          cached.factory.normalize(request,
              raw: Response<dynamic>(
                  requestOptions: request.toRequestOptions(), statusCode: 200));
      await plugin.handle(cached, next);
      cancelOnClone = true;
      final r = await plugin.handle(cached, next);
      expect(outcomeOf(r), diomanTestCancel);
      plugin.dispose();
      ctx.client.dispose();
      cached.client.dispose();
    });
  }
  test('[DiomanCache.clone] B8 命中 clone 时取消不能返回成功', () async {
    final token = CancelToken();
    var hit = false;
    final net = FakeNetwork();
    final api = testClient(statusOf: businessStatus, network: net, plugins: [
      DiomanCache<Result>(clone: (Object? data) {
        if (hit) token.cancel();
        return data;
      })
    ]);
    final options = {DiomanCache.option: true};
    await api.send<dynamic>(_get, _path, call: DiomanCall(options: options));
    hit = true;
    final r = await api.send<dynamic>(_get, _path,
        call: DiomanCall(options: options, cancelToken: token));
    expect(outcomeOf(r), diomanTestCancel);
    expect(net.sends.length, 1);
    api.dispose();
  });
}
