import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../core/api.dart';
import '../../core/model/source.dart';
import '../../core/state/progress.dart';
import '../../core/state/ui_state.dart';
import '../slots/component.dart';
import '../slots/slot.dart';

/// Movement (px) before a one-finger drag locks into an axis.
///
/// 单指拖动锁定方向前需要移动的像素阈值。
const double _kAxisLockThreshold = 8;

/// Which adjustment a one-finger vertical/horizontal drag is driving.
///
/// 单指拖动当前正在驱动哪种调节。
enum _DragMode {
  /// Not yet decided.
  ///
  /// 尚未判定。
  undecided,

  /// Horizontal drag → seek.
  ///
  /// 横向拖动 → 进度。
  seek,

  /// Left-half vertical drag → volume.
  ///
  /// 左半屏竖向拖动 → 音量。
  volume,

  /// Right-half vertical drag → brightness.
  ///
  /// 右半屏竖向拖动 → 亮度。
  brightness,

  /// Two-finger pinch → zoom.
  ///
  /// 双指捏合 → 缩放。
  zoom,
}

/// Component that recognizes gestures on the video surface (drag/pinch/tap)
/// and drives the matching [VmApi] intent — never touching playback state
/// directly. Side mapping (left=volume, right=brightness) and axis-lock
/// behaviour are reproduced byte-for-byte from the 0.1.0 `VmGestureDetector`
/// baseline; only the seek-gating logic is generalized to consider
/// `liveSeekable`/`allowWhenLive` for an eventual live-seek feature.
///
/// 识别视频画面手势（拖动/捏合/点击）并驱动对应 [VmApi] 意图的组件——绝不
/// 直接操作播放状态。侧别映射（左音量/右亮度）与轴向锁定行为与 0.1.0
/// 基线的 `VmGestureDetector` 逐字一致；仅进度门控逻辑做了泛化，纳入
/// `liveSeekable`/`allowWhenLive` 以支持后续的直播拖动功能。
class GestureLayerComponent extends VmComponent {
  /// Creates a gesture-layer component.
  ///
  /// 创建手势层组件。
  GestureLayerComponent();

  @override
  String get name => 'gestureLayer';

  @override
  VmSlot get slot => VmSlot.gesture;

  @override
  Widget build(BuildContext context, VmApi api, List<Widget> children) {
    return _GestureLayer(api: api);
  }
}

/// Stateful gesture recognizer wired to [VmApi]; holds per-drag snapshots
/// that must survive across `onScaleUpdate` calls within one drag.
///
/// 接入 [VmApi] 的有状态手势识别器；保存单次拖动内、需跨多次
/// `onScaleUpdate` 调用存活的起始快照。
class _GestureLayer extends StatefulWidget {
  /// Creates the internal gesture widget.
  ///
  /// [api] is the capability surface to drive intents through.
  ///
  /// 创建内部手势 widget。
  ///
  /// [api] 为用于驱动意图的能力面。
  const _GestureLayer({required this.api});

  /// The capability surface this gesture layer drives.
  ///
  /// 该手势层驱动的能力面。
  final VmApi api;

  @override
  State<_GestureLayer> createState() => _GestureLayerState();
}

/// State machine for [_GestureLayer]; mirrors 0.1.0's
/// `_VmGestureDetectorState` math exactly, re-pointed at [VmApi] calls.
///
/// [_GestureLayer] 的状态机；手势数学与 0.1.0 的
/// `_VmGestureDetectorState` 完全一致，只是出口改为 [VmApi] 调用。
class _GestureLayerState extends State<_GestureLayer> {
  /// Which intent the current one-finger drag is driving, if decided.
  ///
  /// 当前单指拖动正在驱动的意图（若已判定）。
  _DragMode _mode = _DragMode.undecided;

  /// Accumulated focal-point delta since the drag started.
  ///
  /// 自拖动开始累计的焦点位移。
  Offset _cum = Offset.zero;

  /// Volume (0–100) or brightness (0–1) snapshotted when the mode locked.
  ///
  /// 模式锁定时拍下的起始音量（0–100）或亮度（0–1）。
  double _startValue = 0;

