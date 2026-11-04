import 'package:flutter/material.dart';

import '../../core/options/options.dart';
import '../scope/scope.dart';

/// 播放器视图的样式；各节整体替换、独立回落。
/// 优先级：视图参数 > ThemeExtension > 旧 options > 默认值。
/// 切换主题只更新视图，不重建引擎。
/// 示例：`MovaPlayerStyle(strings: MovaStrs(live: 'ON AIR'))`。
@immutable
class MovaPlayerStyle extends ThemeExtension<MovaPlayerStyle> {
  /// 创建样式；未指定的节沿查找链回落。
  const MovaPlayerStyle({
    this.theme,
    this.strings,
    this.gesture,
    this.controls,
    this.danmaku,
  });

  /// 颜色与字号；null 时回落。
  final MovaTheme? theme;

  /// 界面文案；null 时回落。
  final MovaStrs? strings;

  /// 手势映射与灵敏度；null 时回落。
  final MovaGestureConfig? gesture;

  /// 控制条行为；null 时回落。
  final MovaCtrlsConfig? controls;

  /// 弹幕展示样式；null 时回落。
  final MovaDanmakuStyle? danmaku;

  /// 返回当前视图生效的颜色与字号；在构建或事件回调中调用。
  static MovaTheme themeOf(BuildContext context) =>
      _pick(context, (s) => s.theme) ?? movaLegacyOptionsOf(context).theme;

  /// 返回当前视图生效的界面文案；在构建或事件回调中调用。
  static MovaStrs stringsOf(BuildContext context) =>
      _pick(context, (s) => s.strings) ?? movaLegacyOptionsOf(context).strings;

  /// 返回当前视图生效的手势映射与灵敏度；在构建或事件回调中调用。
  static MovaGestureConfig gestureOf(BuildContext context) =>
      _pick(context, (s) => s.gesture) ?? movaLegacyOptionsOf(context).gesture;

  /// 返回当前视图生效的控制条行为；在构建或事件回调中调用。
  static MovaCtrlsConfig controlsOf(BuildContext context) =>
      _pick(context, (s) => s.controls) ??
      movaLegacyOptionsOf(context).controls;

  /// 返回当前视图生效的弹幕展示样式；在构建或事件回调中调用。
  static MovaDanmakuStyle danmakuOf(BuildContext context) =>
      _pick(context, (s) => s.danmaku) ??
      MovaDanmakuStyle.fromConfig(movaLegacyOptionsOf(context).danmaku);

  /// 返回替换指定节的拷贝；未指定的节保留。
  @override
  MovaPlayerStyle copyWith({
    MovaTheme? theme,
    MovaStrs? strings,
    MovaGestureConfig? gesture,
    MovaCtrlsConfig? controls,
    MovaDanmakuStyle? danmaku,
  }) => MovaPlayerStyle(
    theme: theme ?? this.theme,
    strings: strings ?? this.strings,
    gesture: gesture ?? this.gesture,
    controls: controls ?? this.controls,
    danmaku: danmaku ?? this.danmaku,
  );

  /// 离散切换；t 小于 0.5 或 other 为 null 时返回自身。
  @override
  MovaPlayerStyle lerp(covariant MovaPlayerStyle? other, double t) =>
      other != null && t >= 0.5 ? other : this;
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MovaPlayerStyle &&
          theme == other.theme &&
          strings == other.strings &&
          gesture == other.gesture &&
          controls == other.controls &&
          danmaku == other.danmaku;
  @override
  int get hashCode => Object.hash(theme, strings, gesture, controls, danmaku);
}

/// 弹幕展示样式；开关与条目仍来自旧配置。
@immutable
class MovaDanmakuStyle {
  /// 创建展示样式；默认值与旧弹幕配置一致。
  const MovaDanmakuStyle({
    this.trackCount = 4,
    this.trackHeight = 28.0,
    this.fontSize = 14.0,
    this.opacity = 0.9,
    this.crossDuration = const Duration(seconds: 8),
  }) : assert(trackCount > 0);

  /// 轨道数，必须大于零。
  final int trackCount;

  /// 每条轨道高度。
  final double trackHeight;

  /// 文字字号。
  final double fontSize;

  /// 整体透明度。
  final double opacity;

  /// 划过屏幕的时长。
  final Duration crossDuration;

  /// 从旧配置提取五个展示字段。
  factory MovaDanmakuStyle.fromConfig(MovaDanmakuConfig config) =>
      MovaDanmakuStyle(
        trackCount: config.trackCount,
        trackHeight: config.trackHeight,
        fontSize: config.fontSize,
        opacity: config.opacity,
        crossDuration: config.crossDuration,
      );

  /// 覆盖 data 的展示字段，保留开关与条目引用。
  MovaDanmakuConfig applyTo(MovaDanmakuConfig data) => data.copyWith(
    trackCount: trackCount,
    trackHeight: trackHeight,
    fontSize: fontSize,
    opacity: opacity,
    crossDuration: crossDuration,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MovaDanmakuStyle &&
          trackCount == other.trackCount &&
          trackHeight == other.trackHeight &&
          fontSize == other.fontSize &&
          opacity == other.opacity &&
          crossDuration == other.crossDuration;
  @override
  int get hashCode =>
      Object.hash(trackCount, trackHeight, fontSize, opacity, crossDuration);
}

/// 包内：下发当前视图样式与旧配置。
class MovaStyleScope extends InheritedWidget {
  const MovaStyleScope({
    super.key,
    this.local,
    this.legacy,
    required super.child,
  });
  final MovaPlayerStyle? local;
  final MovaOpts? legacy;
  static MovaStyleScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MovaStyleScope>();
  @override
  bool updateShouldNotify(MovaStyleScope oldWidget) =>
      local != oldWidget.local || legacy != oldWidget.legacy;
}

T? _pick<T>(BuildContext context, T? Function(MovaPlayerStyle) field) {
  final local = MovaStyleScope.maybeOf(context)?.local;
  final themed = Theme.of(context).extension<MovaPlayerStyle>();
  return (local == null ? null : field(local)) ??
      (themed == null ? null : field(themed));
}

/// 包内：视图提供的旧配置优先，否则读取当前 API，最后使用默认值。
MovaOpts movaLegacyOptionsOf(BuildContext context) =>
    MovaStyleScope.maybeOf(context)?.legacy ??
    context.dependOnInheritedWidgetOfExactType<MovaScope>()?.api.options ??
    const MovaOpts();

/// 包内：供位于自身作用域之外的播放器解析控制条配置。
MovaCtrlsConfig movaResolveControls(
  BuildContext context,
  MovaPlayerStyle? local,
  MovaOpts fallback,
) =>
    local?.controls ??
    Theme.of(context).extension<MovaPlayerStyle>()?.controls ??
    MovaStyleScope.maybeOf(context)?.legacy?.controls ??
    fallback.controls;
