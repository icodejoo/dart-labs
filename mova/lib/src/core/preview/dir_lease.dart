/// Internal optional lifetime capability for a leased thumbnail directory.
/// Disk caches release it after pending work; ordinary providers only need
/// the unchanged directory-provider port.
///
/// 缩略图租约目录的包内可选生命周期能力；磁盘缓存等工作收敛后释放它，
/// 普通 provider 仍只需实现原有目录端口。
abstract interface class MovaThumbDirLease {
  /// Releases the lease without clearing thumbnails; repeated calls are safe.
  /// Example: `await lease.dispose()`.
  ///
  /// 释放租约但不清空缩略图；可重复调用。示例：`await lease.dispose()`。
  Future<void> dispose();
}