  /// Whether the drag started in the left half of the surface.
  ///
  /// 本次拖动是否从画面左半屏开始。
  bool _startedLeft = true;

  /// Current layout size of the gesture surface.
  ///
  /// 手势识别区域当前的布局尺寸。
  Size _size = Size.zero;

  /// Horizontal position of the most recent double-tap-down.
  ///
  /// 最近一次双击按下的横坐标。
  double _lastDoubleTapDx = 0;

  /// Zoom factor snapshotted at the start of the current pinch gesture,
  /// used as the baseline that `d.scale` multiplies.
  ///
  /// 本次捏合手势开始时拍下的缩放系数，作为 `d.scale` 相乘的基准值。
  double _startZoom = 1.0;

  /// Latest known playback position, tracked from [VmApi.progress] since
  /// position does not live on [VmApi.state].
  ///
  /// 已知的最新播放位置，从 [VmApi.progress] 追踪而来（位置字段不在
  /// [VmApi.state] 里）。
  Duration _lastPosition = Duration.zero;

  /// Subscription feeding [_lastPosition]; cancelled on dispose.
  ///
  /// 为 [_lastPosition] 供数的订阅；在 dispose 时取消。
  StreamSubscription<VmProgress>? _progressSub;

  /// Shorthand for the capability surface this state drives.
  ///
  /// 该状态驱动的能力面的简写访问器。
  VmApi get _api => widget.api;

  @override
  void initState() {
    super.initState();
    _progressSub = _api.progress.listen((p) => _lastPosition = p.position);
  }

  @override
  void dispose() {
    _progressSub?.cancel();
    super.dispose();
  }

  /// Whether seek gestures are currently allowed: always for VOD; for a
  /// live source only if `allowWhenLive` is on and the current state
  /// reports `liveSeekable`.
  ///
  /// 判断当前是否允许进度类手势：点播下总是允许；直播下仅当
  /// `allowWhenLive` 开启且当前状态 `liveSeekable` 为真时允许。
  bool get _seekAllowed {
    final state = _api.state;
    final live = state.type == VmStreamType.live;
    if (!live) return true;
    if (!_api.options.gesture.allowWhenLive) return false;
    return state.liveSeekable;
  }

  /// Records the tap position so double-tap can tell left from right.
  ///
  /// 记录点击位置，供双击判定左/右半屏。
  void _onDoubleTapDown(TapDownDetails d) => _lastDoubleTapDx = d.localPosition.dx;

  /// Applies a double-tap seek toward the tapped side, gated the same way
  /// as horizontal drag-seek.
  ///
  /// 按点击侧执行双击快进/快退，门控逻辑与横滑进度一致。
  void _onDoubleTap() {
    final cfg = _api.options.gesture;
    if (!cfg.doubleTapSeek || !_seekAllowed) return;
    final backward = _lastDoubleTapDx < _size.width / 2;
    final step = cfg.doubleTapStep;
    _api.seek(_lastPosition + (backward ? -step : step));
    _api.showHud(VmHud.seek);
  }

  /// Toggles control-bar visibility on a plain (non-double) tap.
  ///
  /// 单击（非双击）时切换控制条显隐。
  void _onTap() {
    if (_api.uiState.controlsVisible) {
      _api.hideControls();
    } else {
      _api.showControls();
    }
  }

  /// Resets per-drag state and snapshots the starting side/zoom baseline.
  ///
  /// 重置本次拖动状态并记录起始侧别/缩放基准。
  void _onScaleStart(ScaleStartDetails d) {
    _mode = _DragMode.undecided;
    _cum = Offset.zero;
    _startedLeft = d.localFocalPoint.dx < _size.width / 2;
    _startZoom = _api.state.zoom;
  }

