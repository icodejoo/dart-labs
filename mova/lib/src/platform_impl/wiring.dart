// Wires a [MovaEngine] to the real platform adapters implemented under
// `lib/src/platform_impl/`. This file — not `core/engine.dart` — is the only
// place allowed to reference those adapters, since `lib/src/core/**` must
// never import `package:flutter/*` or any `platform_impl/*` file (enforced
// by `test/core/purity_test.dart`).
//
// 把 [MovaEngine] 接到 `lib/src/platform_impl/` 下的真实平台适配器。只有本文件
// （而非 `core/engine.dart`）允许引用这些适配器，因为 `lib/src/core/**` 绝不能
// 引入 `package:flutter/*` 或任何 `platform_impl/*` 文件（由
// `test/core/purity_test.dart` 强制检查）。

import 'package:flutter/foundation.dart';

import '../core/engine.dart';
import '../core/interceptor/interceptor.dart';
import '../core/kernel/kernel.dart';
import '../core/options/options.dart';
import '../core/platform/ports.dart';
import '../core/preview/dir_provider.dart';
import '../core/preview/extractor.dart';
import '../core/preview/fetcher.dart';
import '../core/preview/net_probe.dart';
import 'brightness_impl.dart';
import 'orientation_impl.dart';
import 'pip_impl.dart';
import 'thumb_dir_impl.dart';
import 'volume_impl.dart';

/// The default [MovaVolumePort] for this platform: the native system-media-volume
/// port on Android, and `null` elsewhere so the engine keeps the player-volume
/// path (iOS restricts programmatic system volume; desktop has no channel impl).
///
/// 本平台的默认 [MovaVolumePort]：Android 上是原生系统媒体音量端口，其余平台为
/// `null`，让引擎保持播放器音量路径（iOS 限制代码改系统音量；桌面无通道实现）。
MovaVolumePort? _defaultVolumePort() {
  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
      return MovaSystemVolumePort();
    default:
      return null;
  }
}

