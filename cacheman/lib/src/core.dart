part of 'cacheman.dart';

/// Explicit initialization assertion. / 显式初始化断言。
const _initializationMessage =
    'Must await ensureInitialized() before writing. / 写入前必须先 await ensureInitialized()。';

/// Whole-backend error key. / 整个后端的错误键。
const _allKeys = '*';

/// Storage-free semantics shared by both facades through composition.
/// 两个薄层通过组合共用的纯语义内核，不接触存储。
class _CacheCore {
  /// Validates options without constructing any backend. / 校验配置，不构造后端。
  _CacheCore(CachemanOptions options)
      : _opts = options,
        _ns = _initialNs(options.namespace) {
    if (_opts.enckey && _keyCodec == null) {
      // ignore: avoid_print
      print(
          '[cacheman] `enckey` requires a `keyCodec` or `codec`; none provided — keys remain in plaintext.');
    }
    if (_opts.codeable && _opts.codec == null) {
      // ignore: avoid_print
      print(
          '[cacheman] `codeable` requires a `codec`; none provided — values are not encoded.');
    }
  }

  /// Escapes and terminates a namespace to prevent prefix collisions.
  /// 命名空间前缀：转义 `%`/`:` 后再接 `:`，保证 `ns:key` 的拼接无歧义。
  static String _initialNs(String? namespace) =>
      namespace != null && namespace.isNotEmpty
          ? '${_escapeNs(namespace)}:'
          : '';

  /// Escapes namespace delimiters.
  /// 转义命名空间里的 `%` 和 `:`，让前缀里的 `:` 只可能是分隔符。
  static String _escapeNs(String ns) =>
      ns.replaceAll('%', '%25').replaceAll(':', '%3A');

  /// Shared configuration. / 共用配置。
  final CachemanOptions _opts;

  /// Mutable escaped scope. / 可变的转义作用域。
  String _ns;

  /// Whether value encoding is active. / 是否启用值编码。
  bool get _codeable => _opts.codeable && _opts.codec != null;

  /// Key codec falls back to the value codec.
  /// 键编码用的 codec：优先 `keyCodec`，缺省回退 `codec`。
  Codec? get _keyCodec => _opts.keyCodec ?? _opts.codec;

  /// Whether key encoding is active. / 是否启用键编码。
  bool get _enckey => _opts.enckey && _keyCodec != null;

  /// Maximum entries per key mapping cache; overflow clears the whole map.
  /// 每个键映射缓存的容量上限；溢出时整体清空。
  static const int _keyCacheLimit = 1024;

  /// Memoized namespace-prefixed key -> encoded storage key.
  /// Escapes and terminates a namespace to prevent prefix collisions.
  /// 命名空间前缀键 -> 编码后的存储键缓存。
  final Map<String, String> _ekCache = <String, String>{};

  /// Memoized storage key -> namespace-stripped logical key for enumeration.
  /// 枚举用的存储键 -> 去命名空间前缀的逻辑键缓存。
  final Map<String, String> _lkCache = <String, String>{};

  /// Escaped namespace prefix. / 转义后的命名空间前缀。
  String get namespace => _ns;

  /// Resets both bounded key mappings. / 切换时清空两个有界键映射。
  void setNamespace(String? namespace) {
    _ns = _initialNs(namespace);
    _ekCache.clear();
    _lkCache.clear();
  }

  /// Builds primitive context from a storage key. / 从存储键生成原语上下文。
  CacheContext context(CacheOp op, [String? storageKey]) => CacheContext(
        key: storageKey == null ? null : _logical(storageKey),
        namespace: _ns,
        op: op,
      );

  /// Prefixes and optionally encodes a logical key, with bounded memoization.
  /// 给逻辑键加前缀并按需编码，以有界缓存复用结果。
  String _fullKey(String key) {
    final nk = '$_ns$key';
    if (!_enckey) return nk;
    final cached = _ekCache[nk];
    if (cached != null) return cached;
    if (_ekCache.length >= _keyCacheLimit) _ekCache.clear();
    final encoded = _keyCodec!.encode(nk);
    _ekCache[nk] = encoded;
    return encoded;
  }

  /// Whether this storage key is owned by this instance (namespace matches;
  /// with `enckey`, it must decode successfully).
  ///
  /// 该存储键是否归本实例管辖（命名空间匹配；`enckey` 时须能解开）。
  bool _owns(String storageKey) {
    if (_enckey) {
      final decoded = _keyCodec!.decode(storageKey);
      return decoded != null && decoded.startsWith(_ns);
    }
    return storageKey.startsWith(_ns);
  }

  /// Decodes and strips the namespace, caching only successful key decodes.
  /// 解码并去掉命名空间，仅缓存成功的键解码结果。
  String _logical(String storageKey) {
    if (_enckey) {
      final cached = _lkCache[storageKey];
      if (cached != null) return cached;
    }
    final decoded = _enckey ? _keyCodec!.decode(storageKey) : storageKey;
    final fk = decoded ?? storageKey;
    final logical =
        _ns.isNotEmpty && fk.startsWith(_ns) ? fk.substring(_ns.length) : fk;
    if (_enckey && decoded != null) {
      if (_lkCache.length >= _keyCacheLimit) _lkCache.clear();
      _lkCache[storageKey] = logical;
    }
    return logical;
  }

