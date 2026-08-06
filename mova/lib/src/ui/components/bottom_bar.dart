import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/model/source.dart';
import '../../core/state/progress.dart';
import '../format.dart';
import '../scope/selector.dart';
import '../slots/component.dart';
import '../slots/slot.dart';
import 'common.dart';

/// Adaptive composite for the bottom control bar, serving both VOD and live
/// from one static node. It exposes the *union* of both layouts' children in a
/// fixed order (so patch paths never shift) and lays out only the ones
/// relevant to the current [MovaState.type] — the rest are simply not placed,
/// and thus never mounted.
///
/// - VOD: `positionLabel · seekBar(expanded) · durationLabel` (0.1.0 order).
/// - Live: `liveBadge · seekBar(expanded when seekable, else spacer) ·
///   timeshift · backToLive` (DESIGN §5.4).
///
/// 自适应的底部控制条组合组件，用一个静态节点同时服务点播与直播。它以固定
/// 顺序暴露两种布局子组件的**并集**（使 patch 路径永不错位），且只布置与当前
/// [MovaState.type] 相关的那些——其余的不放置，因而不会挂载。
///
/// - 点播：`positionLabel · seekBar(撑开) · durationLabel`（0.1.0 行序）。
/// - 直播：`liveBadge · seekBar(可拖时撑开，否则占位) · timeshift · backToLive`
///   （DESIGN §5.4）。
class BottomBarComponent extends MovaComp {
  /// Creates the adaptive bottom-bar composite.
  ///
  /// 创建自适应底栏组合组件。
  BottomBarComponent();

  @override
  String get name => 'bottomBar';

  @override
  MovaSlot get slot => MovaSlot.bottom;

  @override
  List<MovaComp> get children => [
        PositionLabelComponent(), // 0 VOD
        LiveBadgeComponent(), // 1 live
        SeekBarComponent(), // 2 shared
        TimeshiftLabelComponent(), // 3 live
        DurationLabelComponent(), // 4 VOD
        BackToLiveComponent(), // 5 live
      ];

  @override
  Widget build(BuildContext context, MovaApi api, List<Widget> children) {
    final theme = api.options.theme;
    return MovaSelect<({MovaStreamType type, bool seekable})>(
      selector: (s) => (type: s.type, seekable: s.liveSeekable),
      builder: (context, v) {
        final row = v.type == MovaStreamType.live
            ? Row(
                children: [
                  const SizedBox(width: 8),
                  children[1], // liveBadge
                  if (v.seekable) Expanded(child: children[2]) else const Spacer(),
                  children[3], // timeshift
                  children[5], // backToLive
                  const SizedBox(width: 4),
                ],
              )
            : Row(
                children: [
                  const SizedBox(width: 8),
                  children[0], // positionLabel
                  Expanded(child: children[2]), // seekBar
                  children[4], // durationLabel
                  const SizedBox(width: 8),
                ],
              );
        return MovaGradBar(top: false, theme: theme, child: row);
      },
    );
  }
}

/// Elapsed-time label; follows [MovaApi.progress]'s `position` field.
///
/// 已播放时间标签；跟随 [MovaApi.progress] 的 `position` 字段。
class PositionLabelComponent extends MovaComp {
  /// Creates the position-label leaf component.
  ///
  /// 创建已播放时间标签叶子组件。
  PositionLabelComponent();

  @override
  String get name => 'positionLabel';

  @override
  MovaSlot get slot => MovaSlot.bottom;

  @override
  Widget build(BuildContext context, MovaApi api, List<Widget> children) {
    final theme = api.options.theme;
    return MovaProgSelect<Duration>(
      selector: (p) => p.position,
      builder: (context, position) {
        return Text(
          formatDuration(position ?? Duration.zero),
          style: TextStyle(color: Color(theme.textColor), fontSize: theme.timeFontSize),
        );
      },
    );
  }
}

/// Total-duration label; reads [MovaState.duration].
///
/// 总时长标签；读取 [MovaState.duration]。
class DurationLabelComponent extends MovaComp {
  /// Creates the duration-label leaf component.
  ///
  /// 创建总时长标签叶子组件。
  DurationLabelComponent();

  @override
  String get name => 'durationLabel';

  @override
  MovaSlot get slot => MovaSlot.bottom;

  @override
  Widget build(BuildContext context, MovaApi api, List<Widget> children) {
    final theme = api.options.theme;
    return MovaSelect<Duration>(
      selector: (s) => s.duration,
      builder: (context, duration) {
        return Text(
          formatDuration(duration),
          style: TextStyle(color: Color(theme.textColor), fontSize: theme.timeFontSize),
        );
      },
    );
  }
}

