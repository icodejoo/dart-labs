import 'dart:io';

/// The host platform, as far as the preview feature needs to distinguish it.
///
/// 预览功能所需区分的宿主平台粒度。
enum VmPlatformKind {
  /// Android.
  ///
  /// 安卓。
  android,

  /// iOS.
  ///
  /// iOS。
  ios,

  /// Windows desktop.
  ///
  /// Windows 桌面。
  windows,

  /// macOS desktop.
  ///
  /// macOS 桌面。
  macos,

  /// Linux desktop.
  ///
  /// Linux 桌面。
  linux,

  /// Anything else / unclassifiable.
  ///
  /// 其他/无法分类的平台。
  other,
}

/// Detects the current [VmPlatformKind] from `dart:io`.
///
/// Uses `dart:io` rather than `defaultTargetPlatform` so the core layer stays
/// free of Flutter imports; videoman is a libmpv-backed plugin and never
/// targets web, so the `dart:io` restriction costs nothing.
///
/// 通过 `dart:io` 判定当前的 [VmPlatformKind]。
///
/// 用 `dart:io` 而非 `defaultTargetPlatform`，是为了让 core 层不引入 Flutter；
/// videoman 是基于 libmpv 的插件、本就不支持 web，因此这个限制没有代价。
///
/// Returns the detected platform kind.
///
/// 返回检测到的平台类型。
VmPlatformKind currentPlatformKind() {
  if (Platform.isAndroid) return VmPlatformKind.android;
  if (Platform.isIOS) return VmPlatformKind.ios;
  if (Platform.isWindows) return VmPlatformKind.windows;
  if (Platform.isMacOS) return VmPlatformKind.macos;
  if (Platform.isLinux) return VmPlatformKind.linux;
  return VmPlatformKind.other;
}
