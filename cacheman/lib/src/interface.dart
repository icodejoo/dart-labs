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

/// Write-failure callback (disk full, permission error, `force`-retry still
/// failing). When provided it replaces the default `print`-based log, so the
/// caller can observe failures (`set` returns `void`, so a failure is
/// otherwise invisible).
///
/// 写入失败回调（磁盘满、权限错误、`force` 重试仍失败）。提供时取代默认的
/// `print` 日志，让调用方能感知失败（`set` 返回 `void`，失败本不可见）。
typedef CachemanOnError = void Function(String key, Object error);
