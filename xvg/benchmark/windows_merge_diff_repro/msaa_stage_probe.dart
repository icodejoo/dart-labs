import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import 'archive_replay.dart';
import 'cache_repro.dart';

/// 每个进程中同一对照连续生成的新纹理数。
const samplesPerArm = 150;

/// 每批结束插入一个宿主帧，给引擎机会回收瞬态绘制缓冲区。
const batchSize = 10;

/// 未合并画稿中需要改变绘制管线的黑色填充。
const triggerFill = 12501;

/// 前置图和同步图用于验收回读的实色。
const marker = ui.Color(0xff215ab4);

/// 同步图使用独立尺寸，以免混入同尺寸前置图的对照。
const syncSide = 16;

/// 读回缓存原件的物理纹素。
const texelX = 160, texelY = 134;

/// 历史观察中出现间歇暗化的红色通道值。
const lowRed = 122;

/// 可分别扰动附件历史、填充管线和读回时序的实验条件。
enum Arm { original, clean, poison, winding, readback, float32, legacy }

/// 制作透明前置图，或用同向双轮廓在整张图上做非零绕数及深度绘制。
ui.Picture recordPrimer(int width, int height, {required bool poison}) {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  if (poison) {
    final w = width.toDouble();
    final h = height.toDouble();
    // 凹口位于屏幕外。整个可见区域都被模板准备和不透明覆盖触及。
    final contour = ui.Path()
      ..moveTo(-8, -8)
      ..lineTo(w / 2, -8)
      ..lineTo(w / 2, -4)
      ..lineTo(w + 8, -4)
      ..lineTo(w + 8, h + 8)
      ..lineTo(-8, h + 8)
      ..close();
    canvas.drawPath(repeatNonZeroPath(contour), ui.Paint()..color = marker);
  }
  return recorder.endRecording();
}

/// 等待一张新纹理回读完成，校验像素并主动释放图像句柄。
Future<int> readPrimer(
  ui.Picture picture,
  int width,
  int height, {
  required bool poison,
}) async {
  final watch = Stopwatch()..start();
  final image = picture.toImageSync(width, height);
  try {
    final sample = pixel(await rgba(image), width, width ~/ 2, height ~/ 2);
    final argb = marker.toARGB32();
    final expected = poison
        ? [argb >> 16 & 255, argb >> 8 & 255, argb & 255, argb >> 24]
        : [0, 0, 0, 0];
    if (sample.toString() != expected.toString()) {
      throw StateError('Unexpected primer texel: $sample, expected $expected');
    }
    return watch.elapsedMicroseconds;
  } finally {
    image.dispose();
  }
}

/// 轮换三轮的起点，让每种条件在不同时间段测量。
List<Arm> armOrder(int round) {
  final start = (round - 1) * 2;
  return [...Arm.values.skip(start), ...Arm.values.take(start)];
}

/// 更新安静宿主的一个像素，等待该帧进入光栅线程。
Future<bool> refreshHost(ValueNotifier<bool> color) async {
  final binding = WidgetsBinding.instance;
  final rasterized = Completer<void>();

  /// 接收宿主的帧时序报告。
  void onTimings(List<ui.FrameTiming> timings) {
    if (!rasterized.isCompleted && timings.isNotEmpty) rasterized.complete();
  }

  binding.addTimingsCallback(onTimings);
  try {
    color.value = !color.value;
    await binding.endOfFrame;
    await rasterized.future.timeout(const Duration(seconds: 3));
    return true;
  } on TimeoutException {
    return false;
  } finally {
    binding.removeTimingsCallback(onTimings);
  }
}

