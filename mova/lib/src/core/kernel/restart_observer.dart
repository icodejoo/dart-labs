/// 可选的精确首帧观察能力；宿主接口无需新增成员。
abstract interface class IMovaRestartObserver {
  /// 为封面启用 RESTART；幂等且不创建尚未打开播放器的客户端，无返回值。
  /// 示例：`(mova as IMovaRestartObserver).observeRestarts()`。
  void observeRestarts();
}
