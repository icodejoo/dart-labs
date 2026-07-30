// Platform capability ports: abstract interfaces the core layer depends on
// for screen brightness, picture-in-picture, and orientation control, plus
// zero-dependency fallback/noop implementations. Real implementations live
// under `lib/src/platform_impl/` and may import flutter/plugin packages;
// this file must stay free of any flutter/media_kit imports.
//
// 平台能力端口：core 层依赖的抽象接口（屏幕亮度、画中画、方向控制），以及零
// 依赖的兜底/空实现。真实实现放在 `lib/src/platform_impl/`，可以引入
// flutter/插件包；本文件必须保持不引入任何 flutter/media_kit 依赖。

/// A port for reading and writing the device/app screen brightness.
///
/// 读写设备/应用屏幕亮度的端口。
abstract class VmBrightnessPort {
  /// Reads the current brightness as a value in `[0.0, 1.0]`.
  ///
  /// 读取当前亮度，取值范围 `[0.0, 1.0]`。
  ///
  /// Returns the current brightness level.
  ///
  /// 返回当前亮度值。
  Future<double> get();

  /// Sets the brightness to [value], a value in `[0.0, 1.0]`.
  ///
  /// 将亮度设置为 [value]，取值范围 `[0.0, 1.0]`。
  ///
  /// - [value]: the target brightness level / 目标亮度值
  Future<void> set(double value);
}

/// A port for entering system picture-in-picture mode.
///
/// 进入系统画中画模式的端口。
abstract class VmPipPort {
  /// Whether the current platform supports PiP.
  ///
  /// 当前平台是否支持画中画。
  ///
  /// Returns whether PiP is supported.
  ///
  /// 返回是否支持画中画。
  Future<bool> isSupported();

  /// Requests entering PiP with an optional aspect-ratio hint.
  ///
  /// 请求进入画中画，可选传入宽高比提示。
  ///
  /// - [width], [height]: optional aspect-ratio hint / 可选的宽高比提示
  ///
  /// Returns whether PiP was successfully entered.
  ///
  /// 返回是否成功进入画中画。
  Future<bool> enter({int? width, int? height});
}

/// A port for applying and resetting fullscreen/immersive orientation and
/// system UI state.
///
/// 应用与重置全屏/沉浸式方向与系统 UI 状态的端口。
abstract class VmOrientationPort {
  /// Applies the orientation/immersive/system-UI state for the given mode.
  ///
  /// 按给定模式应用方向/沉浸式/系统 UI 状态。
  ///
  /// - [fullscreen]: whether fullscreen is active / 是否处于全屏
  /// - [immersive]: whether immersive (edge-to-edge) UI is active /
  ///   是否处于沉浸式（沉浸边到边）UI
  /// - [width], [height]: video pixel dimensions used to pick orientation /
  ///   用于选择方向的视频像素宽高
  Future<void> apply({
    required bool fullscreen,
    required bool immersive,
    required int width,
    required int height,
  });

  /// Resets orientation/system UI back to the default (portrait, edge-to-edge
  /// restored, all orientations allowed).
  ///
  /// 将方向/系统 UI 重置为默认状态（竖屏、恢复边到边、允许全部方向）。
  Future<void> reset();
}

/// A zero-dependency [VmBrightnessPort] fallback that always reports full
/// brightness and silently ignores writes.
///
/// 零依赖的 [VmBrightnessPort] 兜底实现：始终报告最大亮度，写入操作静默忽略。
class FallbackBrightnessPort implements VmBrightnessPort {
  @override
  Future<double> get() => Future.value(1.0);

  @override
  Future<void> set(double value) => Future.value();
}

/// A zero-dependency [VmPipPort] no-op that reports PiP as unsupported.
///
/// 零依赖的 [VmPipPort] 空实现：始终报告不支持画中画。
class NoopPipPort implements VmPipPort {
  @override
  Future<bool> isSupported() => Future.value(false);

  @override
  Future<bool> enter({int? width, int? height}) => Future.value(false);
}

/// A zero-dependency [VmOrientationPort] no-op that does nothing.
///
/// 零依赖的 [VmOrientationPort] 空实现：不执行任何操作。
class NoopOrientationPort implements VmOrientationPort {
  @override
  Future<void> apply({
    required bool fullscreen,
    required bool immersive,
    required int width,
    required int height,
  }) =>
      Future.value();

  @override
  Future<void> reset() => Future.value();
}
