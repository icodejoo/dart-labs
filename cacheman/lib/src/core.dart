part of 'cacheman.dart';

/// Explicit initialization assertion. / 显式初始化断言。
const _initializationMessage =
    'Must await ensureInitialized() before writing. / 写入前必须先 await ensureInitialized()。';

/// Whole-backend error key. / 整个后端的错误键。
const _allKeys = '*';

/// 不接触存储的读取决策，保留调用方的默认值。
sealed class _ReadDecision<T> {
  /// 保存缺失、删除或转换失败时使用的默认值。
  const _ReadDecision(this.storageKey, this.fallback);

  /// 本次读取对应的实际存储键。
  final String storageKey;

  /// 本次读取的默认值。
  final T? fallback;
}

/// 缺失或外部非字符串数据，无需后续 IO。
final class _Miss<T> extends _ReadDecision<T> {
  /// 构造无副作用的缺失结果。
  const _Miss(super.storageKey, super.fallback);
}

/// 删除成功后返回默认值，并按需上报原始解码异常。
final class _DropAndDefault<T> extends _ReadDecision<T> {
  /// 保存待删除条目的错误及堆栈，过期删除不携带错误。
  const _DropAndDefault(super.storageKey, super.fallback,
      [this.error, this.trace]);

  /// 解码失败的原始异常，过期时为空。
  final Object? error;

  /// 解码失败时的原始堆栈。
  final StackTrace? trace;
}

/// 命中后先执行可选续期，再转换原值；续期失败不丢失原值。
final class _Hit<T> extends _ReadDecision<T> {
  /// 保存原值、适配器及可选续期计划。
  const _Hit(
      super.storageKey, super.fallback, this.value, this.adapter, this.renewal);

  /// 解码后的原始业务值，允许为 null。
  final Object? value;

  /// 续期完成后才调用的读取适配器。
  final ValueAdapter<T>? adapter;

  /// 延后编码的续期计划，未到续期阈值时为空。
  final _WritePlan? renewal;
}

/// 只描述一次编码，后端重试始终复用同一个编码字符串。
final class _WritePlan {
  /// 保存编码动作，让外壳先断言初始化再执行编码。
  const _WritePlan(this.encode);

