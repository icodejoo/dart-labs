import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../components/center_play.dart';
import '../components/overlays.dart';
import '../scope/selector.dart';
import '../slots/component.dart';
import '../slots/slot.dart';
import '../slots/tree.dart';
import '../skins/skin.dart';

/// The minimal chrome shown inside the mini window: center play/pause,
/// a buffering spinner, and a close (✕) button — nothing else. A 180px-wide
/// box has no room for a seek bar, quality picker, or fullscreen button, and
/// [MovaMiniHost]'s own auto-hide-bar behavior would only get in the way.
///
/// Reuses [MovaSkin]'s component-tree contract unchanged — proof that new
/// skins really do cost close to nothing, exactly as the 0.3.0 plugin/skin
/// redesign intended.
///
/// 小窗内展示的极简 chrome：中央播放/暂停、缓冲转圈、一个关闭（✕）按钮——
/// 仅此而已。180px 宽的框里放不下进度条/清晰度选择/全屏按钮，`MovaDefSkin`
/// 自带的栏自动隐藏在这里反而是负担。
///
/// 原样复用 [MovaSkin] 的组件树契约——证明新皮肤确实近乎零成本，正是 0.3.0
/// 插件/皮肤改造想达成的效果。
class MovaMiniSkin implements MovaSkin {
  /// Called when the close (✕) button is tapped; `null` disables the button's
  /// effect (it still renders, but taps do nothing). `MovaMiniWindow` wires
  /// this to `MovaMiniCtl.close` when the caller leaves it unset.
  ///
  /// 关闭（✕）按钮被点击时调用；为 `null` 时按钮仍会渲染但点击无效果。
  /// 调用方未设置时，`MovaMiniWindow` 会把它接到 `MovaMiniCtl.close`。
  final VoidCallback? onClose;

  /// Creates the mini-window chrome; [onClose] defaults to `null`.
  ///
  /// 创建小窗内的 chrome；[onClose] 默认为 `null`。
  const MovaMiniSkin({this.onClose});

  @override
  List<MovaComp> components() => [
        MovaCenterPlayComponent(),
        MovaBufferingComponent(),
        MovaMiniCloseComponent(onClose: onClose),
      ];

  @override
  Widget assemble(BuildContext context, MovaSlotBundle slots, Widget video) {
    return Stack(
      children: [
        Positioned.fill(child: video),
        Stack(children: slots[MovaSlot.top]),
        Stack(children: slots[MovaSlot.center]),
      ],
    );
  }
}

/// The mini window's close (✕) button, top-right corner.
///
/// 小窗的关闭（✕）按钮，位于右上角。
class MovaMiniCloseComponent extends MovaComp {
  /// Creates the close-button leaf component.
  ///
  /// 创建关闭按钮叶子组件。
  ///
  /// - [onClose]: tap handler / 点击回调
  MovaMiniCloseComponent({this.onClose});

  /// Tap handler; a no-op button when `null`.
  ///
  /// 点击回调；为 `null` 时按钮不产生效果。
  final VoidCallback? onClose;

  @override
  String get name => 'miniClose';

  @override
  MovaSlot get slot => MovaSlot.top;

  @override
  Widget build(BuildContext context, MovaApi api, List<Widget> children) {
    return Align(
      alignment: Alignment.topRight,
      child: MovaSelect<bool>(
        // Any state field works as a trigger to keep this a proper
        // MovaSelect-driven leaf; it does not actually vary by state.
        //
        // 用任意状态字段驱动即可保持这是一个规范的 MovaSelect 叶子组件；
        // 其外观本身并不随状态变化。
        selector: (s) => s.mini,
        builder: (context, _) => IconButton(
          icon: const Icon(Icons.close, color: Colors.white, size: 18),
          onPressed: onClose,
          padding: const EdgeInsets.all(4),
          constraints: const BoxConstraints(),
        ),
      ),
    );
  }
}
