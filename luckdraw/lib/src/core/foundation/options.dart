import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'constants.dart';

/// 静态段的缓存模式。
enum LuckyCacheMode {
  /// 使用矢量 Picture 回放。
  picture,

  /// 使用受最大边长约束的位图。
  raster,

  /// 运动时使用受限位图，静止时回放矢量；不支持位图的段保持矢量。
  auto,
}

/// 文字的系统缩放策略。
enum LuckyTextScaling {
  /// 使用配置字号，不跟随系统缩放。
  none,

  /// 跟随宿主的系统文字缩放。
  system,
}

/// 静态绘制缓存与不可见时暂停策略。
///
/// 例如 `const LuckyPerformanceOptions(cacheMode: LuckyCacheMode.raster)` 使用位图缓存。
@immutable
final class LuckyPerformanceOptions {
  /// 创建配置，未指定的可选字段使用声明的默认值。
  ///
  /// 实验性（可能调整）：[maxRasterBytes] 限制共享纹理占用，0 禁用 raster。
  const LuckyPerformanceOptions(
      {this.cacheMode = LuckyCacheMode.auto,
      this.maxRasterSide = kLuckyDefaultMaxRasterSide,
      this.maxRasterBytes = kLuckyDefaultMaxRasterBytes,
      this.pauseWhenHidden = true,
      this.filterQuality = FilterQuality.low});

  /// 静态段缓存模式。
  final LuckyCacheMode cacheMode;

  /// 位图缓存单边最大设备像素。
  final int maxRasterSide;

  /// 实验性（可能调整）：本 surface 允许的共享 raster 字节上限，0 禁用 raster。
  ///
  /// 默认 32 MiB；E2 实测 52 MiB 内平稳、104 MiB 掉帧，结果与设备相关。
  /// 仅当共享已用量加新纹理不超过此值才创建；可按设备调大，例如传入 `64 * 1024 * 1024`。
  final int maxRasterBytes;

  /// 不可见时是否暂停动画。
  final bool pauseWhenHidden;

  /// 图片和位图缓存的采样质量。
  final FilterQuality filterQuality;

  /// 返回只替换指定字段的副本；参数为 null 时保留原值。
  ///
  /// 例如 `options.copyWith(pauseWhenHidden: false)` 禁用不可见时暂停。
  /// 实验性（可能调整）：[maxRasterBytes] 覆盖共享字节上限，0 禁用 raster。
  LuckyPerformanceOptions copyWith(
          {LuckyCacheMode? cacheMode,
          int? maxRasterSide,
          int? maxRasterBytes,
          bool? pauseWhenHidden,
          FilterQuality? filterQuality}) =>
      LuckyPerformanceOptions(
          cacheMode: cacheMode ?? this.cacheMode,
          maxRasterSide: maxRasterSide ?? this.maxRasterSide,
          maxRasterBytes: maxRasterBytes ?? this.maxRasterBytes,
          pauseWhenHidden: pauseWhenHidden ?? this.pauseWhenHidden,
          filterQuality: filterQuality ?? this.filterQuality);

  /// 按缓存模式、边长、共享字节预算、暂停策略和采样质量比较配置。
  @override
  bool operator ==(Object other) =>
      other is LuckyPerformanceOptions &&
      other.cacheMode == cacheMode &&
      other.maxRasterSide == maxRasterSide &&
      other.maxRasterBytes == maxRasterBytes &&
      other.pauseWhenHidden == pauseWhenHidden &&
      other.filterQuality == filterQuality;

  /// 与字段值相等性一致的哈希值。
  @override
  int get hashCode => Object.hash(
      cacheMode, maxRasterSide, maxRasterBytes, pauseWhenHidden, filterQuality);
}
