import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'context.dart';
import 'response.dart';

/// 全部 HTTP 状态交给工厂，不让 Dio 构造 badResponse。
bool _acceptStatus(int? _) => true;

/// 只保存原解码器和 HTTP 快照，避免响应配置持有整个传输作用域。
class _ResponseDecoder {
  /// 保存调用方解码器。
  _ResponseDecoder(this.decoder);

  /// 原始解码器，未提供时使用 Dio 的默认文本规则。
  final ResponseDecoder? decoder;

  /// Dio 解码抛错时用于补回 HTTP 元信息。
  Response<dynamic>? response;

  /// 先保存响应快照，再执行原解码或默认解码。
  FutureOr<String?> call(
      List<int> bytes, RequestOptions request, ResponseBody body) {
    response = Response<dynamic>(
        requestOptions: request,
        statusCode: body.statusCode,
        headers: Headers.fromMap(body.headers));
    if (decoder != null) return decoder!(bytes, request, body);
    if (bytes.isEmpty &&
        request.responseType == ResponseType.json &&
        Transformer.isJsonMimeType(
            body.headers[Headers.contentTypeHeader]?.first)) {
      return null;
    }
    return utf8.decode(bytes, allowMalformed: true);
  }
}

/// 递归克隆 JSON 请求体；FormData 使用 Dio 的 clone，其他类型保留身份。
Object? _clone(Object? value, DiomanLogger log) {
  if (value is Map) return value.map((k, v) => MapEntry(k, _clone(v, log)));
  if (value is Uint8List) return Uint8List.fromList(value);
  if (value is List<int>) return List<int>.of(value);
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
  _ResponseDecoder? decoding;
  try {
    final cancelled = ctx.cancelled();
    if (cancelled != null) return cancelled;
    if (!ctx.bodyReplayable &&
        !ctx.state.consumedBodies.add(ctx.request.data!)) {
      throw StateError('插件错误：不可重放请求体被重复发送');
    }
    ctx.state.sentRequest = ctx.request;
    final options = ctx.request.toRequestOptions()
      ..validateStatus = _acceptStatus
      ..cancelToken = ctx.cancelToken;
    decoding = _ResponseDecoder(options.responseDecoder);
    options.responseDecoder = decoding.call;
    if (ctx.replayable) options.data = _clone(options.data, ctx.log);
    final raw = await dio.fetch<dynamic>(options);
    return ctx.factory
        .normalize(ctx.request, raw: raw, cancelled: ctx.isCancelled);
  } catch (e, s) {
    final error =
        e is DioException && e.error is FormatException && e.response == null
            ? e.copyWith(response: decoding?.response)
            : e;
    return ctx.factory.normalize(ctx.request,
        error: error, stack: s, cancelled: ctx.isCancelled);
  }
}
