part of 'response.dart';

/// 内核落定时附加调用栈，不从公共入口导出。
extension DiomanResponseFactoryInternal on DiomanResponseFactory {
  /// 带调用点派生结果并重新经过扩展构造器；不修改共享结果。
  DiomanResponse<dynamic> withCallSite(
          DiomanResponse<dynamic> result, StackTrace callSite) =>
      _finish(result.copy<dynamic>(callSite: callSite));
}
