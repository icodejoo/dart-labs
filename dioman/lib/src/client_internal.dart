part of 'client.dart';

/// 客户端白盒诊断；不从公共入口导出。
extension DiomanDiagnostics on Dioman {
  /// 活跃内核取消等待订阅数，供 I3 不变量检查。
  int get cancellationSubscriptions =>
      _pending.fold(0, (n, s) => n + s.listeners.length);
}
