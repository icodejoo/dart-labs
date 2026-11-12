import 'package:flutter/services.dart';

import '../core/model/orientation.dart';
import '../core/platform/ports.dart';

/// The landscape device-orientation pair (both directions).
///
/// 横屏设备方向对（双向）。
const List<DeviceOrientation> _landscape = [
  DeviceOrientation.landscapeLeft,
  DeviceOrientation.landscapeRight,
];

/// The portrait device-orientation pair (both directions).
///
/// 竖屏设备方向对（双向）。
const List<DeviceOrientation> _portrait = [
  DeviceOrientation.portraitUp,
  DeviceOrientation.portraitDown,
];

/// Chooses the fullscreen orientations that match a video's aspect ratio.
///
/// Landscape (both directions) when width ≥ height, else portrait.
///
/// 按视频宽高比选择全屏方向：宽≥高用横屏（双向），否则竖屏。
///
/// - [width], [height]: video pixel dimensions / 视频像素宽高
///
/// Returns the preferred orientation list.
///
/// 返回首选方向列表。
List<DeviceOrientation> preferredOrientationsFor(int width, int height) {
  return width >= height ? _landscape : _portrait;
}

/// Resolves the device orientations to request, honoring a forced
/// [orientation] override and falling back to the aspect-ratio/fullscreen
/// derivation when it is [MovaOrientation.auto].
///
/// 解析要请求的设备方向：优先服从强制 [orientation] 覆盖，当其为
/// [MovaOrientation.auto] 时回退到按宽高比/全屏的推导。
///
/// - [orientation]: forced override / 强制方向覆盖
/// - [fullscreen]: whether fullscreen is active (only matters for auto) /
///   是否全屏（仅在 auto 下起作用）
/// - [width], [height]: video pixel dimensions (only matter for auto) /
///   视频像素宽高（仅在 auto 下起作用）
///
/// Returns the resolved orientation list.
///
/// 返回解析出的方向列表。
List<DeviceOrientation> resolveOrientations(
  MovaOrientation orientation, {
  required bool fullscreen,
  required int width,
  required int height,
}) {
  switch (orientation) {
    case MovaOrientation.landscape:
      return _landscape;
    case MovaOrientation.portrait:
      return _portrait;
    case MovaOrientation.auto:
      return fullscreen
          ? preferredOrientationsFor(width, height)
          : DeviceOrientation.values;
  }
}

/// A [MovaOrientationPort] implementation backed by [SystemChrome], driving
/// preferred device orientations and immersive system UI mode.
///
/// 基于 [SystemChrome] 实现的 [MovaOrientationPort]，驱动首选设备方向与沉浸式
/// 系统 UI 模式。
class MovaSystemChromeOrientationPort implements MovaOrientationPort {
  /// Creates a port; [config] declares the host orientations and system bars.
  ///
  /// 创建方向端口；[config] 声明宿主离开全屏后使用的方向与系统栏。
  ///
  /// 示例：`MovaSystemChromeOrientationPort(config: MovaOrientationConfig())`。
  const MovaSystemChromeOrientationPort({
    this.config = const MovaOrientationConfig(),
  });

  /// The host restoration settings, e.g. `port.config.allowedOrientations`.
  ///
  /// 宿主的还原配置；示例：`port.config.allowedOrientations`。
  final MovaOrientationConfig config;

  /// Applies the orientation override and restores host system bars on exit.
  ///
  /// 应用强制方向，并在退出全屏时还原宿主系统栏。
  @override
  Future<void> apply({
    required bool fullscreen,
    required bool immersive,
    required int width,
    required int height,
    required MovaOrientation orientation,
  }) async {
    if (!fullscreen && !immersive && orientation == MovaOrientation.auto) {
      return reset();
    }
    await SystemChrome.setPreferredOrientations(
      resolveOrientations(
        orientation,
        fullscreen: fullscreen,
        width: width,
        height: height,
      ),
    );
    await SystemChrome.setEnabledSystemUIMode(
      immersive
          ? SystemUiMode.immersiveSticky
          : (fullscreen ? SystemUiMode.edgeToEdge : config.systemUiMode),
      overlays: config.systemUiOverlays,
    );
  }

  /// Restores the host orientations and system bars.
  ///
  /// 还原宿主方向和系统栏。
  @override
  Future<void> reset() async {
    await SystemChrome.setPreferredOrientations(config.allowedOrientations);
    await SystemChrome.setEnabledSystemUIMode(
      config.systemUiMode,
      overlays: config.systemUiOverlays,
    );
  }
}

/// Host settings restored after fullscreen; defaults to all orientations and edge-to-edge.
///
/// 宿主声明的全屏离场配置；未声明时允许全部方向并使用 edge-to-edge。
///
/// 示例：`createMovaEngine(orientationConfig: MovaOrientationConfig(
///   allowedOrientations: [DeviceOrientation.portraitUp]))`。
class MovaOrientationConfig {
  /// Creates settings with [allowedOrientations], [systemUiMode], and manual
  /// [systemUiOverlays]; see the example below.
  ///
  /// 创建配置；[allowedOrientations] 为宿主允许方向，[systemUiMode] 为系统栏模式，
  /// [systemUiOverlays] 在 manual 模式下指定可见系统栏，返回不可变配置引用。
  ///
  /// 示例：`MovaOrientationConfig(systemUiMode: SystemUiMode.manual,
  ///   systemUiOverlays: [SystemUiOverlay.top])`。
  const MovaOrientationConfig({
    this.allowedOrientations = DeviceOrientation.values,
    this.systemUiMode = SystemUiMode.edgeToEdge,
    this.systemUiOverlays = SystemUiOverlay.values,
  });

  /// Allowed orientations after exit, e.g. `[DeviceOrientation.portraitUp]`.
  ///
  /// 离场后允许的方向；示例：`[DeviceOrientation.portraitUp]`。
  final List<DeviceOrientation> allowedOrientations;

  /// System UI mode after exit, e.g. `SystemUiMode.manual`.
  ///
  /// 离场后的系统栏模式；示例：`SystemUiMode.manual`。
  final SystemUiMode systemUiMode;

  /// Visible bars in manual mode, e.g. `[SystemUiOverlay.top]`.
  ///
  /// manual 模式下可见的系统栏；示例：`[SystemUiOverlay.top]`。
  final List<SystemUiOverlay> systemUiOverlays;
}
