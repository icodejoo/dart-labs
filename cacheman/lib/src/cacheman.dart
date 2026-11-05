import 'package:flutter/foundation.dart' show protected;
import 'package:flutter/widgets.dart' show WidgetsFlutterBinding;
import 'package:get_storage/get_storage.dart';

import 'entity.dart';
import 'interface.dart';
import 'options.dart';

part 'core.dart';
part 'async_cacheman.dart';

/// Synchronous cache semantics over overridable storage primitives.
/// 默认封装 get_storage、可覆写存储原语的同步缓存语义层。
///
/// Await [ensureInitialized] once before use. CRUD stays synchronous: mutation
/// primitives must update backend memory before returning; their Futures only
/// carry background flush errors. Use [AsyncCacheman] for on-demand disk IO.
/// 使用前 await [ensureInitialized]；读写保持同步，原语返回前须完成内存态更新，
/// Future 仅承载后台落盘错误。按需读盘请继承 [AsyncCacheman]。
///
/// ```dart
/// final cache = Cacheman();
/// await cache.ensureInitialized();
/// cache.write('token', 'abc', ttl: 60000);
/// final token = cache.read<String>('token');
/// ```
class Cacheman {
  /// Constructs synchronously; the default container is created lazily with
  /// the supplied path. Subclasses may forward `super.options` etc.
  /// 同步构造；默认 container 首次访问时才按所给 path 创建，子类可转发 super.options 等。
  Cacheman({
    String container = 'cacheman',
    String? path,
    CachemanOptions options = const CachemanOptions(),
  })  : _containerName = container,
        _path = path,
        _core = _CacheCore(options);

  /// Shared storage-free semantics. / 共用的纯语义内核。
  final _CacheCore _core;

  /// Default container identity. / 默认容器名称。
  final String _containerName;

  /// Default backend directory, retained until first use. / 首次使用前保留的默认后端目录。
  final String? _path;

  /// First access preserves GetStorage's first-container-path-wins behavior.
  /// 首次访问仍遵循 GetStorage 同名容器首次 path 生效的行为。
  late final GetStorage _gs = GetStorage(_containerName, _path);

  /// Whether explicit initialization finished. / 是否已完成显式初始化。
  bool _initialized = false;

  /// Per-instance owned-key snapshot; external changes can make it stale.
  /// 本实例自有键快照，外部写删可能使其过时。
  Set<String>? _ownedKeysCache;

  /// Raw get_storage container for interop; accessing it creates it even for
  /// custom subclasses. Use `container.listenKey(storageKey('token'), ...)`.
  /// 互操作用的原始容器；自定义子类访问它也会创建容器。监听时配合 storageKey。
  GetStorage get container => _gs;

  /// Escaped namespace prefix (empty if unset). / 转义后的命名空间前缀（未设置时为空）。
  String get namespace => _core.namespace;

  /// Initializes through [initRaw]; await once before reads/writes.
  /// 通过 [initRaw] 初始化，读写前须 await 一次，例如 `await cache.ensureInitialized()`。
  Future<void> ensureInitialized() async {
    await initRaw(_core.context(CacheOp.init));
    _initialized = true;
  }

  /// Initializes the default binding and path-aware container without GetStorage.init.
  /// 默认初始化 binding 并等待带 path 的容器，不调用 GetStorage.init。
  /// Override to initialize your own sync backend. / 可覆写以初始化自定义同步后端。
  @protected
  Future<void> initRaw(CacheContext ctx) async {
    WidgetsFlutterBinding.ensureInitialized();
    await container.initStorage;
  }

  /// Reads synchronously; null denotes absence. / 同步读取，null 表示缺失。
  /// Override e.g. `return prefs.get(storageKey);`. / 例如覆写为 prefs.get(storageKey)。
  @protected
  Object? getRaw(CacheContext ctx, String storageKey) =>
      container.read<dynamic>(storageKey);

  /// Enumerates actual storage keys synchronously (before namespace filtering).
  /// 同步枚举真实存储键（尚未过滤 namespace），例如返回 map.keys。
  @protected
  Iterable<String> keysRaw(CacheContext ctx) =>
      container.getKeys<Iterable<dynamic>>().map((k) => k.toString());