/// The seek slider; disabled while [MovaState.duration] is zero (unknown, e.g.
/// live), matching 0.1.0's `_bottomBar()` guard.
///
/// While the user is actively dragging, the displayed value is pinned to the
/// local drag value rather than the incoming progress stream, so scrubbing
/// never jitters — mirroring 0.1.0's `value = _dragValue ?? pos...` behaviour.
///
/// 进度滑块；[MovaState.duration] 为零（未知，如直播）时禁用，对齐 0.1.0
/// `_bottomBar()` 的判断。
///
/// 拖动进行中，展示值锁定为本地拖动值而非进度流推送值，避免拖动抖动——对齐
/// 0.1.0 `value = _dragValue ?? pos...` 的行为。
///
/// For a seekable live stream the span is the DVR window rather than
/// `duration`, so one component serves both VOD and DVR live (DESIGN §5.4).
///
/// 对可拖动的直播流，量程取 DVR 窗口而非 `duration`，因此同一个组件同时服务
/// 点播与可拖直播（DESIGN §5.4）。
class SeekBarComponent extends MovaComp {
  /// Creates the seek-bar leaf component.
  ///
  /// 创建进度滑块叶子组件。
  SeekBarComponent();

  @override
  String get name => 'seekBar';

  @override
  MovaSlot get slot => MovaSlot.bottom;

  @override
  Widget build(BuildContext context, MovaApi api, List<Widget> children) {
    return MovaSelect<Duration>(
      selector: (s) => s.type == MovaStreamType.live && s.liveSeekable
          ? s.seekableWindow
          : s.duration,
      builder: (context, span) => _SeekBar(api: api, duration: span),
    );
  }
}

/// Stateful slider widget backing [SeekBarComponent]; holds the in-progress
/// drag value and tracks the latest position from [MovaApi.progress].
///
/// 支撑 [SeekBarComponent] 的有状态滑块；持有拖动中的本地值，并跟踪
/// [MovaApi.progress] 推送的最新位置。
class _SeekBar extends StatefulWidget {
  /// Creates the internal seek-bar widget.
  ///
  /// [api] is the capability surface to seek/drag through; [duration] is the
  /// current total media duration.
  ///
  /// 创建内部进度滑块 widget。
  ///
  /// [api] 为用于拖动/跳转的能力面；[duration] 为当前媒体总时长。
  const _SeekBar({required this.api, required this.duration});

  /// The capability surface this slider drives.
  ///
  /// 该滑块驱动的能力面。
  final MovaApi api;

  /// Current total media duration; zero means unknown/not seekable.
  ///
  /// 当前媒体总时长；零表示未知/不可拖动。
  final Duration duration;

  @override
  State<_SeekBar> createState() => _SeekBarState();
}

/// State for [_SeekBar]; tracks the latest known position and any
/// in-progress local drag value.
///
/// [_SeekBar] 的状态；跟踪最新已知位置及本地拖动中的临时值（若有）。
class _SeekBarState extends State<_SeekBar> {
  /// Latest known playback position in milliseconds, updated from
  /// [MovaApi.progress].
  ///
  /// 最新已知播放位置（毫秒），来自 [MovaApi.progress]。
  double _position = 0;

  /// Slider value currently being dragged by the user, or `null` when not
  /// dragging — non-null pins the displayed value against progress-stream
  /// updates.
  ///
  /// 用户当前正在拖动的滑块值；未拖动时为 `null`——非空时展示值不受进度流
  /// 更新影响。
  double? _dragValue;

  /// Whether [_dragValue] is a committed seek target awaiting confirmation
  /// (post [_onChangeEnd]) rather than a live in-progress drag. Only in this
  /// state does the `progress` listener auto-release the pin once
  /// [_position] settles near it — during an active drag, a progress tick
  /// landing near the current finger position must never prematurely snap
  /// the pin loose.
  ///
  /// [_dragValue] 是否是已提交、正在等待确认的 seek 目标（[_onChangeEnd] 之后），
  /// 而非正在进行的实时拖动。只有在这个状态下，`progress` 监听才会在
  /// [_position] 落定后自动解除钉住——拖动进行中时，一次凑巧落在手指当前位置
  /// 附近的进度 tick 绝不能提前把钉住松开。
  bool _awaitingSeek = false;

  /// Subscription feeding [_position]; cancelled on dispose.
  ///
  /// 为 [_position] 供数的订阅；在 dispose 时取消。
  StreamSubscription<MovaProg>? _sub;

  /// How close [_position] must land to a pinned [_dragValue] before the pin
  /// is released back to following the live progress stream.
  ///
  /// [_position] 需要落在钉住的 [_dragValue] 多近范围内，才会解除钉住、回到
  /// 跟随实时进度流。
  static const double _settleToleranceMs = 500;

