import 'dart:io';
import 'package:dio/dio.dart';
import 'request.dart';

/// 空消息与缺省头值。
const _emptyMessage = '';

/// 链内统一使用的结果类别。
enum DiomanKind {
  ok,
  http,
  biz,
  network,
  timeout,
  cancel,
  parse,
  auth,
  breaker,
  offline,
  internal
}

/// 业务信封字段；含 code 且含 data/message 之一才默认识别。
class Envelope {
  /// 定制字段，例如 `Envelope(code: 'status')`。
  const Envelope(
      {this.code = 'code', this.data = 'data', this.message = 'message'});

  /// 业务码字段。
  final String code;

  /// 数据字段。
  final String data;

  /// 消息字段。
  final String message;
}

/// 不可变归一化结果，同时是可预期失败的异常载体。
class DiomanResponse<D> implements Exception {
  /// 创建已分类的结果；插件通常通过 ctx.fail 构造。
  const DiomanResponse(
      {required this.ok,
      required this.kind,
      required this.status,
      required this.httpStatus,
      this.code,
      this.message = _emptyMessage,
      required this.data,
      this.reason,
      required this.request,
      this.raw,
      this.error,
      this.errorStack,
      this.callSite});

  /// 是否成功。
  final bool ok;

  /// 结果类别。
  final DiomanKind kind;

  /// 插件读取的逻辑状态。
  final int status;

  /// 原始 HTTP 状态，未收到为零。
  final int httpStatus;

  /// 原始业务码。
  final Object? code;

  /// 结果消息。
  final String message;

  /// 已拆包的数据。
  final D? data;

  /// 插件失败的细分原因。
  final String? reason;

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
      kind: kind,
      status: status,
      httpStatus: httpStatus,
      code: code,
      message: message,
      data: ok ? data as T? : (data is T ? data as T : null),
      reason: reason,
      request: request,
      raw: raw,
      error: error,
      errorStack: errorStack,
      callSite: callSite ?? this.callSite);

  /// 安全描述只包含标量，避免 raw、data 或 error 的循环引用及自定义 toString。
  @override
  String toString() => 'DiomanResponse(${kind.name}, $status, $message)';
}

/// 插件凭空生成失败的输入。
class DiomanFailure {
  /// 指定 [kind] 和细分字段，例如 `DiomanFailure(kind: DiomanKind.offline)`。
  const DiomanFailure(
      {required this.kind,
      this.status = 0,
      this.message = _emptyMessage,
      this.reason,
      this.data,
      this.error,
      this.errorStack});

  /// 类别。
  final DiomanKind kind;

  /// 逻辑状态。
  final int status;

  /// 消息。
  final String message;

  /// 细分原因。
  final String? reason;

  /// 失败附带数据。
  final Object? data;

  /// 原始异常。
  final Object? error;

  /// 原始栈。
  final StackTrace? errorStack;
}

/// 响应判定服务；钩子只在收到适用响应时执行。
class DiomanResponseFactory<R extends DiomanResponse<dynamic>> {
  /// 定制信封与判定，例如 `DiomanResponseFactory(envelope: null)`。
  const DiomanResponseFactory(
      {this.envelope = const Envelope(),
      this.isEnvelope,
      this.isSuccess,
      this.logicalStatus,
      this.expectJson = false,
      this.create});

  /// null 关闭信封识别。
  final Envelope? envelope;

  /// 自定义信封识别，call.envelope=false 优先。
  final bool Function(Map<dynamic, dynamic>)? isEnvelope;

  /// 只对 2xx 信封调用的成功判定。
  final bool Function(Object?)? isSuccess;

  /// 收到响应后的逻辑状态映射。
  final int Function(DiomanResponse<dynamic>)? logicalStatus;

  /// 声明 JSON 但仍是非空字符串时判 parse。
  final bool expectJson;

  /// 构造扩展结果；抛错时内核使用基础结果，避免再次调用坏钩子。
  final R Function(DiomanResponse<dynamic>)? create;

  /// 经扩展构造器创建结果；坏工厂回退 internal 并保留首次程序异常。
  DiomanResponse<dynamic> _finish(DiomanResponse<dynamic> init) {
    try {
      return create == null ? init : create!(init);
    } catch (e, s) {
      return _internal(init.request, init.error ?? e, init.errorStack ?? s);
    }
  }

  /// 带调用点派生结果并重新经过扩展构造器；不修改共享结果。
  DiomanResponse<dynamic> withCallSite(
          DiomanResponse<dynamic> result, StackTrace callSite) =>
      _finish(result.copy<dynamic>(callSite: callSite));

  /// 用 [data] 派生 [result] 并经扩展工厂；例如缓存克隆保持业务元信息。
  DiomanResponse<dynamic> derive(
          DiomanResponse<dynamic> result, Object? data) =>
      _finish(DiomanResponse<dynamic>(
          ok: result.ok,
          kind: result.kind,
          status: result.status,
          httpStatus: result.httpStatus,
          code: result.code,
          message: result.message,
          data: data,
          reason: result.reason,
          request: result.request,
          raw: result.raw,
          error: result.error,
          errorStack: result.errorStack,
          callSite: result.callSite));

