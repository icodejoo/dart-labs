export 'abr_opts.dart';
export 'ad_opts.dart';
export 'controls_opts.dart';
export 'danmaku_opts.dart';
export 'gesture_opts.dart';
export 'live_opts.dart';
export 'mini_opts.dart';
export 'playlist_opts.dart';
export 'preview_opts.dart';
export 'recovery_opts.dart';
export 'report_opts.dart';
export 'keep_alive_opts.dart';
export 'stt_opts.dart';
export 'strings.dart';
export 'cutover_opts.dart';
export 'theme.dart';
export 'timeouts.dart';

import 'abr_opts.dart';
import 'ad_opts.dart';
import 'controls_opts.dart';
import 'danmaku_opts.dart';
import 'gesture_opts.dart';
import 'live_opts.dart';
import 'mini_opts.dart';
import 'playlist_opts.dart';
import 'preview_opts.dart';
import 'recovery_opts.dart';
import 'report_opts.dart';
import 'keep_alive_opts.dart';
import 'stt_opts.dart';
import 'strings.dart';
import 'cutover_opts.dart';
import 'theme.dart';

/// Top-level, immutable options bundle for a mova player.
///
/// Groups every configurable aspect (preview, gestures, ABR, control bar,
/// live behaviour, copy, theme) into one object so apps can construct and
/// pass a single [MovaOpts] instance, and so [copyWith] can replace one
/// section without disturbing the others.
///
/// mova 播放器的顶层不可变配置集合。
///
/// 把所有可配置项（预览、手势、ABR、控制条、直播行为、文案、主题）归入一个
/// 对象，应用只需构造并传入一个 [MovaOpts] 实例；[copyWith] 可只替换其中
/// 一节而不影响其他节。
class MovaOpts {
  /// Scrub-preview (thumbnail) options.
  ///
  /// 拖动预览（缩略图）配置。
  final MovaPreviewOpts preview;

  /// Live-playback options.
  ///
  /// 直播播放配置。
  final MovaLiveOpts live;

  /// Gesture options.
  ///
  /// 手势配置。
  /// 过渡公告：计划下个版本弃用样式入口，改用 `MovaPlayerStyle`。
  /// 本版本仍是最低优先级回落值；弹幕开关与条目继续保留。
  final MovaGestureOpts gesture;

  /// Adaptive-bitrate options.
  ///
  /// 自适应码率配置。
  final MovaAbrOpts abr;

  /// Control-bar behaviour options.
  ///
  /// 控制条行为配置。
  /// 过渡公告：计划下个版本弃用样式入口，改用 `MovaPlayerStyle`。
  /// 本版本仍是最低优先级回落值；弹幕开关与条目继续保留。
  final MovaCtrlsOpts controls;

  /// Scrolling-danmaku overlay options.
  ///
  /// 滚动弹幕叠加层配置。
  /// 过渡公告：计划下个版本弃用样式入口，改用 `MovaPlayerStyle`。
  /// 本版本仍是最低优先级回落值；弹幕开关与条目继续保留。
  final MovaDanmakuOpts danmaku;

  /// Speech-to-text subtitle options.
  ///
  /// 语音转字幕配置。
  final MovaSttOpts stt;

  /// Sequential playlist + "next up" card options.
  ///
  /// 顺序播放列表 + "下一集"卡片配置。
  final MovaPlaylistOpts playlist;

  /// Pre/mid/post-roll ad options.
  ///
  /// 前/中/后贴片广告配置。
  final MovaAdOpts ads;

  /// Externalised UI copy.
  ///
  /// 外置 UI 文案。
  /// 过渡公告：计划下个版本弃用样式入口，改用 `MovaPlayerStyle`。
  /// 本版本仍是最低优先级回落值；弹幕开关与条目继续保留。
  final MovaStrs strings;

  /// Externalised visual theme.
  ///
  /// 外置视觉主题。
  /// 过渡公告：计划下个版本弃用样式入口，改用 `MovaPlayerStyle`。
  /// 本版本仍是最低优先级回落值；弹幕开关与条目继续保留。
  final MovaTheme theme;

  /// Seamless player cutover options.
  ///
  /// 无缝播放器切换配置。
  final MovaCutoverOpts cutover;

  /// In-app mini window options.
  ///
  /// App 内小窗配置。
  final MovaMiniOpts mini;

  /// Telemetry / QoE reporting options.
  ///
  /// 埋点 / QoE 上报配置。
  final MovaReportOpts report;

  /// Start-up/stall timeouts and recovery; off by default.
  ///
  /// 起播/卡顿超时与恢复；默认关闭。
  final MovaRecoveryOpts recovery;

  /// KeepAlive tuning (hidden-picture hold); only takes effect once something
  /// calls `IMovaKeepAlive.setKeepAlive`.
  ///
  /// 待机调参（画面被隐藏时的保持）；只有当有人调用 `IMovaKeepAlive.setKeepAlive` 时才生效。
  final MovaKeepAliveOpts keepAlive;

