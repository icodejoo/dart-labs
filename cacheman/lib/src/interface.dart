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

/// Failure callback: exhausted writes (sync or awaited), or an unreadable entry
/// deleted by a read. Receives the storage key and original exception (a null
/// codec result uses FormatException). Replaces the default print-based log.
/// Purge/readonly probes do not report decode failures; with get_storage 2.1.1
/// real disk-flush errors (disk full, permission) never reach this callback.
///
/// 失败回调：同步/await 写入重试耗尽，或读取时删除不可解码的条目。接收实际存储键和
/// 原始异常（codec 返回 null 时使用 FormatException），取代默认 print 日志。
/// purge/readonly 探测不上报解码失败；get_storage 2.1.1 下真正的落盘错误
/// （磁盘满、权限）到不了此回调。
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
  const CacheContext({this.key, required this.namespace, required this.op});

  /// Logical key before prefix/encoding; null for init, enumeration and clear.
  /// 加前缀/编码前的逻辑键；初始化、枚举、清空时为 null。
  final String? key;

  /// Escaped namespace prefix, matching the cache's namespace getter.
  /// 转义后的命名空间前缀，与缓存的 namespace getter 一致。
  final String namespace;

  /// Actual primitive operation, which can differ from the public operation.
  /// 实际原语操作类型，可能与外层公开操作不同。
  final CacheOp op;
}
