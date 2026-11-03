import 'package:dioman/dioman.dart';
import 'package:test/test.dart';
import '../support/b4_helpers.dart';
import '../support/fake_network.dart';
import '../support/helpers.dart';

/// 本文件共用的测试字面量。
const _r2aLiteral0 = 'queued';

/// 本文件共用的测试字面量。
const _r2aLiteral1 = 'result';

/// 本文件共用的测试字面量。
const _r2aLiteral2 = 'kind';

/// 本文件共用的测试字面量。
const _r2aLiteral3 = 'offline';

/// 本文件共用的测试字面量。
const _r2aLiteral4 = 'ok';

/// 本文件共用的测试字面量。
const _r2aLiteral5 = 'data';

/// 本文件共用的测试字面量。
const _r2aLiteral6 = 'expiresAt';

/// 本文件共用的测试字面量。
const _r2aLiteral7 = 'code';

/// 本文件共用的测试字面量。
const _r2aLiteral8 = 'fresh';

/// 持久化新旧格式的失败事实兼容。
void main() {
  test(
      '[DiomanCachePersist.read][DiomanCachePersist.write][DiomanFailure.kind][DiomanFailure.reason] 新条目保留标记，B4 与 0.7 条目仍可读取',
      () async {
    final store = B4Persist();
    final api = testClient(plugins: [
      DiomanCache(
          persist: store,
          cachePolicy: DiomanCachePolicy.persist,
          shouldStore: (_) => true),
      TestPlugin('failure',
          stage: DiomanStage.source,
          handler: (ctx, _) async =>
              ctx.fail(DiomanFailureKind.offline, reason: _r2aLiteral0))
    ]);
    final call = b4Call(cache: true);
    final first = await api.send<Object?>(b4Get, b4Path, call: call);
    final saved = store.values.values.single as Map;
    expect((saved[_r2aLiteral1] as Map)[_r2aLiteral2], _r2aLiteral3);
    final hit = await api.send<Object?>(b4Get, b4Path, call: call);
    expect(hit.ok, isFalse);
    expect(failureOf(hit)?.kind, failureOf(first)?.kind);
    expect(failureOf(hit)?.reason, _r2aLiteral0);
    final key = store.values.keys.single;
    for (final kind in [_r2aLiteral4, 'http', 'biz', _r2aLiteral3]) {
      store.values[key] = {
        _r2aLiteral5: null,
        _r2aLiteral6: 9999999999999,
        _r2aLiteral1: {
          _r2aLiteral2: kind,
          'status': 401,
          'httpStatus': 200,
          _r2aLiteral7: 401,
          'message': '',
          _r2aLiteral5: 7,
          'reason': 'old'
        }
      };
      final old = await api.send<Object?>(b4Get, b4Path, call: call);
      expect(old.status, 200);
      expect(old.code, 401);
      expect(old.ok, kind == _r2aLiteral4);
      expect(failureOf(old)?.kind,
          kind == _r2aLiteral3 ? DiomanFailureKind.offline : null);
    }
    store.values[key] = {
      _r2aLiteral5: {_r2aLiteral7: 0, _r2aLiteral5: 9},
      _r2aLiteral6: 9999999999999
    };
    expect((await api.send<Object?>(b4Get, b4Path, call: call)).data, 9);
    final network = FakeNetwork();
    final success = testClient(network: network, plugins: [
      DiomanCache(persist: store, cachePolicy: DiomanCachePolicy.persist)
    ]);
    await success.send<Object?>(b4Get, '/fresh',
        call: b4Call(cache: true, key: _r2aLiteral8));
    final fresh = store.values[_r2aLiteral8] as Map;
    expect((fresh[_r2aLiteral1] as Map).containsKey(_r2aLiteral2), isFalse);
  });
}
