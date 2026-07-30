import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../scope/selector.dart';
import '../slots/component.dart';
import '../slots/slot.dart';

/// Composite component for the center overlay: currently only the
/// play/pause tap-feedback button, matching 0.1.0's `_centerPlayPause()`.
///
/// 中央叠加层组合组件：目前仅含播放/暂停点按反馈按钮，对齐 0.1.0 的
/// `_centerPlayPause()`。
class CenterPlayComponent extends VmComponent {
  /// Creates the center-play composite with its single child.
  ///
  /// 创建带唯一子组件的中央播放组合组件。
  CenterPlayComponent();

  @override
  String get name => 'centerPlay';

  @override
  VmSlot get slot => VmSlot.center;

  @override
  List<VmComponent> get children => [PlayPauseComponent()];

  @override
  Widget build(BuildContext context, VmApi api, List<Widget> children) {
    return Center(child: children[0]);
  }
}

/// Large center play/pause tap-feedback button.
///
/// Mirrors 0.1.0's `_centerPlayPause()`: an `InkResponse` circle (radius 36)
/// showing a filled play/pause glyph sized/colored from [VmTheme], driven by
/// [VmState.playing], calling [VmApi.playOrPause] on tap.
///
/// 中央大号播放/暂停点按反馈按钮。
///
/// 对齐 0.1.0 的 `_centerPlayPause()`：一个半径 36 的 `InkResponse` 圆形，内含
/// 填充式播放/暂停图标（尺寸/颜色取自 [VmTheme]），由 [VmState.playing] 驱动，
/// 点击调用 [VmApi.playOrPause]。
class PlayPauseComponent extends VmComponent {
  /// Creates the play/pause leaf component.
  ///
  /// 创建播放/暂停叶子组件。
  PlayPauseComponent();

  @override
  String get name => 'playPause';

  @override
  VmSlot get slot => VmSlot.center;

  @override
  Widget build(BuildContext context, VmApi api, List<Widget> children) {
    final theme = api.options.theme;
    return VmSelector<bool>(
      selector: (s) => s.playing,
      builder: (context, playing) {
        return Material(
          type: MaterialType.circle,
          color: Colors.transparent,
          child: InkResponse(
            radius: 36,
            onTap: () => api.playOrPause(),
            child: Icon(
              playing ? Icons.pause_circle_filled_rounded : Icons.play_circle_filled_rounded,
              size: theme.centerIconSize,
              color: Color(theme.iconColor),
            ),
          ),
        );
      },
    );
  }
}
