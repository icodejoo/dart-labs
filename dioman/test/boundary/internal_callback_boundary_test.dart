import 'package:dioman/dioman.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';
import '../support/helpers.dart';

/// 本文件共用的测试字面量。
const _r2aLiteral0 = '/bug';

/// 本文件共用的测试字面量。
const _r2aLiteral1 = 'callback-original-stack';

/// 回调异常不能按传输异常分类。
void main() {
  for (final mapper in [false, true]) {
    test(
        '[DiomanContext.statusOf][INV-pipeline-internals] 回调抛出任意 DioException 仍按程序错误原栈抛出 mapper=$mapper',
        () async {
      for (final type in DioExceptionType.values) {
        final error = DioException(
            requestOptions: RequestOptions(path: _r2aLiteral0),
            type: type,
            error: StateError('cause'));
        final stack = StackTrace.fromString(_r2aLiteral1);
        DiomanResponse<dynamic>? seen;
        final api = testClient(
            statusOf:
                mapper ? (_) => Error.throwWithStackTrace(error, stack) : null,
            plugins: [
              TestPlugin('outer', stage: DiomanStage.outer,
                  handler: (ctx, next) async {
                seen = await next();
                return seen!;
              }),
              if (mapper) const DiomanRetry(max: 1),
              if (!mapper)
                TestPlugin('throw',
                    handler: (ctx, next) async =>
                        Error.throwWithStackTrace(error, stack)),
            ]);
        try {
          await api.send<Object?>('GET', _r2aLiteral0);
          fail('必须抛出程序异常');
        } catch (actual, actualStack) {
          expect(actual, same(error));
          expect(actualStack.toString(), contains(_r2aLiteral1));
        }
        expect(failureOf(seen!)?.kind, DiomanFailureKind.internal);
        expect(api.pending, 0);
        api.dispose();
      }
    });
  }
}
