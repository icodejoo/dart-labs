/// Verdict for one playback error: whether it's fatal, and its stable code.
///
/// 一次播放错误的判定结果：是否致命、以及其对应的稳定错误码。
class MovaErrorVerdict {
  /// Whether the session should be considered terminated by this error.
  ///
  /// 该错误是否应视为终结了当前会话。
  final bool fatal;

  /// A stable, analytics-friendly code (see the mapping table in
  /// `doc/plans/2026-09-29-telemetry-enhancement.md` §D4).
  ///
  /// 一个稳定、便于分析的错误码（映射表见
  /// `doc/plans/2026-09-29-telemetry-enhancement.md` §D4）。
  final String code;

  /// Creates a verdict.
  ///
  /// 创建一个判定结果。
  const MovaErrorVerdict({required this.fatal, required this.code});
}

/// Decides whether a playback error is fatal and what stable code it carries.
///
/// 判定一次播放错误是否致命、以及它对应的稳定错误码。
abstract class MovaErrorPolicy {
  /// [subsystem] is mpv's own log prefix when known (`vd`/`ad`/`stream`/…),
  /// `null` when the error did not come from the log stream.
  /// [afterFirstFrame] says whether playback had already started.
  ///
  /// [subsystem] 为 mpv 自己的日志 prefix（已知时），错误不来自日志流时为 `null`。
  /// [afterFirstFrame] 表示首帧是否已经出来。
  MovaErrorVerdict classify(Object error, {String? subsystem, required bool afterFirstFrame});
}

/// Default policy built on mpv's log prefixes; see the table in
/// `doc/plans/2026-09-29-telemetry-enhancement.md` §D4.
///
/// 基于 mpv 日志 prefix 的默认策略；映射表见
/// `doc/plans/2026-09-29-telemetry-enhancement.md` §D4。
class MovaPrefixError implements MovaErrorPolicy {
  /// Creates the default prefix-based error policy.
  ///
  /// 创建默认的基于 prefix 的错误策略。
  const MovaPrefixError();

  @override
  MovaErrorVerdict classify(Object error, {String? subsystem, required bool afterFirstFrame}) {
    switch (subsystem) {
      case 'stream':
        return const MovaErrorVerdict(fatal: true, code: 'stream');
      case 'file':
        return const MovaErrorVerdict(fatal: true, code: 'file');
      case 'ffmpeg':
        // A network transport error: fatal before the first frame (nothing to
        // recover to yet), recoverable-looking after it (mpv may reconnect).
        //
        // 网络传输错误：首帧前致命（尚无可恢复的既有画面），首帧后视为可恢复
        // （mpv 可能会自行重连）。
        return MovaErrorVerdict(fatal: !afterFirstFrame, code: 'network');
      case 'vd':
        return const MovaErrorVerdict(fatal: false, code: 'decode.video');
      case 'ad':
        return const MovaErrorVerdict(fatal: false, code: 'decode.audio');
      case 'cplayer':
        return const MovaErrorVerdict(fatal: true, code: 'player');
      default:
        return const MovaErrorVerdict(fatal: false, code: 'unknown');
    }
  }
}
