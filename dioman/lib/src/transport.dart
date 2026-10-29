import 'dart:async';
import 'package:dio/dio.dart';
import 'context.dart';
import 'response.dart';

/// 全部 HTTP 状态交给工厂，不让 Dio 构造 badResponse。
bool _acceptStatus(int? _) => true;

/// 递归克隆 JSON 请求体；FormData 使用 Dio 的 clone，其他类型保留身份。
Object? _clone(Object? value, DiomanLogger log) {
  if (value is Map) return value.map((k, v) => MapEntry(k, _clone(v, log)));
  if (value is List) return value.map((v) => _clone(v, log)).toList();
  if (value is FormData) return value.clone();
  if (value != null && value is! num && value is! bool && value is! String) {
    log('请求体无法克隆，回退原引用');
  }
  return value;
}

/// 执行一次发送；传输构造、Dio 及工厂异常都在本边界归一化。
Future<DiomanResponse<dynamic>>
    diomanTransport<R extends DiomanResponse<dynamic>>(
        Dio dio, DiomanContext<R> ctx) async {
  try {
    final cancelled = ctx.cancelled();
    if (cancelled != null) return cancelled;
    final options = ctx.request.toRequestOptions()
      ..validateStatus = _acceptStatus
      ..cancelToken = ctx.cancelToken;
    if (ctx.replayable) options.data = _clone(options.data, ctx.log);
    final raw = await dio.fetch<dynamic>(options);
    return ctx.factory
        .normalize(ctx.request, raw: raw, cancelled: ctx.isCancelled);
  } catch (e, s) {
    return ctx.factory
        .normalize(ctx.request, error: e, stack: s, cancelled: ctx.isCancelled);
  }
}
