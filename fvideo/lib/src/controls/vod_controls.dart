import 'package:flutter/material.dart';

import '../core/fvideo_config.dart';
import '../core/fvideo_controller.dart';
import 'controls_common.dart';

/// On-demand (VOD) control bar: title/lock/fit/fullscreen + play/pause +
/// a seekable progress bar with time labels.
///
/// Lives above the gesture layer but only its top and bottom bars are
/// hit-testable, so center taps/drags still reach the gestures below.
///
/// 点播控制条：标题/锁定/填充/全屏 + 播放暂停 + 可拖动进度条与时间。
///
/// 叠加在手势层之上，但仅顶/底两条可点击，中间区域的点击/拖动仍会落到下层手势。
class VodControls extends StatefulWidget {
  /// Playback controller to read state from and drive.
  ///
  /// 用于读取状态并驱动的播放控制器。
  final FvideoController controller;

  /// Current fill mode (shown on the fit button).
  ///
  /// 当前填充模式（显示在填充按钮上）。
  final FvideoFit fit;

  /// Whether the player is currently fullscreen.
  ///
  /// 播放器当前是否全屏。
  final bool isFullscreen;

  /// Called when the lock button is tapped.
  ///
  /// 点击锁定按钮时调用。
  final VoidCallback onLock;

  /// Called when the fit button is tapped (cycles the mode).
  ///
  /// 点击填充按钮时调用（循环切换模式）。
  final VoidCallback onCycleFit;

  /// Called when the fullscreen button is tapped.
  ///
  /// 点击全屏按钮时调用。
  final VoidCallback onToggleFullscreen;

  /// Called when the quality button is tapped; null hides the button.
  ///
  /// 点击清晰度按钮时调用；为 null 时隐藏该按钮。
  final VoidCallback? onQuality;

  /// Label for the quality button (e.g. current quality).
  ///
  /// 清晰度按钮的标签（如当前清晰度）。
  final String? qualityLabel;

  /// Called when the PiP button is tapped; null hides the button.
  ///
  /// 点击画中画按钮时调用；为 null 时隐藏该按钮。
  final VoidCallback? onPip;

  /// Creates the VOD control bar.
  ///
  /// 创建点播控制条。
  const VodControls({
    super.key,
    required this.controller,
    required this.fit,
    required this.isFullscreen,
    required this.onLock,
    required this.onCycleFit,
    required this.onToggleFullscreen,
    this.onQuality,
    this.qualityLabel,
    this.onPip,
  });

  @override
  State<VodControls> createState() => _VodControlsState();
}

/// State for [VodControls]; holds the in-progress scrub value.
///
/// [VodControls] 的状态；保存进度拖动过程中的临时值。
class _VodControlsState extends State<VodControls> {
  double? _dragValue;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ControlGradientBar(top: true, child: _topBar()),
        Expanded(child: _centerPlayPause()),
        ControlGradientBar(top: false, child: _bottomBar()),
      ],
    );
  }

  /// Builds the top row (title + fit/fullscreen/lock actions).
  ///
  /// 构建顶部行（标题 + 填充/全屏/锁定操作）。
  Widget _topBar() {
    final title = widget.controller.source?.title ?? '';
    return Row(
      children: [
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white, fontSize: 14),
          ),
        ),
        if (widget.onPip != null)
          ControlIconButton(icon: Icons.picture_in_picture_alt_rounded, onPressed: widget.onPip),
        if (widget.onQuality != null)
          ControlIconButton(
            icon: Icons.high_quality_rounded,
            caption: widget.qualityLabel,
            onPressed: widget.onQuality,
          ),
        ControlIconButton(
          icon: Icons.aspect_ratio_rounded,
          caption: widget.fit.label,
          onPressed: widget.onCycleFit,
        ),
        ControlIconButton(
          icon: widget.isFullscreen
              ? Icons.fullscreen_exit_rounded
              : Icons.fullscreen_rounded,
          onPressed: widget.onToggleFullscreen,
        ),
        ControlIconButton(icon: Icons.lock_open_rounded, onPressed: widget.onLock),
      ],
    );
  }

  /// Builds the centered play/pause button, reacting to the playing stream.
  ///
  /// 构建居中的播放/暂停按钮，跟随播放状态流。
  Widget _centerPlayPause() {
    return Center(
      child: StreamBuilder<bool>(
        stream: widget.controller.player.stream.playing,
        initialData: widget.controller.player.state.playing,
        builder: (context, snap) {
          final playing = snap.data ?? false;
          return InkResponse(
            radius: 36,
            onTap: widget.controller.playOrPause,
            child: Icon(
              playing ? Icons.pause_circle_filled_rounded : Icons.play_circle_filled_rounded,
              color: Colors.white,
              size: 64,
            ),
          );
        },
      ),
    );
  }

  /// Builds the bottom row (elapsed / seek slider / total).
  ///
  /// 构建底部行（已播 / 拖动进度条 / 总时长）。
  Widget _bottomBar() {
    return StreamBuilder<Duration>(
      stream: widget.controller.player.stream.position,
      initialData: widget.controller.player.state.position,
      builder: (context, snap) {
        final dur = widget.controller.player.state.duration;
        final pos = snap.data ?? Duration.zero;
        final total = dur.inMilliseconds.toDouble();
        final value = _dragValue ?? pos.inMilliseconds.toDouble();
        return Row(
          children: [
            const SizedBox(width: 12),
            Text(formatDuration(pos), style: _timeStyle),
            Expanded(
              child: Slider(
                min: 0,
                max: total <= 0 ? 1 : total,
                value: value.clamp(0, total <= 0 ? 1 : total),
                onChanged: total <= 0 ? null : (v) => setState(() => _dragValue = v),
                onChangeEnd: total <= 0
                    ? null
                    : (v) {
                        widget.controller.seek(Duration(milliseconds: v.round()));
                        setState(() => _dragValue = null);
                      },
              ),
            ),
            Text(formatDuration(dur), style: _timeStyle),
            const SizedBox(width: 12),
          ],
        );
      },
    );
  }

  /// Shared style for the time labels.
  ///
  /// 时间文字的共享样式。
  static const TextStyle _timeStyle = TextStyle(color: Colors.white, fontSize: 12);
}
