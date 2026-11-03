import 'package:dioman/dioman.dart';
import 'package:dioman/src/response.dart' show DiomanResponseInternal;

/// 测试共用的ok结果标识。
const diomanTestOk = 'ok';

/// 测试共用的http结果标识。
const diomanTestHttp = 'http';

/// 测试共用的biz结果标识。
const diomanTestBiz = 'biz';

/// 测试共用的cancel结果标识。
const diomanTestCancel = 'cancel';

/// 测试共用的timeout结果标识。
const diomanTestTimeout = 'timeout';

/// 测试共用的network结果标识。
const diomanTestNetwork = 'network';

/// 测试共用的parse结果标识。
const diomanTestParse = 'parse';

/// 测试共用的auth结果标识。
const diomanTestAuth = 'auth';

/// 测试共用的breaker结果标识。
const diomanTestBreaker = 'breaker';

/// 测试共用的offline结果标识。
const diomanTestOffline = 'offline';

/// 测试共用的internal结果标识。
const diomanTestInternal = 'internal';

/// 用公开契约描述结果，供组合基线逐项比较。
String outcomeOf(DiomanResponse<dynamic> result) =>
    failureOf(result)?.kind.name ??
    (result.ok
        ? diomanTestOk
        : result.status < 200 || result.status >= 300
            ? diomanTestHttp
            : diomanTestBiz);

/// 构造脚本化结果；测试内部入口附标记，HTTP/业务失败由状态与业务码表达。
DiomanResponse<dynamic> scriptedResult(DiomanContext ctx, String kind,
    {int status = 0,
    String message = '',
    String? reason,
    Object? data,
    Object? error,
    StackTrace? errorStack}) {
  final result = DiomanResponse<dynamic>(
      ok: kind == diomanTestOk,
      status: kind == diomanTestBiz ? 200 : status,
      code: kind == diomanTestBiz ? (status == 0 ? 1 : status) : 0,
      message: message,
      data: data,
      request: ctx.request,
      error: null);
  if (kind != diomanTestOk && kind != diomanTestHttp && kind != diomanTestBiz) {
    DiomanResponseInternal.restore(
        result, DiomanFailureKind.values.byName(kind),
        reason: reason, error: error, errorStack: errorStack);
  }
  return ctx.factory.derive(result, data);
}

/// 使用者显式选择的业务风格有效状态，不改写 HTTP status。
int businessStatus(DiomanResponse<dynamic> r) =>
    r.status >= 200 && r.status < 300 && r.code is int && r.code != 0
        ? r.code as int
        : r.status;
