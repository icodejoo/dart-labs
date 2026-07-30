import 'package:flutter/material.dart';

/// Formats a duration as mm:ss (or h:mm:ss when an hour or longer).
///
/// 将时长格式化为 mm:ss（满一小时用 h:mm:ss）。
///
/// - [d]: the duration to format / 待格式化的时长
/// - returns the formatted string / 返回格式化后的字符串
///
/// Example / 示例:
/// ```dart
/// formatDuration(const Duration(seconds: 75)); // '01:15'
/// ```
String formatDuration(Duration d) {
  final neg = d.isNegative;
  final a = d.abs();
  final h = a.inHours;
  final m = a.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = a.inSeconds.remainder(60).toString().padLeft(2, '0');
  final body = h > 0 ? '$h:$m:$s' : '$m:$s';
  return neg ? '-$body' : body;
}

/// A compact white icon button used across the control bars.
///
/// 控制条中通用的白色小图标按钮。
class ControlIconButton extends StatelessWidget {
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

  /// Creates a control icon button.
  ///
  /// 创建一个控制图标按钮。
  const ControlIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.caption,
  });

  @override
  Widget build(BuildContext context) {
    return InkResponse(
      onTap: onPressed,
      radius: 22,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 22),
            if (caption != null)
              Text(caption!, style: const TextStyle(color: Colors.white, fontSize: 10)),
          ],
        ),
      ),
    );
  }
}

/// A translucent top/bottom gradient bar host that does not absorb pointer
/// events on its empty regions (so center gestures fall through).
///
/// 半透明的顶/底渐变条容器；空白区域不吞点击事件（让中间手势穿透）。
class ControlGradientBar extends StatelessWidget {
  /// Whether this is the top bar (gradient points downward) or bottom.
  ///
  /// 是否为顶部条（渐变向下）；否则为底部条。
  final bool top;

  /// Bar content (buttons, slider, labels).
  ///
  /// 条内内容（按钮、滑块、文字）。
  final Widget child;

  /// Creates a gradient bar.
  ///
  /// 创建一个渐变条。
  const ControlGradientBar({super.key, required this.top, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: top ? Alignment.topCenter : Alignment.bottomCenter,
          end: top ? Alignment.bottomCenter : Alignment.topCenter,
          colors: const [Color(0x99000000), Color(0x00000000)],
        ),
      ),
      child: SafeArea(top: top, bottom: !top, child: child),
    );
  }
}
