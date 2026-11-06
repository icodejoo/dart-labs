// Optional screenshot hook for the benchmark app. Enabled only when
// `--dart-define=CAPTURE_DIR=<dir>` is given: the root `RepaintBoundary` is
// then saved as PNG at a few fixed moments. When the define is absent every
// entry point below is a no-op behind a compile-time constant, so the timing
// behaviour of normal builds is untouched.
//
// 基准应用的可选截图钩子。仅当传入 `--dart-define=CAPTURE_DIR=<目录>` 时启用：
// 在几个固定时刻把根 `RepaintBoundary` 存成 PNG。未传该参数时，下面所有入口都
// 是编译期常量守卫下的空操作，普通构建的计时行为不受任何影响。

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Output directory from `--dart-define=CAPTURE_DIR`; empty means disabled.
/// `--dart-define=CAPTURE_DIR` 给定的输出目录；为空表示关闭。
const String captureDir = String.fromEnvironment('CAPTURE_DIR');

/// Whether capturing is enabled. / 是否启用截图。
const bool captureEnabled = captureDir != '';

/// Key of the root boundary installed by [wrapForCapture].
/// [wrapForCapture] 安装的根边界所用的 key。
final GlobalKey captureBoundaryKey = GlobalKey(debugLabel: 'captureBoundary');

/// Wraps [app] in the capturable root boundary; returns [app] unchanged when
/// capturing is disabled.
///
/// 把 [app] 包进可截图的根边界；未启用截图时原样返回。
///
/// Example: `runApp(wrapForCapture(MaterialApp(home: ...)))`
Widget wrapForCapture(Widget app) =>
    captureEnabled ? RepaintBoundary(key: captureBoundaryKey, child: app) : app;

/// Saves the root boundary as `<CAPTURE_DIR>/<name>.png`; no-op when disabled.
/// Failures are printed, never thrown, so they cannot break a benchmark run.
///
/// 把根边界存成 `<CAPTURE_DIR>/<name>.png`；未启用时空操作。失败只打印、不抛出，
/// 不会打断基准运行。
Future<void> capturePng(String name) async {
  if (!captureEnabled) return;
  try {
    final boundary =
        captureBoundaryKey.currentContext?.findRenderObject()
            as RenderRepaintBoundary?;
    if (boundary == null) {
      debugPrint('[capture] $name: no boundary');
      return;
    }
    final image = await boundary.toImage();
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (data == null) return;
    final dir = Directory(captureDir)..createSync(recursive: true);
    File('${dir.path}${Platform.pathSeparator}$name.png').writeAsBytesSync(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    );
    // ignore: avoid_print
    print('[capture] saved $name.png ${image.width}x${image.height}');
  } catch (e) {
    // ignore: avoid_print
    print('[capture] $name failed: $e');
  }
}

/// Fires [capturePng] (`<prefix>_<offset>ms`) once per [offsets] entry, each
/// measured from now, without blocking the caller. No-op when disabled.
///
/// 从此刻起，对 [offsets] 里每个偏移各触发一次 [capturePng]（名字为
/// `<prefix>_<偏移>ms`），不阻塞调用方。未启用时空操作。
void scheduleCaptures(String prefix, List<Duration> offsets) {
  if (!captureEnabled) return;
  for (final o in offsets) {
    Timer(o, () => capturePng('${prefix}_${o.inMilliseconds}ms'));
  }
}
