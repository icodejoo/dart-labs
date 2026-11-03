import 'network_error_stub.dart' if (dart.library.io) 'network_error_io.dart';
import 'package:dio/dio.dart';
import 'request.dart';

part 'response_internal.dart';

/// 缺省消息。
const _emptyMessage = '';

/// 默认协议字段。
const _codeField = 'code', _dataField = 'data', _messageField = 'message';

/// 内核失败类别；HTTP 与业务失败使用 ok、status、code 表达。
enum DiomanFailureKind {
  /// 调用已取消。
  cancel,

  /// 传输超时。
  timeout,

  /// 连接失败。
  network,

  /// 响应解析失败。
  parse,

  /// 鉴权失败。
  auth,

  /// 熔断拒绝。
  breaker,

  /// 离线拒绝。
  offline,

  /// 程序错误。
  internal
}

/// 内核写入的只读失败事实；通过 failureOf 读取。
class DiomanFailure {
  /// 仅内核构造失败标记。
  const DiomanFailure._(this.kind, this.reason);

  /// 封闭失败类别。
  final DiomanFailureKind kind;

  /// 可选细分原因。
  final String? reason;
}

/// 读取 [result] 的内核失败事实；成功、HTTP 和业务失败返回 null。
/// 示例：`failureOf(result)?.kind == DiomanFailureKind.network`。
DiomanFailure? failureOf(DiomanResponse<dynamic> result) => result._failure;

/// 判断 [error] 是否是取消结果；例如 `isDiomanCancel(error)`。
bool isDiomanCancel(Object? error) =>
    error is DiomanResponse &&
    failureOf(error)?.kind == DiomanFailureKind.cancel;

/// parse 返回的业务字段；缺省码为 0、消息为空、数据为空。
class DiomanParsed {
  /// 转换业务协议，例如 `DiomanParsed(code: 0, data: body)`。
  const DiomanParsed({this.code = 0, this.data, this.message = _emptyMessage});

  /// 业务码。
  final Object? code;

  /// 业务数据。
  final Object? data;

  /// 业务消息。
  final String message;
}

/// 默认协议转换：含 code 且含 data/message 之一才拆信封。
DiomanParsed _parse(Object? body, Response<dynamic> raw) {
  if (body is Map &&
      body.containsKey(_codeField) &&
      (body.containsKey(_dataField) || body.containsKey(_messageField))) {
    return DiomanParsed(
        code: body[_codeField] ?? 0,
        data: body[_dataField],
        message: '${body[_messageField] ?? _emptyMessage}');
  }
  return DiomanParsed(data: body);
}

/// 不可变归一化结果，同时是可预期失败的异常载体。
class DiomanResponse<D> implements Exception {
  /// 用 HTTP 状态和业务字段构造响应；内核失败由 ctx.fail 创建。
  /// 例如 `DiomanResponse(ok: true, status: 200, request: request)`。
  DiomanResponse(
      {required bool ok,
      required this.status,
      this.code = 0,
      this.message = _emptyMessage,
      this.data,
      required this.request,
      this.raw,
      this.error,
      this.errorStack,
      this.callSite})
      : _ok = ok;

  /// 是否成功。
  bool get ok => _failure == null && _ok;

  /// 工厂业务判定。
  final bool _ok;

  /// 内核失败事实。
  DiomanFailure? _failure;

  /// HTTP 状态，未收到响应为零。
  final int status;

  /// 原始业务码。
  final Object? code;

  /// 结果消息。
  final String message;

  /// 已拆包的数据。
  final D? data;

  /// 产生此结果的请求。
  final DiomanRequest request;

  /// Dio 原始响应。
  final Response<dynamic>? raw;

  /// 首次程序异常或传输异常。
  final Object? error;

  /// 原始异常栈。
  final StackTrace? errorStack;

  /// debug 模式下的调用点。
  final StackTrace? callSite;

  /// 派生指定数据类型及调用点；原对象不会被修改。
  DiomanResponse<T> copy<T>({StackTrace? callSite}) => DiomanResponse<T>(
      ok: ok,
      status: status,
      code: code,
      message: message,
      data: ok ? data as T? : (data is T ? data as T : null),
      request: request,
      raw: raw,
      error: error,
      errorStack: errorStack,
      callSite: callSite ?? this.callSite)
    .._failure = _failure;

  /// 安全描述只包含标量，避免 raw、data 或 error 的循环引用及自定义 toString。
  @override
  String toString() => 'DiomanResponse($ok, $status, $message)';
}

/// 响应判定服务；钩子抛错按程序错误处理。
class DiomanResponseFactory<R extends DiomanResponse<dynamic>> {
  /// 配置协议转换、成功判定和扩展构造器。
  /// 例如 `DiomanResponseFactory(parse: (body, raw) => DiomanParsed(data: body))`。
  const DiomanResponseFactory(
      {this.parse = _parse,
      this.isSuccess,
      this.expectJson = false,
      this.create});

  /// 将 [body] 和原始响应转换为业务字段。
  final DiomanParsed Function(Object? body, Response<dynamic> raw) parse;

  /// 仅 HTTP 2xx 时调用；默认业务码为 0 或 '0' 成功。
  final bool Function(Object?)? isSuccess;

