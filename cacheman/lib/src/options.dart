import 'entity.dart';
import 'interface.dart';

/// Per-call `write` options. No method accepts it — pass `ttl`/`expireAt` as
/// named arguments to `write`/`writeAll` instead.
///
/// 单次 `write` 的选项载体。没有任何方法接受它——请直接把 `ttl`/`expireAt`
/// 当命名参数传给 `write`/`writeAll`。
@Deprecated('No method accepts it; pass ttl/expireAt to write()/writeAll() directly. Removed in the next breaking release.')
class CacheOptions {
  const CacheOptions({this.ttl, this.expireAt});

  /// Time-to-live in ms (relative). Sets `expireAt = now + ttl`. An invalid
  /// value (`<= 0` or non-finite) is warned and ignored — the value still
  /// persists, just with no expiry.
  ///
  /// 存活时间（毫秒，相对）。设置 `expireAt = now + ttl`。非法值（`<=0` 或
  /// 非有限数）会警告并忽略——值照样写入，只是不带过期。
  final int? ttl;

  /// Absolute expiry: a `DateTime`, or ms-since-epoch. If in the past (and
  /// not renewable via `sliding` + `ttl`), the write is skipped with a
  /// warning.
  ///
  /// 绝对过期时间：`DateTime`，或毫秒时间戳。如果已经过去（且无法靠
  /// `sliding` + `ttl` 从现在续期），整次写入会被跳过并警告。
  final Object? expireAt;
}

/// Instance-level options for [Cacheman].
///
/// [Cacheman] 的实例级配置。
class CachemanOptions {
  const CachemanOptions({
    String Function(CacheEntity)? serialize,
    CacheEntity Function(String)? deserialize,
    this.codeable = false,
    this.codec,
    this.keyCodec,
    this.sliding = false,
    this.namespace,
    this.raw = false,
    this.force = true,
    this.readonly = false,
    this.enckey = false,
    this.onError,
  })  : serialize = serialize ?? defaultSerialize,
        deserialize = deserialize ?? defaultDeserialize;

  /// Custom entity -> string serializer, defaults to `jsonEncode`.
  ///
  /// 自定义 entity -> 字符串序列化，默认 `jsonEncode`。
  final String Function(CacheEntity) serialize;

  /// Custom string -> entity deserializer, must pair with [serialize].
  ///
  /// 自定义字符串 -> entity 反序列化，须与 [serialize] 配对。
  final CacheEntity Function(String) deserialize;

  /// Whether to invoke [codec]. Lets you toggle encoding per environment
  /// (dev/prod) without removing the codec itself.
  ///
  /// 是否调用 [codec]。可以按环境（开发/生产）开关，而不用整个拿掉 codec。
  final bool codeable;

  /// Encode/decode the serialized string. Takes effect on values only when
  /// [codeable] is `true`. No implementation ships with this package.
  ///
  /// 对序列化后的字符串做编解码。只有 [codeable] 为 `true` 时才对值生效。
  /// 本包不内置任何实现。
  final Codec? codec;

  /// Codec used only for key obfuscation ([enckey]). Must be **deterministic**
  /// (same input → same output), unlike a value codec that may add a random
  /// nonce. Falls back to [codec] when `null`.
  ///
  /// 只用于键混淆（[enckey]）的 codec，必须是**确定性**的（同输入同输出），
  /// 不像值加密可能带随机 nonce。为 `null` 时回退到 [codec]。
  final Codec? keyCodec;

  /// Sliding expiry: renew by the original `ttl` on each read hit (good for
  /// sessions/auth). The write-back is skipped while more than 90% of the
  /// ttl remains, so hot reads don't amplify writes.
  ///
  /// 滑动过期：每次读命中后按原始 `ttl` 续期（适合登录态/会话类数据）。剩余
  /// 寿命超过 90% ttl 时跳过回写，避免高频读放大写次数。
  final bool sliding;

  /// Key prefix (`namespace:key`) to isolate apps/modules sharing the same
  /// underlying container.
  ///
  /// 键前缀（`namespace:key`），隔离共用同一底层 container 的不同应用/模块。
  final String? namespace;

  /// Store the raw value directly, skipping the entity envelope (no
  /// ttl/codec). The value must be a [String] — anything else is warned and
  /// the write is skipped (mirrors a fix in the sibling `@codejoo/storage` TS
  /// project).
  ///
  /// 直接存裸值，跳过 entity 信封（不带 ttl/codec）。值必须是 [String]——
  /// 其它类型会警告并跳过写入（对齐姊妹 TS 项目 `@codejoo/storage` 修过的
  /// 一个坑）。
  final bool raw;

  /// On a write exception, purge expired entries and retry the write once;
  /// otherwise log and give up. Only triggers for a *synchronous* failure
  /// (e.g. a custom [serialize]/codec throwing). Real disk-flush failures are
  /// asynchronous, never retried, and with get_storage 2.1.1 don't reach
  /// [onError] at all (its write Future can't carry them).
  ///
  /// 写入抛异常时，清理过期条目后重试一次；否则记录日志并放弃。只对**同步**
  /// 失败（比如自定义 [serialize]/codec 抛错）触发。真正的落盘失败是异步的、
  /// 从不重试，而且 get_storage 2.1.1 下根本到不了 [onError]（它的 write
  /// Future 带不出错误）。
  final bool force;

  /// Write-once: only write when the key is empty (absent/expired);
  /// otherwise discard the write.
  ///
  /// 只写一次：仅当键为空（不存在/已过期）时才写入，否则丢弃本次写入。
  final bool readonly;

  /// Also obfuscate the key: when enabled with a [keyCodec] (or [codec]), the
  /// storage key is deterministically run through it. Requires one of them,
  /// else it warns and degrades to plaintext keys.
  ///
  /// 也对键做混淆：提供了 [keyCodec]（或 [codec]）时，存储键会经它做确定性
  /// 变换。二者至少要有一个，否则警告并降级为明文键。
  final bool enckey;

  /// Write-failure callback. Guaranteed for synchronous failures only.
  ///
  /// 写入失败回调。只保证同步失败会触发。
  final CachemanOnError? onError;
}
