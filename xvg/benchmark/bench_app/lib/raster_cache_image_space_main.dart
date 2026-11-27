// Internal cache controls and the shell's Material implementation are intentional.
// ignore_for_file: deprecated_member_use, implementation_imports, invalid_use_of_visible_for_testing_member

import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:xvg/src/rust/api/svg.dart' show parseSvgAsync;
import 'package:xvg/src/xvg_raster_cache.dart';
import 'package:xvg/xvg.dart';

import 'raster_cache_auto_bench.dart' show runRasterCacheAutomatic;
import 'svg_gen.dart';

/// Runtime-only input and output directory. / 仅运行时使用的输入输出目录。
const _root =
    '/sdcard/Android/data/com.example.bench_app/files/xvg-image-space';

/// Modes measured with the same runtime APK. / 同一个 APK 测量的全部模式。
const _modes = {'off': XvgRasterCacheOverride.disabled, 'final': null};

/// Baseline layout width for the zoom artwork. / 缩放插画的基础布局宽度。
const _zoomWidth = 360.0;

/// The zoom endpoint used for both animation and capture. / 动画及截图使用的缩放终点。
const _zoomEndpoint = 4.0;

/// Animation and stable endpoint durations. / 动画与终点停稳时长。
const _motion = Duration(milliseconds: 720);
const _hold = Duration(seconds: 1);

/// Stable foreground used by image captures. / 截图使用的固定前景色。
const _paper = Color(0xfff6f5f6);

/// The same distinct Material Design Icons as the existing scroll benchmark. / 复用现有滚动基准的互异 Material Design 图标。
const _iconCount = 1000;
const _iconColumns = 8;

/// Replaces status atomically while the host polls. / 主机轮询期间原子更新状态。
void _status(String value) => (File(
  '$_root/status.tmp',
)..writeAsStringSync(value, flush: true)).renameSync('$_root/status.txt');

