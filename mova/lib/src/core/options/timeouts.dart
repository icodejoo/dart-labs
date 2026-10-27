/// 由 mpv 侧最长窗口派生 Dart 看门狗期限时额外加的余量，保证 mpv 总能先报自己的错。
///
/// Margin added on top of the longest mpv-side window when deriving the Dart
/// watchdog deadlines, so mpv always gets to report its own error first.
const Duration kMovaWatchdogMargin = Duration(seconds: 5);

/// 未配置时 mpv 自带的 `network-timeout`（60 秒）。
///
/// mpv's built-in `network-timeout` when none is configured.
const Duration kMpvDefaultNetworkTimeout = Duration(seconds: 60);

/// ffmpeg HTTP 重连的大致窗口（`reconnect_delay_max=7`，退避 0/1/3/7 秒）。
///
/// Rough ffmpeg HTTP reconnect window (`reconnect_delay_max=7`, backoff 0/1/3/7s).
const Duration kFfmpegReconnectWindow = Duration(seconds: 11);

/// WHEP 补丁默认的 `handshake_timeout`（10 秒）。
///
/// WHEP patch default `handshake_timeout`.
const Duration kWhepDefaultHandshake = Duration(seconds: 10);

/// WHEP 补丁默认的 `first_frame_timeout`（10 秒）。
///
/// WHEP patch default `first_frame_timeout`.
const Duration kWhepDefaultFirstFrame = Duration(seconds: 10);

/// WHEP 补丁默认的 `media_timeout`（5 秒）。
///
/// WHEP patch default `media_timeout`.
const Duration kWhepDefaultMedia = Duration(seconds: 5);

/// 统一超时配置，每次 open 前透传给 libmpv/ffmpeg；`null` 表示不动 mpv 侧默认值。超时由
/// mpv/ffmpeg 负责，失败（END_FILE error）触发重连；`MovaRecoveryConfig` 里的 Dart 看门狗
/// 只是由这些窗口派生出的兜底。按源的 `mpvOptions`/`demuxerOptions`/`whepMediaTimeout`
/// 对同一选项的显式设置优先于本配置。
///
/// Unified timeout settings, forwarded to libmpv/ffmpeg before each open;
/// `null` leaves the mpv-side default untouched. mpv/ffmpeg own the timeouts
/// and report failures (END_FILE error) that drive reconnects; the Dart
/// watchdog in `MovaRecoveryConfig` is only a fallback derived from these
/// windows. A per-source `mpvOptions` / `demuxerOptions` / `whepMediaTimeout`
/// entry for the same option wins over this config.
///
/// Example / 示例:
/// ```dart
/// const MovaOpts(recovery: MovaRecoveryConfig(
///   enabled: true,
///   timeouts: MovaTimeouts(network: Duration(seconds: 12), whepMedia: Duration(seconds: 8)),
/// ));
/// ```
class MovaTimeouts {
  /// 网络连接/读取超时，作为 mpv `network-timeout` 下发（整秒，向上取整，至少 1）；
  /// 同时约束 WHEP 的信令请求。
  ///
  /// Network connect/read timeout, sent as mpv `network-timeout` (whole
  /// seconds, rounded up, at least 1). Also bounds the WHEP signaling request.
  final Duration? network;

  /// WHEP `handshake_timeout`（ICE/DTLS），以微秒下发。
  ///
  /// WHEP `handshake_timeout`, sent in microseconds.
  final Duration? whepHandshake;

  /// WHEP `first_frame_timeout`（等首个关键帧），以微秒下发。
  ///
  /// WHEP `first_frame_timeout`, in microseconds.
  final Duration? whepFirstFrame;

  /// WHEP `media_timeout`（播放后无媒体），以微秒下发。
  ///
  /// WHEP `media_timeout`, in microseconds.
  final Duration? whepMedia;

  /// 创建配置；所有字段默认“不动 mpv 默认值”。
  ///
  /// Creates the settings; every field defaults to leaving mpv's default.
  const MovaTimeouts({this.network, this.whepHandshake, this.whepFirstFrame, this.whepMedia});

  /// [address] 是否为 `whep…` 地址。
  ///
  /// Whether [address] is a `whep…` address.
  static bool isWhep(String address) => address.toLowerCase().startsWith('whep');

  /// [address] 对应的 mpv 顶层选项（`network-timeout`）；返回新 Map。
  ///
  /// Top-level mpv options for [address]; returns a fresh map.
  ///
  /// - [address]: 即将加载的地址 / the address about to load
  Map<String, String> mpvOptionsFor(String address) {
    final n = network;
    if (n == null) return {};
    final secs = (n.inMilliseconds / 1000).ceil();
    return {'network-timeout': (secs < 1 ? 1 : secs).toString()};
  }

  /// [address] 对应的 `demuxer-lavf-o` 条目（仅 WHEP，微秒）；返回新 Map。
  ///
  /// `demuxer-lavf-o` entries for [address] (WHEP only, microseconds); fresh map.
  ///
  /// - [address]: 即将加载的地址 / the address about to load
  Map<String, String> demuxerOptionsFor(String address) {
    if (!isWhep(address)) return {};
    return {
      if (whepHandshake != null) 'handshake_timeout': whepHandshake!.inMicroseconds.toString(),
      if (whepFirstFrame != null) 'first_frame_timeout': whepFirstFrame!.inMicroseconds.toString(),
      if (whepMedia != null) 'media_timeout': whepMedia!.inMicroseconds.toString(),
    };
  }

  /// 起播尝试在 mpv 自己报错前最长可能耗时：WHEP 为 信令+握手+首帧；其余取
  /// `network-timeout` 与 ffmpeg 重连窗口中较长者。
  ///
  /// Longest time mpv itself may take before a start attempt reports an error.
  ///
  /// - [address]: 正在加载的地址 / the address being loaded
  Duration startWindowFor(String address) {
    final net = network ?? kMpvDefaultNetworkTimeout;
    if (isWhep(address)) {
      return net + (whepHandshake ?? kWhepDefaultHandshake) + (whepFirstFrame ?? kWhepDefaultFirstFrame);
    }
    return net > kFfmpegReconnectWindow ? net : kFfmpegReconnectWindow;
  }

  /// 出首帧后 mpv 自己最长可能沉默多久才报错：WHEP 为 `media_timeout`；其余同 [startWindowFor]。
  ///
  /// Longest time mpv may stay silent after the first frame before reporting an error.
  ///
  /// - [address]: 正在播放的地址 / the address being played
  Duration stallWindowFor(String address) {
    if (isWhep(address)) return whepMedia ?? kWhepDefaultMedia;
    return startWindowFor(address);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MovaTimeouts &&
          network == other.network &&
          whepHandshake == other.whepHandshake &&
          whepFirstFrame == other.whepFirstFrame &&
          whepMedia == other.whepMedia;

  @override
  int get hashCode => Object.hash(network, whepHandshake, whepFirstFrame, whepMedia);
}
