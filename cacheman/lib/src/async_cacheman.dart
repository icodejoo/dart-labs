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

  /// Reads a fresh string; foreign non-strings are absent. / 每次读字符串，外部非字符串视为缺失。
  Future<String?> _get(String key) async {
    final value = await getRaw(_core.context(CacheOp.read, key), key);
    return value is String ? value : null;
  }

  /// Deletes via the primitive. / 经原语删除。
  Future<void> _del(String key) =>
      removeRaw(_core.context(CacheOp.remove, key), key);

  /// Always scans backend keys; no owned-key set is retained.
  /// 每次扫描后端键，不保留自有键集合。
  Future<List<String>> _ownKeys() async =>
      (await keysRaw(_core.context(CacheOp.keys)))
          .where(_core._owns)
          .toList(growable: false);

  /// Purges quietly, protecting raw values and unmarked foreign envelopes.
  /// 静默清理，保护 raw 值及无本库标记的外部信封。
  Future<void> _purgeExpired() async {
    if (_core._opts.raw) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final key in await _ownKeys()) {
      final raw = await _get(key);
      if (raw != null && _core._isExpired(_core._load(raw), now)) {
        await _del(key);
      }
    }
  }

  /// Awaits persistence; serialization and primitive failures share one retry.
  /// 等待写入完成；序列化与原语失败共用一次重试。
  Future<bool> _persist(String key, String Function() build) async {
    assert(_initialized, _initializationMessage);
    try {
      await setRaw(_core.context(CacheOp.write, key), key, build());
      return true;
    } catch (error) {
      if (!_core._opts.force) {
        _core._reportError(key, error);
        return false;
      }
      try {
        await _purgeExpired();
        await setRaw(_core.context(CacheOp.write, key), key, build());
        return true;
      } catch (retryError) {
        _core._reportError(key, retryError);
        return false;
      }
    }
  }

  /// Reads with lazy expiry, decode-error reporting and awaited sliding renewal.
  /// 读取时懒删除过期项、上报解码失败并等待滑动续期；续期写入失败仍返回原值。
  /// Example / 示例：`await cache.read<String>('report', 'missing')`.
  Future<T?> read<T>(String key, [T? defaultValue]) async {
    final sk = _core._fullKey(key);
    final raw = await _get(sk);
    if (raw == null) return defaultValue;
    if (_core._opts.raw) return raw as T?;
    Object? failure;
    final entity = _core._load(raw, onFailure: (error) => failure = error);
    if (entity == null) {
      await _del(sk);
      if (failure != null) _core.reportDecodeError(sk, failure!);
      return defaultValue;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    if (_core._isExpired(entity, now)) {
      await _del(sk);
      return defaultValue;
    }
    final renewed = _core.renewal(entity, now);
    if (renewed != null) await _persist(sk, () => _core._dump(renewed));
    return entity.value as T?;
  }

  /// Sequential positional reads; missing defaults are null.
  /// 顺序按位置批量读取，缺省默认值为 null。
  /// Example / 示例：`await cache.readAll(['a', 'b'], [1])`.
  Future<List<dynamic>> readAll(List<String> keys,
          [List<dynamic>? defaults]) async =>
      [
        for (var i = 0; i < keys.length; i++)
          await read<dynamic>(keys[i],
              defaults != null && i < defaults.length ? defaults[i] : null),
      ];

  /// Writes with millisecond TTL or DateTime/integer absolute expiry.
  /// 按毫秒 TTL 或 DateTime/整数绝对过期时间写入。
  /// Example / 示例：`await cache.write('report', 'text', ttl: 60000)`.
  Future<void> write<T>(String key, T value,
      {int? ttl, Object? expireAt}) async {
    final sk = _core._fullKey(key);
    if (_core._opts.readonly && await _alive(sk)) return;
    if (_core._opts.raw) {
      if (_core.acceptsRaw(key, value)) {
        await _persist(sk, () => value as String);
      }
      return;
    }
    final entity = _core._mkEntity(value, ttl, expireAt, key);
    if (entity != null) await _persist(sk, () => _core._dump(entity));
  }

  /// Presence probe without side effects; stored null counts as present.
  /// 无副作用的存在性探测，存储的 null 值也算存在。
  Future<bool> _alive(String key) async {
    final raw = await _get(key);
    if (raw == null) return false;
    if (_core._opts.raw) return true;
    final entity = _core._load(raw);
    return entity != null &&
        !_core._isExpired(entity, DateTime.now().millisecondsSinceEpoch);
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
    if (namespace.isEmpty && !_core._enckey) {
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
