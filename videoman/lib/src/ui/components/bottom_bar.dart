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

/// Composite component for the VOD bottom control bar: elapsed-time label,
/// the seek slider (expanded), then total-duration label — matching 0.1.0's
/// `_bottomBar()` row order.
///
/// 点播底部控制条组合组件：已播放时间标签、进度滑块（撑开）、总时长标签，
/// 行序对齐 0.1.0 的 `_bottomBar()`。
class BottomBarComponent extends VmComponent {
  /// Creates the bottom-bar composite with its 3 fixed children.
  ///
  /// 创建带 3 个固定子组件的底栏组合组件。
  BottomBarComponent();

  @override
  String get name => 'bottomBar';

  @override
  VmSlot get slot => VmSlot.bottom;

  @override
  List<VmComponent> get children => [
        PositionLabelComponent(),
        SeekBarComponent(),
        DurationLabelComponent(),
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
          Expanded(child: children[1]),
          children[2],
          const SizedBox(width: 8),
        ],
      ),
    );
  }
}

/// Elapsed-time label; follows [VmApi.progress]'s `position` field.
///
/// 已播放时间标签；跟随 [VmApi.progress] 的 `position` 字段。
class PositionLabelComponent extends VmComponent {
  /// Creates the position-label leaf component.
  ///
  /// 创建已播放时间标签叶子组件。
  PositionLabelComponent();

  @override
  String get name => 'positionLabel';

  @override
  VmSlot get slot => VmSlot.bottom;

  @override
  Widget build(BuildContext context, VmApi api, List<Widget> children) {
    final theme = api.options.theme;
    return VmProgressSelector<Duration>(
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

/// Total-duration label; reads [VmState.duration].
///
/// 总时长标签；读取 [VmState.duration]。
class DurationLabelComponent extends VmComponent {
  /// Creates the duration-label leaf component.
  ///
  /// 创建总时长标签叶子组件。
  DurationLabelComponent();

  @override
  String get name => 'durationLabel';

  @override
  VmSlot get slot => VmSlot.bottom;

  @override
  Widget build(BuildContext context, VmApi api, List<Widget> children) {
    final theme = api.options.theme;
    return VmSelector<Duration>(
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

/// The seek slider; disabled while [VmState.duration] is zero (unknown, e.g.
/// live), matching 0.1.0's `_bottomBar()` guard.
///
/// While the user is actively dragging, the displayed value is pinned to the
/// local drag value rather than the incoming progress stream, so scrubbing
/// never jitters — mirroring 0.1.0's `value = _dragValue ?? pos...` behaviour.
///
/// 进度滑块；[VmState.duration] 为零（未知，如直播）时禁用，对齐 0.1.0
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
class SeekBarComponent extends VmComponent {
  /// Creates the seek-bar leaf component.
  ///
  /// 创建进度滑块叶子组件。
  SeekBarComponent();

  @override
  String get name => 'seekBar';

  @override
  VmSlot get slot => VmSlot.bottom;

  @override
  Widget build(BuildContext context, VmApi api, List<Widget> children) {
    return VmSelector<Duration>(
      selector: (s) => s.type == VmStreamType.live && s.liveSeekable
          ? s.seekableWindow
          : s.duration,
      builder: (context, span) => _SeekBar(api: api, duration: span),
    );
  }
}

/// Stateful slider widget backing [SeekBarComponent]; holds the in-progress
/// drag value and tracks the latest position from [VmApi.progress].
///
/// 支撑 [SeekBarComponent] 的有状态滑块；持有拖动中的本地值，并跟踪
/// [VmApi.progress] 推送的最新位置。
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
  final VmApi api;

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
  /// [VmApi.progress].
  ///
  /// 最新已知播放位置（毫秒），来自 [VmApi.progress]。
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
  StreamSubscription<VmProgress>? _sub;

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
  /// position via [VmApi.setDragging].
  ///
  /// 记录拖动中的值，并通过 [VmApi.setDragging] 预览目标跳转位置。
  ///
  /// - [v]: the new slider value in milliseconds / 新滑块值（毫秒）
  void _onChanged(double v) {
    setState(() {
      _dragValue = v;
      _awaitingSeek = false;
    });
    widget.api.setDragging(true, previewAt: Duration(milliseconds: v.round()));
  }

  /// Commits the dragged position via [VmApi.seek] and clears the drag
  /// preview.
  ///
  /// Deliberately does *not* clear [_dragValue] here: [VmApi.seek] pins the
  /// engine's own progress stream to the target too, but that stream is
  /// throttled, so clearing the local pin immediately could still flash the
  /// slider back to the stale pre-seek position for the throttle window.
  /// [_dragValue] is released once [_position] actually reports something
  /// close to it (see the `progress` listener in [initState]), so the
  /// displayed value never regresses.
  ///
  /// 通过 [VmApi.seek] 提交拖动结果，清除拖动预览。
  ///
  /// 这里刻意**不**清空 [_dragValue]：[VmApi.seek] 也会把 engine 自身的进度流
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
