part of 'cache.dart';

/// 内置缓存的白盒诊断；不从公共入口导出，不适用于自定义管理端口。
extension DiomanCacheDiagnostics on DiomanCacheApi {
  /// 在途屏障数，所有请求结束后应为零。
  int get pendingWrites => (this as _Cache).barriers.length;

  /// 内存物理条目数，包括尚未惰性过期的条目。
  int get entryCount => (this as _Cache).entries.length;
}