  /// Interprets drag/pinch movement and drives the matching intent.
  ///
  /// 解释拖动/捏合位移并驱动对应意图。
  void _onScaleUpdate(ScaleUpdateDetails d) {
    if (_mode == _DragMode.zoom) {
      _applyZoom(d.scale);
      return;
    }
    if (d.pointerCount >= 2) {
      if (!_api.options.gesture.pinchZoom) return;
      _mode = _DragMode.zoom;
      _applyZoom(d.scale);
      return;
    }

    _cum += d.focalPointDelta;
    if (_mode == _DragMode.undecided) {
      if (_cum.distance < _kAxisLockThreshold) return;
      _mode = _decideMode();
      _snapshotStartValue();
    }
    _drive();
  }

  /// Multiplies the pinch-start zoom baseline by [scale], clamps to
  /// `[1.0, maxZoom]`, and applies it.
  ///
  /// 用 [scale] 乘以捏合起点的缩放基准，clamp 到 `[1.0, maxZoom]` 后应用。
  void _applyZoom(double scale) {
    final maxZoom = _api.options.gesture.maxZoom;
    final z = (_startZoom * scale).clamp(1.0, maxZoom);
    _api.setZoom(z);
  }

  /// Chooses the axis/side once movement passes the lock threshold; stays
  /// [_DragMode.undecided] (no fallback) if the config disables the mode
  /// that would otherwise be chosen.
  ///
  /// 位移越过阈值后判定方向/侧别；若配置禁用了本应选中的模式，则保持
  /// [_DragMode.undecided]（不回退到其他模式）。
  _DragMode _decideMode() {
    final cfg = _api.options.gesture;
    if (_cum.dx.abs() > _cum.dy.abs()) {
      final canSeek = cfg.horizontalSeek && _seekAllowed;
      return canSeek ? _DragMode.seek : _DragMode.undecided;
    }
    if (_startedLeft) {
      return cfg.leftVerticalVolume ? _DragMode.volume : _DragMode.undecided;
    }
    return cfg.rightVerticalBrightness ? _DragMode.brightness : _DragMode.undecided;
  }

  /// Captures the starting volume/brightness for the chosen mode.
  ///
  /// 为所选模式捕获起始音量/亮度。
  void _snapshotStartValue() {
    if (_mode == _DragMode.volume) {
      _startValue = _api.state.volume;
    } else if (_mode == _DragMode.brightness) {
      _startValue = _api.state.brightness;
    }
  }

  /// Emits the intent value derived from accumulated movement.
  ///
  /// 根据累计位移驱动对应意图。
  void _drive() {
    switch (_mode) {
      case _DragMode.seek:
        final seconds = _cum.dx /
            _size.width *
            _api.options.gesture.hSeekSpanPerScreen.inSeconds.toDouble();
        final target = _lastPosition + Duration(seconds: seconds.round());
        _api.setDragging(true, previewAt: target);
        _api.showHud(VmHud.seek);
        break;
      case _DragMode.volume:
        final frac = -_cum.dy / _size.height; // up = louder
        _api.setVolume((_startValue + frac * 100).clamp(0, 100));
        break;
      case _DragMode.brightness:
        final frac = -_cum.dy / _size.height; // up = brighter
        _api.setBrightness((_startValue + frac).clamp(0.0, 1.0));
        break;
      case _DragMode.undecided:
      case _DragMode.zoom:
        break;
    }
  }

  /// Commits the seek when a seek drag ends; zoom needs no explicit commit
  /// beyond the last [VmApi.setZoom] call already applied.
  ///
  /// 横滑结束时提交进度；缩放手势结束无需额外提交，最后一次
  /// [VmApi.setZoom] 调用即已生效。
  void _onScaleEnd(ScaleEndDetails d) {
    if (_mode == _DragMode.seek) {
      final seconds = _cum.dx /
          _size.width *
          _api.options.gesture.hSeekSpanPerScreen.inSeconds.toDouble();
      _api.seek(_lastPosition + Duration(seconds: seconds.round()));
      _api.setDragging(false);
    }
    _mode = _DragMode.undecided;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _size = constraints.biggest;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _onTap,
          onDoubleTapDown: _onDoubleTapDown,
          onDoubleTap: _onDoubleTap,
          onScaleStart: _onScaleStart,
          onScaleUpdate: _onScaleUpdate,
          onScaleEnd: _onScaleEnd,
        );
      },
    );
  }
}
