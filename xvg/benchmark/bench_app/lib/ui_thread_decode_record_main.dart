// The profile harness deliberately uses the library's timing hooks and FRB
// dependency. / profile 基准需访问库的计时钩子及其现有 FRB 依赖。
// ignore_for_file: depend_on_referenced_packages, implementation_imports, invalid_use_of_visible_for_testing_member

import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';
import 'dart:ui' as ui;

// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/scheduler.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:xvg/src/rust/api/svg.dart';
import 'package:xvg/src/rust/frb_generated.dart';
import 'package:xvg/src/rust_static_svg.dart';
import 'package:xvg/src/xvg_raster_cache.dart';

import 'mdi_icons_1000.dart';

/// Isolated runtime directory. / 独立的设备运行目录。
const _root = '/sdcard/Android/data/com.example.bench_app/files/xvg-ui-stage';

/// Spinner observation on either side of the cold mount. / 冷挂载前后各留一段转圈观测时间。
const _spinnerWindow = Duration(milliseconds: 160);

/// Deadline for the first completed Flutter frame. / 首个完成帧的等待上限。
const _frameTimeout = Duration(seconds: 15);

/// Artwork box shared by timing and pixel capture. / 计时与像素采集共用的图稿尺寸。
const _artSize = Size(310, 450);

/// Time to observe raster work after the first artwork frame. / 首图帧后继续观察栅格工作的时长。
const _rasterWindow = Duration(milliseconds: 450);

/// Zoomed case exercises the tiled cache on the same source. / 缩放用例用相同源图实际触发分块缓存。
const _tiledSample = 'web-543-zoom';
const _tiledSource = 'web-543';
const _tileZoom = 2.0;

/// Loads the profile-only plan after the host stages runtime inputs. / 主机推送输入后读取 profile 基准计划。
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final plan = jsonDecode(
      File('$_root/plan.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final bridge = _MeasuredHandler();
    await RustLib.init(handler: bridge);
    runApp(MaterialApp(home: _Bench(plan, bridge)));
  } catch (error, stack) {
    _fail('startup', error, stack);
  }
}

/// Writes status without logging input text or paths. / 写入状态，只记录异常类型及调用栈。
void _fail(String step, Object error, StackTrace stack) {
  File('$_root/status').writeAsStringSync('error $step ${error.runtimeType}');
  File('$_root/error-stack').writeAsStringSync(stack.toString());
}

/// Records the monotonic boundaries for a single cold parse and recording. / 记录一次冷解析及录制的单调时钟边界。
class _Trace {
  /// Named timestamps on the Flutter timeline clock. / Flutter timeline 时钟上的具名时间戳。
  final times = <String, int>{};

  /// Unparsed Rust-to-Dart message size including the SSE action byte. / 未解码的 Rust 到 Dart 消息字节数，含 SSE action 字节。
  int? bytes;

  /// Scene held until counters can be read outside the timed interval. / 保留场景到计时结束后读取计数。
  SvgScene? scene;

  /// Parse dispatch selected by the actual library call. / 库实际选用的解析派发方式。
  String? dispatch;

  /// Optional callback for the first frame showing the picture. / 可选的首次显示 Picture 帧回调。
  VoidCallback? onRecorded;

  /// Image-space generation submission boundaries. / 图片坐标快照的提交边界。
  final requests = <List<int>>[];

  /// Marks a boundary on the engine monotonic clock. / 在引擎单调时钟上打点。
  void mark(String boundary) => times[boundary] = Timeline.now;

  /// Extracts scene counters after all measured boundaries. / 在所有计时边界之后提取场景计数。
  Map<String, Object?> finish(String id, int trial, int units) {
    final value = scene;
    if (value == null ||
        bytes == null ||
        times['record_done'] == null ||
        (value.paths.isEmpty && value.images.isEmpty)) {
      throw StateError('Incomplete or empty SVG render');
    }
    return {
      'id': id,
      'trial': trial,
      'units': units,
      'dispatch': dispatch,
      'bytes': bytes,
      'paths': value.paths.length,
      'commands': value.displayList?.commands.length ?? 0,
      'images': value.images.length,
      'recording_us': [times['record_done']! - times['record']!],
      'requests': requests,
      'times_us': times,
    };
  }
}

/// Uses the generated SSE codec and the default normal-task port handler. / 沿用生成的 SSE codec 和默认异步端口处理器。
class _MeasuredHandler extends BaseHandler {
  /// Only the currently measured cold miss is instrumented. / 只测当前的一次冷未命中。
  _Trace? active;

