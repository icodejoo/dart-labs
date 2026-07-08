import 'engine.dart';

/// Debug snapshot: reads every entry of an engine (`cache.ls` or `cache.ss`)
/// **decrypted** and returns a `{ "namespace:key": value }` map (namespace
/// preserved). A pure read with no side effects beyond what a normal
/// [Engine.get] call already does (lazy-expiry deletion, sliding-TTL
/// renewal) — it does not write the snapshot back, so it never pollutes
/// [Engine.keys]/[Engine.length].
///
/// ```dart
/// final cache = await Cacheman.create(options: CachemanOptions(codeable: true, codec: myCodec));
/// debug(cache.ls); // { "token": "abc", ... }
/// ```
///
/// 调试快照：读出某个引擎（`cache.ls` 或 `cache.ss`）的全部条目**解密后**的
/// 值，组装成 `{ "命名空间:key": 值 }` 的 map（保留命名空间）。除了一次普通
/// [Engine.get] 调用本就会有的副作用（懒过期删除、滑动 TTL 续期）之外没有
/// 别的副作用——不会把快照写回去，所以不会污染 [Engine.keys]/[Engine.length]。
Map<String, dynamic> debug(Engine handler) {
  final ns = handler.namespace;
  final dump = <String, dynamic>{};
  for (final k in handler.keys()) {
    dump['$ns$k'] = handler.get<dynamic>(k);
  }
  return dump;
}
