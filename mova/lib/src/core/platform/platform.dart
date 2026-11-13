// Platform capability ports: abstract interfaces the core layer depends on
// for screen brightness, picture-in-picture, and orientation control, plus
// zero-dependency fallback/noop implementations. Real implementations live
// under `lib/src/platform_impl/` and may import flutter/plugin packages;
// this file must stay free of any flutter/media_kit imports.
//
// 平台能力端口：core 层依赖的抽象接口（屏幕亮度、画中画、方向控制），以及零
// 依赖的兜底/空实现。真实实现放在 `lib/src/platform_impl/`，可以引入
// flutter/插件包；本文件必须保持不引入任何 flutter/media_kit 依赖。

import '../model/orient_mode.dart';

/// A port for reading and writing the device/app screen brightness.
///
/// 读写设备/应用屏幕亮度的端口。
abstract class IMovaBrightness {
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

/// 亮度端口的可选还原能力，用于恢复应用覆盖或交还系统亮度控制。
///
/// 示例：`if (port is IMovaBrightnessRestore) await port.restore(initialBrightness);`
abstract interface class IMovaBrightnessRestore {
  /// 用 [initialBrightness] 还原进入播放器前的亮度，返回完成通知。
  ///
  /// 示例：`await port.restore(0.6)`；支持系统控制的端口可清除应用覆盖。
  Future<void> restore(double initialBrightness);
}

/// A port for reading and writing the device's system media volume, as a
/// percentage in `[0, 100]`.
///
/// This is the injection point for "who owns volume". When one is wired
/// (e.g. by `createMova` on Android, or by a host passing its own), the
/// volume gesture routes the target percent here instead of touching the
/// player's own volume — so the gesture drives the real system volume and the
/// video stays at full player volume. A host that wants full control can pass
/// a [MovaCallbackVolume] and apply the percent however it likes.
///
/// 读写设备系统媒体音量的端口，取值为 `[0, 100]` 的百分比。
///
/// 这是"音量归谁管"的注入点。接上端口后（如 Android 上由 `createMova`
/// 接上，或由宿主自带），音量手势会把目标百分比交给这里，而不去动播放器
/// 自身音量——于是手势驱动的是真实系统音量，视频保持播放器满音量。宿主想
/// 完全接管，可传 [MovaCallbackVolume] 自行处置百分比。
abstract class IMovaVolume {
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
abstract class IMovaPip {
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

/// Optional capability of a [IMovaPip]: reports PiP mode changes that
/// happen outside [IMovaPip.enter] (the user closes or expands the PiP
/// window). The player probes it with `is`, so existing ports stay valid.
///
/// [IMovaPip] 的可选能力：上报 [IMovaPip.enter] 之外发生的画中画变化
/// （用户关闭或展开小窗）。播放器用 `is` 探测，既有端口无需改动。
abstract interface class IMovaPipObservable {
  /// Emits `true` when the host enters PiP and `false` when it leaves.
  ///
  /// 进入画中画时发出 `true`，退出时发出 `false`。
  Stream<bool> get changes;
}

/// A port for applying and resetting fullscreen/immersive orientation and
/// system UI state.
///
/// 应用与重置全屏/沉浸式方向与系统 UI 状态的端口。
abstract class IMovaOrient {
  /// Applies the orientation/immersive/system-UI state for the given mode.
  ///
  /// 按给定模式应用方向/沉浸式/系统 UI 状态。
  ///
  /// - [fullscreen]: whether fullscreen is active / 是否处于全屏
  /// - [immersive]: whether immersive (edge-to-edge) UI is active /
  ///   是否处于沉浸式（沉浸边到边）UI
  /// - [width], [height]: video pixel dimensions used to pick orientation when
  ///   [orient] is [MovaOrientMode.auto] / 当 [orient] 为
  ///   [MovaOrientMode.auto] 时用于选择方向的视频像素宽高
  /// - [orient]: forced-orientation override; [MovaOrientMode.auto] keeps
  ///   the aspect-ratio/fullscreen-derived behavior / 强制方向覆盖；
  ///   [MovaOrientMode.auto] 保持按宽高比/全屏推导的行为
  Future<void> apply({
    required bool fullscreen,
    required bool immersive,
    required int width,
    required int height,
    required MovaOrientMode orient,
  });

  /// Resets orientation/system UI back to the default (portrait, edge-to-edge
  /// restored, all orientations allowed).
  ///
  /// 将方向/系统 UI 重置为默认状态（竖屏、恢复边到边、允许全部方向）。
  Future<void> reset();
}

/// A zero-dependency [IMovaBrightness] fallback that always reports full
/// brightness and silently ignores writes.
///
/// 零依赖的 [IMovaBrightness] 兜底实现：始终报告最大亮度，写入操作静默忽略。
class MovaFallbackBrightness implements IMovaBrightness {
  @override
  Future<double> get() => Future.value(1.0);

  @override
  Future<void> set(double value) => Future.value();
}

/// A zero-dependency [IMovaVolume] fallback that reports full volume and
/// silently ignores writes.
///
/// 零依赖的 [IMovaVolume] 兜底实现：始终报告满音量，写入操作静默忽略。
class MovaFallbackVolume implements IMovaVolume {
  @override
  Future<double> get() => Future.value(100);

  @override
  Future<void> set(double percent) => Future.value();
}

/// A [IMovaVolume] adapter that forwards writes to a plain callback, so a
/// host can control volume without implementing the full interface.
///
/// Pass `createMova(volume: MovaCallbackVolume((percent) => ...))` to take
/// over volume entirely: the video keeps full player volume while your
/// callback applies [percent] (e.g. to the OS media volume). Supply [onGet] if
/// you can report the current level back; otherwise the gesture baseline
/// starts from 100.
///
/// 把写入转发给一个普通回调的 [IMovaVolume] 适配器，宿主无需实现整个接口即可
/// 接管音量。
///
/// 传 `createMova(volume: MovaCallbackVolume((percent) => ...))` 即可完全
/// 接管：视频保持播放器满音量，你的回调负责应用 [percent]（例如写系统媒体
/// 音量）。若能回报当前音量，传入 [onGet]；否则手势基线从 100 起算。
///
/// Example / 示例:
/// ```dart
/// final mova = createMova(
///   options: options,
///   volume: MovaCallbackVolume((percent) => MyAudio.setSystemVolume(percent)),
/// );
/// ```
class MovaCallbackVolume implements IMovaVolume {
  /// Creates a callback-backed volume port.
  ///
  /// [onSet] receives the target percentage on every change; [onGet] optionally
  /// reports the current level for the gesture baseline.
  ///
  /// 创建以回调为后端的音量端口。
  ///
  /// [onSet] 在每次变化时收到目标百分比；[onGet] 可选地回报当前音量用作手势基线。
  const MovaCallbackVolume(this.onSet, {this.onGet});

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

/// A zero-dependency [IMovaPip] no-op that reports PiP as unsupported.
///
/// 零依赖的 [IMovaPip] 空实现：始终报告不支持画中画。
class MovaNoopPip implements IMovaPip {
  @override
  Future<bool> isSupported() => Future.value(false);

  @override
  Future<bool> enter({int? width, int? height}) => Future.value(false);
}

/// A zero-dependency [IMovaOrient] no-op that does nothing.
///
/// 零依赖的 [IMovaOrient] 空实现：不执行任何操作。
class MovaNoopOrient implements IMovaOrient {
  @override
  Future<void> apply({
    required bool fullscreen,
    required bool immersive,
    required int width,
    required int height,
    required MovaOrientMode orient,
  }) =>
      Future.value();

  @override
  Future<void> reset() => Future.value();
}
