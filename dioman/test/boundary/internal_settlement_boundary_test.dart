import '../support/b2_constants.dart';
import 'package:dioman/dioman.dart';
import 'package:test/test.dart';
import '../support/helpers.dart';

/// 验证插件自行构造的不完整 internal 结果仍按内核契约落定。
void main() {
  test(
      '[DiomanFailure.message]'
      '[Dioman.send] internal 缺 error 时抛明确 StateError', () async {
    final api = testClient(plugins: [
      TestPlugin(b2Incomplete,
          handler: (ctx, _) async =>
              ctx.fail(const DiomanFailure(kind: DiomanKind.internal))),
    ]);
    await expectLater(
        api.send<Object?>(b2Get, b2InternalPath),
        throwsA(isA<StateError>().having(
            (e) => e.message, 'message', 'internal result without error')));
    expect(api.pending, 0);
  });
  test(
      '[DiomanFailure.error][DiomanFailure.kind][DiomanKind.internal]'
      '[Dioman.send] internal 缺 stack 时保留原 error 并补当前栈', () async {
    final error = StateError('sentinel');
    final api = testClient(plugins: [
      TestPlugin(b2Incomplete,
          handler: (ctx, _) async =>
              ctx.fail(DiomanFailure(kind: DiomanKind.internal, error: error))),
    ]);
    await expectLater(
        api.send<Object?>(b2Get, b2InternalPath), throwsA(same(error)));
    expect(api.pending, 0);
  });
}
