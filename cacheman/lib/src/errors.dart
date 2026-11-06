/// Structured onError failure; [cause] retains the original exception.
/// 结构化 onError 错误；[cause] 保留原始异常。
/// Breaking: replace `error is FormatException` with
/// `error is CorruptEntryError && error.cause is FormatException`.
/// 破坏性变更：原 `error is FormatException` 应改为
/// `error is CorruptEntryError && error.cause is FormatException`。
/// Example / 示例：`if (error is WriteError) log(error.cause);`.
sealed class CachemanError implements Exception {
  /// Captures the actual storage key, original failure and optional trace.
  /// 记录实际存储键、原始异常及可选堆栈。
  const CachemanError(this.key, this.cause, [this.stackTrace]);

  /// Actual storage key; `*` for a whole-backend operation.
  /// 实际存储键；整库操作使用 `*`。
  final String key;

  /// Original exception, preserving identity. / 保持身份的原始异常。
  final Object cause;

  /// Original stack when available. / 可用时保留原始堆栈。
  final StackTrace? stackTrace;

  @override
  String toString() => '$runtimeType(key: "$key", cause: $cause)';
}

/// Deterministic adapter/serialization/value-codec failure; never retried.
/// 确定性的适配器/序列化/值编码失败，从不重试。
final class SerializeError extends CachemanError {
  /// Example / 示例：`SerializeError(key, cause, trace)`.
  /// Records an encoding failure. / 记录编码失败。
  const SerializeError(super.key, super.cause, [super.stackTrace]);
}

/// Backend write failed after the configured retry policy.
/// 底层写入在配置的重试策略执行后仍失败。
final class WriteError extends CachemanError {
  /// Records final write failure. / 记录最终写入失败。
  /// Example / 示例：`WriteError(key, cause, trace)`.
  const WriteError(super.key, super.cause, [super.stackTrace]);
}

/// Unreadable envelope; [dropped] confirms removal before reporting.
/// 不可解码信封；[dropped] 表示上报前是否已删除。
final class CorruptEntryError extends CachemanError {
  /// Records removal status. / 记录删除状态。
  /// Example / 示例：`CorruptEntryError(key, cause, dropped: true)`.
  const CorruptEntryError(String key, Object cause,
      {required this.dropped, StackTrace? stackTrace})
      : super(key, cause, stackTrace);

  /// Whether the unreadable entry was removed. / 不可读条目是否已删除。
  final bool dropped;
}

/// Value or adapter output does not match the requested type; entry is retained.
/// 值或适配器输出不匹配请求类型；保留条目。
final class TypeMismatchError extends CachemanError {
  /// Records expected/actual types and the original conversion failure.
  /// 记录期望/实际类型及原始转换异常。
  /// Example / 示例：`TypeMismatchError(key, cause, expected: int, actual: String)`.
  const TypeMismatchError(String key, Object cause,
      {required this.expected, required this.actual, StackTrace? stackTrace})
      : super(key, cause, stackTrace);

  /// Requested type. / 请求的类型。
  final Type expected;

  /// Stored value type before adaptation. / 适配前的存储值类型。
  final Type actual;
}

/// Background persistence failed; synchronous force never retries it.
/// 后台落盘失败；同步 force 从不重试此错误。
final class FlushError extends CachemanError {
  /// Records a flush failure. / 记录落盘失败。
  /// Example / 示例：`FlushError(key, cause, trace)`.
  const FlushError(super.key, super.cause, [super.stackTrace]);
}

/// A watch callback or its backend/key lookup failed; distinct from flush errors.
/// watch 回调或其后端/键读取失败；与落盘错误分开。
final class WatchError extends CachemanError {
  /// Records a watch dispatch failure. / 记录监听分发失败。
  /// Example / 示例：`WatchError(key, cause, trace)`.
  const WatchError(super.key, super.cause, [super.stackTrace]);
}
