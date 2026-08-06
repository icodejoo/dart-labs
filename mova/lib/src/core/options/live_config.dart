import '../state/state.dart';

/// Seek behaviour available on a live stream.
///
/// 直播流可用的进度拖动行为。
enum MovaLiveSeekMode {
  /// No seeking on the live timeline.
  ///
  /// 直播时间轴不可拖动。
  off,

  /// Seek within the server-side DVR window.
  ///
  /// 在服务端 DVR 窗口内拖动。
  dvr,

  /// Seek within a locally buffered time-shift window.
  ///
  /// 在本地缓冲的时移窗口内拖动。
  timeshift,
}

/// Builds the playback URL for a time-shifted live stream.
///
/// Servers differ wildly here (`?begin=`, `?starttime=`, path-embedded epochs,
/// signed tokens), so mova never guesses: `timeshift` mode is inert until
/// the host supplies one of these. This is DESIGN section 6.2's "时移 URL"
/// injection point.
///
/// 为时移直播流构造播放 URL。
///
/// 各家服务端差异极大（`?begin=`、`?starttime=`、把时间戳嵌进路径、带签名的
/// token 等），mova 绝不猜测：宿主不提供本回调时 `timeshift` 模式不生效。
/// 这是 DESIGN §6.2「时移 URL」的注入点。
///
/// - [uri]: the original live URI / 原始直播地址
/// - [behind]: how far behind the live edge to start / 相对直播边缘回退的时长
/// - [wallClock]: "now" as seen by the client / 客户端视角的当前时刻
///
/// Returns the URL to open / 返回要打开的地址。
typedef MovaTimeShiftBldr = String Function(
  String uri,
  Duration behind,
  DateTime wallClock,
);

/// Resolves the seekable DVR/time-shift window for the current state.
///
/// The bundled default infers the window from the kernel-reported duration,
/// which is right for HLS sliding windows but wrong for servers that advertise
/// it out-of-band. This is DESIGN section 6.2's `windowResolver` injection
/// point.
///
/// 解析当前状态下可拖动的 DVR/时移窗口。
///
/// 内置默认实现由内核报告的时长推断窗口，这对 HLS 滑动窗口是对的，但对通过
/// 带外方式声明窗口的服务端就不对。这是 DESIGN §6.2 的 `windowResolver` 注入点。
///
/// - [state]: the current player state / 当前播放器状态
///
/// Returns the seekable window length / 返回可拖动窗口长度。
typedef MovaLiveWindowSolver = Duration Function(MovaState state);

/// How "back to live" is performed.
///
/// 「回到直播」的执行方式。
enum MovaBackToLive {
  /// Seek to the end of the seekable window without reopening the source.
  ///
  /// Right for DVR streams, where the same URL already spans the window.
  ///
  /// 不重开源，直接跳到可拖动窗口末端。
  ///
  /// 适用于 DVR 流——同一个地址本身就覆盖整个窗口。
  seekEnd,

  /// Reopen the original live URL from scratch.
  ///
  /// Right for time-shift streams, whose current URL points at a past instant
  /// and can never catch up to the edge by seeking.
  ///
  /// 从头重新打开原始直播地址。
  ///
  /// 适用于时移流——其当前地址指向过去的某一时刻，靠 seek 永远追不上边缘。
  reopen,
}

/// Live-playback configuration.
///
/// 直播播放配置。
class MovaLiveConfig {
  /// Which seek mode is available for the live stream.
  ///
  /// 直播流可用的拖动模式。
  final MovaLiveSeekMode seekMode;

  /// Size of the DVR/time-shift window, when [seekMode] is not [MovaLiveSeekMode.off].
  ///
  /// DVR/时移窗口的大小（[seekMode] 非 [MovaLiveSeekMode.off] 时生效）。
  final Duration? dvrWindow;

  /// How close to the live edge counts as "at the edge" for UI purposes.
  ///
  /// 用于 UI 判断"已处于直播边缘"的接近阈值。
  final Duration edgeThreshold;

  /// Builds the time-shifted playback URL; `null` leaves
  /// [MovaLiveSeekMode.timeshift] inert (seeks are ignored).
  ///
  /// 构造时移播放地址；为 `null` 时 [MovaLiveSeekMode.timeshift] 不生效
  /// （拖动被忽略）。
  final MovaTimeShiftBldr? urlBuilder;

  /// How to return to the live edge; `null` derives it from [seekMode]
  /// (see [effectiveBackToLive]).
  ///
  /// 回到直播边缘的方式；为 `null` 时按 [seekMode] 推导（见
  /// [effectiveBackToLive]）。
  final MovaBackToLive? backToLive;

