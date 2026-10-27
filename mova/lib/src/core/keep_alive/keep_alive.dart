/// Where a player is in the keepAlive lifecycle.
///
/// 播放器处于待机生命周期的哪一段。
enum MovaKeepAlivePhase {
  /// Not in keepAlive (the default).
  ///
  /// 不在待机（默认）。
  off,

  /// Holding the stream: still playing, with video and/or sound off.
  ///
  /// 正在待机：仍在播放，画面和/或声音已关。
  holding,

  /// KeepAlive was asked for but the engine paused instead (VOD, unknown media,
  /// HLS, silent stream with `pause`, kernel without the capability, or a
  /// hold that hit `maxDuration` / failed / ended).
  ///
  /// 请求了待机但引擎改为暂停（点播、媒体信息未知、HLS、配置为暂停的无声流、内核无此能力，
  /// 或待机超过 `maxDuration` / 失败 / 结束）。
  fallback,

  /// KeepAlive ended; waiting for the first fresh frame.
  ///
  /// 待机已结束，等待第一帧新画面。
  resuming,
}

/// How a held stream is kept running.
///
/// 被待机的流以何种方式维持。
enum MovaKeepAliveMode {
  /// Video decoding off, sound muted; audio keeps the clock (stream has audio).
  ///
  /// 关视频解码、静音；由音频维持时钟（流里有音频）。
  muted,

  /// Decoding and rendering go on, sound muted (stream has no audio).
  ///
  /// 继续解码与渲染、静音（流里没有音频）。
  decodeOnly,
}

/// Why the keepAlive phase changed (events), or why an entry was declined
/// (the last three are decision-only and never appear in events).
///
/// 待机阶段为何变化（事件里），或进入为何被拒（最后三个只出现在决策结果里，不会出现在事件中）。
enum MovaKeepAliveReason {
  /// KeepAlive was entered.
  ///
  /// 进入待机。
  requested,

  /// VOD is never held; paused instead.
  ///
  /// 点播不待机，改为暂停。
  vod,

  /// HLS/DASH is paused unless `allowHls` is set.
  ///
  /// HLS/DASH 默认暂停，除非设置了 `allowHls`。
  hls,

  /// A stream without audio, with `silentStreams: pause`.
  ///
  /// 无音频的流，且配置为 `silentStreams: pause`。
  silentStream,

  /// Media facts are not known yet (tracks or audio decoder not ready).
  ///
  /// 媒体信息尚不明确（轨道或音频解码器未就绪）。
  mediaUnknown,

  /// The kernel lacks the capability, or the hold failed to apply.
  ///
  /// 内核不具备该能力，或待机未能生效。
  unsupported,

  /// A hold reached `maxDuration` and fell back to a pause.
  ///
  /// 待机达到 `maxDuration`，退回暂停。
  maxDuration,

  /// A hold failed (or recovery had a retry pending); paused, reopens on wake.
  ///
  /// 待机期间失败（或 recovery 有待执行的重试）；暂停，唤醒时重开。
  failed,

  /// A live stream ended during a hold; paused, reopens on wake.
  ///
  /// 直播在待机期间结束；暂停，唤醒时重开。
  ended,

  /// The host reloaded a source while keepAlive was requested; it loads paused.
  ///
  /// 待机请求期间宿主换了源；新源以暂停态加载。
  reloaded,

  /// `setKeepAlive(false)` began waking.
  ///
  /// `setKeepAlive(false)` 开始唤醒。
  woke,

  /// Waking finished (landed or timed out).
  ///
  /// 唤醒完成（落地或超时）。
  resumed,

  /// The host called `pause()`.
  ///
  /// 宿主调用了 `pause()`。
  paused,

  /// Decision only: already holding or fallen back.
  ///
  /// 仅决策：已在待机或已退回暂停。
  already,

  /// Decision only: shown in PiP or the mini window.
  ///
  /// 仅决策：画面在画中画或小窗里。
  exempt,

  /// Decision only: nobody wants playback right now.
  ///
  /// 仅决策：此刻没人想播放。
  notPlaying,
}

/// Engines that can keep a stream warm while their picture is hidden.
/// A capability next to `MovaApi` (like `MovaCutover`); check with `is`.
///
/// 能在画面被隐藏时让流保持热态的引擎。与 `MovaApi` 并列的能力接口（同
/// `MovaCutover`）；用 `is` 判断。
abstract class MovaKeepAlive {
  /// Tells the engine its picture is hidden ([on] true) or visible again.
  ///
  /// Hidden: a playing live stream is held — still playing with video
  /// decoding off and sound muted (or, without audio, decoding on and
  /// muted) — for at most `MovaKeepAliveConfig.maxDuration`, then paused. When
  /// it cannot be held (VOD, HLS by default, unknown media, no kernel
  /// support) it is paused right away. Not playing, or shown in PiP / the
  /// mini window: nothing happens. Visible again: a held stream resumes
  /// decoding (no reconnect); a paused live stream resumes, or reconnects to
  /// the edge when it was paused long enough. Network is NOT saved while held.
  ///
  /// 告诉引擎它的画面被隐藏了（[on] 为 true）或又可见了。
  ///
  /// 隐藏：正在播放的直播流进入待机——仍在播放，但关视频解码并静音（无音频的流则继续解码并静音），
  /// 最长 `MovaKeepAliveConfig.maxDuration`，之后转为暂停。无法待机（点播、默认下的 HLS、媒体信息未知、
  /// 内核不支持）时立即暂停。没在播，或画面在画中画/小窗里：什么都不做。重新可见：待机中的流恢复解码
  /// （不重连）；暂停中的直播续播，暂停够久则重连到直播边缘。待机期间**不省流量**。
  ///
  /// - [on]: true = hidden, false = visible again / true 为隐藏，false 为重新可见
  ///
  /// Returns the phase once this call has settled (see `MovaState.keepAlivePhase`).
  ///
  /// 返回本次调用落定后的阶段（见 `MovaState.keepAlivePhase`）。
  ///
  /// Example / 示例:
  /// ```dart
  /// final api = createMovaEngine();
  /// if (api is MovaKeepAlive) {
  ///   await api.setKeepAlive(true);   // card scrolled away / 卡片滑走
  ///   await api.setKeepAlive(false);  // back on screen / 回到屏幕
  /// }
  /// ```
  Future<MovaKeepAlivePhase> setKeepAlive(bool on);
}