  /// 直接构造不依赖用户回调的 internal。
  static DiomanResponse<dynamic> _internal(
          DiomanRequest request, Object error, StackTrace stack) =>
      DiomanResponse(
          ok: false,
          kind: DiomanKind.internal,
          status: 0,
          httpStatus: 0,
          data: null,
          request: request,
          error: error,
          errorStack: stack);

  /// 将 [failure] 经过扩展点创建结果；例如 `factory.fail(request, failure)`。
  DiomanResponse<dynamic> fail(DiomanRequest request, DiomanFailure failure) =>
      _finish(DiomanResponse(
          ok: failure.kind == DiomanKind.ok,
          kind: failure.kind,
          status: failure.status,
          httpStatus: 0,
          message: failure.message,
          data: failure.data,
          request: request,
          reason: failure.reason,
          error: failure.error,
          errorStack: failure.errorStack));

  /// 分类响应或异常；[cancelled] 的优先级最高，任何钩子异常都归 internal。
  DiomanResponse<dynamic> normalize(DiomanRequest request,
      {Response<dynamic>? raw,
      Object? error,
      StackTrace? stack,
      bool cancelled = false}) {
    try {
      if (cancelled) {
        return fail(
            request,
            DiomanFailure(
                kind: DiomanKind.cancel, error: error, errorStack: stack));
      }
      if (error != null) {
        var kind = DiomanKind.internal;
        var status = 0;
        if (error is DioException) {
          switch (error.type) {
            case DioExceptionType.connectionTimeout:
            case DioExceptionType.sendTimeout:
            case DioExceptionType.receiveTimeout:
              kind = DiomanKind.timeout;
            case DioExceptionType.connectionError:
            case DioExceptionType.badCertificate:
              kind = DiomanKind.network;
            case DioExceptionType.badResponse:
              kind = DiomanKind.http;
              status = error.response?.statusCode ?? 0;
            case DioExceptionType.unknown:
              final cause = error.error;
              if (cause is SocketException ||
                  cause is HttpException ||
                  cause is TlsException) {
                kind = DiomanKind.network;
              }
            case DioExceptionType.cancel:
              return fail(
                  request,
                  DiomanFailure(
                      kind: DiomanKind.cancel,
                      error: error,
                      errorStack: stack));
            default:
              break;
          }
        }
        final cause = error is DioException ? error.error ?? error : error;
        return _finish(DiomanResponse(
            ok: false,
            kind: kind,
            status: status,
            httpStatus: status,
            data: null,
            request: request,
            error: cause,
            errorStack: error is DioException
                ? error.stackTrace
                : stack ?? StackTrace.current,
            raw: error is DioException ? error.response : null));
      }
      final response = raw!;
      final http = response.statusCode ?? 0;
      final httpOk = http >= 200 && http < 300;
      final body = response.data;
      if (httpOk &&
          expectJson &&
          body is String &&
          body.isNotEmpty &&
          (response.headers.value(Headers.contentTypeHeader) ?? _emptyMessage)
              .toLowerCase()
              .contains('json')) {
        return _finish(DiomanResponse(
            ok: false,
            kind: DiomanKind.parse,
            status: http,
            httpStatus: http,
            data: body,
            request: request,
            raw: response));
      }
      final env = envelope;
      final wrapped = request.call.envelope != false &&
          env != null &&
          body is Map &&
          (isEnvelope?.call(body) ??
              (body.containsKey(env.code) &&
                  (body.containsKey(env.data) ||
                      body.containsKey(env.message))));
      final code = wrapped ? (body)[env.code] : null;
      final ok = httpOk &&
          (!wrapped ||
              (isSuccess?.call(code) ??
                  (code == null || code == 0 || code == '0')));
      final status = !ok && httpOk && code is int && code >= 400 && code <= 599
          ? code
          : http;
      var result = DiomanResponse<dynamic>(
          ok: ok,
          kind:
              ok ? DiomanKind.ok : (httpOk ? DiomanKind.biz : DiomanKind.http),
          status: status,
          httpStatus: http,
          code: code,
          message: wrapped
              ? '${(body)[env.message] ?? _emptyMessage}'
              : _emptyMessage,
          data: wrapped ? (body)[env.data] : body,
          request: request,
          raw: response);
      if (logicalStatus != null) {
        result = DiomanResponse(
            ok: result.ok,
            kind: result.kind,
            status: logicalStatus!(result),
            httpStatus: http,
            code: code,
            message: result.message,
            data: result.data,
            request: request,
            raw: response);
      }
      return _finish(result);
    } catch (e, s) {
      return _internal(request, e, s);
    }
  }
}
