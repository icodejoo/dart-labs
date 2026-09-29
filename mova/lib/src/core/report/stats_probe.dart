/// One error-level log line from the kernel, with the subsystem prefix mpv
/// itself attaches (media_kit's `error` stream throws this away).
///
/// 内核的一条 error 级日志行，带有 mpv 自己附加的子系统 prefix（media_kit 的
/// `error` 流会把它丢弃）。
class MovaLogLine {
  /// mpv's own subsystem name, e.g. `vd`/`ad`/`stream`/`file`/`ffmpeg`/`cplayer`.
  ///
  /// mpv 自己的子系统名称，如 `vd`/`ad`/`stream`/`file`/`ffmpeg`/`cplayer`。
  final String prefix;

  /// mpv's log level for this line (mova only forwards `error`).
  ///
  /// 该行日志的 mpv 级别（mova 只转发 `error`）。
  final String level;

  /// The log message text.
  ///
  /// 日志正文文本。
  final String text;

  /// Creates a log line.
  ///
  /// 创建一条日志行。
  const MovaLogLine({required this.prefix, required this.level, required this.text});
}

/// A single sample of libmpv's playback counters.
///
/// libmpv 各播放计数器的一次采样。
class MovaStatsSnapshot {
  /// Encoded video bitrate in bps (mpv `video-bitrate`, CMCD `br`).
  ///
  /// 视频编码码率（bps；mpv `video-bitrate`，对应 CMCD `br`）。
  final int? videoBps;

  /// Measured network throughput in bytes/s over a 1s window
  /// (mpv `cache-speed`, CMCD `mtp`).
  ///
  /// 1 秒窗口内的实测网络吞吐（字节/秒；mpv `cache-speed`，对应 CMCD `mtp`）。
  final int? inputBps;

  /// Frames dropped by the video output (mpv `frame-drop-count`).
  ///
  /// 视频输出侧丢帧数（mpv `frame-drop-count`）。
  final int? voDrops;

  /// Frames dropped by the decoder (mpv `decoder-frame-drop-count`).
  ///
  /// 解码器侧丢帧数（mpv `decoder-frame-drop-count`）。
  final int? decoderDrops;

  /// Active hardware decoder, or `no` for software (mpv `hwdec-current`).
  ///
  /// 当前生效的硬解方式，软解时为 `no`（mpv `hwdec-current`）。
  final String? hwdec;

  /// Whether the stream is most likely played over the network
  /// (mpv `demuxer-via-network`).
  ///
  /// 该流是否很可能走网络播放（mpv `demuxer-via-network`）。
  final bool? viaNetwork;

  /// Container format name (mpv `file-format`).
  ///
  /// 容器格式名（mpv `file-format`）。
  final String? fileFormat;

  /// Creates a stats snapshot; every field is independently optional since
  /// each underlying mpv property may be unavailable on its own.
  ///
  /// 创建一次统计快照；每个字段都各自可选，因为对应的 mpv 属性可能各自不可用。
  const MovaStatsSnapshot({
    this.videoBps,
    this.inputBps,
    this.voDrops,
    this.decoderDrops,
    this.hwdec,
    this.viaNetwork,
    this.fileFormat,
  });
}

/// mpv's own end-of-file reasons (`mpv_end_file_reason`), reachable via
/// media_kit master's `observeEvent(MPV_EVENT_END_FILE)`. `eof` is
/// intentionally absent: media_kit forces `--keep-open=yes`, under which mpv
/// never truly ends the file on a natural EOF — that case stays covered by
/// `MovaDone`/`completed`, not this enum. See
/// `doc/plans/2026-09-29-telemetry-enhancement.md` §D3's 2026-09-29 update.
///
/// mpv 自己的文件结束原因（`mpv_end_file_reason`），经 media_kit master 新增的
/// `observeEvent(MPV_EVENT_END_FILE)` 可达。刻意不包含 `eof`：media_kit 强制
/// `--keep-open=yes`，该模式下 mpv 到自然 EOF 根本不会真正结束文件——这种情形
/// 仍由 `MovaDone`/`completed` 覆盖，不归这个枚举管。详见
/// `doc/plans/2026-09-29-telemetry-enhancement.md` §D3 的 2026-09-29 更新。
enum MovaEndFileReason {
  /// Playback was stopped by an external action (mpv `STOP`).
  ///
  /// 播放被外部动作停止（mpv `STOP`）。
  stop,

