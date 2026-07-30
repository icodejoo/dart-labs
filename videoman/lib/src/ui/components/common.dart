import 'package:flutter/material.dart';

import '../../core/options/theme.dart';

/// A compact themed icon button used across the control bars.
///
/// Presentation-only and reusable: it never reads VmApi itself, only the
/// [VmTheme] it is given — the calling component is responsible for reading
/// `api.options.theme` and passing it down.
///
/// 控制条中通用的带主题小图标按钮。
///
/// 仅负责展示、可复用：它自身从不读取 VmApi，只使用传入的 [VmTheme]——由
/// 调用方组件负责读取 `api.options.theme` 并向下传递。
class VmIconButton extends StatelessWidget {
  /// The glyph to show.
  ///
  /// 要显示的图标。
  final IconData icon;

  /// Tap handler; disabled when null.
  ///
  /// 点击回调；为 null 时禁用。
  final VoidCallback? onPressed;

  /// Optional short caption under the icon (e.g. fit-mode label).
  ///
  /// 图标下方可选的短文字（如填充模式标签）。
  final String? caption;

  /// The theme supplying icon/text colors and caption font size.
  ///
  /// 提供图标/文字颜色及说明文字字号的主题。
  final VmTheme theme;

  /// Creates a themed icon button.
  ///
  /// 创建一个带主题的图标按钮。
  const VmIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    required this.theme,
    this.caption,
  });

  @override
  Widget build(BuildContext context) {
    // Uses a plain GestureDetector rather than InkResponse/InkWell: those
    // require a Material ancestor, which the player overlay (composed via
    // VmScope/component tree, not a Scaffold) does not always provide.
    //
    // 用普通 GestureDetector 而非 InkResponse/InkWell：后者需要 Material
    // 祖先节点，而播放器叠加层（经 VmScope/组件树组合，并非 Scaffold）不一定
    // 提供这个祖先。
    return GestureDetector(
      onTap: onPressed,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Color(theme.iconColor), size: 22),
            if (caption != null)
              Text(
                caption!,
                style: TextStyle(color: Color(theme.textColor), fontSize: theme.captionFontSize),
              ),
          ],
        ),
      ),
    );
  }
}

/// A translucent top/bottom gradient bar host that does not absorb pointer
/// events on its empty regions (so center gestures fall through).
///
/// Presentation-only and reusable: it never reads VmApi itself, only the
/// [VmTheme] it is given.
///
/// 半透明的顶/底渐变条容器；空白区域不吞点击事件（让中间手势穿透）。
///
/// 仅负责展示、可复用：它自身从不读取 VmApi，只使用传入的 [VmTheme]。
class VmGradientBar extends StatelessWidget {
  /// Whether this is the top bar (gradient points downward) or bottom.
  ///
  /// 是否为顶部条（渐变向下）；否则为底部条。
  final bool top;

  /// Bar content (buttons, slider, labels).
  ///
  /// 条内内容（按钮、滑块、文字）。
  final Widget child;

  /// The theme supplying the gradient color.
  ///
  /// 提供渐变颜色的主题。
  final VmTheme theme;

  /// Creates a themed gradient bar.
  ///
  /// 创建一个带主题的渐变条。
  const VmGradientBar({super.key, required this.top, required this.child, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: top ? Alignment.topCenter : Alignment.bottomCenter,
          end: top ? Alignment.bottomCenter : Alignment.topCenter,
          colors: [Color(theme.barGradientColor), const Color(0x00000000)],
        ),
      ),
      child: SafeArea(top: top, bottom: !top, child: child),
    );
  }
}

