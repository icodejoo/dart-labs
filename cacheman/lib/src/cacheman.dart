import 'dart:async';

import 'package:flutter/foundation.dart' show protected, VoidCallback;
import 'package:flutter/widgets.dart'
    show
        WidgetsFlutterBinding,
        WidgetsBinding,
        WidgetsBindingObserver,
        AppLifecycleState;
import 'package:get_storage/get_storage.dart';

import 'entity.dart';
import 'errors.dart';
import 'value_adapter.dart';
import 'interface.dart';
import 'options.dart';

part 'core.dart';
part 'async_cacheman.dart';
part 'hub.dart';

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
    String container = _defaultContainer,
    String? path,
    CachemanOptions options = const CachemanOptions(),
  })  : _containerName = container,
        _path = path,
        _custom = false,
        _core = _CacheCore(options);

  /// For subclasses that supply their own storage primitives (no get_storage).
  /// Hub identity defaults to `this`; notifications are off until [listenRaw]
  /// is overridden; delayed writes fall back to [setRaw]; [flushRaw] is a no-op.
  /// Plain forwarding subclasses should use the default constructor instead.
  /// 供自带存储原语（不用 get_storage）的子类使用：Hub 身份默认 `this`，覆写
  /// [listenRaw] 前不支持通知，延迟写退化为 [setRaw]，[flushRaw] 不操作。
  /// 只转发参数的子类应使用默认构造。
  ///
  /// ```dart
  /// class PrefsCache extends Cacheman {
  ///   PrefsCache({super.options}) : super.custom();
  ///   // override initRaw/getRaw/keysRaw/setRaw/removeRaw/clearRaw ...
  /// }
  /// ```
  Cacheman.custom({CachemanOptions options = const CachemanOptions()})
      : _containerName = _defaultContainer,
        _path = null,
        _custom = true,
        _core = _CacheCore(options);

  /// Default get_storage container name. / 默认 get_storage 容器名。
  static const _defaultContainer = 'cacheman';

  /// Whether a subclass supplies its own primitives via [Cacheman.custom].
  /// 子类是否经 [Cacheman.custom] 自带存储原语。
  final bool _custom;

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

  /// Owned-key snapshot healed by shared versions; unsupported backends rescan.
  /// 共享版本自动修复自有键快照；无同步通知的后端每次重扫。
  Set<String>? _ownedKeysCache;

  /// Version represented by the current snapshot. / 当前快照对应的版本。
  int _indexVersion = -1;

  /// Reentrant own-mutation depth for feedback-loop suppression. / 本实例嵌套写入深度，用于断环。
  int _selfDepth = 0;

  /// Subscriptions that migrate with this instance's namespace. / 随本实例命名空间迁移的订阅。
  final _watches = <_HubWatch>{};

  /// One shared hub, created only when needed. / 按需创建的共享 Hub。
  late final _hub = _ContainerHub.of(
    hubIdentity,
    listen: (callback) => listenRaw(_core.context(CacheOp.init), callback),
    synchronous: syncNotificationsRaw,
    flush: () => flushRaw(_core.context(CacheOp.write)),
    report: _reportHubError,
  );

  /// Reports hub flush errors on the whole-backend key. / 以整库错误键上报 Hub 落盘异常。
  void _reportHubError(Object error, StackTrace trace) =>
      _core._reportFlushError(_allKeys, error, trace);

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
    if (_core._opts.purgeOnInit && !_core._opts.raw) Timer.run(_purgeExpired);
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

  /// Shared identity: the GetStorage singleton for the default constructor
  /// (including forwarding subclasses), `this` for [Cacheman.custom].
  /// 共享身份：默认构造（含只转发参数的子类）为 GetStorage 单例，[Cacheman.custom] 为 `this`。
  /// Override with your stable backend handle. / 可覆写为稳定的底层句柄。
  @protected
  Object get hubIdentity => _custom ? this : container;

  /// Subscribe to storage keys; null denotes clear. Null return means unsupported.
  /// Notifications must describe memory after mutation; default maps erase's empty
  /// key to null. Subclasses opt in by overriding this hook.
  /// 订阅存储键，null 表示整体清空；返回 null 表示不支持。通知须反映变更后的内存，
  /// 默认把 erase 的空键转为 null；子类可覆写以支持通知。
  /// Context uses init with no key. / 上下文使用无键 init。
  @protected
  VoidCallback? listenRaw(CacheContext ctx, void Function(String?) onChange) {
    if (_custom) return null;
    return container.listen(() {
      final key = container.changes.keys.single;
      onChange(key.isEmpty ? null : key);
    });
  }

  /// Whether notifications precede mutation return; verified for get_storage 2.1.1.
  /// 通知是否在变更原语返回前发出；已实测 get_storage 2.1.1 为同步。
  @protected
  bool get syncNotificationsRaw => true;

  /// Memory-only write for delayed flush; custom backends fall back to setRaw.
  /// 延迟落盘用的仅内存写；自定义底层默认退化为 setRaw。
  @protected
  void setDeferredRaw(CacheContext ctx, String storageKey, String value) {
    if (_custom) {
      setRaw(ctx, storageKey, value).catchError((Object e, StackTrace trace) =>
          _core._reportFlushError(storageKey, e, trace));
    } else {
      container.writeInMemory(storageKey, value);
    }
  }

  /// Queue persistence; custom backends whose setRaw already persists need no work.
  /// 排一次落盘；setRaw 已持久化的自定义后端默认无需额外操作。
  /// Context uses write with no key. / 上下文使用无键 write。
  @protected
  Future<void> flushRaw(CacheContext ctx) =>
      _custom ? Future<void>.value() : container.save();

  /// Queue a shared flush immediately; errors go to onError. Returns synchronously.
  /// 立即排共享落盘；错误走 onError，同步返回。例如 `cache.flush()`。
  void flush() => _hub.flushNow(_reportHubError);

  /// Watch decoded values, including expiry semantics; cancel with the return value.
  /// Own writes (including renewal/lazy deletion) are excluded by default, allowing
  /// Rx feedback binding. Unsupported notifications throw UnsupportedError; with
  /// asynchronous notifications own writes may still arrive: compare values yourself.
  /// 监听解码值（含过期语义），返回取消函数；默认忽略本实例写入（含续期/懒删），
  /// 可用于 Rx 双向断环。底层不支持通知时抛 UnsupportedError；异步通知可能仍收到
  /// 本实例写入，此时调用方须自行判等。
  /// Example / 示例：`final stop = cache.watch<int>('count', (v) => print(v)); stop();`.
  VoidCallback watch<T>(String key, void Function(T? value) onChange,
      {bool includeOwnWrites = false}) {
    if (!_hub.supportsWatch) {
      throw UnsupportedError('Backend does not support watch / 底层不支持变更通知');
    }
    late final _HubWatch watcher;
    watcher = _HubWatch(key, storageKey(key), () {
      if (!includeOwnWrites && _selfDepth > 0) return;
      final errorKey = watcher.storageKey;
      final handlerFailures = _core.handlerFailures;
      try {
        onChange(read<T>(key));
      } catch (error, trace) {
        if (_core.handlerFailures != handlerFailures) rethrow;
        _core._reportError(WatchError(errorKey, error, trace));
      }
    });
    _watches.add(watcher);
    _hub.add(watcher);
    return () {
      watcher.active = false;
      _watches.remove(watcher);
      _hub.remove(watcher);
    };
  }

  /// Switches scope without deleting old data; invalidates key caches.
  /// 切换作用域但不删旧数据，并清空键缓存，例如 cache.setNamespace('alice')。
  void setNamespace([String? namespace]) {
    _core.setNamespace(namespace);
    _ownedKeysCache = null;
    for (final watcher in _watches) {
      _hub.remove(watcher);
      watcher.storageKey = storageKey(watcher.key);
      _hub.add(watcher);
    }
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
    _mutate(key, () {
      removeRaw(_core.context(CacheOp.remove, key), key).catchError(
          (Object e, StackTrace trace) =>
              _core._reportFlushError(key, e, trace));
    }, remove: true);
  }

  /// Rebuild only on external changes, or always without synchronous notifications.
  /// 外部变更时才重建；没有同步通知能力则每次重建。
  Set<String> _ownSet() {
    if (_ownedKeysCache == null ||
        !_hub.synchronous ||
        _indexVersion != _hub.version) {
      _ownedKeysCache =
          keysRaw(_core.context(CacheOp.keys)).where(_core._owns).toSet();
      _indexVersion = _hub.version;
    }
    return _ownedKeysCache!;
  }

  /// Track only a fresh index and one notification; reentrant external mutations
  /// invalidate it rather than incorrectly blessing a partial snapshot.
  /// 仅对新鲜索引且恰好一次通知做增量更新；重入外部写入使索引失效，避免错误标新。
  void _mutate(String key, VoidCallback action, {bool remove = false}) {
    final version = _hub.version;
    final fresh = _ownedKeysCache != null && _indexVersion == version;
    _selfDepth++;
    try {
      action();
      if (fresh &&
          _ownedKeysCache != null &&
          _hub.synchronous &&
          _hub.version == version + 1) {
        if (remove) {
          _ownedKeysCache!.remove(key);
        } else {
          _ownedKeysCache!.add(key);
        }
        _indexVersion = _hub.version;
      } else {
        _ownedKeysCache = null;
      }
    } finally {
      _selfDepth--;
    }
  }

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

  /// Builds once, then retries only backend writes; background failures stay separate.
  /// 仅构造一次，然后只重试底层写入；后台失败独立处理。
  bool _persist(String key, String Function() build) {
    assert(_initialized, _initializationMessage);
    final encoded = _core.build(key, build);
    if (encoded == null) return false;
    final handlerFailures = _core.handlerFailures;
    try {
      _writeNow(key, encoded);
      return true;
    } catch (error, trace) {
      if (_core.handlerFailures != handlerFailures) rethrow;
      if (!_core._opts.force) {
        _core._reportError(WriteError(key, error, trace));
        return false;
      }
      try {
        _purgeExpired();
        _writeNow(key, encoded);
        return true;
      } catch (retryError, retryTrace) {
        if (_core.handlerFailures != handlerFailures) rethrow;
        _core._reportError(WriteError(key, retryError, retryTrace));
        return false;
      }
    }
  }

  /// Tracks successful memory writes, including retries. / 记录成功的内存态写入（含重试）。
  void _writeNow(String key, String value) {
    _mutate(key, () {
      final ctx = _core.context(CacheOp.write, key);
      final delay = _core._opts.flushDelay;
      if (delay == null) {
        setRaw(ctx, key, value).catchError((Object e, StackTrace trace) =>
            _core._reportFlushError(key, e, trace));
      } else {
        setDeferredRaw(ctx, key, value);
        _hub.scheduleFlush(delay, _reportHubError);
      }
    });
  }

  /// Reads with lazy expiry, decode reporting and guarded sliding renewal.
  /// 读取时懒删除过期项、上报解码失败并按阈值续期。
  /// Type/adapter mismatches return the default and retain data; no numeric coercion.
  /// 类型/适配器不符返回默认值并保留数据；不做数字互转，int 可用 num 读取。
  /// Backend IO and user onError exceptions still propagate. / 后端 IO 及用户 onError 异常仍传播。
  /// Example / 示例：`cache.read<String>('token', 'guest')`.
  T? read<T>(String key, [T? defaultValue]) => _read(key, defaultValue, null);

  /// Reads with JSON adaptation; mismatches return defaultValue without removal.
  /// 带 JSON 适配读取；不匹配返回 defaultValue，不删除数据。
  /// Dart cannot mix optional positional and named parameters; read keeps its
  /// positional default, while this entry accepts named defaultValue/adapter.
  /// Dart 无法混合可选位置与命名参数；read 保留位置默认值，本方法提供命名参数。
  /// Example / 示例：
  /// ```dart
  /// cache.readWith<List<String>>('names', adapter: ValueAdapter.listOf<String>());
  /// ```
  T? readWith<T>(String key, {T? defaultValue, ValueAdapter<T>? adapter}) =>
      _read(key, defaultValue, adapter);

  /// Shared read orchestration with optional adaptation. / 带可选适配的共用读取编排。
  T? _read<T>(String key, T? defaultValue, ValueAdapter<T>? adapter) {
    final sk = storageKey(key);
    final raw = _get(sk);
    if (raw == null) return defaultValue;
    if (_core._opts.raw) {
      _core.warnRawAdapter(adapter);
      return _core.typed(sk, raw, defaultValue, null);
    }
    final entity = _core._load(raw, onFailure: (error, trace) {
      _del(sk);
      _core.reportDecodeError(sk, error, trace);
    });
    if (entity == null) return defaultValue;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (_core._isExpired(entity, now)) {
      _del(sk);
      return defaultValue;
    }
    final renewed = _core.renewal(entity, now);
    if (renewed != null) _persist(sk, () => _core._dump(renewed));
    return _core.typed(sk, entity.value, defaultValue, adapter);
  }

  /// Positional batch read; missing defaults are null. / 按位置批量读取，缺省默认值为 null。
  /// Example / 示例：`cache.readAll(['a', 'b'], [1])`.
  List<dynamic> readAll(List<String> keys, [List<dynamic>? defaults]) => [
        for (var i = 0; i < keys.length; i++)
          read<dynamic>(keys[i],
              defaults != null && i < defaults.length ? defaults[i] : null),
      ];

  /// Writes with millisecond TTL or DateTime/integer absolute expiry.
  /// Optional adapter converts before serialization; raw ignores it.
  /// 可选 adapter 在序列化前转换；raw 忽略它。
  /// Example / 示例：`cache.write('names', ['Ada'], adapter: ValueAdapter.listOf<String>())`.
  /// 按毫秒 TTL 或 DateTime/整数绝对过期时间写入。
  /// Example / 示例：`cache.write('token', 'abc', ttl: 60000)`.
  void write<T>(String key, T value,
      {int? ttl, Object? expireAt, ValueAdapter<T>? adapter}) {
    final sk = storageKey(key);
    if (_core._opts.readonly && _alive(sk)) return;
    if (_core._opts.raw) {
      _core.warnRawAdapter(adapter);
      if (_core.acceptsRaw(key, value)) _persist(sk, () => value as String);
      return;
    }
    final entity = _core._mkEntity(value, ttl, expireAt, key);
    if (entity != null) {
      _persist(sk, () => _core.encode(entity, value, adapter));
    }
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
      _selfDepth++;
      try {
        clearRaw(_core.context(CacheOp.clear)).catchError(
            (Object e, StackTrace trace) =>
                _core._reportFlushError(_allKeys, e, trace));
        _ownedKeysCache = null;
      } finally {
        _selfDepth--;
      }
      return;
    }
    _ownKeys().forEach(_del);
  }

  /// Positional logical key, null out of range. O(index); use one keys() snapshot
  /// instead of O(n²) indexed loops. / 按下标取逻辑键，越界返回 null；O(index)，
  /// 循环为 O(n²)，请改用一次 keys() 快照。Example / 示例：`for (final k in cache.keys()) ...`.
  @Deprecated('O(index); loops cost O(n²). Use keys() instead. / 请使用 keys()。')
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