  /// Wraps the original async task at dispatch and message decode. / 在派发和消息解码处包装原异步任务。
  @override
  Future<S> executeNormal<S, E extends Object>(NormalTask<S, E> task) {
    final trace = active;
    if (trace == null ||
        task.constMeta.debugName !=
            'parse_svg_async_with_merge_policy(dart_style=parseSvgAsync)') {
      return super.executeNormal(task);
    }
    trace.dispatch = 'worker';
    return super.executeNormal(
      NormalTask<S, E>(
        callFfi: (port) {
          trace.mark('call');
          task.callFfi(port);
          trace.mark('call_return');
        },
        codec: _MeasuredCodec(task.codec as SseCodec<S, E>, trace),
        constMeta: task.constMeta,
        argValues: task.argValues,
        apiImpl: task.apiImpl,
      ),
    );
  }

  /// Times the same generated decoder for small synchronous control mounts. / 用相同的生成解码器测同步挂载的小图对照。
  @override
  S executeSync<S, E extends Object, W>(SyncTask<S, E, W> task) {
    final trace = active;
    if (trace == null ||
        task.constMeta.debugName !=
            'parse_svg_with_merge_policy(dart_style=parseSvg)') {
      return super.executeSync(task);
    }
    trace.dispatch = 'sync';
    trace.mark('call');
    final wire = task.callFfi();
    trace.mark('call_return');
    try {
      trace.bytes = wireSyncRust2DartSseAsUint8ListView(
        wire as WireSyncRust2DartSse,
      ).lengthInBytes;
      trace.mark('decode');
      final value = task.codec.decodeWireSyncType(wire);
      trace.mark('decode_done');
      trace.scene = value as SvgScene;
      return value;
    } finally {
      task.codec.freeWireSyncRust2Dart(
        wire,
        task.apiImpl.generalizedFrbRustBinding,
      );
    }
  }
}

/// Measures the original decoder with the exact port payload. / 用原端口载荷测生成的解码器。
class _MeasuredCodec<S, E extends Object> extends SseCodec<S, E> {
  /// Wraps an existing codec for one parse. / 针对一次解析包装已有 codec。
  _MeasuredCodec(this._original, this._trace)
    : super(
        decodeSuccessData: _original.decodeSuccessData,
        decodeErrorData: _original.decodeErrorData,
      );

  /// Original generated codec. / 原生成 codec。
  final SseCodec<S, E> _original;

  /// Timestamps for this call. / 本次调用的时间戳。
  final _Trace _trace;

  /// Captures the payload length without copying, then times deserialization. / 无拷贝读取载荷长度，再测反序列化。
  @override
  S decodeObject(dynamic raw) {
    _trace.mark('message');
    if (raw is Uint8List) _trace.bytes = raw.lengthInBytes;
    _trace.mark('decode');
    final value = _original.decodeObject(raw);
    _trace.mark('decode_done');
    _trace.scene = value as SvgScene;
    return value;
  }
}

/// Runs batch measurements on a stationary profile screen. / 在静止的 profile 页面运行批次测量。
class _Bench extends StatefulWidget {
  /// Creates the runner for one cold process. / 为一次冷进程创建运行器。
  const _Bench(this.plan, this.bridge);

  /// Host-provided sample and repeat plan. / 主机提供的样本和重复次数计划。
  final Map<String, dynamic> plan;

  /// Instrumented FRB handler for the normal generated API. / 正常生成 API 的计时 handler。
  final _MeasuredHandler bridge;

  /// Creates the screen state. / 创建页面状态。
  @override
  State<_Bench> createState() => _BenchState();
}

/// Mounts and removes one real StaticXvg at a time. / 每次挂载和移除一张真实 StaticXvg。
class _BenchState extends State<_Bench> {
  /// Shared library picture cache. / 库共享的 Picture 缓存。
  final _cache = RustXvgPictureCache.instance;

  /// Engine reports captured across the spinner trials. / 转圈试次期间采集的引擎报告。
  final _frames = <ui.FrameTiming>[];

  /// Identifies the measured art subtree across async placeholder frames. / 跨异步占位帧定位计时的图稿子树。
  final _artKey = GlobalKey();

  /// Identifies the art capture layer used after timing. / 定位计时结束后使用的图稿采集层。
  final _pixelKey = GlobalKey();

