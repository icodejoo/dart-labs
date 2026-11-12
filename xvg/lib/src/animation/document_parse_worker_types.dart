/// Infrastructure failure categories, separate from parse errors.
/// 基础设施失败分类，与文档解析错误分开。
enum DocumentParseWorkerFailureKind {
  /// Native loading or self-check failed. / 原生加载或自检失败。
  initialization,

  /// The isolate could not be spawned. / isolate 无法启动。
  spawn,

  /// A running or starting isolate died unexpectedly. / 运行或启动中的 isolate 意外退出。
  unexpectedExit,

  /// The owner explicitly stopped the worker. / 持有者主动停止 worker。
  disposed,
}

/// Unavailable worker infrastructure; XML/parser exceptions stay unwrapped.
/// worker 基础设施不可用；XML 或解析器异常不使用此包装。
class DocumentParseWorkerUnavailable implements Exception {
  /// Retains the cause and lifecycle category. / 保留原因及生命周期分类。
  const DocumentParseWorkerUnavailable(this.cause, {required this.kind});

  /// Original infrastructure error. / 原始基础设施错误。
  final Object cause;

  /// Failure phase used for retry policy. / 决定重试策略的失败阶段。
  final DocumentParseWorkerFailureKind kind;

  /// Startup failures cool down; isolated crashes allow an immediate rebuild.
  /// 启动失败进入冷却；单次崩溃不代表环境不可用，允许立即重建。
  bool get shouldCooldown =>
      kind == DocumentParseWorkerFailureKind.initialization ||
      kind == DocumentParseWorkerFailureKind.spawn;

  @override
  String toString() => 'DocumentParseWorkerUnavailable(${kind.name}): $cause';
}

/// Explicitly identifies a root-only parser failure. / 明确标识仅可在主 isolate 解析的失败。
class RootIsolateParseError implements Exception {
  /// Retains the original UI failure. / 保留原始 UI 错误。
  const RootIsolateParseError(this.cause);

  /// Original engine failure. / 原始引擎错误。
  final Object cause;
}
