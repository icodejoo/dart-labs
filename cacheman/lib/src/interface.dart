/// Pluggable string transform, applied to the serialized entity string before
/// it's written and after it's read (obfuscation / encryption / compression).
/// No implementation ships with this package — bring your own; [Cacheman]
/// only calls `encode`/`decode` when [CachemanOptions.codeable] is true and a
/// [Codec] is provided.
///
/// 可插拔的字符串变换，作用在序列化后的 entity 字符串上，写入前 encode、
/// 读出后 decode（混淆/加密/压缩都行）。本包不内置任何实现——自己接入；
/// [Cacheman] 只在 [CachemanOptions.codeable] 为 true 且提供了 [Codec] 时才会
/// 调用 `encode`/`decode`。
abstract class Codec {
  /// Transforms a string before it's persisted.
  ///
  /// 落盘前对字符串做变换。
  String encode(String value);

  /// Reverses [encode]. Returns `null` on failure (wrong key / corrupted
  /// data) — the caller treats a `null` as "unreadable", clears the stale
  /// entry, and falls back to the default value, never throwing.
  ///
  /// 反向还原 [encode]。失败（密钥不对/数据损坏）返回 `null`——调用方视为
  /// "读不出来"，清掉这条脏数据并回退默认值，不抛异常。
  String? decode(String value);
}

/// Receives an actual storage key and a CachemanError; cause is the original error.
/// All reported failures are classified; callback exceptions still propagate.
/// Breaking: replace `error is FormatException` with
/// `error is CorruptEntryError && error.cause is FormatException`.
/// 接收实际存储键与 CachemanError，cause 保留原异常；回调自身异常仍向上传播。
/// 破坏性：原 `error is FormatException` 判断需改为
/// `error is CorruptEntryError && error.cause is FormatException`。
/// Example / 示例：`onError: (key, error) => print(error)`.
typedef CachemanOnError = void Function(String key, Object error);

/// Backend primitive operation, including internal expiry cleanup/renewal.
/// 底层原语操作类型，也用于内部过期清理与续期。
enum CacheOp {
  /// Initialize. / 初始化。
  init,

  /// Read. / 读取。
  read,

  /// Write or renew. / 写入或续期。
  write,

  /// Remove. / 删除。
  remove,

  /// Enumerate storage keys. / 枚举存储键。
  keys,

  /// Clear the backend. / 清空后端。
  clear,
}

/// Immutable routing/logging context for one primitive call.
/// 单次原语调用的不可变路由/日志上下文。
/// Example / 示例：`if (ctx.key?.startsWith('large/') ?? false) ...`.
class CacheContext {
  /// Captures the scope at the primitive boundary. / 在原语边界记录作用域。
  const CacheContext(
      {String? key, required this.namespace, required this.op, this.storageKey})
      : _key = key,
        _lazy = null;

  /// Defers logical-key resolution until a backend needs it.
  /// 延迟解析逻辑键，直到后端实际访问它。
  /// Example / 示例：`CacheContext.lazy(storageKey: 'n:x', namespace: 'n:',
  /// op: CacheOp.read, resolveKey: () => 'x')`.
  CacheContext.lazy(
      {required this.storageKey,
      required this.namespace,
      required this.op,
      required String? Function() resolveKey})
      : _key = null,
        _lazy = _LazyKey(resolveKey);

  /// Explicit logical key for the compatible const constructor. / 兼容 const 构造的逻辑键。
  final String? _key;

  /// Mutable memoization lives outside the immutable context. / 惰性缓存独立于不可变上下文。
  final _LazyKey? _lazy;

  /// Logical key before prefix/encoding; null for init, enumeration and clear.
  /// 加前缀/编码前的逻辑键；初始化、枚举、清空时为 null。
  String? get key => _lazy == null ? _key : _lazy.value;

  /// Actual backend key; null for operations without a key.
  /// 实际底层键；无键操作时为 null。
  final String? storageKey;

  /// Escaped namespace prefix, matching the cache's namespace getter.
  /// 转义后的命名空间前缀，与缓存的 namespace getter 一致。
  final String namespace;

  /// Actual primitive operation, which can differ from the public operation.
  /// 实际原语操作类型，可能与外层公开操作不同。
  final CacheOp op;
}

/// Resolves once, including null results. / 只解析一次，也缓存 null 结果。
class _LazyKey {
  _LazyKey(this.resolve);

  /// Captured resolver. / 捕获的解析函数。
  final String? Function() resolve;

  /// Memoized logical key. / 缓存的逻辑键。
  late final String? value = resolve();
}
