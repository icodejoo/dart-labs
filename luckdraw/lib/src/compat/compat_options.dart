import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../core/motion/stop_solver.dart';
import '../core/motion/timebase.dart';

/// 上游默认的根字号，单位为逻辑像素。
const double kCompatRemBase = 16;

/// lucky-canvas 迁移选项；例如 const LuckyCanvasCompatOptions(remBase: 20)。
@immutable
final class LuckyCanvasCompatOptions {
  /// 创建迁移选项；默认使用有效时间与单调停止求解。
  const LuckyCanvasCompatOptions({
    this.remBase = kCompatRemBase,
    this.viewportWidth,
    this.handleCssUnit,
    this.timebase = LuckyTimebase.time,
    this.stopSolver = const MonotonicStopSolver(),
    this.honorSpeedFunction = false,
    this.honorDisabled = false,
    this.assetResolver,
  });

  /// 创建逐帧上游预设；[remBase] 默认 16，[handleCssUnit] 处理未知单位。
  factory LuckyCanvasCompatOptions.strictUpstream({
    double remBase = kCompatRemBase,
    double? viewportWidth,
    double Function(double value, String unit)? handleCssUnit,
  }) =>
      LuckyCanvasCompatOptions(
        remBase: remBase,
        viewportWidth: viewportWidth,
        handleCssUnit: handleCssUnit,
        timebase: LuckyTimebase.frame,
        stopSolver: const UpstreamStopSolver(),
      );

  /// rem 的根字号基准。
  final double remBase;

  /// vw 的视口宽度；缺失时解析器警告并保留数字。
  final double? viewportWidth;

  /// 未知单位回调，返回逻辑像素。
  final double Function(double value, String unit)? handleCssUnit;

  /// 动画时间基准。
  final LuckyTimebase timebase;

  /// 停止求解策略。
  final LuckyStopSolver stopSolver;

  /// 是否采用上游声明但默认未使用的速度函数。
  final bool honorSpeedFunction;

  /// 是否尊重奖品禁用标记。
  final bool honorDisabled;

  /// 资源路径解析器；未设置时使用 AssetImage。
  final ImageProvider<Object> Function(String src)? assetResolver;

  /// 返回替换非 null 参数的副本；例如 options.copyWith(remBase: 24)。
  LuckyCanvasCompatOptions copyWith({
    double? remBase,
    double? viewportWidth,
    double Function(double value, String unit)? handleCssUnit,
    LuckyTimebase? timebase,
    LuckyStopSolver? stopSolver,
    bool? honorSpeedFunction,
    bool? honorDisabled,
    ImageProvider<Object> Function(String src)? assetResolver,
  }) =>
      LuckyCanvasCompatOptions(
        remBase: remBase ?? this.remBase,
        viewportWidth: viewportWidth ?? this.viewportWidth,
        handleCssUnit: handleCssUnit ?? this.handleCssUnit,
        timebase: timebase ?? this.timebase,
        stopSolver: stopSolver ?? this.stopSolver,
        honorSpeedFunction: honorSpeedFunction ?? this.honorSpeedFunction,
        honorDisabled: honorDisabled ?? this.honorDisabled,
        assetResolver: assetResolver ?? this.assetResolver,
      );

  /// 按全部迁移选项比较。
  @override
  bool operator ==(Object other) =>
      other is LuckyCanvasCompatOptions &&
      remBase == other.remBase &&
      viewportWidth == other.viewportWidth &&
      handleCssUnit == other.handleCssUnit &&
      timebase == other.timebase &&
      stopSolver == other.stopSolver &&
      honorSpeedFunction == other.honorSpeedFunction &&
      honorDisabled == other.honorDisabled &&
      assetResolver == other.assetResolver;

  /// 与选项相等性一致的哈希。
  @override
  int get hashCode => Object.hash(remBase, viewportWidth, handleCssUnit,
      timebase, stopSolver, honorSpeedFunction, honorDisabled, assetResolver);
}

/// 带诊断的迁移结果；警告列表须由调用方保持不可变。
@immutable
final class LuckyCanvasCompatResult<C> {
  /// 创建结果；[width] 和 [height] 缺省时由父布局决定尺寸。
  const LuckyCanvasCompatResult(
      {required this.config,
      this.width,
      this.height,
      this.warnings = const []});

  /// 类型化配置。
  final C config;

  /// 可选逻辑宽度。
  final double? width;

  /// 可选逻辑高度。
  final double? height;

  /// 转换警告，按发现顺序排列。
  final List<LuckyCanvasCompatWarning> warnings;

  /// 返回替换非 null 参数的结果副本。
  LuckyCanvasCompatResult<C> copyWith(
          {C? config,
          double? width,
          double? height,
          List<LuckyCanvasCompatWarning>? warnings}) =>
      LuckyCanvasCompatResult(
          config: config ?? this.config,
          width: width ?? this.width,
          height: height ?? this.height,
          warnings: warnings ?? this.warnings);

  /// 比较配置、尺寸和警告内容。
  @override
  bool operator ==(Object other) =>
      other is LuckyCanvasCompatResult<C> &&
      config == other.config &&
      width == other.width &&
      height == other.height &&
      listEquals(warnings, other.warnings);

  /// 与结果相等性一致的哈希。
  @override
  int get hashCode =>
      Object.hash(config, width, height, Object.hashAll(warnings));
}

/// 迁移诊断；[path] 使用 `prizes[2].fonts[0].fontSize` 形式的字段路径。
@immutable
final class LuckyCanvasCompatWarning {
  /// 创建指定字段路径和中文说明的警告。
  const LuckyCanvasCompatWarning(this.path, this.message);

  /// 上游配置字段路径。
  final String path;

  /// 可读的警告原因。
  final String message;

  /// 返回替换非 null 参数的警告副本。
  LuckyCanvasCompatWarning copyWith({String? path, String? message}) =>
      LuckyCanvasCompatWarning(path ?? this.path, message ?? this.message);

  /// 按路径与原因比较警告。
  @override
  bool operator ==(Object other) =>
      other is LuckyCanvasCompatWarning &&
      path == other.path &&
      message == other.message;

  /// 与警告相等性一致的哈希。
  @override
  int get hashCode => Object.hash(path, message);

  /// 返回包含路径与原因的诊断文本。
  @override
  String toString() => '$path: $message';
}
