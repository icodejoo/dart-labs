part of 'cacheman.dart';

/// Asynchronous cache semantics; extend and implement storage primitives only.
/// 异步缓存语义层；继承后只需实现存储原语，不带内置后端或读值/自有键集合缓存。
///
/// Await initialization and each operation. Backend errors normally propagate;
/// writes/renewals report exhausted failures through onError. Serialize namespace
/// switches with pending operations; no transactions or concurrent-write isolation.
/// 须 await 初始化及每次操作。后端异常通常向上传播；写入/续期最终失败走 onError。
/// 切换命名空间前须等待进行中的操作；不提供事务或并发写入隔离。
///
/// ```dart
/// final cache = MyDiskCache(options: const CachemanOptions(namespace: 'large'));
/// await cache.ensureInitialized();
/// await cache.write('report', {'rows': 1000}, ttl: 60000);
/// final report = await cache.read<Map<String, dynamic>>('report');
/// ```
abstract class AsyncCacheman {
  /// Shares CachemanOptions without constructing any default backend.
  /// 共用 CachemanOptions，不构造默认后端；例如子类转发 super.options。
  AsyncCacheman({CachemanOptions options = const CachemanOptions()})
      : _core = _CacheCore(options);

  /// Storage-independent semantics. / 与存储无关的语义。
  final _CacheCore _core;

  /// Whether explicit initialization finished. / 是否完成显式初始化。
  bool _initialized = false;

  /// Escaped namespace prefix (empty if unset). / 转义后的命名空间前缀（未设置时为空）。
  String get namespace => _core.namespace;

  /// Initializes through initRaw before use. / 使用前通过 initRaw 初始化。
  /// Example / 示例：`await cache.ensureInitialized()`.
  Future<void> ensureInitialized() async {
    await initRaw(_core.context(CacheOp.init));
    _initialized = true;
  }

  /// Optional backend initialization, e.g. opening a LazyBox; default no-op.
  /// 可选的后端初始化，例如打开 LazyBox；默认不操作。
  @protected
  Future<void> initRaw(CacheContext ctx) async {}

  /// Reads the actual storage key on demand; null denotes absence.
  /// 按需读取真实存储键，null 表示缺失；例如 return await box.get(storageKey)。
  @protected
  Future<Object?> getRaw(CacheContext ctx, String storageKey);

  /// Persists an envelope string; completion/failure must reflect the write.
  /// 持久化信封字符串，Future 须反映写入完成/失败；例如 await box.put(storageKey, value)。
  @protected
  Future<void> setRaw(CacheContext ctx, String storageKey, String value);

  /// Deletes the actual storage key; await completion, e.g. box.delete(storageKey).
  /// 删除真实存储键并等待完成，例如 box.delete(storageKey)。
  @protected
  Future<void> removeRaw(CacheContext ctx, String storageKey);

  /// Enumerates actual storage keys; the facade filters ownership each time.
  /// 枚举真实存储键，语义层每次过滤归属；例如 `box.keys.cast<String>()`。
  @protected
  Future<Iterable<String>> keysRaw(CacheContext ctx);

  /// Clears the entire backend by enumerating and removing all keys by default.
  /// 默认枚举并逐个删除整个后端的所有键，可覆写成后端的整库清空操作。
  /// Only unscoped erase calls this; scoped erase uses removeRaw directly.
  /// 仅无作用域 erase 调用本方法；有作用域时直接调用 removeRaw。
  @protected
  Future<void> clearRaw(CacheContext ctx) async {
    final keys =
        (await keysRaw(_core.context(CacheOp.keys))).toList(growable: false);
    for (final key in keys) {
      await _del(key);
    }
  }

  /// Switches scope without deleting old data; await pending operations first.
  /// 切换作用域但不删旧数据，须先等待进行中的操作完成。
  /// Example / 示例：`await cache.setNamespace('alice')`.
  Future<void> setNamespace([String? namespace]) async =>
      _core.setNamespace(namespace);

