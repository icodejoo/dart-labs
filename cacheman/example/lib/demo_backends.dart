import 'package:cacheman/cacheman.dart';

/// 只用于演示的同步 Map 后端，不提供磁盘持久化。
class MemorySync extends Cacheman {
  /// 创建使用独立内存的自定义同步后端。
  MemorySync() : super.custom();

  /// 本实例的原始信封数据。
  final _data = <String, String>{};

  /// 内存后端无需初始化磁盘容器。
  @override
  Future<void> initRaw(CacheContext ctx) async {}

  /// 从内存读取原始值。
  @override
  Object? getRaw(CacheContext ctx, String storageKey) => _data[storageKey];

  /// 返回前完成内存更新。
  @override
  Future<void> setRaw(CacheContext ctx, String storageKey, String value) {
    _data[storageKey] = value;
    return Future<void>.value();
  }

  /// 返回前完成内存删除。
  @override
  Future<void> removeRaw(CacheContext ctx, String storageKey) {
    _data.remove(storageKey);
    return Future<void>.value();
  }

  /// 枚举本实例的原始键。
  @override
  Iterable<String> keysRaw(CacheContext ctx) => _data.keys;

  /// 同步清空内存并返回完成的保存边界。
  @override
  Future<void> clearRaw(CacheContext ctx) {
    _data.clear();
    return Future<void>.value();
  }
}

/// 只用于演示 await 契约的异步 Map 后端。
class MemoryAsync extends AsyncCacheman {
  /// 创建隔离的异步演示后端。
  MemoryAsync();

  /// 本实例的原始信封数据。
  final _data = <String, String>{};

  /// 等待读取原始值。
  @override
  Future<Object?> getRaw(CacheContext ctx, String storageKey) async =>
      _data[storageKey];

  /// 等待完成内存写入。
  @override
  Future<void> setRaw(CacheContext ctx, String storageKey, String value) async {
    _data[storageKey] = value;
  }

  /// 等待完成内存删除。
  @override
  Future<void> removeRaw(CacheContext ctx, String storageKey) async {
    _data.remove(storageKey);
  }

  /// 等待获得原始键快照。
  @override
  Future<Iterable<String>> keysRaw(CacheContext ctx) async =>
      _data.keys.toList();
}
