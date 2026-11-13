/// Pure Dart memory storage; named containers share data within one isolate.
/// 纯 Dart 内存后端；同名容器在当前 isolate 内共享，重启后数据丢失。
class MemoryStorage {
  /// Creates an isolated memory store. / 创建独立内存后端。
  MemoryStorage();

  /// Returns the shared store for a name. / 返回指定名称的共享内存后端。
  factory MemoryStorage.named(String name) =>
      _containers.putIfAbsent(name, MemoryStorage.new);

  /// Named stores retained for this isolate. / 当前 isolate 保留的同名容器。
  static final _containers = <String, MemoryStorage>{};

  /// Raw values, including foreign entries. / 原始值，可包含外部条目。
  final _data = <String, Object?>{};

  /// Synchronous key listeners. / 同步键变更监听器。
  final _listeners = <void Function(String?)>{};

  /// Snapshot of raw keys. / 原始键快照。
  Iterable<String> get keys => _data.keys.toList(growable: false);

  /// Reads a raw value; absent keys return null. / 读取原始值，缺失返回 null。
  T? read<T>(String key) => _data[key] as T?;

  /// Checks raw key presence. / 检查原始键是否存在。
  bool hasData(String key) => _data.containsKey(key);

  /// Updates memory and notifies before return; callback errors enter the Future.
  /// 返回前更新内存并通知；回调异常由 Future 传播。
  Future<void> write(String key, Object? value) async {
    _data[key] = value;
    _notify(key);
  }

  /// Removes a key and notifies before return. / 返回前删除键并通知。
  Future<void> remove(String key) async {
    _data.remove(key);
    _notify(key);
  }

  /// Clears all data and reports a null key. / 清空全部数据并通知 null 键。
  Future<void> erase() async {
    _data.clear();
    _notify(null);
  }

  /// Subscribes to keys (null means clear); returns a cancel function.
  /// 订阅键变更（null 表示清空），返回取消函数。
  void Function() listen(void Function(String?) onChange) {
    _listeners.add(onChange);
    return () => _listeners.remove(onChange);
  }

  /// Dispatches a snapshot, respecting cancellation during callbacks.
  /// 分发监听快照，跳过回调中已取消的订阅。
  void _notify(String? key) {
    for (final listener in _listeners.toList()) {
      if (_listeners.contains(listener)) listener(key);
    }
  }
}
