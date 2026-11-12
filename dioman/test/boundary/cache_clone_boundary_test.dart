import '../support/response_contract.dart';
import 'package:dioman/src/diagnostics.dart';
import 'package:dioman/dioman.dart';
import 'package:test/test.dart';
import '../support/source_test_helpers.dart';
import '../support/helpers.dart';


/// 验证对应主题的行为与边界。
void main() {
  test(
      '[DiomanResponseFactory.derive]'
      '[DiomanCache.clone] 显式缓存失败时深拷贝隔离来源首返回和后续命中数据', () async {
    for (final policy in DiomanCachePolicy.values) {
      final body = <int, dynamic>{
        1: <int>[2]
      };
      final api = testClient(plugins: [
        DiomanCache<Result>(
            persist: B4Persist(),
            cachePolicy: policy,
            shouldStore: (_) => true,
            clone: DiomanClonePolicy.deep),
        TestPlugin(b4LiteralSource,
            stage: DiomanStage.source,
            handler: (ctx, next) async => scriptedResult(ctx, diomanTestBiz,
                status: 409, reason: b4LiteralSource, data: body))
      ]);
      final first =
          await api.send<Object?>(b4Get, b4Path, call: b4Call(cache: true));
      body[1][0] = 9;
      (first.data as Map)[1][0] = 7;
      final hit =
          await api.send<Object?>(b4Get, b4Path, call: b4Call(cache: true));
      expect(hit.data, {
        1: [2]
      });
      expect([hit.ok, outcomeOf(hit), hit.status, failureOf(hit)?.reason],
          [false, diomanTestBiz, 200, null]);
      (hit.data as Map)[1][0] = 8;
      expect(
          (await api.send<Object?>(b4Get, b4Path, call: b4Call(cache: true)))
              .data,
          {
            1: [2]
          });
      expect(api.plugin<DiomanCacheApi>()!.pendingWrites, 0);
      api.dispose();
    }
  });
}
