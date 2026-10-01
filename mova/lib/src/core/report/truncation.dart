/// How far before `MovaDone` an ffmpeg-prefixed error log still counts as the
/// cause of a live stream's EOF.
///
/// EOF 之前多久内的 ffmpeg 错误日志仍视为直播流 EOF 的成因。
const movaTruncationLogWindow = Duration(seconds: 5);

/// The stable error code reported when a session is judged truncated.
///
/// 会话被判定为被截断时上报的稳定错误码。
const movaTruncatedCode = 'truncated';

/// Judges whether an EOF-ended session was really a silently cut-off stream
/// (server FIN / network drop that ffmpeg reports as plain EOF). Pure.
///
/// 判定一次以 EOF 结束的会话是否其实是被静默截断（服务端 FIN/断网被 ffmpeg 当成
/// 正常 EOF）。纯函数。
///
/// - [threshold]: completion ratio below which a VOD counts as truncated;
///   `<= 0` disables the check / 完播率阈值，低于它的点播视为截断；`<= 0` 禁用
/// - [durationMs]: media duration, `<= 0` means live/unknown / 媒体时长，`<= 0`
///   表示直播或未知
/// - [validPositionMs]: furthest position reached in this session after the
///   first frame (never a previous clip's residue) / 本会话首帧后到达的最远位置
///   （不含上一素材残留）
/// - [isLiveSource]: the source is declared live / 源声明为直播
/// - [ffmpegErrorBeforeEof]: an ffmpeg error log landed shortly before EOF /
///   EOF 前不久出现过 ffmpeg 错误日志
///
/// Returns true when the session should be recorded as truncated / 返回 true
/// 表示应记为截断。
///
/// ```dart
/// resolveTruncated(threshold: 0.9, durationMs: 100000, validPositionMs: 40000,
///     isLiveSource: false, ffmpegErrorBeforeEof: false); // true
/// ```
bool resolveTruncated({
  required double threshold,
  required int durationMs,
  required int validPositionMs,
  required bool isLiveSource,
  required bool ffmpegErrorBeforeEof,
}) {
  if (threshold <= 0) return false;
  if (isLiveSource || durationMs <= 0) return ffmpegErrorBeforeEof;
  return validPositionMs / durationMs < threshold;
}
