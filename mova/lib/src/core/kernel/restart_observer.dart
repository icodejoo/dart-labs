/// 可选的精确首帧观察能力；宿主接口无需新增成员。
abstract interface class MovaRestartObserver {
  /// 为封面启用 RESTART；幂等且不创建尚未打开引擎的客户端，无返回值。
  /// 示例：`(engine as MovaRestartObserver).observeRestarts()`。
  void observeRestarts();
}
