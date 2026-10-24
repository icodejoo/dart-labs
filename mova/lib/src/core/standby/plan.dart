import '../kernel/standby_kernel.dart';
import '../model/source.dart';
import '../options/standby_config.dart';
import 'standby.dart';

/// Demuxers treated as segmented (HLS/DASH) for `MovaStandbyConfig.allowHls`.
/// mpv's `file-format` values — to be confirmed on device.
///
/// 在 `MovaStandbyConfig.allowHls` 里视为分片流（HLS/DASH）的 demuxer。取自 mpv 的
/// `file-format`——实际取值待真机确认。
const Set<String> movaSegmentedFormats = {'hls', 'dash'};

/// What `setStandby(true)` should do.
///
/// 进入待机该做什么。
enum MovaStandbyEntryKind {
  /// Hold the stream.
  ///
  /// 待机维持流。
  hold,

  /// Pause instead.
  ///
  /// 改为暂停。
  fallback,

  /// Do nothing.
  ///
  /// 什么都不做。
  skip,
}

/// One entry decision.
///
/// 一次进入判定。
class MovaStandbyEntry {
  /// Hold with [mode].
  ///
  /// 以 [mode] 待机。
  const MovaStandbyEntry.hold(MovaStandbyMode this.mode)
      : kind = MovaStandbyEntryKind.hold,
        reason = MovaStandbyReason.requested;

  /// Pause for [reason].
  ///
  /// 因 [reason] 改为暂停。
  const MovaStandbyEntry.fallback(this.reason)
      : kind = MovaStandbyEntryKind.fallback,
        mode = null;

  /// Do nothing for [reason].
  ///
  /// 因 [reason] 什么都不做。
  const MovaStandbyEntry.skip(this.reason)
      : kind = MovaStandbyEntryKind.skip,
        mode = null;

  /// The decision kind.
  ///
  /// 决策类别。
  final MovaStandbyEntryKind kind;

  /// The hold mode, set only for [MovaStandbyEntryKind.hold].
  ///
  /// 待机组合，仅 [MovaStandbyEntryKind.hold] 时有值。
  final MovaStandbyMode? mode;

  /// Why.
  ///
  /// 原因。
  final MovaStandbyReason reason;
}

/// Decides how to enter standby. Pure; the order of checks is the contract.
///
/// 判定如何进入待机。纯函数；检查顺序即契约。
///
/// - [phase]: the current phase / 当前阶段
/// - [intent]: the engine's play intent, not the kernel's playing flag / 引擎的播放意图，不是内核回报的播放标志
/// - [exempt]: shown in PiP or the mini window / 画面在画中画或小窗里
/// - [type]: the stream type / 流类型
/// - [recovering]: a recovery retry is pending / recovery 有待执行的重试
/// - [kernelCapable]: the kernel implements the standby capability / 内核具备待机能力
/// - [media]: facts about the media, null when unreadable / 媒体事实，读不到为 null
/// - [config]: the tuning / 调参
///
/// Returns the decision / 返回决策。
MovaStandbyEntry decideStandbyEntry({
  required MovaStandbyPhase phase,
  required bool intent,
  required bool exempt,
  required MovaStreamType type,
  required bool recovering,
  required bool kernelCapable,
  required MovaStandbyMedia? media,
  required MovaStandbyConfig config,
}) {
  if (phase == MovaStandbyPhase.holding || phase == MovaStandbyPhase.fallback) {
    return const MovaStandbyEntry.skip(MovaStandbyReason.already);
  }
  if (exempt) return const MovaStandbyEntry.skip(MovaStandbyReason.exempt);
  if (!intent) return const MovaStandbyEntry.skip(MovaStandbyReason.notPlaying);
  if (type != MovaStreamType.live) {
    return const MovaStandbyEntry.fallback(MovaStandbyReason.vod);
  }
  if (recovering) return const MovaStandbyEntry.fallback(MovaStandbyReason.failed);
  if (!kernelCapable) {
    return const MovaStandbyEntry.fallback(MovaStandbyReason.unsupported);
  }
  final m = media;
  if (m == null || m.audio == MovaAudioPresence.unknown) {
    return const MovaStandbyEntry.fallback(MovaStandbyReason.mediaUnknown);
  }
  if (!config.allowHls) {
    final f = m.format;
    if (f == null) {
      return const MovaStandbyEntry.fallback(MovaStandbyReason.mediaUnknown);
    }
    if (movaSegmentedFormats.contains(f)) {
      return const MovaStandbyEntry.fallback(MovaStandbyReason.hls);
    }
  }
  if (m.audio == MovaAudioPresence.present) {
    return const MovaStandbyEntry.hold(MovaStandbyMode.muted);
  }
  return config.silentStreams == MovaSilentStandby.keepDecoding
      ? const MovaStandbyEntry.hold(MovaStandbyMode.decodeOnly)
      : const MovaStandbyEntry.fallback(MovaStandbyReason.silentStream);
}

/// How `setStandby(false)` brings playback back.
///
/// 唤醒如何恢复播放。
enum MovaStandbyWake {
  /// Nothing to do.
  ///
  /// 无事可做。
  none,

  /// Undo the kernel hold.
  ///
  /// 撤销内核待机。
  restore,

  /// Just mark standby over; nobody wants playback (intent false).
  ///
  /// 只把待机归位；没人想播（意图为 false）。
  settle,

  /// Plain `play()` (VOD, or a live pause shorter than the grace).
  ///
  /// 普通续播（点播，或短于宽限的直播暂停）。
  resumePlay,

  /// Back to the live edge, then play.
  ///
  /// 回直播边缘再播放。
  reloadEdge,

  /// Reopen the live source (the hold failed or the stream ended).
  ///
  /// 重开直播源（待机期间失败或结束）。
  reopen,
}

/// Decides how to wake. Pure.
///
/// 判定如何唤醒。纯函数。
///
/// - [phase]: the current phase / 当前阶段
/// - [intent]: the play intent right now / 此刻的播放意图
/// - [type]: the stream type / 流类型
/// - [cause]: why the fallback happened, null outside a fallback / 退回暂停的原因，非 fallback 时为 null
/// - [pausedFor]: how long the fallback has lasted / fallback 已持续多久
/// - [config]: the tuning / 调参
///
/// Returns the wake action / 返回唤醒动作。
MovaStandbyWake decideStandbyWake({
  required MovaStandbyPhase phase,
  required bool intent,
  required MovaStreamType type,
  required MovaStandbyReason? cause,
  required Duration pausedFor,
  required MovaStandbyConfig config,
}) {
  switch (phase) {
    case MovaStandbyPhase.off:
    case MovaStandbyPhase.resuming:
      return MovaStandbyWake.none;
    case MovaStandbyPhase.holding:
      return MovaStandbyWake.restore;
    case MovaStandbyPhase.fallback:
      if (!intent) return MovaStandbyWake.settle;
      if (type != MovaStreamType.live) return MovaStandbyWake.resumePlay;
      if (cause == MovaStandbyReason.failed || cause == MovaStandbyReason.ended) {
        return MovaStandbyWake.reopen;
      }
      if (cause == MovaStandbyReason.maxDuration || pausedFor >= config.liveResumeGrace) {
        return MovaStandbyWake.reloadEdge;
      }
      return MovaStandbyWake.resumePlay;
  }
}