  /// 严格 JSON：json 模式的 2xx 非空文本视为解析失败。
  /// 显式 plain、bytes、stream 不判 parse，例如 `DiomanResponseFactory(expectJson: true)`。
  final bool expectJson;

  /// 构造扩展结果；内核失败事实在返回后写入。
  final R Function(DiomanResponse<dynamic>)? create;

  /// 扩展构造后保护失败事实，坏工厂保留首次异常。
  DiomanResponse<dynamic> _finish(DiomanResponse<dynamic> init) {
    try {
      final result = create == null ? init : create!(init);
      DiomanResponseInternal.mark(result, init._failure);
      if (init._failure?.kind == DiomanFailureKind.internal &&
          init.error != null &&
          (!identical(result.error, init.error) ||
              !identical(result.errorStack, init.errorStack))) {
        return _internal(
            init.request, init.error!, init.errorStack ?? StackTrace.current,
            status: init.status, raw: init.raw);
      }
      return result;
    } catch (e, s) {
      return _internal(init.request, init.error ?? e, init.errorStack ?? s,
          status: init.status, raw: init.raw);
    }
  }

  /// 用 [data] 派生 [result]，保留内核事实并经过扩展构造器。
  /// 例如 `factory.derive(result, copiedData)`。
  DiomanResponse<dynamic> derive(
          DiomanResponse<dynamic> result, Object? data) =>
      _finish(DiomanResponse<dynamic>(
          ok: result.ok,
          status: result.status,
          code: result.code,
          message: result.message,
          data: data,
          request: result.request,
          raw: result.raw,
          error: result.error,
          errorStack: result.errorStack,
          callSite: result.callSite)
        .._failure = result._failure);

  /// 不经过用户钩子的内部错误回退。
  static DiomanResponse<dynamic> _internal(
          DiomanRequest request, Object error, StackTrace stack,
          {int status = 0, Response<dynamic>? raw}) =>
      DiomanResponse<dynamic>(
          ok: false,
          status: status,
          raw: raw,
          request: request,
          error: error,
          errorStack: stack)
        .._failure = const DiomanFailure._(DiomanFailureKind.internal, null);

  /// 用封闭类别生成失败；[reason] 为可选细分原因。
  /// 示例：`factory.fail(request, DiomanFailureKind.offline, reason: 'timeout')`。
  DiomanResponse<dynamic> fail(DiomanRequest request, DiomanFailureKind kind,
          {String? reason}) =>
      _finish(DiomanResponse<dynamic>(ok: false, status: 0, request: request)
        .._failure = DiomanFailure._(kind, reason));

  /// 分类响应或异常；取消优先，判定钩子异常回退 internal。
  DiomanResponse<dynamic> normalize(DiomanRequest request,
      {Response<dynamic>? raw,
      Object? error,
      StackTrace? stack,
      bool cancelled = false}) {
    try {
      final source = raw ?? (error is DioException ? error.response : null);
      final status = source?.statusCode ?? 0;
      DiomanFailureKind? kind;
      if (cancelled) {
        kind = DiomanFailureKind.cancel;
      } else if (error != null) {
        kind = DiomanFailureKind.internal;
        if (error is DioException) {
          switch (error.type) {
            case DioExceptionType.connectionTimeout:
            case DioExceptionType.sendTimeout:
            case DioExceptionType.receiveTimeout:
              kind = DiomanFailureKind.timeout;
            case DioExceptionType.connectionError:
            case DioExceptionType.badCertificate:
              kind = DiomanFailureKind.network;
            case DioExceptionType.badResponse:
              kind = null;
            case DioExceptionType.cancel:
              kind = DiomanFailureKind.cancel;
            case DioExceptionType.unknown:
              final cause = error.error;
              if (cause is FormatException) {
                kind = DiomanFailureKind.parse;
              } else if (isDiomanNetworkError(cause)) {
                kind = DiomanFailureKind.network;
              }
            default:
              break;
          }
        }
      }
      if (cancelled || error != null) {
        final result = DiomanResponse<dynamic>(
            ok: false,
            status: status,
            request: request,
            raw: source,
            error: error is DioException ? error.error ?? error : error,
            errorStack: error is DioException
                ? error.stackTrace
                : stack ?? StackTrace.current);
        if (kind != null) result._failure = DiomanFailure._(kind, null);
        return _finish(result);
      }
      final response = raw!;
      final httpOk = status >= 200 && status < 300;
      final body = response.data;
      if (httpOk &&
          expectJson &&
          request.toRequestOptions().responseType == ResponseType.json &&
          body is String &&
          body.isNotEmpty) {
        return _finish(DiomanResponse<dynamic>(
            ok: false,
            status: status,
            data: body,
            request: request,
            raw: response)
          .._failure = const DiomanFailure._(DiomanFailureKind.parse, null));
      }
      final fields = parse(body, response);
      return _finish(DiomanResponse<dynamic>(
          ok: httpOk &&
              (isSuccess?.call(fields.code) ??
                  (fields.code == 0 || fields.code == '0')),
          status: status,
          code: fields.code,
          message: fields.message,
          data: fields.data,
          request: request,
          raw: response));
    } catch (e, s) {
      return _internal(request, e, s, status: raw?.statusCode ?? 0, raw: raw);
    }
  }
}