  /// Updates memory synchronously before returning; Future is only for background
  /// flush errors, never force-retried. Do not implement with an async body.
  /// 返回前同步更新内存态；Future 只承载后台落盘错误，不参与 force 重试。
  /// 不可用 async 函数体实现；例如先 map[storageKey] = value，再返回 Future.value()。
  @protected
  Future<void> setRaw(CacheContext ctx, String storageKey, String value) =>
      container.write(storageKey, value);

  /// Deletes synchronously before return; Future only carries background errors.
  /// 返回前同步删除，Future 仅承载后台错误；例如先 map.remove(storageKey)。
  @protected
  Future<void> removeRaw(CacheContext ctx, String storageKey) =>
      container.remove(storageKey);

  /// Clears the entire backend synchronously; Future only carries background errors.
  /// 返回前同步清空整个后端，Future 仅承载后台错误；例如先 map.clear()。
  /// Scoped erase uses removeRaw instead. / 有作用域的 erase 改用 removeRaw。
  @protected
  Future<void> clearRaw(CacheContext ctx) => container.erase();

  /// Switches scope without deleting old data; invalidates key caches.
  /// 切换作用域但不删旧数据，并清空键缓存，例如 cache.setNamespace('alice')。
  void setNamespace([String? namespace]) {
    _core.setNamespace(namespace);
    _ownedKeysCache = null;
  }

  /// Actual prefixed/encoded storage key, e.g. for container.listenKey.
  /// 实际加前缀/编码后的存储键，例如供 container.listenKey 使用。
  String storageKey(String key) => _core._fullKey(key);

  /// Reads a fresh backend string; foreign non-strings count as absent.
  /// 每次读取后端字符串，外部非字符串数据视为缺失。
  String? _get(String key) {
    final value = getRaw(_core.context(CacheOp.read, key), key);
    return value is String ? value : null;
  }

  /// Removes and updates the owned-key snapshot. / 删除并维护自有键快照。
  void _del(String key) {
    removeRaw(_core.context(CacheOp.remove, key), key).catchError(
        (Object e, StackTrace _) => _core._reportFlushError(key, e));
    _ownedKeysCache?.remove(key);
  }

  /// Lazily scans once; only this instance's mutations maintain this set.
  /// 懒扫描一次；此集合只随本实例写删维护。
  Set<String> _ownSet() => _ownedKeysCache ??=
      keysRaw(_core.context(CacheOp.keys)).where(_core._owns).toSet();

  /// Snapshot safe for removal during iteration. / 允许遍历中删除的快照。
  List<String> _ownKeys() => _ownSet().toList(growable: false);

