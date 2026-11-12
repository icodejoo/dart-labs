import 'package:dioman/dioman.dart';
import 'package:test/test.dart';
import '../support/helpers.dart';
import '../support/fake_network.dart';

/// 本主题共用的测试值。
const _diomanLiteral0 = "invalid";

/// 本主题共用的测试值。
const _diomanLiteral1 = "GET";

/// 本主题共用的测试值。
const _diomanLiteral2 = "/options";

/// 请求级宽类型字段的调试校验。
void main() {
  test('[DiomanRetryOptions.jitter][Dioman.new(debug)] debug 在成功请求前拒绝非法 jitter',
      () async {
    for (final value in [
      null,
      false,
      true,
      (Duration d) => d,
      _diomanLiteral0
    ]) {
      final api = testClient(debug: true, plugins: [const DiomanRetry()]);
      final pending = api.send<Object?>(_diomanLiteral1, _diomanLiteral2,
          call: DiomanCall(options: {
            DiomanRetry.option: DiomanRetryOptions(jitter: value)
          }));
      if (value is String) {
        await expectLater(pending, throwsArgumentError);
      } else {
        expect((await pending).ok, isTrue);
      }
    }
    final quiet = testClient(plugins: [const DiomanRetry()]);
    expect(
        (await quiet.send<Object?>(_diomanLiteral1, _diomanLiteral2,
                call: DiomanCall(options: {
                  DiomanRetry.option:
                      const DiomanRetryOptions(jitter: _diomanLiteral0)
                })))
            .ok,
        isTrue);
  });

  test('[DiomanCacheOptions.clone][Dioman.new(debug)] debug 在首次缓存写入前拒绝非法 clone',
      () async {
    for (final value in [
      ...DiomanClonePolicy.values,
      (Object? v) => v,
      _diomanLiteral0
    ]) {
      final network = FakeNetwork();
      final api = testClient(
          network: network, debug: true, plugins: [const DiomanCache()]);
      final pending = api.send<Object?>(_diomanLiteral1, _diomanLiteral2,
          call: DiomanCall(
              options: {DiomanCache.option: DiomanCacheOptions(clone: value)}));
      if (value is String) {
        await expectLater(pending, throwsArgumentError);
        expect(network.sends, isEmpty);
      } else {
        expect((await pending).ok, isTrue);
      }
    }
    final quiet = testClient(plugins: [const DiomanCache()]);
    await expectLater(
        quiet.send<Object?>(_diomanLiteral1, _diomanLiteral2,
            call: DiomanCall(options: {
              DiomanCache.option:
                  const DiomanCacheOptions(clone: _diomanLiteral0)
            })),
        throwsArgumentError);
  });
}