  @override
  void initState() {
    super.initState();
    _sub = widget.api.progress.listen((p) {
      setState(() {
        _position = p.position.inMilliseconds.toDouble();
        final drag = _dragValue;
        if (_awaitingSeek &&
            drag != null &&
            (_position - drag).abs() < _settleToleranceMs) {
          _dragValue = null;
          _awaitingSeek = false;
        }
      });
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.api.options.theme;
    final max = widget.duration.inMilliseconds.toDouble();
    final enabled = max > 0;
    final value = (_dragValue ?? _position).clamp(0.0, enabled ? max : 0.0);
    return Material(
      type: MaterialType.transparency,
      child: SliderTheme(
        data: SliderTheme.of(context).copyWith(trackHeight: theme.progressHeight),
        child: Slider(
          value: value,
          min: 0,
          max: enabled ? max : 1,
          onChanged: enabled ? _onChanged : null,
          onChangeEnd: enabled ? _onChangeEnd : null,
        ),
      ),
    );
  }

  /// Records the in-progress drag value and previews the target seek
  /// position via [MovaApi.setDragging].
  ///
  /// 记录拖动中的值，并通过 [MovaApi.setDragging] 预览目标跳转位置。
  ///
  /// - [v]: the new slider value in milliseconds / 新滑块值（毫秒）
  void _onChanged(double v) {
    setState(() {
      _dragValue = v;
      _awaitingSeek = false;
    });
    widget.api.setDragging(true, previewAt: Duration(milliseconds: v.round()));
  }

  /// Commits the dragged position via [MovaApi.seek] and clears the drag
  /// preview.
  ///
  /// Deliberately does *not* clear [_dragValue] here: [MovaApi.seek] pins the
  /// engine's own progress stream to the target too, but that stream is
  /// throttled, so clearing the local pin immediately could still flash the
  /// slider back to the stale pre-seek position for the throttle window.
  /// [_dragValue] is released once [_position] actually reports something
  /// close to it (see the `progress` listener in [initState]), so the
  /// displayed value never regresses.
  ///
  /// 通过 [MovaApi.seek] 提交拖动结果，清除拖动预览。
  ///
  /// 这里刻意**不**清空 [_dragValue]：[MovaApi.seek] 也会把 engine 自身的进度流
  /// 钉在目标值上，但那条流带节流，若立刻清掉本地钉住值，滑块仍可能在节流
  /// 窗口内闪回 seek 前的旧位置。[_dragValue] 只在 [_position] 真的报告出
  /// 接近目标的值时才释放（见 [initState] 里的 `progress` 监听），因此展示值
  /// 绝不会倒退。
  ///
  /// - [v]: the final slider value in milliseconds / 最终滑块值（毫秒）
  void _onChangeEnd(double v) {
    widget.api.seek(Duration(milliseconds: v.round()));
    widget.api.setDragging(false);
    setState(() => _awaitingSeek = true);
  }
}

/// The live/time-shift badge: a red `LIVE` pill at the edge, a muted `时移`
/// pill while replaying. Nested under [BottomBarComponent] in live mode.
///
/// Colour and copy both come from options ([MovaTheme.accentColor] /
/// [MovaTheme.timeshiftBadgeColor], [MovaStrs.live] / [MovaStrs.timeshift]).
///
/// 直播/时移角标：在边缘时是红色 `LIVE` 胶囊，回看时是灰色 `时移` 胶囊；直播
/// 模式下嵌套在 [BottomBarComponent] 之下。
///
/// 配色与文案都取自配置（[MovaTheme.accentColor] / [MovaTheme.timeshiftBadgeColor]、
/// [MovaStrs.live] / [MovaStrs.timeshift]）。
class LiveBadgeComponent extends MovaComp {
  /// Creates the live-badge leaf component.
  ///
  /// 创建直播角标叶子组件。
  LiveBadgeComponent();

  @override
  String get name => 'liveBadge';

  @override
  MovaSlot get slot => MovaSlot.bottom;

  @override
  Widget build(BuildContext context, MovaApi api, List<Widget> children) {
    final theme = api.options.theme;
    final strings = api.options.strings;
    return MovaSelect<bool>(
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
class TimeshiftLabelComponent extends MovaComp {
  /// Creates the timeshift-label leaf component.
  ///
  /// 创建时移标签叶子组件。
  TimeshiftLabelComponent();

  @override
  String get name => 'timeshift';

  @override
  MovaSlot get slot => MovaSlot.bottom;

  @override
  Widget build(BuildContext context, MovaApi api, List<Widget> children) {
    final theme = api.options.theme;
    return MovaSelect<Duration?>(
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
/// Delegates the *how* entirely to [MovaApi.backToLiveEdge], which follows
/// `MovaLiveConfig.effectiveBackToLive` (seek to the window end for DVR, reopen
/// the original URL for time-shift). Replaces 0.1.0's `backToEdge` button,
/// which called `reload()` unconditionally.
///
/// 让播放回到直播边缘的按钮。
///
/// **具体怎么回**完全交给 [MovaApi.backToLiveEdge]，由
/// `MovaLiveConfig.effectiveBackToLive` 决定（DVR 跳到窗口末端，时移则重开原始
/// 地址）。它取代了 0.1.0 里无条件调用 `reload()` 的 `backToEdge` 按钮。
class BackToLiveComponent extends MovaComp {
  /// Creates the back-to-live leaf component.
  ///
  /// 创建回到直播叶子组件。
  BackToLiveComponent();

  @override
  String get name => 'backToLive';

  @override
  MovaSlot get slot => MovaSlot.bottom;

  @override
  Widget build(BuildContext context, MovaApi api, List<Widget> children) {
    final theme = api.options.theme;
    final strings = api.options.strings;
    return MovaIconButton(
      icon: Icons.sync_rounded,
      caption: strings.backToLive,
      theme: theme,
      onPressed: api.backToLiveEdge,
    );
  }
}
