import 'package:flutter/widgets.dart';

import '../components/overlays.dart';
import '../slots/component.dart';
import '../slots/slot.dart';
import '../slots/tree.dart';
import 'skin.dart';

/// A chrome-free skin: just the picture plus an optional buffering spinner
/// (and optionally the error overlay). No gesture layer, no bars — taps fall
/// through to whatever wraps the player. For preview cards, live tiles and
/// backgrounds.
///
/// 无 chrome 的皮肤：只有画面加可选的缓冲转圈（以及可选的错误层）。不挂手势层、
/// 不挂任何栏——点击会落到包住播放器的外层组件上。适用于预览卡片、直播小窗格、
/// 背景视频。
///
/// Example / 示例:
/// ```dart
/// MovaPlayer(
///   api: engine,
///   skin: const MovaMinimalSkin(),
/// )
/// // spinner style comes from MovaOpts.theme / 转圈样式来自 MovaOpts.theme:
/// createMovaEngine(options: const MovaOpts(
///   theme: MovaTheme(bufferingSize: 24, bufferingStrokeWidth: 2, bufferingColor: 0xFFFFFFFF),
/// ));
/// ```
class MovaMinimalSkin implements MovaSkin {
  /// Creates the skin.
  ///
  /// 创建皮肤。
  ///
  /// - [showBuffering]: show the spinner while buffering, default true / 缓冲时显示转圈，默认 true
  /// - [showError]: show the error overlay with its retry button, default false / 显示带重试按钮的错误层，默认 false
  const MovaMinimalSkin({this.showBuffering = true, this.showError = false});

  /// Whether the buffering spinner is part of the tree.
  ///
  /// 缓冲转圈是否进入组件树。
  final bool showBuffering;

  /// Whether the error overlay is part of the tree.
  ///
  /// 错误层是否进入组件树。
  final bool showError;

  @override
  List<MovaComponent> components() => [
        if (showBuffering) MovaBufferingComponent(),
        if (showError) MovaErrorComponent(),
      ];

  @override
  Widget assemble(BuildContext context, MovaSlotBundle slots, Widget video) => Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(child: video),
          Positioned.fill(child: Stack(children: slots[MovaSlot.center])),
        ],
      );
}
