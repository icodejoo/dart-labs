import 'package:dioman/dioman.dart';
import 'package:test/test.dart';
import '../support/source_test_helpers.dart';
import '../support/helpers.dart';

/// 缓存不能持有程序错误或取消结果。
void main() {
  for (final kind in [DiomanFailureKind.internal, DiomanFailureKind.cancel]) {
    test('[DiomanCache.shouldStore] $kind 硬否决不写内存和磁盘，也不调用覆盖回调', () async {
      final store = B4Persist();
      var calls = 0;
      var decisions = 0;
      final api = testClient(plugins: [
        DiomanCache(
            persist: store,
            cachePolicy: DiomanCachePolicy.both,
            shouldStore: (_) {
              decisions++;
              return true;
            }),
        TestPlugin('failure', stage: DiomanStage.source,
            handler: (ctx, next) async {
          calls++;
          return ctx.fail(kind);
        })
      ]);
      for (var i = 0; i < 2; i++) {
        final pending =
            api.send<Object?>(b4Get, b4Path, call: b4Call(cache: true));
        if (kind == DiomanFailureKind.internal) {
          await expectLater(pending, throwsStateError);
        } else {
          expect(failureOf(await pending)?.kind, kind);
        }
      }
      expect(calls, 2);
      expect(decisions, 0);
      expect(store.writes, 0);
      expect(store.values, isEmpty);
    });
  }
}
