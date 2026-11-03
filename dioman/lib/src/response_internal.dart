part of 'response.dart';

/// 内核落定时附加调用栈，不从公共入口导出。
extension DiomanResponseFactoryInternal on DiomanResponseFactory {
  /// 程序错误固定归 internal，不按 Dio 异常类型重新分类。
  DiomanResponse<dynamic> internalError(
          DiomanRequest request, Object error, StackTrace stack) =>
      _finish(DiomanResponseFactory._internal(request, error, stack));

  /// 带调用点派生结果并重新经过扩展构造器；不修改共享结果。
  DiomanResponse<dynamic> withCallSite(
          DiomanResponse<dynamic> result, StackTrace callSite) =>
      _finish(result.copy<dynamic>(callSite: callSite));
}

/// 内核失败写入入口，不由公开库导出。
abstract final class DiomanResponseInternal {
  /// 工厂返回后附加事实，空值不清除已存在标记。
  static void mark(DiomanResponse<dynamic> result, DiomanFailure? failure) {
    if (failure != null) result._failure = failure;
  }

  /// 从持久化事实恢复类别。
  static void restore(DiomanResponse<dynamic> result, DiomanFailureKind kind,
          {String? reason}) =>
      result._failure = DiomanFailure._(kind, reason);
}