  /// Whether a buffering stall while time-shifted automatically jumps back to
  /// the live edge. Off by default — silently losing the user's chosen replay
  /// position is a surprising default, so it is opt-in.
  ///
  /// 时移状态下发生卡顿是否自动跳回直播边缘。默认关闭——悄悄丢掉用户选定的
  /// 回看位置是个意外的默认行为，因此需显式开启。
  final bool autoBackToLiveOnStall;

  /// Overrides how the seekable window is computed; `null` uses
  /// [dvrWindow] when set, otherwise the kernel-reported duration.
  ///
  /// 覆盖可拖动窗口的计算方式；为 `null` 时优先用 [dvrWindow]，否则用内核报告
  /// 的时长。
  final MovaLiveWindowSolver? windowResolver;

  /// Creates a live config; seeking off and a 10-second edge threshold by
  /// default.
  ///
  /// 创建直播配置；默认禁用拖动，边缘阈值为 10 秒。
  const MovaLiveConfig({
    this.seekMode = MovaLiveSeekMode.off,
    this.dvrWindow,
    this.edgeThreshold = const Duration(seconds: 10),
    this.urlBuilder,
    this.backToLive,
    this.autoBackToLiveOnStall = false,
    this.windowResolver,
  });

  /// The back-to-live strategy actually in effect.
  ///
  /// Returns [backToLive] when configured; otherwise derives it from
  /// [seekMode] per DESIGN section 6.2 — `timeshift` reopens, everything else
  /// seeks to the window end.
  ///
  /// 实际生效的回到直播策略。
  ///
  /// 配置了 [backToLive] 就用它；否则按 DESIGN §6.2 由 [seekMode] 推导——
  /// `timeshift` 重开源，其余一律跳到窗口末端。
  MovaBackToLive get effectiveBackToLive =>
      backToLive ??
      (seekMode == MovaLiveSeekMode.timeshift
          ? MovaBackToLive.reopen
          : MovaBackToLive.seekEnd);

  /// Returns a copy with the given fields replaced.
  ///
  /// Nullable strategy fields ([dvrWindow], [urlBuilder], [backToLive],
  /// [windowResolver]) can only be set, not cleared — clearing an injected
  /// strategy has no use case and would need a flag per field.
  ///
  /// 返回一份替换了指定字段的拷贝。
  ///
  /// 可空的策略字段（[dvrWindow]、[urlBuilder]、[backToLive]、
  /// [windowResolver]）只能设置、不能清空——清空已注入的策略没有使用场景，
  /// 且会需要给每个字段配一个标志位。
  ///
  /// - [seekMode]: replacement seek mode / 替换用的拖动模式
  /// - [dvrWindow]: replacement DVR window / 替换用的 DVR 窗口
  /// - [edgeThreshold]: replacement edge threshold / 替换用的边缘阈值
  /// - [urlBuilder]: replacement time-shift URL builder / 替换用的时移地址构造器
  /// - [backToLive]: replacement back-to-live strategy / 替换用的回直播策略
  /// - [autoBackToLiveOnStall]: replacement stall behaviour / 替换用的卡顿行为
  /// - [windowResolver]: replacement window resolver / 替换用的窗口解析器
  ///
  /// Returns the new [MovaLiveConfig] / 返回新的 [MovaLiveConfig]。
  MovaLiveConfig copyWith({
    MovaLiveSeekMode? seekMode,
    Duration? dvrWindow,
    Duration? edgeThreshold,
    MovaTimeShiftBldr? urlBuilder,
    MovaBackToLive? backToLive,
    bool? autoBackToLiveOnStall,
    MovaLiveWindowSolver? windowResolver,
  }) {
    return MovaLiveConfig(
      seekMode: seekMode ?? this.seekMode,
      dvrWindow: dvrWindow ?? this.dvrWindow,
      edgeThreshold: edgeThreshold ?? this.edgeThreshold,
      urlBuilder: urlBuilder ?? this.urlBuilder,
      backToLive: backToLive ?? this.backToLive,
      autoBackToLiveOnStall:
          autoBackToLiveOnStall ?? this.autoBackToLiveOnStall,
      windowResolver: windowResolver ?? this.windowResolver,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MovaLiveConfig &&
          runtimeType == other.runtimeType &&
          seekMode == other.seekMode &&
          dvrWindow == other.dvrWindow &&
          edgeThreshold == other.edgeThreshold &&
          urlBuilder == other.urlBuilder &&
          backToLive == other.backToLive &&
          autoBackToLiveOnStall == other.autoBackToLiveOnStall &&
          windowResolver == other.windowResolver;

  @override
  int get hashCode => Object.hash(
        seekMode,
        dvrWindow,
        edgeThreshold,
        urlBuilder,
        backToLive,
        autoBackToLiveOnStall,
        windowResolver,
      );
}
