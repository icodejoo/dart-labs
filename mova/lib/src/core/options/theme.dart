/// Externalised visual theme for the player overlay.
///
/// Colors are stored as raw ARGB `int` (not `package:flutter/material.dart`'s
/// `Color`) so that `lib/src/core/**` stays free of any Flutter import; the
/// `ui/` layer converts these ints to `Color` at the point of use.
///
/// 播放器覆盖层的外置视觉主题。
///
/// 颜色以原始 ARGB `int` 存储（而非 `package:flutter/material.dart` 的
/// `Color`），以保证 `lib/src/core/**` 不引入任何 Flutter 依赖；`ui/` 层在
/// 使用处再把这些 int 转换为 `Color`。
class MovaTheme {
  /// ARGB color for icons.
  ///
  /// 图标的 ARGB 颜色。
  final int iconColor;

  /// ARGB color for text.
  ///
  /// 文字的 ARGB 颜色。
  final int textColor;

  /// ARGB color for accented elements (e.g. active progress, live badge).
  ///
  /// 强调元素（如进度条高亮、直播角标）的 ARGB 颜色。
  final int accentColor;

  /// ARGB color for the badge while the live stream is time-shifted (i.e. not
  /// at the live edge).
  ///
  /// 直播处于时移状态（即不在直播边缘）时角标的 ARGB 颜色。
  final int timeshiftBadgeColor;

  /// ARGB color for the top/bottom gradient behind the control bars.
  ///
  /// 控制条上下渐变背景的 ARGB 颜色。
  final int barGradientColor;

  /// Font size for the title text.
  ///
  /// 标题文字的字号。
  final double titleFontSize;

  /// Font size for time labels (elapsed/duration).
  ///
  /// 时间标签（已播放/总时长）的字号。
  final double timeFontSize;

  /// Font size for small captions (e.g. fit-mode toast).
  ///
  /// 小号说明文字（如观看模式提示）的字号。
  final double captionFontSize;

  /// Font size for the live badge text.
  ///
  /// 直播角标文字的字号。
  final double badgeFontSize;

  /// Size of the large center icon (e.g. play/pause tap feedback).
  ///
  /// 中央大图标（如播放/暂停点按反馈）的尺寸。
  final double centerIconSize;

  /// Height of the progress bar track.
  ///
  /// 进度条轨道的高度。
  final double progressHeight;

  /// ARGB color for modal sheet backgrounds (e.g. the quality picker).
  ///
  /// 弹层（如清晰度选择器）背景的 ARGB 颜色。
  final int sheetBackgroundColor;

  /// Creates a theme; defaults to the product's white-on-dark, red-accent
  /// look.
  ///
  /// 创建主题；默认使用产品的深色背景白字、红色强调配色。
  const MovaTheme({
    this.iconColor = 0xFFFFFFFF,
    this.textColor = 0xFFFFFFFF,
    this.accentColor = 0xFFE53935,
    this.timeshiftBadgeColor = 0xFF616161,
    this.barGradientColor = 0x99000000,
    this.titleFontSize = 14.0,
    this.timeFontSize = 12.0,
    this.captionFontSize = 10.0,
    this.badgeFontSize = 11.0,
    this.centerIconSize = 64.0,
    this.progressHeight = 2.0,
    this.sheetBackgroundColor = 0xEE1A1A1A,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MovaTheme &&
          runtimeType == other.runtimeType &&
          iconColor == other.iconColor &&
          textColor == other.textColor &&
          accentColor == other.accentColor &&
          timeshiftBadgeColor == other.timeshiftBadgeColor &&
          barGradientColor == other.barGradientColor &&
          titleFontSize == other.titleFontSize &&
          timeFontSize == other.timeFontSize &&
          captionFontSize == other.captionFontSize &&
          badgeFontSize == other.badgeFontSize &&
          centerIconSize == other.centerIconSize &&
          progressHeight == other.progressHeight &&
          sheetBackgroundColor == other.sheetBackgroundColor;

  @override
  int get hashCode => Object.hash(
        iconColor,
        textColor,
        accentColor,
        timeshiftBadgeColor,
        barGradientColor,
        titleFontSize,
        timeFontSize,
        captionFontSize,
        badgeFontSize,
        centerIconSize,
        progressHeight,
        sheetBackgroundColor,
      );
}