  // ── serialize / codec ────────────────────────────────────────────────────

  /// Serializes and optionally encodes an envelope. / 序列化信封并按需编码。
  String _dump(CacheEntity e) {
    final s = _opts.serialize(e);
    return _codeable ? _opts.codec!.encode(s) : s;
  }

  /// Loads an envelope, optionally forwarding the original decode failure.
  /// 加载信封，可选转交原始解码异常。
  /// Purge/readonly probes omit the callback to avoid repeated scan reports.
  /// purge/readonly 探测不传回调，避免重复扫描刷屏。
  CacheEntity? _load(String raw, {void Function(Object error)? onFailure}) {
    try {
      final text = _codeable ? _opts.codec!.decode(raw) : raw;
      if (text == null) {
        throw const FormatException(
            'Value codec returned null; entry cannot be decoded');
      }
      return _opts.deserialize(text);
    } catch (error) {
      onFailure?.call(error);
      return null;
    }
  }

  /// Builds the entity to persist; `null` means validation failed (already
  /// warned) and the write should be skipped.
  ///
  /// 构造要落盘的 entity；`null` 表示校验没过（已经警告过），应放弃写入。
  CacheEntity? _mkEntity(
      dynamic value, int? ttl, Object? expireAt, String key) {
    final now = DateTime.now().millisecondsSinceEpoch;
    int? finalTtl = ttl;
    if (finalTtl != null && finalTtl <= 0) {
      // ignore: avoid_print
      print(
          '[cacheman] ttl must be a positive number of ms, got $finalTtl; ignoring ttl for "$key"');
      finalTtl = null;
    }
    int? entityExpireAt = finalTtl == null ? null : now + finalTtl;
    if (expireAt != null) {
      final abs = expireAt is DateTime
          ? expireAt.millisecondsSinceEpoch
          : expireAt is int
              ? expireAt
              : null;
      final inPast = abs != null && abs <= now;
      // 绝对时间已过：只有 sliding + ttl 能从现在重新起算，否则放弃写入
      if (abs == null || (inPast && !(_opts.sliding && finalTtl != null))) {
        // ignore: avoid_print
        print(
            '[cacheman] expireAt is invalid or in the past; skipped writing "$key"');
        return null;
      }
      entityExpireAt = inPast ? now + finalTtl! : abs;
    }
    return CacheEntity(
        value: value, createdAt: now, expireAt: entityExpireAt, ttl: finalTtl);
  }

  /// Only marked library envelopes can expire. / 只有带本库标记的信封才会过期。
  bool _isExpired(CacheEntity? e, int now) =>
      e != null &&
      e.expireAt != null &&
      e.createdAt != null &&
      now >= e.expireAt!;

  /// Returns a renewal copy at the inclusive 90% boundary; performs no IO.
  /// 剩余寿命到达 90%（含边界）时返回续期副本，不执行 IO。
  CacheEntity? renewal(CacheEntity entity, int now) => _opts.sliding &&
          entity.ttl != null &&
          entity.expireAt != null &&
          entity.expireAt! - now <= entity.ttl! * 0.9
      ? entity.renewed(now + entity.ttl!)
      : null;

  /// Rejects non-string raw writes consistently. / 统一拒绝非字符串 raw 写入。
  bool acceptsRaw(String key, Object? value) {
    if (value is String) return true;
    // ignore: avoid_print
    print(
        '[cacheman] raw mode requires a String value for "$key", got ${value.runtimeType}; skipped');
    return false;
  }

  /// Warns once per short batch and returns its paired length.
  /// 每批缺值时警告一次并返回可配对长度。
  int batchLength(List<String> keys, List<dynamic> values) {
    if (values.length < keys.length) {
      // ignore: avoid_print
      print(
          '[cacheman] batch set: values(${values.length}) shorter than keys(${keys.length}); missing entries skipped');
    }
    return keys.length < values.length ? keys.length : values.length;
  }

  /// Reports the original decode error after removal. / 删除后上报原始解码异常。
  void reportDecodeError(String key, Object error) =>
      _emitError(key, error, 'decode failed for "$key", entry removed');

  /// Reports an exhausted write failure in either facade.
  /// 上报任一薄层最终失败的写入。
  void _reportError(String key, Object error) =>
      _emitError(key, error, 'write failed for "$key", giving up');

  /// Reports a background disk-flush failure. Note: with get_storage 2.1.1 the
  /// Future returned by `write`/`remove`/`erase` never carries flush errors, so
  /// this is best-effort and may never fire.
  ///
  /// 上报后台落盘失败。注意：get_storage 2.1.1 里 `write`/`remove`/`erase`
  /// 返回的 Future 带不出 flush 错误，这里是尽力而为，可能永远不触发。
  void _reportFlushError(String key, Object error) =>
      _emitError(key, error, 'background flush failed for "$key"');

  /// Dispatches the original error or prints the fallback message.
  /// 分发原始异常或打印默认消息。
  void _emitError(String key, Object error, String message) {
    final cb = _opts.onError;
    if (cb != null) {
      cb(key, error);
    } else {
      // ignore: avoid_print
      print('[cacheman] $message: $error');
    }
  }
}
