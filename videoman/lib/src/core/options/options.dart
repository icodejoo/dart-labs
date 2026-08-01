export 'abr_config.dart';
export 'controls_config.dart';
export 'danmaku_config.dart';
export 'gesture_config.dart';
export 'live_config.dart';
export 'preview_config.dart';
export 'strings.dart';
export 'theme.dart';

import 'abr_config.dart';
import 'controls_config.dart';
import 'danmaku_config.dart';
import 'gesture_config.dart';
import 'live_config.dart';
import 'preview_config.dart';
import 'strings.dart';
import 'theme.dart';

/// Top-level, immutable configuration bundle for a videoman player.
///
/// Groups every configurable aspect (preview, gestures, ABR, control bar,
/// live behaviour, copy, theme) into one object so apps can construct and
/// pass a single [VmOptions] instance, and so [copyWith] can replace one
/// section without disturbing the others.
///
/// videoman 播放器的顶层不可变配置集合。
///
/// 把所有可配置项（预览、手势、ABR、控制条、直播行为、文案、主题）归入一个
/// 对象，应用只需构造并传入一个 [VmOptions] 实例；[copyWith] 可只替换其中
/// 一节而不影响其他节。
class VmOptions {
  /// Scrub-preview (thumbnail) configuration.
  ///
  /// 拖动预览（缩略图）配置。
  final VmPreviewConfig preview;

  /// Live-playback configuration.
  ///
  /// 直播播放配置。
  final VmLiveConfig live;

  /// Gesture configuration.
  ///
  /// 手势配置。
  final VmGestureConfig gesture;

  /// Adaptive-bitrate configuration.
  ///
  /// 自适应码率配置。
  final VmAbrConfig abr;

  /// Control-bar behaviour configuration.
  ///
  /// 控制条行为配置。
  final VmControlsConfig controls;

  /// Scrolling-danmaku overlay configuration.
  ///
  /// 滚动弹幕叠加层配置。
  final VmDanmakuConfig danmaku;

  /// Externalised UI copy.
  ///
  /// 外置 UI 文案。
  final VmStrings strings;

  /// Externalised visual theme.
  ///
  /// 外置视觉主题。
  final VmTheme theme;

  /// Creates an options bundle; every section defaults to its own defaults.
  ///
  /// 创建配置集合；每一节均使用其自身默认值。
  const VmOptions({
    this.preview = const VmPreviewConfig(),
    this.live = const VmLiveConfig(),
    this.gesture = const VmGestureConfig(),
    this.abr = const VmAbrConfig(),
    this.controls = const VmControlsConfig(),
    this.danmaku = const VmDanmakuConfig(),
    this.strings = const VmStrings(),
    this.theme = const VmTheme(),
  });

  /// Returns a copy with the given sections replaced; omitted sections keep
  /// their current value.
  ///
  /// 返回一份替换了指定节的拷贝；未指定的节保持当前值。
  ///
  /// - [preview]: replacement preview config / 替换用的预览配置
  /// - [live]: replacement live config / 替换用的直播配置
  /// - [gesture]: replacement gesture config / 替换用的手势配置
  /// - [abr]: replacement ABR config / 替换用的 ABR 配置
  /// - [controls]: replacement controls config / 替换用的控制条配置
  /// - [danmaku]: replacement danmaku config / 替换用的弹幕配置
  /// - [strings]: replacement strings / 替换用的文案
  /// - [theme]: replacement theme / 替换用的主题
  ///
  /// Returns the new [VmOptions] instance / 返回新的 [VmOptions] 实例。
  VmOptions copyWith({
    VmPreviewConfig? preview,
    VmLiveConfig? live,
    VmGestureConfig? gesture,
    VmAbrConfig? abr,
    VmControlsConfig? controls,
    VmDanmakuConfig? danmaku,
    VmStrings? strings,
    VmTheme? theme,
  }) {
    return VmOptions(
      preview: preview ?? this.preview,
      live: live ?? this.live,
      gesture: gesture ?? this.gesture,
      abr: abr ?? this.abr,
      controls: controls ?? this.controls,
      danmaku: danmaku ?? this.danmaku,
      strings: strings ?? this.strings,
      theme: theme ?? this.theme,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VmOptions &&
          runtimeType == other.runtimeType &&
          preview == other.preview &&
          live == other.live &&
          gesture == other.gesture &&
          abr == other.abr &&
          controls == other.controls &&
          danmaku == other.danmaku &&
          strings == other.strings &&
          theme == other.theme;

  @override
  int get hashCode =>
      Object.hash(preview, live, gesture, abr, controls, danmaku, strings, theme);
}