  /// Measures the displayed artwork layer. / 测量实际显示的图稿图层。
  bool get _displayedPixels => widget.plan['displayed_pixels'] == true;

  /// Runs only cold recording, whole-image snapshots and pixel comparison. / 只运行冷录制、整图快照和像素对比。
  bool get _quickMerge => widget.plan['quick_merge'] == true;

  /// Observation window long enough for queued tiles to finish. / 留出足够时间让排队的纹理块生成完。
  Duration get _tileWindow =>
      Duration(milliseconds: widget.plan['tile_window_ms'] as int);

  /// The active artwork, or null during the spinner baseline. / 当前图稿，转圈基线时为空。
  String? _source;

  /// Scale applied inside the fixed artwork viewport. / 固定图稿视口内的缩放比例。
  double _scale = 1;

  /// Whether the spinner should keep the page producing frames. / 是否用转圈让页面持续出帧。
  bool _spinner = false;

  /// Enables the screenshot layer only during pixel capture. / 只在像素采集阶段启用截图层。
  bool _capturingPixels = false;

  /// Installs library hooks before starting measurements. / 在测量开始前安装库钩子。
  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addTimingsCallback(_frames.addAll);
    RustXvgPictureCache.debugWrapRecordingCanvas = (canvas) {
      widget.bridge.active?.times.putIfAbsent('record', () => Timeline.now);
      return canvas;
    };
    debugXvgRasterRequest = (started, width, height) {
      widget.bridge.active?.requests.add([
        Timeline.now,
        started ? 1 : 0,
        width,
        height,
      ]);
    };
    _cache.onParseMiss = (_) {
      final trace = widget.bridge.active;
      trace?.mark('record_done');
      trace?.onRecorded?.call();
    };
    unawaited(_run());
  }

  /// Detects the first frame with the real painter in the artwork subtree. / 检测图稿子树首次挂上真实画家的帧。
  bool _hasArt(Element element) {
    final child = element.widget;
    if (child is XvgRasterPaint ||
        (child is CustomPaint && child.painter != null)) {
      return true;
    }
    var found = false;
    element.visitChildren((child) {
      if (!found) found = _hasArt(child);
    });
    return found;
  }

  /// Removes instrumentation when the benchmark screen is detached. / 页面卸载时移除计时钩子。
  @override
  void dispose() {
    SchedulerBinding.instance.removeTimingsCallback(_frames.addAll);
    RustXvgPictureCache.debugWrapRecordingCanvas = null;
    debugXvgRasterRequest = null;
    _cache.onParseMiss = null;
    super.dispose();
  }

  /// Reads one staged file or reuses the existing MDI control dataset. / 读取一份运行时文件或复用已有 MDI 对照集。
  Future<String> _read(String id) => id.startsWith('mdi-')
      ? Future.value(mdiIcons1000[int.parse(id.substring(4))])
      : File('$_root/${id == _tiledSample ? _tiledSource : id}.svg')
            .readAsString();

  /// Records a cold picture while forcing only the microbenchmark onto the worker. / 冷录制 Picture，仅在分段测量中强制走 worker。
  Future<_Trace> _stages(String source) async {
    final trace = _Trace();
    widget.bridge.active = trace;
    debugStaticSvgAsyncParseThreshold = 0;
    try {
      final info = await _cache.getOrRenderAsync(source);
      info.picture.dispose();
      return trace;
    } finally {
      _cache.clear();
      debugStaticSvgAsyncParseThreshold = null;
      widget.bridge.active = null;
    }
  }

  /// Captures the real widget's first painted frame with the spinner still moving. / 保持转圈，采集真实组件的首个绘制帧。
  Future<_Trace> _scenario(
    String source, {
    bool jump = false,
    bool tiled = false,
  }) async {
    if (!_quickMerge) await Future<void>.delayed(_spinnerWindow);
    final trace = _Trace();
    final shown = Completer<void>();
    void observeArt(Duration _) {
      if (widget.bridge.active != trace) return;
      final art = _artKey.currentContext;
      if (_displayedPixels && (art is! Element || !_hasArt(art))) {
        SchedulerBinding.instance.addPostFrameCallback(observeArt);
        return;
      }
      trace.times['first_art_frame'] =
          ui.PlatformDispatcher.instance.frameData.frameNumber;
      trace.mark('first_art_post_frame');
      shown.complete();
    }

    trace.onRecorded = () =>
        SchedulerBinding.instance.addPostFrameCallback(observeArt);
    widget.bridge.active = trace;
    trace.mark('mount');
    if (jump) {
      final navigator = Navigator.of(context);
      unawaited(
        navigator.push<void>(
          MaterialPageRoute(
            builder: (_) => Scaffold(body: Center(child: _art(source))),
          ),
        ),
      );
    } else {
      setState(() {
        _source = source;
        _scale = tiled ? _tileZoom : 1;
      });
    }
    await shown.future.timeout(_frameTimeout);
    await Future<void>.delayed(
      tiled
          ? _tileWindow
          : (widget.plan['drawcall'] == true || _displayedPixels
                ? _rasterWindow
                : _spinnerWindow),
    );
    trace.mark('window_end');
    final info = _cache.peek(source)!;
    if (jump) {
      Navigator.of(context).pop();
      await Future<void>.delayed(const Duration(milliseconds: 360));
    } else {
      setState(() => _source = null);
      await SchedulerBinding.instance.endOfFrame;
    }
    _cache.clear();
    info.picture.dispose();
    widget.bridge.active = null;
    return trace;
  }

  /// Exercises a cold scroll through the existing 1,000 distinct icons. / 使用现有一千个不同图标执行冷滚动。
  Future<Map<String, int>> _icons() async {
    final controller = ScrollController();
    final navigator = Navigator.of(context);
    _cache.clear();
    unawaited(
      navigator.push<void>(
        MaterialPageRoute(
          builder: (_) => Scaffold(
            body: GridView.builder(
              controller: controller,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 6,
              ),
              itemCount: mdiIcons1000.length,
              itemBuilder: (_, index) => Center(
                child: StaticXvg(mdiIcons1000[index], width: 32, height: 32),
              ),
            ),
          ),
        ),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 400));
    final start = Timeline.now;
    await controller.animateTo(
      controller.position.maxScrollExtent,
      duration: const Duration(milliseconds: 1650),
      curve: Curves.linear,
    );
    final end = Timeline.now;
    navigator.pop();
    await Future<void>.delayed(const Duration(milliseconds: 360));
    controller.dispose();
    _cache.clear();
    return {'start': start, 'end': end};
  }

  /// Captures original RGBA at the spinner artwork's physical size. / 捕获转圈场景图稿物理尺寸下的原始 RGBA。
  Future<void> _capture(String id, double dpr) async {
    final info = await _cache.getOrRenderAsync(await _read(id));
    final image = await rasterizeSvgPicture(
      info,
      width: (_artSize.width * dpr).round(),
      height: (_artSize.height * dpr).round(),
    );
    try {
      final rgba = (await image.toByteData())!.buffer.asUint8List();
      File('$_root/$id.rgba.z').writeAsBytesSync(ZLibEncoder().convert(rgba));
    } finally {
      image.dispose();
      _cache.clear();
      info.picture.dispose();
    }
  }

  /// Captures settled pixels from the displayed widget's layer. / 读取真机上已稳定显示的组件图层像素。
  Future<List<int>> _captureDisplayed(String id, double dpr) async {
    final source = await _read(id);
    setState(() {
      _capturingPixels = true;
      _source = source;
      _scale = id == _tiledSample ? _tileZoom : 1;
    });
    final watch = Stopwatch()..start();
    while (true) {
      await SchedulerBinding.instance.endOfFrame;
      final art = _artKey.currentContext;
      if (art is Element && _hasArt(art)) break;
      if (watch.elapsed > _frameTimeout) throw StateError('Artwork is missing');
    }
    await Future<void>.delayed(
      id == _tiledSample ? _tileWindow : _rasterWindow,
    );
    final boundary =
        _pixelKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: dpr);
    try {
      final rgba = (await image.toByteData())!.buffer.asUint8List();
      File('$_root/$id.rgba.z').writeAsBytesSync(ZLibEncoder().convert(rgba));
      return [image.width, image.height];
    } finally {
      image.dispose();
      setState(() {
        _capturingPixels = false;
        _source = null;
      });
      await SchedulerBinding.instance.endOfFrame;
      final info = _cache.peek(source)!;
      _cache.clear();
      info.picture.dispose();
    }
  }

  /// Runs the arranged cold trials and flushes the engine's timing batches. / 执行安排好的冷试次并等待引擎送齐批量帧数据。
  Future<void> _run() async {
    var step = 'warmup';
    final results = <Map<String, Object?>>[];
    final scenarios = <Map<String, Object?>>[];
    final jumps = <Map<String, Object?>>[];
    final pixelSizes = <String, List<int>>{};
    Map<String, int>? iconScroll;
    final status = File('$_root/status');
    try {
      await SchedulerBinding.instance.endOfFrame;
      if (!mounted) return;
      final view = View.of(context);
      final plan = widget.plan;
      final trials = plan['trials'] as int;
      final samples = (plan['samples'] as List<dynamic>).cast<String>();
      final drawcall = plan['drawcall'] == true;
      if (drawcall || _displayedPixels) {
        status.writeAsStringSync('ready');
        while (!File('$_root/trace.ready').existsSync()) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
      }
      for (final id in samples) {
        step = 'stages $id';
        status.writeAsStringSync(step);
        final source = await _read(id);
        for (var trial = 1; trial <= trials; trial++) {
          final trace = await _stages(source);
          results.add(trace.finish(id, trial, source.length));
        }
      }
      if (!_quickMerge) {
        setState(() => _spinner = true);
        await Future<void>.delayed(const Duration(milliseconds: 700));
      }
      for (final id in samples) {
        step = 'scenario $id';
        status.writeAsStringSync(step);
        final source = await _read(id);
        for (var trial = 1; trial <= trials; trial++) {
          final trace = await _scenario(source, tiled: id == _tiledSample);
          scenarios.add({
            ...trace.finish(id, trial, source.length),
            'hz': view.display.refreshRate,
          });
        }
      }
      if (!_quickMerge) setState(() => _spinner = false);
      if (_displayedPixels) {
        for (final id in samples) {
          step = 'pixels $id';
          status.writeAsStringSync(step);
          pixelSizes[id] = await _captureDisplayed(id, view.devicePixelRatio);
        }
      }
      if (_displayedPixels && !_quickMerge) {
        step = 'icons';
        status.writeAsStringSync(step);
        iconScroll = await _icons();
      }
      if (drawcall) {
        for (final id in samples) {
          step = 'jump $id';
          status.writeAsStringSync(step);
          final source = await _read(id);
          final trace = await _scenario(source, jump: true);
          jumps.add({
            ...trace.finish(id, 1, source.length),
            'hz': view.display.refreshRate,
          });
        }
        step = 'icons';
        status.writeAsStringSync(step);
        iconScroll = await _icons();
        for (final id in samples) {
          step = 'pixels $id';
          status.writeAsStringSync(step);
          await _capture(id, view.devicePixelRatio);
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 1250));
      File('$_root/result.json').writeAsStringSync(
        jsonEncode({
          'round': plan['round'],
          'width_px': view.physicalSize.width,
          'height_px': view.physicalSize.height,
          'dpr': view.devicePixelRatio,
          'stages': results,
          'scenarios': scenarios,
          'jumps': jumps,
          'icon_scroll': iconScroll,
          'pixel_sizes': pixelSizes,
          'frame_phases': [
            ...ui.FramePhase.values.map((phase) => phase.name),
            'frameNumber',
          ],
          'frames': [
            for (final frame in _frames)
              [
                for (final phase in ui.FramePhase.values)
                  frame.timestampInMicroseconds(phase),
                frame.frameNumber,
              ],
          ],
        }),
      );
      status.writeAsStringSync('done');
    } catch (error, stack) {
      _fail(step, error, stack);
    }
  }

  /// Same art constraints in both route and spinner cases. / 路由和转圈场景使用相同的图稿约束。
  Widget _art(String? source) {
    final art = source == null ? null : StaticXvg(source, fit: BoxFit.contain);
    final box = SizedBox.fromSize(
      key: _displayedPixels ? _artKey : null,
      size: _artSize,
      child: _scale == 1
          ? art
          : ClipRect(
              child: Transform.scale(scale: _scale, child: art),
            ),
    );
    return _capturingPixels ? RepaintBoundary(key: _pixelKey, child: box) : box;
  }

  /// Keeps the layout static while the separate spinner produces frames. / 固定布局，由独立的转圈区域持续出帧。
  @override
  Widget build(BuildContext context) {
    final source = _source;
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox.square(
              dimension: 28,
              child: _spinner
                  ? const RepaintBoundary(child: CircularProgressIndicator())
                  : null,
            ),
            _art(source),
          ],
        ),
      ),
    );
  }
}
