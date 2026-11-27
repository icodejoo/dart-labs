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
import 'package:flutter/scheduler.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:xvg/src/rust/api/svg.dart';
import 'package:xvg/src/rust/frb_generated.dart';
import 'package:xvg/src/rust_static_svg.dart';

import 'mdi_icons_1000.dart';

/// Isolated runtime directory. / 独立的设备运行目录。
const _root = '/sdcard/Android/data/com.example.bench_app/files/xvg-ui-stage';

/// Spinner observation on either side of the cold mount. / 冷挂载前后各留一段转圈观测时间。
const _spinnerWindow = Duration(milliseconds: 160);

/// Deadline for the first completed Flutter frame. / 首个完成帧的等待上限。
const _frameTimeout = Duration(seconds: 15);

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
    if (trace == null || task.constMeta.debugName != 'parse_svg_async') {
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
    if (trace == null || task.constMeta.debugName != 'parse_svg') {
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

  /// The active artwork, or null during the spinner baseline. / 当前图稿，转圈基线时为空。
  String? _source;

  /// Whether the spinner should keep the page producing frames. / 是否用转圈让页面持续出帧。
  bool _spinner = false;

  /// Installs library hooks before starting measurements. / 在测量开始前安装库钩子。
  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addTimingsCallback(_frames.addAll);
    RustXvgPictureCache.debugWrapRecordingCanvas = (canvas) {
      widget.bridge.active?.mark('record');
      return canvas;
    };
    _cache.onParseMiss = (_) {
      final trace = widget.bridge.active;
      trace?.mark('record_done');
      trace?.onRecorded?.call();
    };
    unawaited(_run());
  }

  /// Removes instrumentation when the benchmark screen is detached. / 页面卸载时移除计时钩子。
  @override
  void dispose() {
    SchedulerBinding.instance.removeTimingsCallback(_frames.addAll);
    RustXvgPictureCache.debugWrapRecordingCanvas = null;
    _cache.onParseMiss = null;
    super.dispose();
  }

  /// Reads one staged file or reuses the existing MDI control dataset. / 读取一份运行时文件或复用已有 MDI 对照集。
  Future<String> _read(String id) => id.startsWith('mdi-')
      ? Future.value(mdiIcons1000[int.parse(id.substring(4))])
      : File('$_root/$id.svg').readAsString();

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
  Future<_Trace> _scenario(String source) async {
    await Future<void>.delayed(_spinnerWindow);
    final trace = _Trace();
    final shown = Completer<void>();
    trace.onRecorded = () {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        trace.times['first_art_frame'] =
            ui.PlatformDispatcher.instance.frameData.frameNumber;
        trace.mark('first_art_post_frame');
        shown.complete();
      });
    };
    widget.bridge.active = trace;
    trace.mark('mount');
    setState(() => _source = source);
    await shown.future.timeout(_frameTimeout);
    await Future<void>.delayed(_spinnerWindow);
    trace.mark('window_end');
    final info = _cache.peek(source)!;
    setState(() => _source = null);
    await SchedulerBinding.instance.endOfFrame;
    _cache.clear();
    info.picture.dispose();
    widget.bridge.active = null;
    return trace;
  }

  /// Runs the arranged cold trials and flushes the engine's timing batches. / 执行安排好的冷试次并等待引擎送齐批量帧数据。
  Future<void> _run() async {
    var step = 'warmup';
    final results = <Map<String, Object?>>[];
    final scenarios = <Map<String, Object?>>[];
    final status = File('$_root/status');
    try {
      await SchedulerBinding.instance.endOfFrame;
      if (!mounted) return;
      final view = View.of(context);
      final plan = widget.plan;
      final trials = plan['trials'] as int;
      final samples = (plan['samples'] as List<dynamic>).cast<String>();
      for (final id in samples) {
        step = 'stages $id';
        status.writeAsStringSync(step);
        final source = await _read(id);
        for (var trial = 1; trial <= trials; trial++) {
          final trace = await _stages(source);
          results.add(trace.finish(id, trial, source.length));
        }
      }
      setState(() => _spinner = true);
      await Future<void>.delayed(const Duration(milliseconds: 700));
      for (final id in samples) {
        step = 'scenario $id';
        status.writeAsStringSync(step);
        final source = await _read(id);
        for (var trial = 1; trial <= trials; trial++) {
          final trace = await _scenario(source);
          scenarios.add({
            ...trace.finish(id, trial, source.length),
            'hz': view.display.refreshRate,
          });
        }
      }
      setState(() => _spinner = false);
      await Future<void>.delayed(const Duration(milliseconds: 1250));
      File('$_root/result.json').writeAsStringSync(
        jsonEncode({
          'round': plan['round'],
          'width_px': view.physicalSize.width,
          'height_px': view.physicalSize.height,
          'dpr': view.devicePixelRatio,
          'stages': results,
          'scenarios': scenarios,
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
            SizedBox(
              width: 310,
              height: 450,
              child: source == null
                  ? null
                  : StaticXvg(source, fit: BoxFit.contain),
            ),
          ],
        ),
      ),
    );
  }
}
