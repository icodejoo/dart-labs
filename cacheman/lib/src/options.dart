import 'entity.dart';
import 'interface.dart';

/// Shared instance-level options for Cacheman and AsyncCacheman.
///
/// Cacheman 与 AsyncCacheman 共用的实例级配置。
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
    this.flushDelay,
    this.purgeOnInit = false,
  })  : serialize = serialize ?? defaultSerialize,
        deserialize = deserialize ?? defaultDeserialize;

  /// Sync Cacheman only: coalesce memory writes until the earliest deadline.
  /// Default null preserves per-event-loop flushing. Deletes still flush immediately.
  /// A crash may lose writes within this window; recommended opt-in: 200ms.
  /// 仅同步 Cacheman：合并内存写入到最早截止时间；默认 null 保持原行为。
  /// 删除仍立即排落盘，崩溃可能丢失窗口内写入，推荐显式设置 200ms。
  /// Example / 示例：`CachemanOptions(flushDelay: Duration(milliseconds: 200))`.
  final Duration? flushDelay;

  /// Sync Cacheman only: schedule expiry cleanup after initialization, without
  /// delaying completion. Raw mode ignores it. Default false.
  /// 仅同步 Cacheman：初始化后异步调度过期清理，不阻塞完成；raw 忽略，默认 false。
  /// Example / 示例：`CachemanOptions(purgeOnInit: true)`.
  final bool purgeOnInit;

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

  /// Default true: purge expired entries and retry a backend write once.
  /// Serialization/adapter/value-codec failures never purge or retry.
  /// Cacheman retries only synchronous setRaw throws; AsyncCacheman also
  /// catches awaited setRaw failures. Sync background failures are FlushError,
  /// never retried; get_storage 2.1.1 may hide real disk failures.
  /// 默认 true：底层写失败时清过期并重试一次；序列化/适配器/值编码失败不清理、不重试。
  /// Cacheman 仅重试 setRaw 同步异常；AsyncCacheman 也捕获 await setRaw 失败。
  /// 同步后台失败为 FlushError、不重试；get_storage 2.1.1 可能隐藏真实磁盘失败。
  /// Example / 示例：`CachemanOptions(force: false)`.
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

  /// Receives the storage key and a CachemanError; original exception is cause.
  /// Corrupt reads delete before reporting; type mismatches retain data.
  /// Breaking: `error is FormatException` becomes
  /// `error is CorruptEntryError && error.cause is FormatException`.
  /// 接收存储键与 CachemanError；原异常在 cause。解码失败先删再报，类型不符保留数据。
  /// 破坏性：原 FormatException 判断改为 CorruptEntryError 并检查 cause。
  /// User callback errors propagate; real disk-flush reporting is best-effort.
  /// 用户回调异常向上传播；真实磁盘失败上报为尽力而为。
  /// Example / 示例：`CachemanOptions(onError: (key, e) => print(e))`.
  final CachemanOnError? onError;
}
