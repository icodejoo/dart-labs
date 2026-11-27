// Uses the same internal cache and override as the merge benchmark. / 沿用合并基准的内部缓存和开关。
// ignore_for_file: implementation_imports, invalid_use_of_visible_for_testing_member

import 'dart:convert';
import 'dart:developer';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:xvg/src/rust_static_svg.dart';
import 'package:xvg/xvg.dart' show RustLib;

/// Length of each scripted phase. / 每段基准场景的时长。
const _phaseDuration = Duration(seconds: 2);

/// Number of polygons in the original SVG. / 原始 SVG 的多边形数。
const _sourcePaths = 192;

/// Duration of one marker sweep in microseconds. / 标记单次横移的微秒数。
const _sweepUs = 1200000;

/// Collects release-like frame and VM timeline data in profile mode. / 在 profile 模式采集帧和 VM 时间线数据。
Future<void> main(List<String> args) async {
  final binding = WidgetsFlutterBinding.ensureInitialized();
  final root = Platform.isWindows
      ? Directory(args.single)
      : Directory(
          '/sdcard/Android/data/com.example.bench_app/files/xvg-merge-jank',
        );

  /// Resolves a host signal or report within the run directory. / 在本轮目录内定位主机信号或报告。
  File file(String name) => File('${root.path}/$name');

  try {
    final scheduler = SchedulerBinding.instance;
    final frames = <ui.FrameTiming>[];
    final off = file('off').existsSync();
    final on = file('on').existsSync();
    final continuous = file('continuous').existsSync();
    final alternating = file('alternating').existsSync();
    debugPathMergeOverride = off ? false : (on ? true : null);
    final collectTimings = frames.addAll;
    binding.addTimingsCallback(collectTimings);
    final motion = ValueNotifier(0.0);
    final art = ValueNotifier<ui.Picture?>(null);
    runApp(
      Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox.expand(
          child: CustomPaint(painter: _Scene(art, motion)),
        ),
      ),
    );
    await RustLib.init();
    await scheduler.endOfFrame;
    final service = await Service.getInfo();
    file('vm').writeAsStringSync(service.serverUri!.toString());
    final stopAt = DateTime.now().add(const Duration(seconds: 20));
    while (!file('go').existsSync()) {
      if (DateTime.now().isAfter(stopAt)) throw StateError('missing go');
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }

    final ticker = Ticker((time) {
      motion.value = (time.inMicroseconds % _sweepUs) / _sweepUs;
    });
    final info = RustXvgPictureCache.instance.getOrRender(
      _buildSvg(alternating: alternating),
    );
    art.value = info.picture;
    ticker.start();
    await scheduler.endOfFrame;
    final stageStarts = <String, int>{'animation_1': _mark('artFrame')};
    await Future<void>.delayed(_phaseDuration);
    if (!continuous) ticker.stop();
    stageStarts[continuous ? 'animation_2' : 'quiet'] = _mark('phase2');
    await Future<void>.delayed(_phaseDuration);
    if (!continuous) ticker.start();
    stageStarts['animation_3'] = _mark('phase3');
    await Future<void>.delayed(_phaseDuration);
    ticker.dispose();
    final end = _mark('end');
    final probe = await debugPathMergeProbeResult?.timeout(_phaseDuration);
    // Give the engine time to deliver its final batch. / 等引擎交付最后一批帧计时。
    await Future<void>.delayed(const Duration(milliseconds: 1050));
    binding.removeTimingsCallback(collectTimings);
    final view = ui.PlatformDispatcher.instance.views.first;
    final report = {
      'art_frame': stageStarts.values.first,
      'phase_starts_us': stageStarts,
      'end_us': end,
      'continuous': continuous,
      'alternating': alternating,
      'merge_override': debugPathMergeOverride,
      'source_paths': _sourcePaths,
      'paths': info.pathCount,
      'display_hz': view.display.refreshRate,
      'dpr': view.devicePixelRatio,
      'shader_filter': ui.ImageFilter.isShaderFilterSupported,
      'probe': probe == null
          ? null
          : {
              'allowed': probe.allowed,
              'elapsed_us': probe.elapsed.inMicroseconds,
              'dpr': probe.dpr,
              'max_delta': probe.maxDelta,
              'started_us': probe.startedUs,
              'timed_out': probe.timedOut,
            },
      'frame_columns': [
        'number',
        ...ui.FramePhase.values.map((phase) => phase.name),
      ],
      'frames': [
        for (final frame in frames)
          [
            frame.frameNumber,
            ...ui.FramePhase.values.map(frame.timestampInMicroseconds),
          ],
      ],
    };
    file('result.tmp').writeAsStringSync(jsonEncode(report));
    file('result.tmp').renameSync(file('result.json').path);
    if (Platform.isWindows) {
      while (!file('exit').existsSync() && DateTime.now().isBefore(stopAt)) {
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
      exit(0);
    }
  } catch (error, stack) {
    file('error').writeAsStringSync('$error\n$stack');
    exit(1);
  }
}

/// Marks a phase boundary on the frame timings clock. / 在帧计时的同一时钟上标记阶段边界。
int _mark(String name) {
  Timeline.instantSync('xvg.mergeJank.$name');
  return Timeline.now;
}

/// Builds disjoint SVG polygons, optionally alternating every fill as in the previous benchmark. / 构造相离 SVG 多边形，可沿用旧基准的逐条交替填色。
String _buildSvg({required bool alternating}) {
  const columns = 16;
  final source = StringBuffer(
    '<svg xmlns="http://www.w3.org/2000/svg" width="160" height="96">',
  );
  for (var i = 0; i < _sourcePaths; i++) {
    final fill = alternating ? i : i ~/ columns;
    source.write(
      '<path fill="#${fill.isEven ? '3584e4' : '33d17a'}" '
      'd="M${(i % columns) * 10} ${(i ~/ columns) * 8}l8 1 -2 5 -6 -1Z"/>',
    );
  }
  source.write('</svg>');
  return source.toString();
}

/// Keeps the SVG visible while a separate marker moves each frame. / 持续显示 SVG，每帧更新一个独立移动标记。
class _Scene extends CustomPainter {
  /// Repaints when either the SVG arrives or the marker moves. / SVG 到达或标记移动时重绘。
  _Scene(this.art, this.motion)
    : super(repaint: Listenable.merge([art, motion]));

  /// The first complex cached picture. / 首张复杂缓存 Picture。
  final ValueNotifier<ui.Picture?> art;

  /// The marker position as a fraction of the available width. / 标记在可用宽度内的相对位置。
  final ValueNotifier<double> motion;

  /// Paints the SVG and moving marker. / 绘制 SVG 和移动标记。
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawColor(const Color(0xff19212b), BlendMode.src);
    final picture = art.value;
    if (picture != null) {
      canvas.save();
      canvas.translate(12, 12);
      canvas.drawPicture(picture);
      canvas.restore();
    }
    canvas.drawRect(
      Rect.fromLTWH((size.width - 16) * motion.value, 124, 16, 16),
      Paint()..color = const Color(0xfff8e45c),
    );
  }

  /// Uses the listenables for all repaints. / 由监听对象触发重绘。
  @override
  bool shouldRepaint(_Scene oldDelegate) => false;
}
