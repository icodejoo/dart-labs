part of 'response.dart';

/// 内核落定时附加调用栈，不从公共入口导出。
extension DiomanResponseFactoryInternal on DiomanResponseFactory {
  /// 程序错误固定归 internal，不按 Dio 异常类型重新分类。
  DiomanResponse<dynamic> internalError(
          DiomanRequest request, Object error, StackTrace stack) =>
      _finish(DiomanResponseFactory._internal(request, error, stack));

  /// 落定副本经扩展工厂创建后附原生数据，保留调用方子类。
  DiomanResponse<dynamic> withNative(
      DiomanResponse<dynamic> result, Response<dynamic>? raw, Object? error) {
    final copy = _finish(result.copy<dynamic>());
    copy._raw = raw;
    copy._error = error;
    return copy;
  }

  /// 带调用点派生结果并重新经过扩展构造器；不修改共享结果。
  DiomanResponse<dynamic> withCallSite(
          DiomanResponse<dynamic> result, StackTrace callSite) =>
      _finish(result.copy<dynamic>(callSite: callSite));
}

/// 内核失败写入入口，不由公开库导出。
abstract final class DiomanResponseInternal {
  /// 用成功解码数据派生结果，不修改共享响应或重新进入工厂。
  static DiomanResponse<T> decoded<T>(DiomanResponse<dynamic> result, T data) =>
      DiomanResponse<T>(
          ok: result.ok,
          status: result.status,
          code: result.code,
          message: result.message,
          data: data,
          request: result.request,
          raw: result.raw,
          error: result.error,
          callSite: result.callSite)
        .._failure = result._failure
        .._retryAfter = result._retryAfter
        .._nativeIdentity = result._nativeIdentity;

  /// 工厂返回后附加事实，空值不清除已存在标记。
  static void mark(DiomanResponse<dynamic> result, DiomanFailure? failure) {
    if (failure != null) result._failure = failure;
  }

  /// 读取仅供重试使用的小事实。
  static String? retryAfter(DiomanResponse<dynamic> result) =>
      result._retryAfter;

  /// 传输边界写入原始头字符串。
  static void setRetryAfter(DiomanResponse<dynamic> result, String? value) =>
      result._retryAfter = value;

  /// 判断结果是否来自同一次传输或其派生。
  static bool sameNative(
          DiomanResponse<dynamic> a, DiomanResponse<dynamic> b) =>
      identical(a._nativeIdentity, b._nativeIdentity);

  /// 从持久化事实恢复类别。
  static void restore(DiomanResponse<dynamic> result, DiomanFailureKind kind,
          {String? reason, Object? error, StackTrace? errorStack}) =>
      result._failure = DiomanFailure._(kind, reason, error, errorStack);
}
