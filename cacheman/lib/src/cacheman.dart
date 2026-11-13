import 'dart:async';

import 'package:flutter/foundation.dart' show protected, VoidCallback;
import 'package:flutter/widgets.dart'
    show
        WidgetsFlutterBinding,
        WidgetsBinding,
        WidgetsBindingObserver,
        AppLifecycleState;
import 'memory_storage.dart';

import 'entity.dart';
import 'errors.dart';
import 'value_adapter.dart';
import 'interface.dart';
import 'options.dart';

part 'core.dart';
part 'async_cacheman.dart';
part 'hub.dart';

/// Synchronous cache semantics over overridable storage primitives.
/// 默认使用内存、可覆写存储原语的同步缓存语义层。
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
  /// Creates a memory cache; equal container names share data within this isolate.
  /// 创建内存缓存；当前 isolate 内同名容器共享数据，重启后数据丢失。
  Cacheman({
    String container = _defaultContainer,
    CachemanOptions options = const CachemanOptions(),
  })  : _containerName = container,
        _custom = false,
        _core = _CacheCore(options);

  /// For subclasses that supply their own storage primitives.
  /// Hub identity defaults to `this`; notifications are off until [listenRaw]
  /// is overridden; delayed writes fall back to [setRaw]; [flushRaw] is a no-op.
  /// Plain forwarding subclasses should use the default constructor instead.
  /// 供自带存储原语的子类使用：Hub 身份默认 `this`，覆写
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
        _custom = true,
        _core = _CacheCore(options);

  /// Default memory container name. / 默认内存容器名。
  static const _defaultContainer = 'cacheman';

  /// Whether a subclass supplies its own primitives via [Cacheman.custom].
  /// 子类是否经 [Cacheman.custom] 自带存储原语。
  final bool _custom;

  /// Shared storage-free semantics. / 共用的纯语义内核。
  final _CacheCore _core;

  /// Default container identity. / 默认容器名称。
  final String _containerName;

  /// Lazy pure Dart memory backend. / 惰性创建的纯 Dart 内存后端。
  late final MemoryStorage _memory = MemoryStorage.named(_containerName);

  /// Whether explicit initialization finished. / 是否已完成显式初始化。
  bool _initialized = false;

  /// Owned-key snapshot healed by shared versions; unsupported backends rescan.
  /// 共享版本自动修复自有键快照；无同步通知的后端每次重扫。
  Set<String>? _ownedKeysCache;

  /// Version represented by the current snapshot. / 当前快照对应的版本。
  int _indexVersion = -1;

  /// Scope generation detects namespace switches during mutations.
  /// 作用域代数用于识别写入期间发生的命名空间切换。
  int _scopeGeneration = 0;

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

  /// Observe background failures without reclassifying onError exceptions.
  /// 观察后台失败，保留 onError 异常的原始身份与分类边界。
  void _observeFlush(String key, Future<void> pending) {
    pending.catchError((Object error, StackTrace trace) {
      // An async mutation may capture synchronous notification handler
      // exceptions in its Future and must propagate unchanged to the Zone.
      // 异步变更原语中，同步通知的处理器异常进入其 Future，
      // 须保留原异常并按 Zone 规则传播。
      if (identical(error, _CacheCore._propagatingHandlerError)) {
        Error.throwWithStackTrace(error, trace);
      }
      _core._reportFlushError(key, error, trace);
    });
  }

  /// Raw default memory container; custom backends expose their own handle.
  /// 默认内存容器的原始句柄；自定义后端应另行暴露自己的句柄。
  MemoryStorage get container => _memory;

  /// Escaped namespace prefix (empty if unset). / 转义后的命名空间前缀（未设置时为空）。
  String get namespace => _core.namespace;

  /// Initializes through [initRaw]; await once before reads/writes.
  /// 通过 [initRaw] 初始化，读写前须 await 一次，例如 `await cache.ensureInitialized()`。
  Future<void> ensureInitialized() async {
    await initRaw(_core.context(CacheOp.init));
    _initialized = true;
    if (_core._opts.purgeOnInit && !_core._opts.raw) Timer.run(_purgeExpired);
  }

  /// Initializes the backend; the default memory backend needs no setup.
  /// 初始化后端；默认内存后端无需额外准备。
  @protected
  Future<void> initRaw(CacheContext ctx) async {}

  /// Reads synchronously; null denotes absence. / 同步读取，null 表示缺失。
  /// Override e.g. `return prefs.get(storageKey);`. / 例如覆写为 prefs.get(storageKey)。
  @protected
  Object? getRaw(CacheContext ctx, String storageKey) =>
      container.read<dynamic>(storageKey);

  /// Enumerates actual storage keys synchronously (before namespace filtering).
  /// 同步枚举真实存储键（尚未过滤 namespace），例如返回 map.keys。
  @protected
  Iterable<String> keysRaw(CacheContext ctx) => container.keys;

  /// Updates memory synchronously before returning; Future is only for background
  /// flush errors, never force-retried. Do not await before updating memory.
  /// 返回前同步更新内存态；Future 只承载后台落盘错误，不参与 force 重试。
  /// 不得在更新内存前 await；例如先 map[storageKey] = value，再返回 Future.value()。
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

  /// Shared identity: the named memory container for the default constructor
  /// (including forwarding subclasses), `this` for [Cacheman.custom].
  /// 共享身份：默认构造（含只转发参数的子类）为同名内存容器，[Cacheman.custom] 为 `this`。
  /// Override with your stable backend handle. / 可覆写为稳定的底层句柄。
  @protected
  Object get hubIdentity => _custom ? this : container;

  /// Subscribe to storage keys; null denotes clear. Null return means unsupported.
  /// Notifications describe memory after mutation; table replacements and erase
  /// report null, while writes to the empty key stay keyed. Subclasses may opt in.
  /// 订阅存储键，null 表示整体清空；返回 null 表示不支持。通知须反映变更后的内存，
  /// 整表替换及 erase 上报 null，空串键写入仍按键上报；子类可覆写以支持通知。
  /// Context uses init with no key. / 上下文使用无键 init。
  @protected
  VoidCallback? listenRaw(CacheContext ctx, void Function(String?) onChange) =>
      _custom ? null : container.listen(onChange);

  /// Whether notifications precede mutation return. / 通知是否在变更原语返回前发出。
  @protected
  bool get syncNotificationsRaw => true;

  /// Memory-only write for delayed flush; custom backends fall back to setRaw.
  /// 延迟落盘用的仅内存写；自定义底层默认退化为 setRaw。
  @protected
  void setDeferredRaw(CacheContext ctx, String storageKey, String value) =>
      _observeFlush(storageKey, setRaw(ctx, storageKey, value));

  /// Queue persistence; custom backends whose setRaw already persists need no work.
  /// 排一次落盘；setRaw 已持久化的自定义后端默认无需额外操作。
  /// Context uses write with no key. / 上下文使用无键 write。
  @protected
  Future<void> flushRaw(CacheContext ctx) => Future<void>.value();

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
      try {
        onChange(read<T>(key));
      } catch (error, trace) {
        if (identical(error, _CacheCore._propagatingHandlerError)) rethrow;
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
    _scopeGeneration++;
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
      _observeFlush(key, removeRaw(_core.context(CacheOp.remove, key), key));
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

  /// Increment only the same fresh index in the same scope with one notification.
  /// Reentrant index rebuilds or scope changes invalidate it instead.
  /// 仅对同一作用域内未替换的新鲜索引且恰好一次通知做增量更新；重建或切域则失效。
  void _mutate(String key, VoidCallback action, {bool remove = false}) {
    final version = _hub.version;
    final before = _ownedKeysCache;
    final generation = _scopeGeneration;
    final fresh = before != null && _indexVersion == version;
    _selfDepth++;
    try {
      action();
      if (fresh &&
          identical(_ownedKeysCache, before) &&
          _scopeGeneration == generation &&
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
    try {
      _writeNow(key, encoded);
      return true;
    } catch (error, trace) {
      if (identical(error, _CacheCore._propagatingHandlerError)) rethrow;
      if (!_core._opts.force) {
        _core._reportError(WriteError(key, error, trace));
        return false;
      }
      try {
        _purgeExpired();
        _writeNow(key, encoded);
        return true;
      } catch (retryError, retryTrace) {
        if (identical(retryError, _CacheCore._propagatingHandlerError)) rethrow;
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
        _observeFlush(key, setRaw(ctx, key, value));
      } else {
        // Register before notification so a nested writer becomes the latest owner.
        // 通知前登记，使回调内的嵌套写入者后登记并成为最新错误归属。
        _hub.scheduleFlush(delay, _reportHubError);
        setDeferredRaw(ctx, key, value);
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
  /// With sliding, ttl takes precedence and expireAt only sets the first expiry;
  /// past expireAt restarts from now, and renewal may extend beyond expireAt.
  /// sliding 下 ttl 优先，expireAt 只决定首次过期时间；过去的 expireAt 会从现在
  /// 重新起算；续期可能使实际过期时间超过原 expireAt。
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
        _observeFlush(_allKeys, clearRaw(_core.context(CacheOp.clear)));
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