  /// Playback was stopped by the quit command or player shutdown (mpv `QUIT`).
  ///
  /// 播放被 quit 命令或播放器关闭停止（mpv `QUIT`）。
  quit,

  /// A fatal error aborted playback (mpv `ERROR`).
  ///
  /// 致命错误终止了播放（mpv `ERROR`）。
  error,

  /// The entry was a playlist/redirect, not real media (mpv `REDIRECT`);
  /// mova doesn't use mpv's own playlist so this should not occur in
  /// practice, kept only for completeness with the native enum.
  ///
  /// 该条目是播放列表/重定向而非真实媒体（mpv `REDIRECT`）；mova 不使用 mpv
  /// 自己的播放列表，实践中不应出现，保留只是为了与原生枚举对齐完整性。
  redirect,
}

/// Optional kernel capability exposing libmpv's own statistics. A kernel that
/// does not implement it simply degrades the QoE layer — never an error.
///
/// 可选的内核能力，暴露 libmpv 自己的统计量。未实现它的内核只会让 QoE 层降级，
/// 绝不构成错误。
abstract class MovaStatsProbe {
  /// Fires once per `MPV_EVENT_PLAYBACK_RESTART` — libmpv's own signal that
  /// "playback was reinitialized, usually at start of playback and after
  /// seeking". This is the precise, native TTFF landing signal (2026-09-29
  /// update to §D1); kernels/platforms where subscribing to it failed
  /// silently degrade to an empty stream, and the QoE layer falls back to
  /// the `buffering`-edge heuristic.
  ///
  /// 每次 `MPV_EVENT_PLAYBACK_RESTART` 触发一次——libmpv 自己的信号，语义是
  /// "播放被重新初始化，通常发生在起播和 seek 完成时"。这是精确的原生 TTFF
  /// 落地信号（§D1 的 2026-09-29 更新）；订阅失败的内核/平台会静默降级为空流，
  /// QoE 层退回 `buffering` 边沿的启发式判定。
  Stream<void> get playbackRestarts;

  /// Fires once per `MPV_EVENT_END_FILE`, carrying mpv's own termination
  /// reason. Lets the session-end state machine read the reason directly
  /// instead of inferring it from `stop()`/`dispose()`/source-change timing
  /// (2026-09-29 update to §D3). Empty stream when unavailable.
  ///
  /// 每次 `MPV_EVENT_END_FILE` 触发一次，带上 mpv 自己的终止原因。让会话结束
  /// 状态机能直接读原因，而不必靠 `stop()`/`dispose()`/换源的时序去推断
  /// （§D3 的 2026-09-29 更新）。不可用时为空流。
  Stream<MovaEndFileReason> get endFiles;
  /// True exactly while playback is stopped waiting for the cache — mpv's
  /// `paused-for-cache`. This is the *real* rebuffer signal; the kernel's
  /// `buffering` stream is media_kit's merge of `core-idle` and
  /// `paused-for-cache` and also fires on pause/seek/startup.
  ///
  /// 恰在"播放因等待缓存而停住"期间为 true——即 mpv 的 `paused-for-cache`。
  /// 这才是真正的卡顿信号；内核的 `buffering` 流是 media_kit 把 `core-idle` 与
  /// `paused-for-cache` 合并后的产物，暂停/seek/起播时也会触发。
  Stream<bool> get stalling;

  /// mpv's error-level log lines, with the subsystem prefix the kernel's
  /// `error` stream throws away.
  ///
  /// mpv 的 error 级日志行，带上内核 `error` 流丢掉的那个子系统 prefix。
  Stream<MovaLogLine> get logs;

  /// One-shot sample of libmpv's counters; `null` when unavailable.
  ///
  /// 对 libmpv 各计数器取一次样；取不到时返回 `null`。
  Future<MovaStatsSnapshot?> sample();
}
