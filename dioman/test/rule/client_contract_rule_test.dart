import 'package:dioman/dioman.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';
import '../support/helpers.dart';

/// 本文件共用的测试值。
const _diomanLiteral0 = 'GET';

/// 本文件共用的测试值。
const _diomanLiteral1 = '/debug';

/// 取消原因的统一测试值。
const _reason = 'user-stop';

/// 取消入口、下一层短路和选项诊断的规则回归。
void main() {
  test('[DiomanContext.cancelled][Dioman.cancelAll] next 已取消不进内层，原因一致',
      () async {
    for (final all in [false, true]) {
      for (final preCancelled in [false, true]) {
        final token = CancelToken();
        if (preCancelled) token.cancel(_reason);
        var inner = 0;
        final api = testClient(plugins: [
          TestPlugin('cancel', stage: DiomanStage.outer,
              handler: (ctx, next) async {
            if (all) {
              ctx.client.cancelAll(_reason);
            } else {
              token.cancel(_reason);
            }
            await flush();
            return next();
          }),
          TestPlugin('inner', handler: (ctx, next) async {
            inner++;
            return next();
          })
        ]);
        final result = await api.send<Object?>(_diomanLiteral0, '/cancel',
            call: DiomanCall(cancelToken: token));
        expect(failureOf(result)?.kind, DiomanFailureKind.cancel);
        expect(failureOf(result)?.reason, _reason);
        expect(inner, 0);
        expect(api.pending, 0);
      }
    }
  });
  test('[Dioman.new(debug)] 未装插件的选项每客户端只告警一次，安装后无误报', () async {
    final logs = <String>[];
    final api = testClient(debug: logs.add);
    final call = DiomanCall(options: {DiomanRetry.option: false});
    for (var i = 0; i < 2; i++) {
      await api.send<Object?>(_diomanLiteral0, _diomanLiteral1, call: call);
    }
    expect(logs, hasLength(1));
    expect(logs.single, contains(DiomanRetry.pluginName));
    api.use(const DiomanRetry());
    await api.send<Object?>(_diomanLiteral0, _diomanLiteral1, call: call);
    expect(logs, hasLength(1));
    final quiet = testClient(debug: false);
    await quiet.send<Object?>(_diomanLiteral0, _diomanLiteral1, call: call);
  });
  test('[Dioman.new(response)] 扩展类型缺 create 构造期报错且说明修法', () {
    final dio = Dio();
    expect(
        () => Dioman<_Extended>(dio: dio),
        throwsA(isA<ArgumentError>()
            .having((e) => e.message.toString(), '修法', contains('create:'))));
    expect(
        () => Dioman<_Extended>(
            dio: dio, response: const DiomanResponseFactory<_Extended>()),
        throwsArgumentError);
    final api = Dioman<_Extended>(
        dio: dio, response: DiomanResponseFactory(create: _Extended.new));
    api.dispose();
    final base = Dioman(dio: dio);
    base.dispose();
  });
}

/// 测试自定义工厂的结果类型。
class _Extended extends DiomanResponse<dynamic> {
  /// 从基础结果构造扩展结果。
  _Extended(DiomanResponse<dynamic> result)
      : super(ok: result.ok, status: result.status, request: result.request);
}
