import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../format.dart';
import '../scope/selector.dart';
import '../slots/component.dart';
import '../slots/slot.dart';
import 'bottom_bar.dart';
import 'common.dart';

/// Composite component for the live-stream bottom control bar.
///
/// Layout mirrors DESIGN section 5.4's live tree
/// `bottomBar/{liveBadge, seekBar, timeshift, backToLive}`. The seek bar is
/// only *placed* when [seekable]; the skin decides that from
/// `VmState.liveSeekable`, so a non-DVR stream keeps 0.1.0's badge-only bar.
///
/// 直播底部控制条组合组件。
///
/// 布局对应 DESIGN §5.4 的直播树
/// `bottomBar/{liveBadge, seekBar, timeshift, backToLive}`。进度条仅在
/// [seekable] 为真时才被**放置**；皮肤依据 `VmState.liveSeekable` 决定该值，
/// 因此非 DVR 流保持 0.1.0 那种只有角标的底栏。
class LiveBarComponent extends VmComponent {
  /// Creates the live-bar composite.
  ///
  /// [seekable] decides whether the seek bar is laid out; defaults to `false`
  /// so a bare `LiveBarComponent()` reproduces the non-seekable live bar.
  ///
  /// 创建直播底栏组合组件。
  ///
  /// [seekable] 决定是否布置进度条；默认 `false`，因此裸的
  /// `LiveBarComponent()` 复现不可拖动的直播底栏。
  LiveBarComponent({this.seekable = false});

  /// Whether this stream can be scrubbed within its DVR window.
  ///
  /// 该流是否可在其 DVR 窗口内拖动。
  final bool seekable;

  @override
  String get name => 'bottomBar';

  @override
  VmSlot get slot => VmSlot.bottom;

  // The child list is fixed-length regardless of [seekable] so child indices
  // (and therefore patch paths) never shift; only placement varies.
  //
  // 无论 [seekable] 取值，子组件列表长度恒定，使子节点下标（以及 patch 路径）
  // 永不错位；变化的只是是否布置。
  @override
  List<VmComponent> get children => [
        LiveBadgeComponent(),
        SeekBarComponent(),
        TimeshiftLabelComponent(),
        BackToLiveComponent(),
      ];

  @override
  Widget build(BuildContext context, VmApi api, List<Widget> children) {
    final theme = api.options.theme;
    return VmGradientBar(
      top: false,
      theme: theme,
      child: Row(
        children: [
          const SizedBox(width: 8),
          children[0],
          if (seekable) Expanded(child: children[1]) else const Spacer(),
          children[2],
          children[3],
          const SizedBox(width: 4),
        ],
      ),
    );
  }
}

/// The live/time-shift badge: a red `LIVE` pill at the edge, a muted
/// `时移` pill while replaying.
///
/// Colour and copy both come from options ([VmTheme.accentColor] /
/// [VmTheme.timeshiftBadgeColor], [VmStrings.live] / [VmStrings.timeshift]).
///
/// 直播/时移角标：在边缘时是红色 `LIVE` 胶囊，回看时是灰色 `时移` 胶囊。
///
/// 配色与文案都取自配置（[VmTheme.accentColor] / [VmTheme.timeshiftBadgeColor]、
/// [VmStrings.live] / [VmStrings.timeshift]）。
class LiveBadgeComponent extends VmComponent {
  /// Creates the live-badge leaf component.
  ///
  /// 创建直播角标叶子组件。
  LiveBadgeComponent();

  @override
  String get name => 'liveBadge';

  // Inert: this component is only ever nested under [LiveBarComponent],
  // which lays out its children directly rather than via slot placement.
  //
  // 无效：该组件始终嵌套在 [LiveBarComponent] 之下，父组件直接通过 children
  // 布局，而非按槽位放置。
  @override
  VmSlot get slot => VmSlot.bottom;

  @override
  Widget build(BuildContext context, VmApi api, List<Widget> children) {
    final theme = api.options.theme;
    final strings = api.options.strings;
    return VmSelector<bool>(
      selector: (s) => s.timeshiftBehind == null,
      builder: (context, atEdge) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: Color(atEdge ? theme.accentColor : theme.timeshiftBadgeColor),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            atEdge ? strings.live : strings.timeshift,
            style: TextStyle(
              color: Color(theme.textColor),
              fontWeight: FontWeight.bold,
              fontSize: theme.badgeFontSize,
            ),
          ),
        );
      },
    );
  }
}

/// Shows how far behind the live edge playback currently is, as `-MM:SS`.
///
/// Renders nothing at the live edge, so the bar is visually identical to a
/// plain live stream until the user actually scrubs back.
///
/// 以 `-MM:SS` 展示当前落后直播边缘的时长。
///
/// 处于直播边缘时不渲染任何内容，因此在用户真正回看之前，底栏与普通直播流
/// 在视觉上完全一致。
class TimeshiftLabelComponent extends VmComponent {
  /// Creates the timeshift-label leaf component.
  ///
  /// 创建时移标签叶子组件。
  TimeshiftLabelComponent();

  @override
  String get name => 'timeshift';

  // Inert: nested under [LiveBarComponent], which positions it directly.
  //
  // 无效：嵌套在 [LiveBarComponent] 之下，由父组件直接定位。
  @override
  VmSlot get slot => VmSlot.bottom;

  @override
  Widget build(BuildContext context, VmApi api, List<Widget> children) {
    final theme = api.options.theme;
    return VmSelector<Duration?>(
      selector: (s) => s.timeshiftBehind,
      builder: (context, behind) {
        if (behind == null) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Text(
            '-${formatDuration(behind)}',
            style: TextStyle(
              color: Color(theme.textColor),
              fontSize: theme.timeFontSize,
            ),
          ),
        );
      },
    );
  }
}

/// Button returning playback to the live edge.
///
/// Delegates the *how* entirely to [VmApi.backToLiveEdge], which follows
/// `VmLiveConfig.effectiveBackToLive` (seek to the window end for DVR, reopen
/// the original URL for time-shift). Replaces 0.1.0's `backToEdge` button,
/// which called `reload()` unconditionally.
///
/// 让播放回到直播边缘的按钮。
///
/// **具体怎么回**完全交给 [VmApi.backToLiveEdge]，由
/// `VmLiveConfig.effectiveBackToLive` 决定（DVR 跳到窗口末端，时移则重开原始
/// 地址）。它取代了 0.1.0 里无条件调用 `reload()` 的 `backToEdge` 按钮。
class BackToLiveComponent extends VmComponent {
  /// Creates the back-to-live leaf component.
  ///
  /// 创建回到直播叶子组件。
  BackToLiveComponent();

  @override
  String get name => 'backToLive';

  // Inert: nested under [LiveBarComponent], which positions it directly.
  //
  // 无效：嵌套在 [LiveBarComponent] 之下，由父组件直接定位。
  @override
  VmSlot get slot => VmSlot.bottom;

  @override
  Widget build(BuildContext context, VmApi api, List<Widget> children) {
    final theme = api.options.theme;
    final strings = api.options.strings;
    return VmIconButton(
      icon: Icons.sync_rounded,
      caption: strings.backToLive,
      theme: theme,
      onPressed: api.backToLiveEdge,
    );
  }
}
