import 'package:flutter/widgets.dart';

import '../core/standby/standby.dart';
import 'scope/selector.dart';

/// The poster layer [MovaPlayer] paints over the video surface: fully opaque
/// until the current source has a rendered frame with a known picture size,
/// then faded out. Re-covering is instant, so a source change never flashes
/// the previous picture. Taps pass through.
///
/// [MovaPlayer] 盖在视频画面上的封面层：当前源出了首帧且画面尺寸已知之前完全
/// 不透明，之后淡出。重新盖上是瞬间完成的，所以换源不会闪出上一条的画面。点击
/// 会穿透。
class MovaPosterLayer extends StatelessWidget {
  /// Creates the layer.
  ///
  /// 创建封面层。
  ///
  /// - [poster]: the cover widget / 封面组件
  /// - [fade]: fade-out duration / 淡出时长
  const MovaPosterLayer({super.key, required this.poster, required this.fade});

  /// The cover widget.
  ///
  /// 封面组件。
  final Widget poster;

  /// How long the fade-out takes.
  ///
  /// 淡出时长。
  final Duration fade;

  @override
  Widget build(BuildContext context) {
    return MovaSelect<bool>(
      selector: (s) =>
          !(s.rendered && s.width > 0 && s.height > 0) ||
          s.standby == MovaStandbyPhase.holding ||
          s.standby == MovaStandbyPhase.resuming,
      builder: (context, shown) => IgnorePointer(
        child: AnimatedOpacity(
          opacity: shown ? 1 : 0,
          duration: shown ? Duration.zero : fade,
          child: poster,
        ),
      ),
    );
  }
}
