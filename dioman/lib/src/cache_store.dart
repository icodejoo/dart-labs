import 'dart:async';

/// 持久化后端；格式为 data、expiresAt（epoch 毫秒），兼容 0.7。
/// 例如实现 read/write/remove/erase 后传给 `DiomanCache(persist: store)`。
abstract interface class DiomanCachePersist {
  /// 读取 [key]，不存在返回 null；可同步或异步。
  FutureOr<dynamic> read(String key);

  /// 写入 JSON 可编码的 [value]；包含 data、expiresAt 及可选 result 元信息。
  /// 后端应完整保存 Map，返回持久化完成信号。
  Future<void> write(String key, Map<String, dynamic> value);

  /// 删除 [key]，不存在也成功。
  Future<void> remove(String key);

  /// 清空该后端。
  Future<void> erase();
}
