import 'package:flutter/material.dart';

import '../core/fvideo_config.dart';
import '../core/fvideo_controller.dart';
import 'controls_common.dart';

/// Live control bar: no seek bar (live edge follows real time). Shows a LIVE
/// badge, play/pause, a "back to edge" refresh, and fit/fullscreen/lock.
///
/// 直播控制条：无进度条（直播边缘跟随实时）。显示 LIVE 标记、播放暂停、
/// "回到边缘"刷新，以及填充/全屏/锁定。
class LiveControls extends StatelessWidget {
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

  /// Creates the live control bar.
  ///
  /// 创建直播控制条。
  const LiveControls({
    super.key,
    required this.controller,
    required this.fit,
    required this.isFullscreen,
    required this.onLock,
    required this.onCycleFit,
    required this.onToggleFullscreen,
  });

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
    final title = controller.source?.title ?? '';
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
        ControlIconButton(
          icon: Icons.aspect_ratio_rounded,
          caption: fit.label,
          onPressed: onCycleFit,
        ),
        ControlIconButton(
          icon: isFullscreen ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
          onPressed: onToggleFullscreen,
        ),
        ControlIconButton(icon: Icons.lock_open_rounded, onPressed: onLock),
      ],
    );
  }

  /// Builds the centered play/pause button, reacting to the playing stream.
  ///
  /// 构建居中的播放/暂停按钮，跟随播放状态流。
  Widget _centerPlayPause() {
    return Center(
      child: StreamBuilder<bool>(
        stream: controller.player.stream.playing,
        initialData: controller.player.state.playing,
        builder: (context, snap) {
          final playing = snap.data ?? false;
          return InkResponse(
            radius: 36,
            onTap: controller.playOrPause,
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

  /// Builds the bottom row (LIVE badge + back-to-edge refresh).
  ///
  /// 构建底部行（LIVE 标记 + 回到边缘刷新）。
  Widget _bottomBar() {
    return Row(
      children: [
        const SizedBox(width: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: const Color(0xFFE53935),
            borderRadius: BorderRadius.circular(4),
          ),
          child: const Text(
            'LIVE',
            style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
          ),
        ),
        const Spacer(),
        ControlIconButton(
          icon: Icons.sync_rounded,
          caption: '回到边缘',
          onPressed: controller.reload,
        ),
        const SizedBox(width: 4),
      ],
    );
  }
}