/// 回读待测纹理，或在请求后等待另一张纹理完成 GPU 回读再取样。
Future<List<int>> captureTexel(
  ui.Picture vector,
  Target target, {
  required ui.TargetPixelFormat format,
  Future<void> Function()? afterRequest,
}) async {
  final picture = recordCachePicture(
    vector,
    target,
    paste: ui.Offset(target.pasteX, target.pasteY),
  );
  final ui.Image image;
  try {
    image = picture.toImageSync(
      target.textureWidth,
      target.textureHeight,
      targetFormat: format,
    );
  } finally {
    picture.dispose();
  }
  try {
    if (afterRequest != null) await afterRequest();
    return pixel(await rgba(image), target.textureWidth, texelX, texelY);
  } finally {
    image.dispose();
  }
}

/// 对每个条件重放同一份完整 C1，逐张保存纹素和前置图耗时。
Future<void> main() async {
  final round = int.parse(Platform.environment['XVG_MSAA_ROUND']!);
  if (round < 1 || round > 3) throw ArgumentError.value(round);
  final hostColor = ValueNotifier(false);
  final binding = WidgetsFlutterBinding.ensureInitialized();
  runApp(
    ValueListenableBuilder(
      valueListenable: hostColor,
      builder: (_, colored, _) => Align(
        alignment: Alignment.topLeft,
        child: SizedBox.square(
          dimension: 1,
          child: ColoredBox(color: colored ? marker : const ui.Color(0)),
        ),
      ),
    ),
  );
  await binding.endOfFrame;
  final target = targetFor(false);
  final width = target.textureWidth;
  final height = target.textureHeight;
  final original = await archive('C1');
  final winding = await archive('C1', duplicateNonZeroFill: triggerFill);
  final clean = recordPrimer(width, height, poison: false);
  final poison = recordPrimer(width, height, poison: true);
  final sync = recordPrimer(syncSide, syncSide, poison: true);
  final report = File(Platform.environment['XVG_MICRO_OUT']!)
      .openSync(mode: FileMode.write);

  /// 每个完成的观察立即落盘，保留 GPU 异常退出前的记录。
  void checkpoint(Map<String, Object?> row) {
    report
      ..writeStringSync('${jsonEncode(row)}\n')
      ..flushSync();
  }

  /// 生成并落盘一个对照条件的第 number 张纹理。
  Future<void> sampleOnce(Arm arm, int number) async {
    final readbacksUs = <int>[];

    /// 在独立尺寸的纹理上等待像素读回，记录同步发生的时点。
    Future<void> synchronize() async {
      readbacksUs.add(await readPrimer(sync, syncSide, syncSide, poison: true));
    }

    if (arm == Arm.legacy) {
      checkpoint({
        'arm': arm.name,
        'sample': number,
        ...await capturePair(original, target),
      });
      return;
    }
    if (arm == Arm.clean || arm == Arm.poison) {
      final isPoison = arm == Arm.poison;
      readbacksUs.add(
        await readPrimer(
          isPoison ? poison : clean,
          width,
          height,
          poison: isPoison,
        ),
      );
    } else if (arm == Arm.readback) {
      await synchronize();
    }
    final texel = await captureTexel(
      arm == Arm.winding ? winding : original,
      target,
      format: arm == Arm.float32
          ? ui.TargetPixelFormat.rgbaFloat32
          : ui.TargetPixelFormat.dontCare,
      afterRequest: arm == Arm.readback ? synchronize : null,
    );
    checkpoint({
      'arm': arm.name,
      'sample': number,
      'texel': texel,
      'texel_xy': [texelX, texelY],
      'readback_us': readbacksUs,
    });
  }

  try {
    // 各条件按批轮流采样，进程中途异常退出也保持各档数量接近。
    for (var start = 0; start < samplesPerArm; start += batchSize) {
      for (final arm in armOrder(round)) {
        for (var i = start; i < start + batchSize; i++) {
          await sampleOnce(arm, i + 1);
        }
        checkpoint({
          'after_arm': arm.name,
          'after_sample': start + batchSize,
          'host_rasterized': await refreshHost(hostColor),
        });
      }
    }
  } finally {
    report.closeSync();
    for (final picture in [original, winding, clean, poison, sync]) {
      picture.dispose();
    }
  }
  exit(0);
}