/// Creates a [MovaEngine] wired to the real platform adapters
/// ([MovaScreenBrightnessPort], [MovaChannelPipPort], [MovaSystemChromeOrientationPort],
/// and — since phase B — [MovaThumbDirProvider]/[MovaFramePuller] for scrub
/// preview) instead of [MovaEngine]'s own noop/fallback defaults.
///
/// [MovaEngine]'s bare constructor intentionally defaults to zero-dependency
/// noop ports so it stays usable from pure-Dart unit tests that can't touch
/// platform channels; app code should call this factory instead so the
/// brightness-drag gesture, PiP, fullscreen-orientation, and scrub-preview
/// thumbnails actually work. Any port can still be overridden (e.g. with a
/// fake, in a widget test that exercises the real engine wiring).
///
/// 创建一个接入真实平台适配器（[MovaScreenBrightnessPort]、[MovaChannelPipPort]、
/// [MovaSystemChromeOrientationPort]，以及阶段 B 起新增的拖动预览端口
/// [MovaThumbDirProvider]/[MovaFramePuller]）的 [MovaEngine]，而非使用 [MovaEngine]
/// 自身的空/兜底默认实现。
///
/// [MovaEngine] 的裸构造函数刻意默认使用零依赖的空端口，以便纯 Dart 单测（无法
/// 触达平台通道）也能直接使用；app 代码应改用本工厂函数，这样亮度拖拽手势、
/// 画中画、全屏方向、拖动预览缩略图这些功能才能真正生效。每个端口仍可分别
/// 覆盖（例如在验证真实 engine 接线的 widget 测试中传入 fake）。
///
/// - [kernel]: the playback kernel; defaults to a new `MovaMpvKernel` (see
///   [MovaEngine.new]) / 播放内核，省略时默认新建 `MovaMpvKernel`（见
///   [MovaEngine.new]）
/// - [audioOnly]: builds an audio-only engine — the default kernel skips its
///   `VideoController` and the frame-extraction fallback is left unwired,
///   so no video pipeline of any kind is created. `renderHandle` is then
///   `null` and `MovaPlayer` renders its placeholder (or the `surface` you
///   pass it). Ignored when [kernel] is supplied. Hosts should also turn
///   scrub preview off (`MovaPreviewConfig(enabled: false)`) — there are no
///   frames to preview /
///   构建仅音频引擎——默认内核跳过 `VideoController`，抽帧兜底也不接线，
///   因此不会创建任何形式的视频管线。此时 `renderHandle` 为 `null`，
///   `MovaPlayer` 渲染占位符（或你传入的 `surface`）。传入 [kernel] 时本参数
///   被忽略。宿主还应关掉拖动预览（`MovaPreviewConfig(enabled: false)`）——
///   没有帧可预览
/// - [options]: engine configuration / engine 配置
/// - [interceptors]: interceptor chain consulted before open/seek/play /
///   在 open/seek/play 前咨询的拦截链
/// - [brightness]: overrides the real [MovaScreenBrightnessPort] default /
///   覆盖默认的真实 [MovaScreenBrightnessPort]
/// - [volume]: overrides the default volume port. Defaults to the native
///   [MovaSystemVolumePort] on Android and `null` (player-volume path) elsewhere;
///   pass a [MovaCallbackVolumePort] to drive system volume yourself on any
///   platform / 覆盖默认音量端口。Android 默认接原生 [MovaSystemVolumePort]，其余
///   平台默认 `null`（播放器音量路径）；任意平台都可传 [MovaCallbackVolumePort]
///   自行驱动系统音量
/// - [pip]: overrides the real [MovaChannelPipPort] default / 覆盖默认的真实
///   [MovaChannelPipPort]
/// - [orientation]: overrides the real [MovaSystemChromeOrientationPort] default
///   / 覆盖默认的真实 [MovaSystemChromeOrientationPort]
/// - [thumbDir]: overrides the real [MovaTempThumbDirProvider] default used for
///   the on-disk thumbnail cache / 覆盖默认的真实 [MovaTempThumbDirProvider]（磁盘
///   缓存图缓存目录）
/// - [extractor]: the scrub-preview frame-extraction fallback source. `null`
///   by default — unlike the other ports, this one is **not** wired to a
///   platform default here, because the only default implementation
///   (`MovaFrameExtractor`, `package:mova/mova.dart`) pulls in
///   `media_kit_video` as a *statically reachable* dependency the moment this
///   function references it, defeating tree-shaking for hosts that never use
///   scrub preview. Pass `MovaFrameExtractor()` explicitly to opt in / 拖动预览
///   的抽帧兜底来源。默认为 `null`——与其余端口不同，本参数**不会**在这里接一个
///   平台默认实现，因为唯一的默认实现（`MovaFrameExtractor`，见
///   `package:mova/mova.dart`）一旦被本函数引用就会把 `media_kit_video`
///   变成静态可达依赖，让从不使用拖动预览的宿主也摇不掉它。要启用请显式传入
///   `MovaFrameExtractor()`
/// - [probe]: the connectivity probe consulted under `wifiOnly` preview
///   network policy. `null` by default for the same tree-shaking reason as
///   [extractor] — the default implementation (`MovaConnectivityNetProbe`) pulls
///   in `connectivity_plus`; [MovaEngine] itself already falls back to a
///   pure-Dart `MovaAlwaysAllowNetProbe()` when this stays unset, so `wifiOnly`
///   preview policy is simply not enforced unless you opt in / `wifiOnly`
///   预览网络策略要咨询的连通性探针。默认为 `null`，原因与 [extractor] 相同——
///   默认实现（`MovaConnectivityNetProbe`）会引入 `connectivity_plus`；未设置时
///   [MovaEngine] 自己会兜底为纯 Dart 的 `MovaAlwaysAllowNetProbe()`，即不显式启用
///   时 `wifiOnly` 策略不会被强制执行
/// - [fetcher]: overrides the HTTP fetcher used to pull WebVTT tracks and
///   sprites; left null, [MovaEngine] falls back to its own `MovaIoHttpFetcher()` /
///   覆盖拉取 WebVTT 轨与雪碧图的 HTTP 客户端；留空则由 [MovaEngine] 自己兜底为
///   `MovaIoHttpFetcher()`
///
/// Returns a [MovaEngine] ready for use by app code.
///
/// 返回一个可供 app 代码直接使用的 [MovaEngine]。
MovaEngine createMovaEngine({
  MovaKernel? kernel,
  bool audioOnly = false,
  MovaOpts options = const MovaOpts(),
  List<MovaHook> interceptors = const [],
  MovaBrightPort? brightness,
  MovaVolumePort? volume,
  MovaPipPort? pip,
  MovaOrientationPort? orientation,
  MovaThumbDirProvider? thumbDir,
  MovaFramePuller? extractor,
  MovaNetProbe? probe,
  MovaHttpFetch? fetcher,
}) {
  return MovaEngine(
    kernel: kernel,
    audioOnly: audioOnly,
    options: probe == null ? options : options.copyWith(preview: options.preview.copyWith(probe: probe)),
    interceptors: interceptors,
    brightness: brightness ?? MovaScreenBrightnessPort(),
    volume: volume ?? _defaultVolumePort(),
    pip: pip ?? MovaChannelPipPort(),
    orientation: orientation ?? MovaSystemChromeOrientationPort(),
    thumbDir: thumbDir ?? const MovaTempThumbDirProvider(),
    extractor: extractor,
    fetcher: fetcher,
  );
}
