import '../style/style.dart';

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
class MovaCenterPlayComponent extends MovaComponent {
  /// Creates the center-play composite with its single child.
  ///
  /// 创建带唯一子组件的中央播放组合组件。
  MovaCenterPlayComponent();

  /// This component's path segment for `MovaPatch` addressing.
  ///
  /// 该组件在 `MovaPatch` 寻址体系里的路径片段。
  static const String componentName = 'centerPlay';

  @override
  String get name => componentName;

  @override
  MovaSlot get slot => MovaSlot.center;

  @override
  List<MovaComponent> get children => [MovaPlayPauseComponent()];

  @override
  Widget build(BuildContext context, MovaApi api, List<Widget> children) {
    return Center(child: children[0]);
  }
}

/// Large center play/pause tap-feedback button.
///
/// Mirrors 0.1.0's `_centerPlayPause()`: an `InkResponse` circle (radius 36)
/// showing a filled play/pause glyph sized/colored from [MovaTheme], driven by
/// [MovaState.playing], calling [MovaApi.playOrPause] on tap.
///
/// 中央大号播放/暂停点按反馈按钮。
///
/// 对齐 0.1.0 的 `_centerPlayPause()`：一个半径 36 的 `InkResponse` 圆形，内含
/// 填充式播放/暂停图标（尺寸/颜色取自 [MovaTheme]），由 [MovaState.playing] 驱动，
/// 点击调用 [MovaApi.playOrPause]。
class MovaPlayPauseComponent extends MovaComponent {
  /// Creates the play/pause leaf component.
  ///
  /// 创建播放/暂停叶子组件。
  MovaPlayPauseComponent();

  /// This component's path segment for `MovaPatch` addressing.
  ///
  /// 该组件在 `MovaPatch` 寻址体系里的路径片段。
  static const String componentName = 'playPause';

  @override
  String get name => componentName;

  @override
  MovaSlot get slot => MovaSlot.center;

  @override
  Widget build(BuildContext context, MovaApi api, List<Widget> children) {
    final theme = MovaPlayerStyle.themeOf(context);
    return MovaSelect<bool>(
      selector: (s) => s.playing,
      builder: (context, playing) {
        return Semantics(
          button: true,
          label: playing
              ? MovaPlayerStyle.stringsOf(context).pause
              : MovaPlayerStyle.stringsOf(context).play,
          child: Tooltip(
            // 持久小窗位于 Overlay 外时只保留按钮语义。
            message: Overlay.maybeOf(context) == null
                ? ''
                : (playing
                      ? MovaPlayerStyle.stringsOf(context).pause
                      : MovaPlayerStyle.stringsOf(context).play),
            excludeFromSemantics: true,
            child: Material(
              type: MaterialType.circle,
              color: Colors.transparent,
              child: InkResponse(
                radius: 36,
                onTap: () => api.playOrPause(),
                child: Icon(
                  playing
                      ? MovaPlayerStyle.iconsOf(context).pause
                      : MovaPlayerStyle.iconsOf(context).play,
                  size: theme.centerIconSize,
                  color: Color(theme.iconColor),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
