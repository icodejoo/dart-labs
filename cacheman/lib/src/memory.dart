import 'dart:collection';

import 'interface.dart';

/// In-memory [Store]: a `LinkedHashMap<String, String>`-backed synchronous
/// implementation. Backs the `ss` tier (pure in-memory — cleared on process
/// restart, holds serialized strings just like the persistent tier does).
///
/// 内存 [Store]：`LinkedHashMap<String, String>` 支撑的同步实现。给 `ss`
/// 层（纯内存——进程重启即丢，存的是序列化字符串，跟持久层一致）当后端。
class Memory implements Store {
  Memory({this.cap});

  /// Soft capacity, in total `String.length` (UTF-16 code units) of all keys
  /// + values combined — a fast proxy for byte size, not an exact UTF-8
  /// count. `null` (default) means unlimited. When a `set` pushes the total
  /// over this cap, the oldest entries (by original insertion order — an
  /// overwrite of an existing key does not change its position) are evicted
  /// first. An entry larger than the cap on its own is evicted right after
  /// insertion (effectively dropped, with a warning).
  ///
  /// 软容量上限，按全部 key+value 的 `String.length`（UTF-16 code unit 数）
  /// 之和算——是字节数的快速代理，不是精确 UTF-8 字节数。`null`（默认）表示
  /// 不限制。`set` 导致总量超限时，按最早插入顺序淘汰（覆写已存在的 key 不
  /// 会改变它的位置）。单条 entry 本身就超过上限时，写入后会被立刻淘汰
  /// （等效丢弃，附警告）。
  ///
  /// **注意**：覆写不重置位置意味着"很早插入、一直没删"的 key 突然写入一个
  /// 大值，可能因总量超限而被自己刚写的这次 `set` 立刻淘汰掉——即使这条
  /// entry 本身没有超过 `cap`。这是纯按插入顺序（非 LRU）淘汰的设计取舍。
  final int? cap;

  final LinkedHashMap<String, String> _store = LinkedHashMap<String, String>();
  int _size = 0;

  static int _entrySize(String key, String value) => key.length + value.length;

  @override
  int get length => _store.length;

  @override
  void clear() {
    _store.clear();
    _size = 0;
  }

  @override
  String? get(String key) => _store[key];

  @override
  List<String> keys() => _store.keys.toList(growable: false);

  @override
  String? key(int index) {
    if (index < 0 || index >= _store.length) return null;
    return _store.keys.elementAt(index);
  }

  @override
  void remove(String key) {
    final old = _store.remove(key);
    if (old != null) _size -= _entrySize(key, old);
  }

  @override
  void set(String key, String value) {
    final old = _store[key];
    if (old != null) _size -= _entrySize(key, old);
    _store[key] = value;
    _size += _entrySize(key, value);
    _evictIfNeeded(key, _entrySize(key, value));
  }

  void _evictIfNeeded(String justSetKey, int justSetSize) {
    final maxCap = cap;
    if (maxCap == null || _size <= maxCap) return;
    while (_size > maxCap && _store.isNotEmpty) {
      final oldestKey = _store.keys.first;
      final oldestValue = _store.remove(oldestKey)!;
      _size -= _entrySize(oldestKey, oldestValue);
    }
    if (!_store.containsKey(justSetKey)) {
      if (justSetSize > maxCap) {
        // ignore: avoid_print
        print('[cacheman] entry "$justSetKey" exceeds ss cap ($maxCap) on its own; dropped');
      } else {
        // ignore: avoid_print
        print('[cacheman] entry "$justSetKey" evicted immediately: total size exceeded ss cap '
            '($maxCap) and this key was oldest by insertion order (overwrites keep original '
            'position, see the `cap` doc above)');
      }
    }
  }
}