/// Reads the plan and warms only the vector pictures. / 读取计划并只预热向量 Picture。
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (File(
    '/sdcard/Android/data/com.example.bench_app/files/xvg-auto-mode/plan.json',
  ).existsSync()) {
    await runRasterCacheAutomatic();
    return;
  }
  try {
    final plan = jsonDecode(
      File('$_root/plan.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    await RustLib.init();
    final sources = <String, String>{};
    final features = <String, Object?>{};
    final ids = List<String>.from(plan['ids'] as List);
    final icons = generateIcons(_iconCount);
    RustXvgPictureCache.instance.maximumSize = icons.length + ids.length;
    for (final id in ids) {
      final source = File('$_root/$id.svg').readAsStringSync();
      sources[id] = source;
      final scene = await parseSvgAsync(data: source);
      features[id] = [scene.paths.length, scene.width, scene.height];
      await RustXvgPictureCache.instance.getOrRenderAsync(source);
    }
    for (final icon in icons) {
      await RustXvgPictureCache.instance.getOrRenderAsync(icon);
    }
    runApp(MaterialApp(home: _Bench(plan, sources, features, icons)));
  } catch (error, stack) {
    _status('error $error\n$stack');
  }
}

/// Records the action window and image state for each measurement. / 记录各次测量的动作窗口及位图状态。
class _Bench extends StatefulWidget {
  /// Owns immutable inputs shared by all scenarios. / 持有场景共用的固定输入。
  const _Bench(this.plan, this.sources, this.features, this.icons);

  /// Cases, capture configuration and device inputs. / 测量组合、截图设置和设备输入。
  final Map<String, dynamic> plan;

  /// Preloaded SVG samples and their parsed descriptors. / 已加载 SVG 及解析特征。
  final Map<String, String> sources;
  final Map<String, Object?> features;

  /// Distinct warmed vector icons for the grid. / 图标网格已经预热的互异向量图。
  final List<String> icons;

  @override
  State<_Bench> createState() => _BenchState();
}

/// Drives real routes, clips, Hero flights, and retained scroll transforms. / 驱动实际路由、裁剪、Hero 飞行与滚动变换。
class _BenchState extends State<_Bench> with TickerProviderStateMixin {
  /// Captures only the zoom viewport. / 仅捕获缩放视口。
  final _zoomBoundary = GlobalKey();

  /// Active workload selected by the driver. / 驱动器选中的当前场景。
  Widget _body = const SizedBox.expand();

  /// Collected engine frame timings. / 引擎帧计时记录。
  final _frames = <List<int>>[];

  /// Complete request intervals and texture samples in the active window. / 当前窗口内的完整请求区间及纹理采样。
  final _requests = <List<int>>[];
  final _memory = <List<int>>[];
  List<int>? _request;

  /// Drives regular frames while static endpoints settle. / 在静态阶段持续触发普通帧。
  late final AnimationController _heartbeat;

  /// Stops collecting before captures and teardown. / 在截图和卸载前停止采集。
  bool _collecting = false;

  @override
  void initState() {
    super.initState();
    _heartbeat = AnimationController(vsync: this, duration: _hold)..repeat();
    SchedulerBinding.instance.addTimingsCallback(_timings);
    debugXvgRasterRequest = _rasterRequest;
    unawaited(_run());
  }

  @override
  void dispose() {
    debugXvgRasterRequest = null;
    SchedulerBinding.instance.removeTimingsCallback(_timings);
    _heartbeat.dispose();
    super.dispose();
  }

  /// Records timing phases in the monotonic engine clock. / 记录引擎单调时钟上的各计时阶段。
  void _timings(List<ui.FrameTiming> timings) {
    if (!_collecting) return;
    for (final frame in timings) {
      _frames.add([
        for (final phase in [
          ui.FramePhase.vsyncStart,
          ui.FramePhase.buildStart,
          ui.FramePhase.rasterStart,
          ui.FramePhase.rasterFinish,
        ])
          frame.timestampInMicroseconds(phase),
      ]);
    }
  }

  /// Records width, height, request time, scene vsync, and handle return. / 记录尺寸、请求时刻、场景 vsync 和句柄返回时刻。
  void _rasterRequest(bool started, int width, int height) {
    final now = developer.Timeline.now;
    if (started) {
      _request = _collecting
          ? [
              width,
              height,
              now,
              SchedulerBinding
                  .instance
                  .currentSystemFrameTimeStamp
                  .inMicroseconds,
            ]
          : null;
    } else if (_request case final request?) {
      _requests.add([...request, now]);
      _request = null;
    }
  }

  /// Adds a low-cost draw to ensure static viewport frames reach raster. / 添加低开销绘制使静态视口帧提交到 raster。
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: _paper,
    body: Stack(
      fit: StackFit.expand,
      children: [
        _body,
        Positioned(
          top: 0,
          left: 0,
          child: RepaintBoundary(
            child: CustomPaint(
              size: const Size(2, 2),
              painter: _Pulse(_heartbeat, _sampleMemory),
            ),
          ),
        ),
      ],
    ),
  );

  /// Captures resident bytes on each framework frame. / 每个框架帧记录驻留字节。
  void _sampleMemory() {
    if (_collecting) {
      _memory.add([developer.Timeline.now, XvgRasterCache.bytesUsed]);
    }
  }

  /// Renders an SVG at a fixed layout size using the normal widget entry point. / 经常规组件入口按固定尺寸绘制 SVG。
  Widget _art(String id, double width, [double? height]) =>
      StaticXvg(widget.sources[id]!, width: width, height: height ?? width);

  /// Mounts a scene and waits until at least one frame is submitted. / 挂载场景并等待至少一帧提交。
  Future<void> _show(Widget body) async {
    setState(() => _body = body);
    await SchedulerBinding.instance.endOfFrame;
  }

  /// Runs the current batch and checkpoints each completed case. / 运行当前批并逐组落盘。
  Future<void> _run() async {
    final output = File('$_root/frames.jsonl').openWrite();
    try {
      await SchedulerBinding.instance.endOfFrame;
      if (!mounted) return;
      final view = View.of(context);
      if (widget.plan['trace'] == true) {
        _status('ready');
        while (!File('$_root/trace.ready').existsSync()) {
          await Future<void>.delayed(const Duration(milliseconds: 25));
        }
      }
      output.writeln(
        jsonEncode({
          'dpr': view.devicePixelRatio,
          'hz': view.display.refreshRate,
          'size': [view.physicalSize.width, view.physicalSize.height],
          'features': widget.features,
        }),
      );
      for (final raw in widget.plan['cases'] as List<dynamic>) {
        final test = Map<String, dynamic>.from(raw as Map);
        final scenario = test['scenario'] as String;
        final mode = test['mode'] as String;
        final round = test['round'] as int;
        _status('running $round $scenario $mode');
        await _show(const SizedBox.expand());
        await Future<void>.delayed(const Duration(milliseconds: 140));
        debugXvgRasterCacheOverride = _modes[mode];
        _frames.clear();
        _requests.clear();
        _memory.clear();
        _request = null;
        _collecting = true;
        final startEpoch = DateTime.now().millisecondsSinceEpoch;
        final start = developer.Timeline.now;
        final phases = <String, int>{};
        await _exercise(scenario, phases);
        final end = developer.Timeline.now;
        final endEpoch = DateTime.now().millisecondsSinceEpoch;
        final resident = XvgRasterCache.bytesUsed;
        // Profile mode delivers frame timings in batches. / Profile 模式会批量下发帧计时。
        await Future<void>.delayed(const Duration(milliseconds: 420));
        _collecting = false;
        output.writeln(
          jsonEncode({
            ...test,
            'start': start,
            'end': end,
            'start_epoch_ms': startEpoch,
            'end_epoch_ms': endEpoch,
            'phases': phases,
            'resident': resident,
            'frames': _frames
                .where((frame) => frame[1] >= start && frame[1] <= end)
                .toList(),
            'requests': _requests.where((request) => request[2] < end).toList(),
            'memory': _memory.where((sample) => sample[0] < end).toList(),
          }),
        );
        await output.flush();
      }
      if (widget.plan['capture'] == true) await _captureZoom();
      _status('done');
    } catch (error, stack) {
      _status('error $error\n$stack');
    } finally {
      await output.close();
      _heartbeat.stop();
    }
  }

  /// Selects the exact workload for a benchmark case. / 为一组测量选定场景。
  Future<void> _exercise(String scenario, Map<String, int> phases) async {
    final navigator = Navigator.of(context);
    switch (scenario) {
      case 'route':
        final route = MaterialPageRoute<void>(
          builder: (_) => Scaffold(
            backgroundColor: _paper,
            body: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _art('web-543', 104),
                  _art('aurora', 76, 304),
                  _art('web-469', 116),
                ],
              ),
            ),
          ),
        );
        unawaited(navigator.push(route));
        await Future<void>.delayed(const Duration(milliseconds: 780));
        phases['pop'] = developer.Timeline.now;
        navigator.pop();
        await route.completed;
      case 'dialog':
        final done = showGeneralDialog<void>(
          context: context,
          barrierDismissible: false,
          transitionDuration: const Duration(milliseconds: 300),
          pageBuilder: (_, _, _) => Center(
            child: Material(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: _art('aurora', 102, 408),
              ),
            ),
          ),
          transitionBuilder: (_, motion, _, child) => FadeTransition(
            opacity: motion,
            child: ScaleTransition(
              scale: Tween(begin: 0.65, end: 1.0).animate(motion),
              child: child,
            ),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 690));
        phases['pop'] = developer.Timeline.now;
        navigator.pop();
        await done;
        await Future<void>.delayed(const Duration(milliseconds: 340));
      case 'hero':
        await _show(
          Center(
            child: Hero(tag: 'hero', child: _art('web-469', 104, 53)),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 100));
        phases['push'] = developer.Timeline.now;
        final route = MaterialPageRoute<void>(
          builder: (_) => Scaffold(
            backgroundColor: _paper,
            body: Center(
              child: Hero(tag: 'hero', child: _art('web-469', 330, 168)),
            ),
          ),
        );
        unawaited(navigator.push(route));
        await Future<void>.delayed(const Duration(milliseconds: 730));
        phases['pop'] = developer.Timeline.now;
        navigator.pop();
        await route.completed;
      case 'list48' || 'list200' || 'icons':
        await _scroll(scenario, phases);
      case 'zoom':
        await _zoom(phases);
      default:
        throw StateError('Unknown scenario $scenario');
    }
  }

  /// Scrolls a fixed number of viewport lengths without realizing the whole list. / 连续滚动固定屏数，懒构建列表。
  Future<void> _scroll(String scenario, Map<String, int> phases) async {
    final controller = ScrollController();
    final icons = scenario == 'icons';
    final edge = scenario == 'list200' ? 200.0 : 48.0;
    final ids = List<String>.from(widget.plan['medium'] as List);
    await _show(
      icons
          ? GridView.builder(
              controller: controller,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: _iconColumns,
              ),
              itemCount: widget.icons.length,
              itemBuilder: (_, index) => Center(
                child: StaticXvg(widget.icons[index], width: 32, height: 32),
              ),
            )
          : ListView.builder(
              controller: controller,
              itemExtent: edge,
              itemCount: ids.length,
              itemBuilder: (_, index) => Center(child: _art(ids[index], edge)),
            ),
    );
    phases['scroll'] = developer.Timeline.now;
    final max = controller.position.maxScrollExtent;
    await controller.animateTo(
      max,
      duration: const Duration(milliseconds: 1650),
      curve: Curves.linear,
    );
    phases['visible_bytes_at_stop'] = XvgRasterCache.bytesUsed;
    await _show(const SizedBox.expand());
    controller.dispose();
  }

  /// Uses InteractiveViewer's regular compositing path with scripted matrices. / 以程序矩阵驱动 InteractiveViewer 的常规合成链路。
  Widget _viewer(TransformationController transform) => Center(
    child: SizedBox(
      width: _zoomWidth,
      height: 300,
      child: RepaintBoundary(
        key: _zoomBoundary,
        child: ColoredBox(
          color: _paper,
          child: InteractiveViewer(
            transformationController: transform,
            maxScale: _zoomEndpoint,
            child: _art('web-469', _zoomWidth, 300),
          ),
        ),
      ),
    ),
  );

  /// Sets the zoom about the viewport center. / 围绕视口中心缩放。
  void _setZoom(TransformationController transform, double value) {
    transform.value = Matrix4.translationValues(
      (1 - value) * _zoomWidth / 2,
      (1 - value) * 150,
      0,
    )..scaleByDouble(value, value, 1, 1);
  }

  /// Animates up, holds, animates back, and holds for the downsample. / 放大停稳、缩回并等待降采样。
  Future<void> _zoom(Map<String, int> phases) async {
    final transform = TransformationController();
    final motion = AnimationController(vsync: this, duration: _motion);
    motion.addListener(
      () => _setZoom(transform, 1 + (_zoomEndpoint - 1) * motion.value),
    );
    await _show(_viewer(transform));
    await Future<void>.delayed(const Duration(milliseconds: 220));
    phases['up'] = developer.Timeline.now;
    await motion.forward();
    phases['hold4'] = developer.Timeline.now;
    await Future<void>.delayed(_hold);
    phases['down'] = developer.Timeline.now;
    phases['hold4_bytes'] = XvgRasterCache.bytesUsed;
    await motion.reverse();
    phases['hold1'] = developer.Timeline.now;
    await Future<void>.delayed(_hold);
    phases['hold1_bytes'] = XvgRasterCache.bytesUsed;
    await _show(const SizedBox.expand());
    motion.dispose();
    transform.dispose();
  }

  /// Captures each settled 4× viewport outside the performance windows. / 在性能窗口之外截图各模式停稳后的 4 倍视口。
  Future<void> _captureZoom() async {
    final dpr = View.of(context).devicePixelRatio;
    final references = <int, Uint8List>{};
    final comparisons = <String, Object?>{};
    for (final mode in _modes.keys) {
      _status('capture $mode');
      await _show(const SizedBox.expand());
      debugXvgRasterCacheOverride = _modes[mode];
      final transform = TransformationController();
      final motion = AnimationController(vsync: this, duration: _motion);
      motion.addListener(
        () => _setZoom(transform, 1 + (_zoomEndpoint - 1) * motion.value),
      );
      await _show(_viewer(transform));
      await Future<void>.delayed(const Duration(milliseconds: 600));
      for (final scale in [1, _zoomEndpoint.toInt()]) {
        if (scale != 1) {
          await motion.forward();
          await Future<void>.delayed(_hold);
        }
        final name = '$mode-$scale';
        final (pixels, width, height) = await _capture(name, dpr);
        final reference = references[scale];
        if (reference == null) references[scale] = pixels;
        comparisons[name] = {
          'size': [width, height],
          'resident': XvgRasterCache.bytesUsed,
          if (reference != null) ..._pixelDifference(reference, pixels),
        };
      }
      await _show(const SizedBox.expand());
      motion.dispose();
      transform.dispose();
    }
    await File('$_root/clarity.json').writeAsString(jsonEncode(comparisons));
  }

  /// Saves one PNG and returns its raw pixels for the exact comparison. / 保存 PNG 并返回精确对照所需的原始像素。
  Future<(Uint8List, int, int)> _capture(String name, double dpr) async {
    final boundary =
        _zoomBoundary.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
    // Capture with the displayed physical origin so the cached phase is valid.
    // 按实际显示的物理原点截图，保留缓存相位对应的像素坐标。
    // ignore: invalid_use_of_protected_member
    ContainerLayer root = boundary.layer!;
    while (root.parent != null) {
      root = root.parent!;
    }
    final view = View.of(context);
    final scene = root.buildScene(ui.SceneBuilder());
    final fullWidth = view.physicalSize.width.toInt();
    final fullHeight = view.physicalSize.height.toInt();
    final frame = await scene.toImage(fullWidth, fullHeight);
    scene.dispose();
    final origin = boundary.localToGlobal(Offset.zero) * dpr;
    final left = origin.dx.round();
    final top = origin.dy.round();
    final width = (boundary.size.width * dpr).ceil();
    final height = (boundary.size.height * dpr).ceil();
    final source = Rect.fromLTWH(
      left.toDouble(),
      top.toDouble(),
      width.toDouble(),
      height.toDouble(),
    );
    final destination = Rect.fromLTWH(
      0,
      0,
      width.toDouble(),
      height.toDouble(),
    );
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawImageRect(frame, source, destination, Paint());
    final picture = recorder.endRecording();
    final image = await picture.toImage(width, height);
    try {
      final png = (await image.toByteData(format: ui.ImageByteFormat.png))!;
      await File('$_root/$name.png').writeAsBytes(png.buffer.asUint8List());
      final pixels = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      return (pixels.buffer.asUint8List(), width, height);
    } finally {
      image.dispose();
      picture.dispose();
      frame.dispose();
    }
  }

  /// Compares rendered RGB with the measured vector reference. / 对照实测向量图比较渲染 RGB。
  Map<String, Object> _pixelDifference(
    Uint8List reference,
    Uint8List candidate,
  ) {
    var sum = 0;
    var peak = 0;
    var changed = 0;
    var aboveEight = 0;
    for (var pixel = 0; pixel < reference.length; pixel += 4) {
      var local = 0;
      for (var channel = pixel; channel < pixel + 3; channel++) {
        final delta = (reference[channel] - candidate[channel]).abs();
        sum += delta;
        if (delta > local) local = delta;
      }
      if (local > peak) peak = local;
      if (local > 0) changed++;
      if (local > 8) aboveEight++;
    }
    return {
      'max_rgb_delta': peak,
      'mean_rgb_delta': sum / (reference.length * 0.75),
      'changed_pixels': changed,
      'pixels_delta_gt_8': aboveEight,
    };
  }
}

/// A tiny independently repainting draw that samples the memory ledger. / 独立重绘并采样内存账本的微小图元。
class _Pulse extends CustomPainter {
  /// Connects the pulse to a ticker and a byte sampler. / 连接帧计时器和字节采样器。
  _Pulse(this.phase, this.sample) : super(repaint: phase);

  /// Shared timing ticker and resident byte sampler. / 共用计时器及驻留字节采样器。
  final Animation<double> phase;
  final VoidCallback sample;

  @override
  void paint(Canvas canvas, Size size) {
    sample();
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = phase.value < 0.5 ? Colors.black : Colors.white,
    );
  }

  @override
  bool shouldRepaint(_Pulse oldDelegate) => false;
}
