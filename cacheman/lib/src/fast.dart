import 'cacheman.dart';
import 'value_adapter.dart';

/// A key-bound shortcut accessor, so callers stop repeating the key. See
/// [fast].
///
/// 绑定 key 的快捷访问器，免去反复写 key。见 [fast]。
class FastAccessor<V> {
  /// Binds a key with an optional adapter and default ttl in milliseconds.
  /// 绑定键及可选适配器、默认毫秒 ttl。
  /// Example / 示例：`FastAccessor<String>(cache, 'token', ttl: 60000)`.
  FastAccessor(this._cacheman, this._key, {ValueAdapter<V>? adapter, int? ttl})
      : _adapter = adapter,
        _ttl = ttl;

  /// Synchronous facade. / 同步薄层。
  final Cacheman _cacheman;

  /// Bound logical key. / 绑定的逻辑键。
  final String _key;

  /// Conversion used on both reads and writes. / 读写共用转换器。
  final ValueAdapter<V>? _adapter;

  /// Default lifetime in milliseconds. / 默认毫秒寿命。
  final int? _ttl;

  /// Reads the bound key.
  ///
  /// 读取绑定的 key。
  V? get([V? defaultValue]) => _cacheman.readWith<V>(_key,
      defaultValue: defaultValue, adapter: _adapter);

  /// Writes the bound key.
  ///
  /// 写入绑定的 key；ttl 未指定时使用访问器默认值。
  /// Uses the accessor ttl when omitted; an explicit ttl overrides it.
  void set(V value, {int? ttl, Object? expireAt}) =>
      _cacheman.write<V>(_key, value,
          ttl: ttl ?? _ttl, expireAt: expireAt, adapter: _adapter);

  /// Deletes the bound key.
  ///
  /// 删除绑定的 key。
  void remove() => _cacheman.remove(_key);
}

/// Binds a [Cacheman] instance and a key, returning a [FastAccessor] so the
/// key stops being repeated at every call site. Specify the value type once
/// via `fast<V>(...)`. adapter applies in both directions; ttl defaults each set.
/// adapter 用于双向转换，ttl 作为每次 set 的默认值。
///
/// ```dart
/// final token = fast<String>(cache, 'token', ttl: 60000);
/// token.set('abc');
/// token.get();      // String?
/// token.get('def'); // String
/// token.remove();
/// ```
///
/// 绑定一个 [Cacheman] 实例和一个 key，返回 [FastAccessor]，各调用点不用再
/// 反复写 key。值类型在 `fast<V>(...)` 指定一次即可。
FastAccessor<V> fast<V>(Cacheman target, String key,
        {ValueAdapter<V>? adapter, int? ttl}) =>
    FastAccessor<V>(target, key, adapter: adapter, ttl: ttl);

/// Like [fast], but returns a getter that builds the accessor on first call
/// and caches it — handy for a central registry of many keys where most
/// won't actually be used in a given run.
///
/// ```dart
/// final token = lazy<String>(cache, 'token', ttl: 60000);
/// token().get(); // accessor created on first use, reused after
/// ```
///
/// adapter/ttl are forwarded unchanged. / adapter/ttl 原样转发。
/// 跟 [fast] 一样，但返回一个 getter，首次调用才建访问器并缓存复用——适合
/// 一个集中管理很多 key 的注册表，大多数 key 在某次运行里其实用不上。
FastAccessor<V> Function() lazy<V>(Cacheman target, String key,
    {ValueAdapter<V>? adapter, int? ttl}) {
  FastAccessor<V>? acc;
  return () => acc ??= fast<V>(target, key, adapter: adapter, ttl: ttl);
}

/// Binds several keys at once, returning a map keyed by each key name, each
/// value a [FastAccessor] for that key.
///
/// ```dart
/// final accessors = batchFast<String>(cache, ['token', 'user'], ttl: 60000);
/// accessors['token']!.set('abc');
/// ```
///
/// adapter/ttl apply to every accessor. / adapter/ttl 应用于每个访问器。
/// 一次绑定多个 key，返回以 key 名为键的 map，每个值是对应 key 的
/// [FastAccessor]。
Map<String, FastAccessor<V>> batchFast<V>(Cacheman target, List<String> keys,
        {ValueAdapter<V>? adapter, int? ttl}) =>
    {
      for (final k in keys) k: fast<V>(target, k, adapter: adapter, ttl: ttl),
    };
