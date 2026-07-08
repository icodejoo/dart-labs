import 'interface.dart';

/// Plain `Map`-backed [MemoCache]: the engine's opt-in read cache, one
/// instance per tier (`ls`/`ss`), isolated per [Cacheman] instance (separate
/// instances never share a memo — no cross-instance reads).
///
/// 纯 `Map` 支撑的 [MemoCache]：engine 的可选读缓存，每个 tier（`ls`/`ss`）
/// 各一个实例，按 [Cacheman] 实例隔离（不同实例的 memo 互不共享，不会跨实例
/// 串读）。
class Memo implements MemoCache {
  final Map<String, dynamic> _store = <String, dynamic>{};

  @override
  dynamic get(String key) => _store.containsKey(key) ? _store[key] : null;

  @override
  void set(String key, dynamic value) => _store[key] = value;

  @override
  void remove(String key) => _store.remove(key);

  @override
  void clear() => _store.clear();
}
