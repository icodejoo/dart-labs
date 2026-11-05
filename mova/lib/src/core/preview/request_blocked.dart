/// 资源访问被网络策略阻止；区别于可进入失败冷却的获取故障。
/// 由内置资源门控抛出，来源应透传给预览服务处理。
class PreviewPolicyBlocked implements Exception {
  /// 创建策略拒绝信号。
  const PreviewPolicyBlocked();
}
