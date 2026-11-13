import '../report/stats_probe.dart';

/// 带加载尝试身份的文件结束通知。
typedef MovaAttemptEnd = ({int attempt, MovaEndFileReason reason});

/// 包内可选事件能力，不扩展公开内核和统计端口。
abstract interface class IMovaAttemptEventKernel {
  /// 暂存尝试编号；实现须在实际加载前同步排空旧队列并绑定编号。
  void prepareAttempt(int attempt);

  /// 带尝试编号的文件结束流。
  Stream<MovaAttemptEnd> get attemptEnds;

  /// END_FILE 泵当前是否可用，与 RESTART 开关无关。
  bool get endFileAvailable;
}
