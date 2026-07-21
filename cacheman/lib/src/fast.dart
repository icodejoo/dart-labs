import 'cacheman.dart';

/// A key-bound shortcut accessor, so callers stop repeating the key. See
/// [fast].
///
/// 绑定 key 的快捷访问器，免去反复写 key。见 [fast]。
class FastAccessor<V> {
  FastAccessor(this._cacheman, this._key);

  final Cacheman _cacheman;
  final String _key;

  /// Reads the bound key.
  ///
  /// 读取绑定的 key。
  V? get([V? defaultValue]) => _cacheman.read<V>(_key, defaultValue);

  /// Writes the bound key.
  ///
  /// 写入绑定的 key。
  void set(V value, {int? ttl, Object? expireAt, bool? memoized}) => _cacheman.write<V>(_key, value, ttl: ttl, expireAt: expireAt, memoized: memoized);

  /// Deletes the bound key.
  ///
  /// 删除绑定的 key。
  void remove() => _cacheman.remove(_key);
}

/// Binds a [Cacheman] instance and a key, returning a [FastAccessor] so the
/// key stops being repeated at every call site. Specify the value type once
/// via `fast<V>(...)`.
///
/// ```dart
/// final token = fast<String>(cache, 'token');
/// token.set('abc');
/// token.get();      // String?
/// token.get('def'); // String
/// token.remove();
/// ```
///
/// 绑定一个 [Cacheman] 实例和一个 key，返回 [FastAccessor]，各调用点不用再
/// 反复写 key。值类型在 `fast<V>(...)` 指定一次即可。
FastAccessor<V> fast<V>(Cacheman target, String key) => FastAccessor<V>(target, key);

/// Like [fast], but returns a getter that builds the accessor on first call
/// and caches it — handy for a central registry of many keys where most
/// won't actually be used in a given run.
///
/// ```dart
/// final token = lazy<String>(cache, 'token');
/// token().get(); // accessor created on first use, reused after
/// ```
///
/// 跟 [fast] 一样，但返回一个 getter，首次调用才建访问器并缓存复用——适合
/// 一个集中管理很多 key 的注册表，大多数 key 在某次运行里其实用不上。
FastAccessor<V> Function() lazy<V>(Cacheman target, String key) {
  FastAccessor<V>? acc;
  return () => acc ??= fast<V>(target, key);
}

/// Binds several keys at once, returning a map keyed by each key name, each
/// value a [FastAccessor] for that key.
///
/// ```dart
/// final accessors = batchFast<String>(cache, ['token', 'user']);
/// accessors['token']!.set('abc');
/// ```
///
/// 一次绑定多个 key，返回以 key 名为键的 map，每个值是对应 key 的
/// [FastAccessor]。
Map<String, FastAccessor<V>> batchFast<V>(Cacheman target, List<String> keys) => {
      for (final k in keys) k: fast<V>(target, k),
    };
