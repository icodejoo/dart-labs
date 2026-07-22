import 'cacheman.dart';

/// Debug snapshot: reads every entry of a [Cacheman] instance (`cache`)
/// **decrypted** and returns a `{ "namespace:key": value }` map (namespace
/// preserved). A pure read with no side effects beyond what a normal
/// [Cacheman.read] call already does (lazy-expiry deletion, sliding-TTL
/// renewal) — it does not write the snapshot back, so it never pollutes
/// [Cacheman.keys]/[Cacheman.length].
///
/// ```dart
/// final cache = Cacheman(options: CachemanOptions(codeable: true, codec: myCodec));
/// await cache.ensureInitialized();
/// debug(cache); // { "token": "abc", ... }
/// ```
///
/// 调试快照：读出某个 [Cacheman] 实例（`cache`）的全部条目**解密后**的
/// 值，组装成 `{ "命名空间:key": 值 }` 的 map（保留命名空间）。除了一次普通
/// [Cacheman.read] 调用本就会有的副作用（懒过期删除、滑动 TTL 续期）之外没有
/// 别的副作用——不会把快照写回去，所以不会污染 [Cacheman.keys]/[Cacheman.length]。
Map<String, dynamic> debug(Cacheman handler) {
  final ns = handler.namespace;
  final dump = <String, dynamic>{};
  for (final k in handler.keys()) {
    dump['$ns$k'] = handler.read<dynamic>(k);
  }
  return dump;
}
