// Platform capability ports: abstract interfaces the core layer depends on
// for screen brightness, picture-in-picture, and orientation control, plus
// zero-dependency fallback/noop implementations. Real implementations live
// under `lib/src/platform_impl/` and may import flutter/plugin packages;
// this file must stay free of any flutter/media_kit imports.
//
// 平台能力端口：core 层依赖的抽象接口（屏幕亮度、画中画、方向控制），以及零
// 依赖的兜底/空实现。真实实现放在 `lib/src/platform_impl/`，可以引入
// flutter/插件包；本文件必须保持不引入任何 flutter/media_kit 依赖。

import '../model/orientation.dart';

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

/// A port for reading and writing the device's system media volume, as a
/// percentage in `[0, 100]`.
///
/// This is the injection point for "who owns volume". When one is wired
/// (e.g. by `createVmEngine` on Android, or by a host passing its own), the
/// volume gesture routes the target percent here instead of touching the
/// player's own volume — so the gesture drives the real system volume and the
/// video stays at full player volume. A host that wants full control can pass
/// a [CallbackVolumePort] and apply the percent however it likes.
///
/// 读写设备系统媒体音量的端口，取值为 `[0, 100]` 的百分比。
///
/// 这是"音量归谁管"的注入点。接上端口后（如 Android 上由 `createVmEngine`
/// 接上，或由宿主自带），音量手势会把目标百分比交给这里，而不去动播放器
/// 自身音量——于是手势驱动的是真实系统音量，视频保持播放器满音量。宿主想
/// 完全接管，可传 [CallbackVolumePort] 自行处置百分比。
abstract class VmVolumePort {
  /// Reads the current volume as a percentage in `[0, 100]`.
  ///
  /// 读取当前音量，取值为 `[0, 100]` 的百分比。
  ///
  /// Returns the current volume percentage.
  ///
  /// 返回当前音量百分比。
  Future<double> get();

  /// Sets the volume to [percent], a value in `[0, 100]`.
  ///
  /// 将音量设置为 [percent]，取值为 `[0, 100]`。
  ///
  /// - [percent]: the target volume percentage / 目标音量百分比
  Future<void> set(double percent);
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
  /// - [width], [height]: video pixel dimensions used to pick orientation when
  ///   [orientation] is [VmOrientation.auto] / 当 [orientation] 为
  ///   [VmOrientation.auto] 时用于选择方向的视频像素宽高
  /// - [orientation]: forced-orientation override; [VmOrientation.auto] keeps
  ///   the aspect-ratio/fullscreen-derived behavior / 强制方向覆盖；
  ///   [VmOrientation.auto] 保持按宽高比/全屏推导的行为
  Future<void> apply({
    required bool fullscreen,
    required bool immersive,
    required int width,
    required int height,
    required VmOrientation orientation,
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

/// A zero-dependency [VmVolumePort] fallback that reports full volume and
/// silently ignores writes.
///
/// 零依赖的 [VmVolumePort] 兜底实现：始终报告满音量，写入操作静默忽略。
class FallbackVolumePort implements VmVolumePort {
  @override
  Future<double> get() => Future.value(100);

  @override
  Future<void> set(double percent) => Future.value();
}

/// A [VmVolumePort] adapter that forwards writes to a plain callback, so a
/// host can control volume without implementing the full interface.
///
/// Pass `createVmEngine(volume: CallbackVolumePort((percent) => ...))` to take
/// over volume entirely: the video keeps full player volume while your
/// callback applies [percent] (e.g. to the OS media volume). Supply [onGet] if
/// you can report the current level back; otherwise the gesture baseline
/// starts from 100.
///
/// 把写入转发给一个普通回调的 [VmVolumePort] 适配器，宿主无需实现整个接口即可
/// 接管音量。
///
/// 传 `createVmEngine(volume: CallbackVolumePort((percent) => ...))` 即可完全
/// 接管：视频保持播放器满音量，你的回调负责应用 [percent]（例如写系统媒体
/// 音量）。若能回报当前音量，传入 [onGet]；否则手势基线从 100 起算。
///
/// Example / 示例:
/// ```dart
/// final engine = createVmEngine(
///   options: options,
///   volume: CallbackVolumePort((percent) => MyAudio.setSystemVolume(percent)),
/// );
/// ```
class CallbackVolumePort implements VmVolumePort {
  /// Creates a callback-backed volume port.
  ///
  /// [onSet] receives the target percentage on every change; [onGet] optionally
  /// reports the current level for the gesture baseline.
  ///
  /// 创建以回调为后端的音量端口。
  ///
  /// [onSet] 在每次变化时收到目标百分比；[onGet] 可选地回报当前音量用作手势基线。
  const CallbackVolumePort(this.onSet, {this.onGet});

  /// The sink applied on every volume change, in `[0, 100]`.
  ///
  /// 每次音量变化时调用的回调，取值 `[0, 100]`。
  final void Function(double percent) onSet;

  /// Optional reader for the current volume; defaults to reporting 100.
  ///
  /// 可选的当前音量读取器；默认回报 100。
  final Future<double> Function()? onGet;

  @override
  Future<double> get() => onGet?.call() ?? Future.value(100);

  @override
  Future<void> set(double percent) async => onSet(percent);
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
    required VmOrientation orientation,
  }) =>
      Future.value();

  @override
  Future<void> reset() => Future.value();
}