  /// Purge silently probes marked envelopes only. / 清理只静默探测带标记的信封。
  void _purgeExpired() {
    if (_core._opts.raw) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final key in _ownKeys()) {
      final raw = _get(key);
      if (raw != null && _core._isExpired(_core._load(raw), now)) _del(key);
    }
  }

  /// Retries synchronous construction/write errors once; flush Futures are separate.
  /// 同步构造/写入失败重试一次，后台 flush Future 独立处理。
  bool _persist(String key, String Function() build) {
    assert(_initialized, _initializationMessage);
    try {
      _writeNow(key, build());
      return true;
    } catch (error) {
      if (!_core._opts.force) {
        _core._reportError(key, error);
        return false;
      }
      _purgeExpired();
      try {
        _writeNow(key, build());
        return true;
      } catch (retryError) {
        _core._reportError(key, retryError);
        return false;
      }
    }
  }

  /// Tracks successful memory writes, including retries. / 记录成功的内存态写入（含重试）。
  void _writeNow(String key, String value) {
    setRaw(_core.context(CacheOp.write, key), key, value).catchError(
        (Object e, StackTrace _) => _core._reportFlushError(key, e));
    _ownedKeysCache?.add(key);
  }

  /// Reads with lazy expiry, decode reporting and guarded sliding renewal.
  /// 读取时懒删除过期项、上报解码失败并按阈值续期。
  /// Example / 示例：`cache.read<String>('token', 'guest')`.
  T? read<T>(String key, [T? defaultValue]) {
    final sk = storageKey(key);
    final raw = _get(sk);
    if (raw == null) return defaultValue;
    if (_core._opts.raw) return raw as T?;
    final entity = _core._load(raw, onFailure: (error) {
      _del(sk);
      _core.reportDecodeError(sk, error);
    });
    if (entity == null) return defaultValue;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (_core._isExpired(entity, now)) {
      _del(sk);
      return defaultValue;
    }
    final renewed = _core.renewal(entity, now);
    if (renewed != null) _persist(sk, () => _core._dump(renewed));
    return entity.value as T?;
  }

  /// Positional batch read; missing defaults are null. / 按位置批量读取，缺省默认值为 null。
  /// Example / 示例：`cache.readAll(['a', 'b'], [1])`.
  List<dynamic> readAll(List<String> keys, [List<dynamic>? defaults]) => [
        for (var i = 0; i < keys.length; i++)
          read<dynamic>(keys[i],
              defaults != null && i < defaults.length ? defaults[i] : null),
      ];

  /// Writes with millisecond TTL or DateTime/integer absolute expiry.
  /// 按毫秒 TTL 或 DateTime/整数绝对过期时间写入。
  /// Example / 示例：`cache.write('token', 'abc', ttl: 60000)`.
  void write<T>(String key, T value, {int? ttl, Object? expireAt}) {
    final sk = storageKey(key);
    if (_core._opts.readonly && _alive(sk)) return;
    if (_core._opts.raw) {
      if (_core.acceptsRaw(key, value)) _persist(sk, () => value as String);
      return;
    }
    final entity = _core._mkEntity(value, ttl, expireAt, key);
    if (entity != null) _persist(sk, () => _core._dump(entity));
  }

  /// Presence probe without deletion, reporting or renewal; null values count.
  /// 存在性探测不删除、不上报、不续期；存储的 null 值也算存在。
  bool _alive(String key) {
    final raw = _get(key);
    if (raw == null) return false;
    if (_core._opts.raw) return true;
    final entity = _core._load(raw);
    return entity != null &&
        !_core._isExpired(entity, DateTime.now().millisecondsSinceEpoch);
  }

  /// Positional batch write, warning/skipping missing values; expiry applies to all.
  /// 按位置批量写入，缺值警告并跳过；过期参数应用于全部键。
  /// Example / 示例：`cache.writeAll(['a', 'b'], [1, 2], ttl: 60000)`.
  void writeAll(List<String> keys, List<dynamic> values,
      {int? ttl, Object? expireAt}) {
    final n = _core.batchLength(keys, values);
    for (var i = 0; i < n; i++) {
      write<dynamic>(keys[i], values[i], ttl: ttl, expireAt: expireAt);
    }
  }

  /// Removes one key, e.g. cache.remove('token'). / 删除一个键，例如 cache.remove('token')。
  void remove(String key) => _del(storageKey(key));

  /// Removes a batch, e.g. cache.removeAll(['a', 'b']). / 批量删除，例如 cache.removeAll(['a', 'b'])。
  void removeAll(List<String> keys) {
    for (final key in keys) {
      remove(key);
    }
  }

  /// Deletes owned keys with namespace/enckey, otherwise clears the whole backend.
  /// 有 namespace/enckey 时删除自有键，否则清空整个后端，例如 cache.erase()。
  void erase() {
    if (namespace.isEmpty && !_core._enckey) {
      clearRaw(_core.context(CacheOp.clear)).catchError(
          (Object e, StackTrace _) => _core._reportFlushError(_allKeys, e));
      _ownedKeysCache = <String>{};
      return;
    }
    _ownKeys().forEach(_del);
  }

  /// Positional logical key, null out of range. / 按下标取逻辑键，越界返回 null。
  String? key(int index) {
    if (namespace.isNotEmpty || _core._enckey) {
      final ks = _ownSet();
      return index < 0 || index >= ks.length
          ? null
          : _core._logical(ks.elementAt(index));
    }
    if (index < 0) return null;
    var i = 0;
    for (final key in keysRaw(_core.context(CacheOp.keys))) {
      if (i == index) return _core._logical(key);
      i++;
    }
    return null;
  }

  /// Owned logical keys, e.g. cache.keys(). / 自有逻辑键，例如 cache.keys()。
  List<String> keys() => _ownSet().map(_core._logical).toList(growable: false);

  /// Proactively deletes owned expired envelopes. / 主动删除自有过期信封。
  void purge() => _purgeExpired();

  /// Counts owned keys; global count without namespace/enckey.
  /// 统计自有键；无 namespace/enckey 时为后端全局数量。
  int get length => namespace.isNotEmpty || _core._enckey
      ? _ownSet().length
      : keysRaw(_core.context(CacheOp.keys)).length;
}
