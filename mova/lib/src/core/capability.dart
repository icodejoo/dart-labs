import 'api.dart';
import 'cutover/cutover.dart';

/// 从 [api] 查找类型为 [T] 的能力，返回实现对象；不支持时返回 null。
/// 优先保留代理自身的能力语义，否则逐层查找 cutover 当前生效播放器，
/// 不创建影子、不缓存结果；换指后应重新查询。不会修改 IMovaApi 契约。
/// 示例：`final keepAlive = movaCapabilityOf<IMovaKeepAlive>(api);`。
T? movaCapabilityOf<T>(IMovaApi api) {
  var current = api;
  while (true) {
    if (current is T) return current as T;
    if (current is! MovaCutover) return null;
    current = current.active;
  }
}
