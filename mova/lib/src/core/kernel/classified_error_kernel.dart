import '../model/playback_error.dart';

/// 可选的带子系统错误能力；不扩展 IMovaKernel 抽象，也不从主入口导出。
/// 播放器优先订阅此能力，避免与旧 error 流重复报告同一日志行。
abstract interface class IMovaClassifiedErrorKernel {
  /// 原始错误及其日志前缀流，返回无配对等待的逐行错误。
  /// 示例：`kernel.kernelErrors.listen((e) => print(e.subsystem))`。
  Stream<MovaKernelError> get kernelErrors;
}