  /// Creates an options bundle; every section defaults to its own defaults.
  ///
  /// 创建配置集合；每一节均使用其自身默认值。
  const MovaOpts({
    this.preview = const MovaPreviewOpts(),
    this.live = const MovaLiveOpts(),
    this.gesture = const MovaGestureOpts(),
    this.abr = const MovaAbrOpts(),
    this.controls = const MovaCtrlsOpts(),
    this.danmaku = const MovaDanmakuOpts(),
    this.stt = const MovaSttOpts(),
    this.playlist = const MovaPlaylistOpts(),
    this.ads = const MovaAdOpts(),
    this.strings = const MovaStrs(),
    this.theme = const MovaTheme(),
    this.cutover = const MovaCutoverOpts(),
    this.mini = const MovaMiniOpts(),
    this.report = const MovaReportOpts(),
    this.recovery = const MovaRecoveryOpts(),
    this.keepAlive = const MovaKeepAliveOpts(),
  });

  /// Returns a copy with the given sections replaced; omitted sections keep
  /// their current value.
  ///
  /// 返回一份替换了指定节的拷贝；未指定的节保持当前值。
  ///
  /// - [preview]: replacement preview options / 替换用的预览配置
  /// - [live]: replacement live options / 替换用的直播配置
  /// - [gesture]: replacement gesture options / 替换用的手势配置
  /// - [abr]: replacement ABR options / 替换用的 ABR 配置
  /// - [controls]: replacement controls options / 替换用的控制条配置
  /// - [danmaku]: replacement danmaku options / 替换用的弹幕配置
  /// - [stt]: replacement STT options / 替换用的 STT 配置
  /// - [playlist]: replacement playlist options / 替换用的播放列表配置
  /// - [ads]: replacement ad options / 替换用的广告配置
  /// - [strings]: replacement strings / 替换用的文案
  /// - [theme]: replacement theme / 替换用的主题
  /// - [cutover]: replacement cutover options / 替换用的切换配置
  /// - [mini]: replacement mini-window options / 替换用的小窗配置
  /// - [report]: replacement telemetry options / 替换用的埋点配置
  /// - [recovery]: replacement recovery options / 替换用的恢复配置
  /// - [keepAlive]: replacement keepAlive options / 替换用的待机配置
  ///
  /// Returns the new [MovaOpts] instance / 返回新的 [MovaOpts] 实例。
  MovaOpts copyWith({
    MovaPreviewOpts? preview,
    MovaLiveOpts? live,
    MovaGestureOpts? gesture,
    MovaAbrOpts? abr,
    MovaCtrlsOpts? controls,
    MovaDanmakuOpts? danmaku,
    MovaSttOpts? stt,
    MovaPlaylistOpts? playlist,
    MovaAdOpts? ads,
    MovaStrs? strings,
    MovaTheme? theme,
    MovaCutoverOpts? cutover,
    MovaMiniOpts? mini,
    MovaReportOpts? report,
    MovaRecoveryOpts? recovery,
    MovaKeepAliveOpts? keepAlive,
  }) {
    return MovaOpts(
      preview: preview ?? this.preview,
      live: live ?? this.live,
      gesture: gesture ?? this.gesture,
      abr: abr ?? this.abr,
      controls: controls ?? this.controls,
      danmaku: danmaku ?? this.danmaku,
      stt: stt ?? this.stt,
      playlist: playlist ?? this.playlist,
      ads: ads ?? this.ads,
      strings: strings ?? this.strings,
      theme: theme ?? this.theme,
      cutover: cutover ?? this.cutover,
      mini: mini ?? this.mini,
      report: report ?? this.report,
      recovery: recovery ?? this.recovery,
      keepAlive: keepAlive ?? this.keepAlive,
    );
  }

  /// 比较本配置与 other 中播放器实际读取的构造节，返回是否等价。
  /// ads、playlist、mini 由宿主消费；五个样式节由视图查找，不参与播放器重建。
  /// 本方法不会更新播放器 options 快照。示例：`old.movaSectionsEqual(next)`。
  bool movaSectionsEqual(MovaOpts other) =>
      preview == other.preview &&
      live == other.live &&
      abr == other.abr &&
      stt == other.stt &&
      cutover == other.cutover &&
      report == other.report &&
      recovery == other.recovery &&
      keepAlive == other.keepAlive;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MovaOpts &&
          runtimeType == other.runtimeType &&
          preview == other.preview &&
          live == other.live &&
          gesture == other.gesture &&
          abr == other.abr &&
          controls == other.controls &&
          danmaku == other.danmaku &&
          stt == other.stt &&
          playlist == other.playlist &&
          ads == other.ads &&
          strings == other.strings &&
          theme == other.theme &&
          cutover == other.cutover &&
          mini == other.mini &&
          report == other.report &&
          recovery == other.recovery &&
          keepAlive == other.keepAlive;

  @override
  int get hashCode => Object.hash(
    preview,
    live,
    gesture,
    abr,
    controls,
    danmaku,
    stt,
    playlist,
    ads,
    strings,
    Object.hash(theme, cutover, mini, report, recovery, keepAlive),
  );
}