  /// 不访问存储的编码动作。
  final String Function() encode;
}

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
  CacheContext context(CacheOp op, [String? storageKey]) {
    final scope = _ns;
    return CacheContext.lazy(
      storageKey: storageKey,
      namespace: scope,
      op: op,
      resolveKey: () {
        if (storageKey == null) return null;
        if (scope == _ns) return _logical(storageKey);
        final decoded = _enckey ? _keyCodec!.decode(storageKey) : storageKey;
        final full = decoded ?? storageKey;
        return full.startsWith(scope) ? full.substring(scope.length) : full;
      },
    );
  }

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
  CacheEntity? _load(String raw,
      {void Function(Object error, StackTrace trace)? onFailure}) {
    try {
      final text = _codeable ? _opts.codec!.decode(raw) : raw;
      if (text == null) {
        throw const FormatException(
            'Value codec returned null; entry cannot be decoded');
      }
      return _opts.deserialize(text);
    } catch (error, trace) {
      onFailure?.call(error, trace);
      return null;
    }
  }

  /// Builds the entity to persist; `null` means validation failed (already
  /// warned) and the write should be skipped.
  ///
  /// 构造要落盘的 entity；`null` 表示校验没过（已经警告过），应放弃写入。
  CacheEntity? _mkEntity(
      dynamic value, int? ttl, Object? expireAt, String key, int now) {
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

  /// Returns a marked envelope's renewal copy at the inclusive 90% boundary; no IO.
  /// 带本库标记的信封剩余寿命到达 90%（含边界）时返回续期副本，不执行 IO。
  CacheEntity? renewal(CacheEntity entity, int now) => _opts.sliding &&
          entity.createdAt != null &&
          entity.ttl != null &&
          entity.expireAt != null &&
          entity.expireAt! - now <= entity.ttl! * 0.9
      ? entity.renewed(now + entity.ttl!)
      : null;

  /// 根据原始值和时间给出读取决策；不调用后端或错误处理器。
  _ReadDecision<T> decideRead<T>(String storageKey, Object? raw, int now,
      T? fallback, ValueAdapter<T>? adapter) {
    if (raw is! String) return _Miss(storageKey, fallback);
    if (_opts.raw) {
      warnRawAdapter(adapter);
      return _Hit(storageKey, fallback, raw, null, null);
    }
    Object? failure;
    StackTrace? failureTrace;
    final entity = _load(raw, onFailure: (error, trace) {
      failure = error;
      failureTrace = trace;
    });
    if (entity == null) {
      return _DropAndDefault(storageKey, fallback, failure, failureTrace);
    }
    if (_isExpired(entity, now)) return _DropAndDefault(storageKey, fallback);
    final renewed = renewal(entity, now);
    return _Hit(storageKey, fallback, entity.value, adapter,
        renewed == null ? null : _WritePlan(() => _dump(renewed)));
  }

  /// 外壳完成删除或续期后才上报、转换，保留回调异常和副作用顺序。
  T? finishRead<T>(_ReadDecision<T> decision) {
    final key = decision.storageKey;
    switch (decision) {
      case _DropAndDefault<T>(:final error, :final trace):
        if (error != null) reportDecodeError(key, error, trace);
        return decision.fallback;
      case _Hit<T>(:final value, :final adapter):
        return typed(key, value, decision.fallback, adapter);
      case _Miss<T>():
        return decision.fallback;
    }
  }

  /// 只有 readonly 写入需要外壳读取现值。
  bool get needsWriteProbe => _opts.readonly;

  /// 静默判定现值是否存活，不删除、不上报、不续期。
  bool alive(Object? raw, int now) {
    if (raw is! String) return false;
    if (_opts.raw) return true;
    final entity = _load(raw);
    return entity != null && !_isExpired(entity, now);
  }

  /// 统一 readonly、raw 和过期参数判定，返回待编码计划或跳过。
  _WritePlan? decideWrite<T>(String key, T value, Object? raw, int now,
      {int? ttl, Object? expireAt, ValueAdapter<T>? adapter}) {
    if (_opts.readonly && alive(raw, now)) return null;
    if (_opts.raw) {
      warnRawAdapter(adapter);
      return acceptsRaw(key, value) ? _WritePlan(() => value as String) : null;
    }
    final entity = _mkEntity(value, ttl, expireAt, key, now);
    return entity == null
        ? null
        : _WritePlan(() => encode(entity, value, adapter));
  }

  /// raw 无需扫描清理，避免枚举后端或读取任何值。
  bool get canPurge => !_opts.raw;

  /// 仅删除带本库标记的过期信封，损坏及外部数据保持原样。
  bool shouldPurge(Object? raw, int now) =>
      canPurge && raw is String && _isExpired(_load(raw), now);

  /// 是否可以整库清空；namespace 或键编码均要求逐个删除自有键。
  bool get clearsBackend => _ns.isEmpty && !_enckey;

  /// 顺序批读的默认值，短列表按 null 补齐。
  dynamic batchDefault(List<dynamic>? defaults, int index) =>
      defaults != null && index < defaults.length ? defaults[index] : null;

  /// 最多指示一次清理重试；最终分类上报，用户处理器异常保持原样传播。
  bool retryWrite(String key, Object error, StackTrace trace,
      {required bool retried}) {
    if (identical(error, _propagatingHandlerError)) {
      Error.throwWithStackTrace(error, trace);
    }
    if (_opts.force && !retried) return true;
    _reportError(WriteError(key, error, trace));
    return false;
  }

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

  /// Encodes an adapted value while preserving envelope metadata.
  /// 编码适配后的值并保留信封元数据。
  String encode<T>(CacheEntity entity, T value, ValueAdapter<T>? adapter) =>
      adapter == null
          ? _dump(entity)
          : _dump(CacheEntity(
              value: adapter.toJson(value),
              createdAt: entity.createdAt,
              expireAt: entity.expireAt,
              ttl: entity.ttl,
            ));

  /// Builds once before any backend retry; encoding failures never purge.
  /// 在底层重试前仅构造一次；编码失败从不清理。
  String? build(String key, String Function() encode) {
    try {
      return encode();
    } catch (error, trace) {
      _reportError(SerializeError(key, error, trace));
      return null;
    }
  }

  /// Ignores raw adapters with a debug-only warning. / raw 忽略适配器并仅在调试时警告。
  void warnRawAdapter(Object? adapter) {
    assert(() {
      if (adapter != null) {
        // ignore: avoid_print
        print(
            '[cacheman] raw mode ignores ValueAdapter / raw 模式忽略 ValueAdapter');
      }
      return true;
    }());
  }

  /// Converts safely; type/adapter failures report without removing data.
  /// 安全转换；类型/适配器失败仅上报，不删除数据。
  T? typed<T>(
      String key, Object? value, T? fallback, ValueAdapter<T>? adapter) {
    try {
      return adapter == null ? value as T? : adapter.fromJson(value);
    } catch (error, trace) {
      _reportError(TypeMismatchError(key, error,
          expected: T, actual: value.runtimeType, stackTrace: trace));
      return fallback;
    }
  }

  /// Reports corruption only after removal succeeds. / 仅在删除成功后上报损坏。
  void reportDecodeError(String key, Object error, StackTrace? trace) =>
      _reportError(
          CorruptEntryError(key, error, dropped: true, stackTrace: trace));

  /// Reports an already classified failure. / 上报已分类的失败。
  void _reportError(CachemanError error) =>
      _emitError(error.key, error, 'operation failed');

  /// Reports observable background failures; get_storage may hide disk failures.
  /// 上报可观察的后台失败；get_storage 可能隐藏磁盘异常。
  void _reportFlushError(String key, Object error, [StackTrace? trace]) =>
      _reportError(FlushError(key, error, trace));

  /// Tracks the exact handler exception across peer retry/watch/Future boundaries.
  /// 跨实例重试、watch 和 Future 边界追踪处理器异常的对象身份。
  static Object? _propagatingHandlerError;

  /// Dispatches the original error or prints the fallback message.
  /// 分发原始异常或打印默认消息。
  void _emitError(String key, CachemanError error, String message) {
    _propagatingHandlerError = null;
    final cb = _opts.onError;
    if (cb != null) {
      try {
        cb(key, error);
      } catch (error) {
        _propagatingHandlerError = error;
        rethrow;
      }
    } else {
      // ignore: avoid_print
      print('[cacheman] $message: $error');
    }
  }
}
