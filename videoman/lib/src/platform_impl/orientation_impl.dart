import 'package:flutter/services.dart';

import '../core/platform/ports.dart';

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
  return width >= height
      ? const [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]
      : const [DeviceOrientation.portraitUp, DeviceOrientation.portraitDown];
}

/// A [VmOrientationPort] implementation backed by [SystemChrome], driving
/// preferred device orientations and immersive system UI mode.
///
/// 基于 [SystemChrome] 实现的 [VmOrientationPort]，驱动首选设备方向与沉浸式
/// 系统 UI 模式。
class SystemChromeOrientationPort implements VmOrientationPort {
  @override
  Future<void> apply({
    required bool fullscreen,
    required bool immersive,
    required int width,
    required int height,
  }) async {
    if (fullscreen) {
      await SystemChrome.setPreferredOrientations(
        preferredOrientationsFor(width, height),
      );
    } else {
      await SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    }
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
