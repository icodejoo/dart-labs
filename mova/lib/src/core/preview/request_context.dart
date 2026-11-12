import 'dart:async';

/// 预览服务传到内置资源门控的单次请求身份，不改变宿主来源接口。
class PreviewRequestContext {
  /// [isWanted] 复核服务代际；[cancelled] 在取消、换源或销毁时完成。
  const PreviewRequestContext(this.isWanted, this.cancelled);

  /// 请求是否仍属于当前拖动意图。
  final bool Function() isWanted;

  /// 请求失效信号，用于解除尚未返回的网络探针等待。
  final Future<void> cancelled;

  static final Object _key = Object();

  /// 当前异步来源调用所属的请求；直接使用来源时为空。
  static PreviewRequestContext? get current => Zone.current[_key] as PreviewRequestContext?;

  /// 在本请求身份下运行 [action]，并保留异步调用链中的身份。
  T run<T>(T Function() action) => runZoned(action, zoneValues: {_key: this});
}

/// 请求已过期或资源包装器已销毁；既不是策略拒绝，也不是获取失败。
class PreviewRequestCancelled implements Exception {
  /// 创建请求失效信号。
  const PreviewRequestCancelled();
}
