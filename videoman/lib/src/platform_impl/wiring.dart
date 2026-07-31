// Wires a [VmEngine] to the real platform adapters implemented under
// `lib/src/platform_impl/`. This file — not `core/engine.dart` — is the only
// place allowed to reference those adapters, since `lib/src/core/**` must
// never import `package:flutter/*` or any `platform_impl/*` file (enforced
// by `test/core/purity_test.dart`).
//
// 把 [VmEngine] 接到 `lib/src/platform_impl/` 下的真实平台适配器。只有本文件
// （而非 `core/engine.dart`）允许引用这些适配器，因为 `lib/src/core/**` 绝不能
// 引入 `package:flutter/*` 或任何 `platform_impl/*` 文件（由
// `test/core/purity_test.dart` 强制检查）。

import '../core/engine.dart';
import '../core/interceptor/interceptor.dart';
import '../core/kernel/kernel.dart';
import '../core/options/options.dart';
import '../core/platform/ports.dart';
import '../core/preview/dir_provider.dart';
import '../core/preview/extractor.dart';
import '../core/preview/fetcher.dart';
import 'brightness_impl.dart';
import 'mpv_extractor_impl.dart';
import 'net_probe_impl.dart';
import 'orientation_impl.dart';
import 'pip_impl.dart';
import 'thumb_dir_impl.dart';

/// Creates a [VmEngine] wired to the real platform adapters
/// ([ScreenBrightnessPort], [ChannelPipPort], [SystemChromeOrientationPort],
/// and — since phase B — [VmThumbDirProvider]/[VmFrameExtractor] for scrub
/// preview) instead of [VmEngine]'s own noop/fallback defaults.
///
/// [VmEngine]'s bare constructor intentionally defaults to zero-dependency
/// noop ports so it stays usable from pure-Dart unit tests that can't touch
/// platform channels; app code should call this factory instead so the
/// brightness-drag gesture, PiP, fullscreen-orientation, and scrub-preview
/// thumbnails actually work. Any port can still be overridden (e.g. with a
/// fake, in a widget test that exercises the real engine wiring).
///
/// 创建一个接入真实平台适配器（[ScreenBrightnessPort]、[ChannelPipPort]、
/// [SystemChromeOrientationPort]，以及阶段 B 起新增的拖动预览端口
/// [VmThumbDirProvider]/[VmFrameExtractor]）的 [VmEngine]，而非使用 [VmEngine]
/// 自身的空/兜底默认实现。
///
/// [VmEngine] 的裸构造函数刻意默认使用零依赖的空端口，以便纯 Dart 单测（无法
/// 触达平台通道）也能直接使用；app 代码应改用本工厂函数，这样亮度拖拽手势、
/// 画中画、全屏方向、拖动预览缩略图这些功能才能真正生效。每个端口仍可分别
/// 覆盖（例如在验证真实 engine 接线的 widget 测试中传入 fake）。
///
/// - [kernel]: the playback kernel; defaults to a new `MpvKernel` (see
///   [VmEngine.new]) / 播放内核，省略时默认新建 `MpvKernel`（见
///   [VmEngine.new]）
/// - [options]: engine configuration / engine 配置
/// - [interceptors]: interceptor chain consulted before open/seek/play /
///   在 open/seek/play 前咨询的拦截链
/// - [brightness]: overrides the real [ScreenBrightnessPort] default /
///   覆盖默认的真实 [ScreenBrightnessPort]
/// - [pip]: overrides the real [ChannelPipPort] default / 覆盖默认的真实
///   [ChannelPipPort]
/// - [orientation]: overrides the real [SystemChromeOrientationPort] default
///   / 覆盖默认的真实 [SystemChromeOrientationPort]
/// - [thumbDir]: overrides the real [TempThumbDirProvider] default used for
///   the on-disk thumbnail cache / 覆盖默认的真实 [TempThumbDirProvider]（磁盘
///   缩略图缓存目录）
/// - [extractor]: overrides the real [MpvFrameExtractor] default used as the
///   frame-extraction fallback source / 覆盖默认的真实 [MpvFrameExtractor]
///   （抽帧兜底来源）
/// - [fetcher]: overrides the HTTP fetcher used to pull WebVTT tracks and
///   sprites; left null, [VmEngine] falls back to its own `IoHttpFetcher()` /
///   覆盖拉取 WebVTT 轨与雪碧图的 HTTP 客户端；留空则由 [VmEngine] 自己兜底为
///   `IoHttpFetcher()`
///
/// Returns a [VmEngine] ready for use by app code.
///
/// 返回一个可供 app 代码直接使用的 [VmEngine]。
VmEngine createVmEngine({
  VmKernel? kernel,
  VmOptions options = const VmOptions(),
  List<VmInterceptor> interceptors = const [],
  VmBrightnessPort? brightness,
  VmPipPort? pip,
  VmOrientationPort? orientation,
  VmThumbDirProvider? thumbDir,
  VmFrameExtractor? extractor,
  VmHttpFetcher? fetcher,
}) {
  return VmEngine(
    kernel: kernel,
    options: options.preview.probe == null
        ? options.copyWith(preview: options.preview.copyWith(probe: ConnectivityNetProbe()))
        : options,
    interceptors: interceptors,
    brightness: brightness ?? ScreenBrightnessPort(),
    pip: pip ?? ChannelPipPort(),
    orientation: orientation ?? SystemChromeOrientationPort(),
    thumbDir: thumbDir ?? const TempThumbDirProvider(),
    extractor: extractor ?? MpvFrameExtractor(),
    fetcher: fetcher,
  );
}
