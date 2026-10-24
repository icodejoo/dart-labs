// Benchmark-only baseline: oldest first; hits remove and reinsert an entry.
class NaiveLru<K, V extends Object> {
  NaiveLru(this.maxSize);
  final int maxSize;
  // Dart map literals use insertion-ordered LinkedHashMap storage.
  final _map = <K, V>{};

  V? get(K key) {
    final value = _map.remove(key);
    if (value != null) _map[key] = value;
    return value;
  }

  void set(K key, V value) {
    _map.remove(key);
    _map[key] = value;
    if (_map.length > maxSize) _map.remove(_map.keys.first);
  }
}
