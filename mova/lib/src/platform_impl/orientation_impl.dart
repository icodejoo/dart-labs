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
/// derivation when it is [MovaOrient.auto].
///
/// 解析要请求的设备方向：优先服从强制 [orientation] 覆盖，当其为
/// [MovaOrient.auto] 时回退到按宽高比/全屏的推导。
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
  MovaOrient orientation, {
  required bool fullscreen,
  required int width,
  required int height,
}) {
  switch (orientation) {
    case MovaOrient.landscape:
      return _landscape;
    case MovaOrient.portrait:
      return _portrait;
    case MovaOrient.auto:
      return fullscreen ? preferredOrientationsFor(width, height) : DeviceOrientation.values;
  }
}

/// A [MovaOrientPort] implementation backed by [SystemChrome], driving
/// preferred device orientations and immersive system UI mode.
///
/// 基于 [SystemChrome] 实现的 [MovaOrientPort]，驱动首选设备方向与沉浸式
/// 系统 UI 模式。
class SystemChromeOrientationPort implements MovaOrientPort {
  @override
  Future<void> apply({
    required bool fullscreen,
    required bool immersive,
    required int width,
    required int height,
    required MovaOrient orientation,
  }) async {
    await SystemChrome.setPreferredOrientations(
      resolveOrientations(orientation, fullscreen: fullscreen, width: width, height: height),
    );
    await SystemChrome.setEnabledSystemUIMode(
      immersive ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
    );
  }

  @override
  Future<void> reset() async {
    await SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }
}
