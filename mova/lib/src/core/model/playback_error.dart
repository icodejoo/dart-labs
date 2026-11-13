import '../recovery/fail.dart';
import '../report/error_policy.dart';
import '../report/stats_probe.dart';

/// 带可选内核子系统的原始错误，保留原对象便于宿主诊断。
/// 示例：`const MovaKernelError('tcp: disconnected', 'ffmpeg')`。
class MovaKernelError {
  /// 创建错误；[error] 是原对象，[subsystem] 是内核日志前缀，未知可省略。
  const MovaKernelError(this.error, [this.subsystem]);

  /// 内核报告的原始错误对象。
  final Object error;

  /// mpv 的日志子系统前缀；未知时为 null。
  final String? subsystem;
}

/// 分类一次播放错误，返回终结标志和与 QoE 一致的稳定 code。
///
/// [error] 为原始错误，[subsystem] 为可选日志前缀；[afterFirstFrame]
/// 表示当前会话已呈现首帧，仅传给共享的 code 映射，不把 QoE 结算判据当播放终结。
/// 内核日志默认非终结；已知耗尽解码器、无法识别格式、END_FILE(error)
/// 和恢复放弃才终结；open 抛出由播放器明确按终结错误上报。
/// 示例：`classifyMovaPlaybackError('tcp: reset', subsystem: 'ffmpeg', afterFirstFrame: true)`。
MovaErrorVerdict classifyMovaPlaybackError(
  Object error, {
  String? subsystem,
  required bool afterFirstFrame,
}) {
  final code = const MovaPrefixError().classify(
    error, subsystem: subsystem, afterFirstFrame: afterFirstFrame,
  ).code;
  final text = error.toString().trim();
  final fatal = error is MovaGiveUpError ||
      error == MovaEndFileReason.error ||
      text.startsWith('Failed to initialize a decoder') ||
      text == 'Failed to recognize file format.';
  return MovaErrorVerdict(fatal: fatal, code: code);
}
