part of 'share.dart';

/// 内置共享实例的诊断标记，仅用于白盒定位，不从公共入口导出。
abstract interface class DiomanShareApi {}

/// 共享活动表白盒诊断，不从公共入口导出。
extension DiomanShareDiagnostics on DiomanShareApi {
  /// 四种策略当前活动轮次总数，结束或销毁后应为零。
  int get activeEntries =>
      (this as _Share).tables.values.fold(0, (n, table) => n + table.length);
}
