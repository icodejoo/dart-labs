/// What keepAlive does with a stream that has no audio.
///
/// 待机如何处理没有音频的流。
enum MovaSilentKeepAlive {
  /// Keep decoding and rendering, muted: instant resume, little power saved.
  ///
  /// 继续解码与渲染并静音：恢复即时，但几乎不省电。
  keepDecoding,

  /// Pause instead, as if keepAlive were off for this stream.
  ///
  /// 改为暂停，就像这条流没开待机一样。
  pause,
}

/// Tuning for keepAlive (`MovaKeepAlive.setKeepAlive`). Nothing here
/// turns keepAlive on — it only takes effect once something calls `setKeepAlive`
/// (e.g. `MovaAutoPauseConfig(hiddenMode: MovaHiddenMode.keepAlive)`).
///
/// 待机的调参（`MovaKeepAlive.setKeepAlive`）。这里没有开关——只有当有人调用
/// `setKeepAlive`（例如 `MovaAutoPauseConfig(hiddenMode: MovaHiddenMode.keepAlive)`）时才生效。
///
/// Example / 示例:
/// ```dart
/// createMovaEngine(options: const MovaOpts(
///   keepAlive: MovaKeepAliveConfig(maxDuration: Duration(seconds: 20)),
/// ));
/// ```
class MovaKeepAliveConfig {
  /// Creates the config; every default is conservative until measured on device.
  ///
  /// 创建配置；在真机测量前每个默认值都取保守值。
  ///
  /// - [maxDuration]: longest hold before falling back to a pause, default 30s / 待机最长时长，超过转暂停，默认 30s
  /// - [silentStreams]: what to do without audio, default [MovaSilentKeepAlive.keepDecoding] / 无音频时怎么办
  /// - [allowHls]: hold HLS/DASH too, default false (they pause) / HLS/DASH 也待机，默认 false（暂停）
  /// - [resumeTimeout]: stop waiting for the first fresh frame after this, default 5s / 等新首帧的上限，默认 5s
  /// - [liveResumeGrace]: a live stream paused at least this long reconnects to the edge on wake, default 3s / 暂停至少这么久的直播唤醒时回边缘，默认 3s
  const MovaKeepAliveConfig({
    this.maxDuration = const Duration(seconds: 30),
    this.silentStreams = MovaSilentKeepAlive.keepDecoding,
    this.allowHls = false,
    this.resumeTimeout = const Duration(seconds: 5),
    this.liveResumeGrace = const Duration(seconds: 3),
  });

  /// Longest hold before falling back to a pause.
  ///
  /// 待机最长时长，超过转暂停。
  final Duration maxDuration;

  /// What to do with a stream that has no audio.
  ///
  /// 无音频的流怎么处理。
  final MovaSilentKeepAlive silentStreams;

  /// Whether HLS/DASH may be held too.
  ///
  /// HLS/DASH 是否也允许待机。
  final bool allowHls;

  /// Longest wait for the first fresh frame after waking.
  ///
  /// 唤醒后等待第一帧新画面的上限。
  final Duration resumeTimeout;

  /// A live pause at least this long reconnects to the edge on wake.
  ///
  /// 直播暂停至少这么久，唤醒时回直播边缘。
  final Duration liveResumeGrace;

  /// Debug-checks the durations; called by the engine on construction (a
  /// `Duration` comparison cannot live in a `const` initializer).
  ///
  /// debug 下检查各时长；由引擎构造时调用（`Duration` 比较不能写在 `const` 构造器的初始化列表里）。
  void assertValid() {
    assert(maxDuration > Duration.zero, 'MovaKeepAliveConfig.maxDuration must be positive');
    assert(resumeTimeout > Duration.zero, 'MovaKeepAliveConfig.resumeTimeout must be positive');
    assert(liveResumeGrace >= Duration.zero, 'MovaKeepAliveConfig.liveResumeGrace must not be negative');
  }

  /// Returns a copy with the given fields replaced.
  ///
  /// 返回替换了指定字段的拷贝。
  ///
  /// - [maxDuration]: replacement hold limit / 替换用的待机上限
  /// - [silentStreams]: replacement silent-stream rule / 替换用的无声流规则
  /// - [allowHls]: replacement HLS switch / 替换用的 HLS 开关
  /// - [resumeTimeout]: replacement resume limit / 替换用的恢复上限
  /// - [liveResumeGrace]: replacement live grace / 替换用的直播宽限
  ///
  /// Returns the new config / 返回新配置。
  MovaKeepAliveConfig copyWith({
    Duration? maxDuration,
    MovaSilentKeepAlive? silentStreams,
    bool? allowHls,
    Duration? resumeTimeout,
    Duration? liveResumeGrace,
  }) {
    return MovaKeepAliveConfig(
      maxDuration: maxDuration ?? this.maxDuration,
      silentStreams: silentStreams ?? this.silentStreams,
      allowHls: allowHls ?? this.allowHls,
      resumeTimeout: resumeTimeout ?? this.resumeTimeout,
      liveResumeGrace: liveResumeGrace ?? this.liveResumeGrace,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MovaKeepAliveConfig &&
          maxDuration == other.maxDuration &&
          silentStreams == other.silentStreams &&
          allowHls == other.allowHls &&
          resumeTimeout == other.resumeTimeout &&
          liveResumeGrace == other.liveResumeGrace;

  @override
  int get hashCode =>
      Object.hash(maxDuration, silentStreams, allowHls, resumeTimeout, liveResumeGrace);
}