  /// Returns the prefixed/encoded key synchronously, without backend IO.
  /// 同步返回加前缀/编码后的键，不访问后端；例如 cache.storageKey('report')。
  String storageKey(String key) => _core._fullKey(key);

  /// 每次异步读取原始后端值，由内核统一判断外部非字符串数据。
  Future<Object?> _get(String key) =>
      getRaw(_core.context(CacheOp.read, key), key);

  /// Deletes via the primitive. / 经原语删除。
  Future<void> _del(String key) =>
      removeRaw(_core.context(CacheOp.remove, key), key);

  /// Always scans backend keys; no owned-key set is retained.
  /// 每次扫描后端键，不保留自有键集合。
  Future<List<String>> _ownKeys() async =>
      (await keysRaw(_core.context(CacheOp.keys)))
          .where(_core._owns)
          .toList(growable: false);

  /// 依照内核决策静默删除过期项，raw 跳过后端枚举。
  Future<void> _purgeExpired() async {
    if (!_core.canPurge) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final key in await _ownKeys()) {
      if (_core.shouldPurge(await _get(key), now)) await _del(key);
    }
  }

  /// 编码一次并执行 IO；重试和错误分类完全由内核决定。
  Future<void> _persist(String key, _WritePlan plan) async {
    assert(_initialized, _initializationMessage);
    final encoded = _core.build(key, plan.encode);
    if (encoded == null) return;
    var retried = false;
    while (true) {
      try {
        if (retried) await _purgeExpired();
        await setRaw(_core.context(CacheOp.write, key), key, encoded);
        return;
      } catch (error, trace) {
        if (!_core.retryWrite(key, error, trace, retried: retried)) return;
        retried = true;
      }
    }
  }

  /// Reads with lazy expiry, decode-error reporting and awaited sliding renewal.
  /// 读取时懒删除过期项、上报解码失败并等待滑动续期；续期写入失败仍返回原值。
  /// Type/adapter mismatches return the default and retain data; no numeric coercion.
  /// 类型/适配器不符返回默认值并保留数据；不做数字互转，int 可用 num 读取。
  /// Backend IO and user onError exceptions still propagate. / 后端 IO 及用户 onError 异常仍传播。
  /// Example / 示例：`await cache.read<String>('report', 'missing')`.
  Future<T?> read<T>(String key, [T? defaultValue]) =>
      _read(key, defaultValue, null);

  /// Reads with JSON adaptation; mismatches return defaultValue without removal.
  /// 带 JSON 适配读取；不匹配返回 defaultValue，不删除数据。
  /// Dart cannot mix optional positional and named parameters; read keeps its
  /// positional default, while this entry accepts named defaultValue/adapter.
  /// Dart 无法混合可选位置与命名参数；read 保留位置默认值，本方法提供命名参数。
  /// Example / 示例：
  /// ```dart
  /// await cache.readWith<List<String>>('names', adapter: ValueAdapter.listOf<String>());
  /// ```
  Future<T?> readWith<T>(String key,
          {T? defaultValue, ValueAdapter<T>? adapter}) =>
      _read(key, defaultValue, adapter);

  /// 执行内核读取决策要求的删除或续期，再完成返回值转换。
  Future<T?> _read<T>(
      String key, T? defaultValue, ValueAdapter<T>? adapter) async {
    final sk = _core._fullKey(key);
    final raw = await _get(sk);
    final decision = _core.decideRead(
        sk, raw, DateTime.now().millisecondsSinceEpoch, defaultValue, adapter);
    switch (decision) {
      case _DropAndDefault<T>():
        await _del(sk);
      case _Hit<T>(:final renewal):
        if (renewal != null) await _persist(sk, renewal);
      case _Miss<T>():
        break;
    }
    return _core.finishRead(decision);
  }

  /// Sequential positional reads; missing defaults are null.
  /// 顺序按位置批量读取，缺省默认值为 null。
  /// Example / 示例：`await cache.readAll(['a', 'b'], [1])`.
  Future<List<dynamic>> readAll(List<String> keys,
          [List<dynamic>? defaults]) async =>
      [
        for (var i = 0; i < keys.length; i++)
          await read<dynamic>(keys[i], _core.batchDefault(defaults, i)),
      ];

  /// Writes with millisecond TTL or DateTime/integer absolute expiry.
  /// Optional adapter converts before serialization; raw ignores it.
  /// 可选 adapter 在序列化前转换；raw 忽略它。
  /// Example / 示例：`cache.write('names', ['Ada'], adapter: ValueAdapter.listOf<String>())`.
  /// 按毫秒 TTL 或 DateTime/整数绝对过期时间写入。
  /// With sliding, ttl takes precedence and expireAt only sets the first expiry;
  /// past expireAt restarts from now, and renewal may extend beyond expireAt.
  /// sliding 下 ttl 优先，expireAt 只决定首次过期时间；过去的 expireAt 会从现在
  /// 重新起算；续期可能使实际过期时间超过原 expireAt。
  /// Example / 示例：`await cache.write('report', 'text', ttl: 60000)`.
  Future<void> write<T>(String key, T value,
      {int? ttl, Object? expireAt, ValueAdapter<T>? adapter}) async {
    final sk = _core._fullKey(key);
    final raw = _core.needsWriteProbe ? await _get(sk) : null;
    final plan = _core.decideWrite(
        key, value, raw, DateTime.now().millisecondsSinceEpoch,
        ttl: ttl, expireAt: expireAt, adapter: adapter);
    if (plan != null) await _persist(sk, plan);
  }

  /// Sequential positional writes; warns/skips missing values; expiry applies to all.
  /// 顺序按位置批量写入，缺值警告并跳过；过期参数应用于全部键。
  /// Example / 示例：`await cache.writeAll(['a', 'b'], [1, 2], ttl: 60000)`.
  Future<void> writeAll(List<String> keys, List<dynamic> values,
      {int? ttl, Object? expireAt}) async {
    final n = _core.batchLength(keys, values);
    for (var i = 0; i < n; i++) {
      await write<dynamic>(keys[i], values[i], ttl: ttl, expireAt: expireAt);
    }
  }

  /// Removes one key, e.g. await cache.remove('report').
  /// 删除一个键，例如 await cache.remove('report')。
  Future<void> remove(String key) => _del(_core._fullKey(key));

  /// Removes a batch sequentially, e.g. await cache.removeAll(['a', 'b']).
  /// 顺序批量删除，例如 await cache.removeAll(['a', 'b'])。
  Future<void> removeAll(List<String> keys) async {
    for (final key in keys) {
      await remove(key);
    }
  }

  /// Deletes owned keys with namespace/enckey, otherwise calls clearRaw on the
  /// whole backend (including foreign keys), matching Cacheman.
  /// 有 namespace/enckey 时删除自有键，否则调用 clearRaw 清空整个后端（含外部键），
  /// 与 Cacheman 一致。例如 await cache.erase()。
  Future<void> erase() async {
    if (_core.clearsBackend) {
      await clearRaw(_core.context(CacheOp.clear));
      return;
    }
    for (final key in await _ownKeys()) {
      await _del(key);
    }
  }

  /// Fresh owned logical keys; expired entries remain until read/purge.
  /// 每次枚举自有逻辑键；过期项在读取/清理前仍计入，例如 await cache.keys()。
  Future<List<String>> keys() async =>
      (await _ownKeys()).map(_core._logical).toList(growable: false);

  /// Fresh owned-key count, e.g. await cache.length().
  /// 每次枚举统计自有键数量，例如 await cache.length()。
  Future<int> length() async => (await _ownKeys()).length;

  /// Proactively deletes owned expired envelopes, e.g. await cache.purge().
  /// 主动删除自有过期信封，例如 await cache.purge()。
  Future<void> purge() => _purgeExpired();
}
