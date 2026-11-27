// 基准直接使用 xvg 内部的阈值覆盖和录制探针，以及 xvg 已使用的 FRB。
// ignore_for_file: implementation_imports, depend_on_referenced_packages, invalid_use_of_visible_for_testing_member

import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

// 沿用 bench_app 现有的 Material 页面组件。
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:xvg/src/rust_static_svg.dart';

import 'frame_timing.dart';
import 'mdi_icons_1000.dart';
import 'report_sink.dart';
import 'stats.dart';

/// 校准档位，单位 KiB。样本均为 ASCII，字节数等于字符串长度。
const asyncThresholdSizesKiB = [4, 8, 16, 32, 48, 64, 96, 128, 192, 256];

/// 每档的不同内容样本数，同一源分别冷测同步和异步。
const _samplesPerSize = 9;

/// 全部计时字段使用微秒，帧数量单独记录。
const _syncWork = 'parse_record_us';
const _dispatch = 'dispatch_us';
const _decode = 'decode_us';
const _record = 'record_us';
const _asyncWork = 'ui_work_us';
const _raster = 'to_raster_us';
const _placeholders = 'placeholder_frames';
const _asyncParseName =
    'parse_svg_async_with_merge_policy(dart_style=parseSvgAsync)';

/// 拼接平铺的 MDI 图形，最后只补齐放不下一整图的尾部空白。
String makeAsyncThresholdSvg(int sizeKiB, int seed) {
  const bytesPerKiB = 1024;
  const tileSize = 24;
  const columns = 32;
  const open =
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${columns * tileSize} ';
  const close = '</svg>';
  const endOfViewBox = '">';
  const viewBoxHeightDigits = 4;
  final available =
      sizeKiB * bytesPerKiB -
      open.length -
      viewBoxHeightDigits -
      endOfViewBox.length -
      close.length;
  final icons = StringBuffer();
  var count = 0;
  for (;;) {
    final icon = mdiIcons1000[(seed + count) % mdiIcons1000.length];
    final inner = icon.substring(icon.indexOf('>') + 1, icon.indexOf(close));
    final x = count % columns * tileSize;
    final y = count ~/ columns * tileSize;
    final group = '<g transform="translate($x $y)">$inner</g>';
    if (icons.length + group.length > available) break;
    icons.write(group);
    count++;
  }
  final height = ((count + columns - 1) ~/ columns) * tileSize;
  final viewBoxHeight = height.toString().padLeft(viewBoxHeightDigits, '0');
  return '$open$viewBoxHeight$endOfViewBox${icons.toString().padRight(available)}$close';
}

/// 在原有 FRB handler 中计量异步调用的 Dart 派发和 SSE 解码。
class AsyncThresholdHandler extends BaseHandler {
  /// 当前异步样本。预热和其他调用直接使用基类的行为。
  _Trial? _trial;

  /// 保留原派发和编解码逻辑，只在计量窗口加时间戳。
  @override
  Future<S> executeNormal<S, E extends Object>(NormalTask<S, E> task) {
    final trial = _trial;
    final codec = task.codec;
    if (trial == null ||
        task.constMeta.debugName != _asyncParseName ||
        codec is! SseCodec<S, E>) {
      return super.executeNormal(task);
    }
    final start = developer.Timeline.now;
    final result = super.executeNormal(
      NormalTask<S, E>(
        callFfi: task.callFfi,
        codec: _TimedDecode<S, E>(codec, trial),
        constMeta: task.constMeta,
        argValues: task.argValues,
        apiImpl: task.apiImpl,
      ),
    );
    trial.dispatchUs = developer.Timeline.now - start;
    return result;
  }
}

/// 使用生成的 SSE 解码函数，在 Dart 解码入口外计时。
class _TimedDecode<S, E extends Object> extends SseCodec<S, E> {
  /// 绑定当前样本和真实的成功、错误解码器。
  _TimedDecode(SseCodec<S, E> codec, this._trial)
    : super(
        decodeSuccessData: codec.decodeSuccessData,
        decodeErrorData: codec.decodeErrorData,
      );

  /// 接收解码计时的样本。
  final _Trial _trial;

  /// 计量结果对象的解码时间。
  @override
  S decodeObject(dynamic raw) {
    final start = developer.Timeline.now;
    final result = super.decodeObject(raw);
    _trial.decodeUs = developer.Timeline.now - start;
    return result;
  }
}

/// 采集一次冷挂载从请求、解析录制到首张图光栅完成的时间。
class _Trial {
  /// 指定档位、样本和强制的解析模式。
  _Trial(this.sizeKiB, this.sample, this.source, {required this.useAsync});

  /// 目标大小，单位 KiB。
  final int sizeKiB;

  /// 同档位内的样本编号。
  final int sample;

  /// 本次试验的 SVG 源。
  final String source;

  /// 是否通过异步缓存入口在 FRB worker 上解析。
  final bool useAsync;

  /// 请求挂载的单调时间戳。
  late final int requestedAt;

  /// 第一次绘制占位或实际图片的单调时间戳。
  int? firstPaintAt;

  /// 第一次绘制实际图片的单调时间戳。
  int? picturePaintAt;

  /// 从录制 canvas 准备好之后开始计量的时间戳。
  int? recordStartedAt;

  /// 缓存未命中的解析加录制总耗时。
  Duration? parseRecord;

  /// Dart 端构造并派发异步调用的耗时。
  int? dispatchUs;

  /// Dart 端解码异步响应的耗时。
  int? decodeUs;

  /// 从录制起点到缓存未命中回调的耗时。
  int? recordUs;

  /// 绘制完成后返回图片，用于记录回收。
  final painted = Completer<RustSvgPictureInfo>();

  /// 通过绘制时间戳定位首帧和出图帧，并核实本次走了指定路径。
  Map<String, int> measurements(List<ui.FrameTiming> frames) {
    final first = frames.indexWhere(
      (frame) => _containsPaint(frame, firstPaintAt!),
    );
    final picture = frames.indexWhere(
      (frame) => _containsPaint(frame, picturePaintAt!),
      math.max(0, first),
    );
    if (first < 0 ||
        picture < 0 ||
        parseRecord == null ||
        (useAsync &&
            (dispatchUs == null || decodeUs == null || recordUs == null))) {
      throw StateError('Incomplete timing for $sizeKiB KiB sample $sample');
    }
    return {
      'sample': sample,
      _syncWork: parseRecord!.inMicroseconds,
      if (useAsync) ...{
        _dispatch: dispatchUs!,
        _decode: decodeUs!,
        _record: recordUs!,
        _asyncWork: dispatchUs! + decodeUs! + recordUs!,
      },
      _raster:
          frames[picture].timestampInMicroseconds(ui.FramePhase.rasterFinish) -
          requestedAt,
      _placeholders: picture - first,
    };
  }

  /// Flutter 的 build 区间包含 UI 绘制，光栅阶段由引擎另报。
  bool _containsPaint(ui.FrameTiming frame, int paintAt) =>
      frame.timestampInMicroseconds(ui.FramePhase.buildStart) <= paintAt &&
      paintAt <= frame.timestampInMicroseconds(ui.FramePhase.buildFinish);
}

/// 按档采样并输出可复核的原始记录，保持页面工作量对两种路径一致。
class AsyncThresholdBench extends StatefulWidget {
  /// 使用随 RustLib 初始化的 FRB 计时 handler。
  const AsyncThresholdBench({super.key, required this.handler});

  /// 记录本基准异步 FFI 调用的 Dart 耗时。
  final AsyncThresholdHandler handler;

  /// 创建校准页的运行状态。
  @override
  State<AsyncThresholdBench> createState() => _AsyncThresholdBenchState();
}

/// 串行执行样本，避免多个 SVG 同时争用解析和 UI 线程。
class _AsyncThresholdBenchState extends State<AsyncThresholdBench> {
  /// 缓存与录制使用实际库代码。
  final _cache = RustXvgPictureCache.instance;

  /// 页面当前的冷挂载样本。
  _Trial? _trial;

  /// 整次运行结束后展示的状态。
  String? _status;

  /// 先出一帧，再开始预热和采集。
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_run()));
  }

  /// 记录每个样本并写出单行 JSON，供独立进程重复运行。
  Future<void> _run() async {
    final frames = <ui.FrameTiming>[];
    final collector = FrameTimingCollector(onFrame: frames.add);
    final report = <String, Object>{
      'started_at': DateTime.now().toUtc().toIso8601String(),
      'display_hz': View.of(context).display.refreshRate,
    };
    try {
      final path = reportOutPath();
      final order = path == null ? null : File('$path.order');
      final run = order != null && order.existsSync()
          ? int.parse(order.readAsStringSync().trim())
          : 1;
      report['run'] = run;
      final previousThreshold = debugStaticSvgAsyncParseThreshold;
      debugStaticSvgAsyncParseThreshold = 0;
      try {
        final warmup = makeAsyncThresholdSvg(asyncThresholdSizesKiB.first, 0);
        _cache.getOrRender(warmup).picture.dispose();
        _cache.clear();
        (await _cache.getOrRenderAsync(warmup)).picture.dispose();
        _cache.clear();
        await warmUpFrameTimingChannel(collector, pumpFrames: false);
        collector.active = true;
        final trialsBySize = {
          for (final sizeKiB in asyncThresholdSizesKiB) sizeKiB: <_Trial>[],
        };
        for (final MapEntry(key: sizeKiB, value: trials)
            in trialsBySize.entries) {
          for (var sample = 0; sample < _samplesPerSize; sample++) {
            final source = makeAsyncThresholdSvg(
              sizeKiB,
              (sample + 1) * mdiIcons1000.length ~/ (_samplesPerSize + 1),
            );
            final asyncFirst = (run + sample).isEven;
            for (final useAsync in [asyncFirst, !asyncFirst]) {
              final trial = _Trial(sizeKiB, sample, source, useAsync: useAsync);
              await _mount(trial);
              trials.add(trial);
            }
          }
        }
        // 引擎批量上报 FrameTiming，保留末尾帧直到最后一次出图收到报告。
        final latest = trialsBySize.values.last.last.picturePaintAt!;
        final deadline = DateTime.now().add(const Duration(seconds: 5));
        while ((frames.isEmpty ||
                frames.last.timestampInMicroseconds(ui.FramePhase.buildFinish) <
                    latest) &&
            DateTime.now().isBefore(deadline)) {
          await SchedulerBinding.instance.endOfFrame;
        }
        report['buckets'] = {
          for (final MapEntry(key: sizeKiB, value: trials)
              in trialsBySize.entries)
            '$sizeKiB': _summarize(trials, frames),
        };
        report['frame_interval_us'] = _percentiles([
          for (var i = 1; i < frames.length; i++)
            frames[i].timestampInMicroseconds(ui.FramePhase.vsyncStart) -
                frames[i - 1].timestampInMicroseconds(ui.FramePhase.vsyncStart),
        ]);
      } finally {
        debugStaticSvgAsyncParseThreshold = previousThreshold;
      }
      report['complete'] = true;
      emitReport('${jsonEncode(report)}\n');
      if (autoExitAfterReport) exit(0);
      if (mounted) setState(() => _status = 'Calibration complete');
    } catch (error, stack) {
      emitReport(
        '${jsonEncode({...report, 'error': '$error', 'stack': '$stack'})}\n',
      );
      if (autoExitAfterReport) exit(1);
      if (mounted) setState(() => _status = '$error');
    } finally {
      collector.dispose();
    }
  }

  /// 冷挂载一个样本，出图并移除后释放本次录制的 picture。
  Future<void> _mount(_Trial trial) async {
    if (_cache.peek(trial.source) != null) {
      throw StateError('Expected a cold picture cache');
    }
    widget.handler._trial = trial.useAsync ? trial : null;
    RustXvgPictureCache.debugWrapRecordingCanvas = (canvas) {
      trial.recordStartedAt = developer.Timeline.now;
      return canvas;
    };
    _cache.onParseMiss = (elapsed) {
      if (trial.parseRecord != null || trial.recordStartedAt == null) {
        throw StateError('Expected one cold parse and recording');
      }
      trial.recordUs = developer.Timeline.now - trial.recordStartedAt!;
      trial.parseRecord = elapsed;
    };
    RustSvgPictureInfo? info;
    try {
      trial.requestedAt = developer.Timeline.now;
      setState(() => _trial = trial);
      info = await trial.painted.future.timeout(const Duration(seconds: 8));
      if (!identical(info, _cache.peek(trial.source))) {
        throw StateError('Displayed picture was not cached');
      }
    } finally {
      widget.handler._trial = null;
      RustXvgPictureCache.debugWrapRecordingCanvas = null;
      _cache.onParseMiss = null;
      _cache.clear();
      if (mounted) {
        setState(() => _trial = null);
        await SchedulerBinding.instance.endOfFrame;
      }
      info?.picture.dispose();
    }
  }

  /// 保留每个样本和各项耗时的 p50、p90。
  Map<String, Object> _summarize(
    List<_Trial> trials,
    List<ui.FrameTiming> frames,
  ) {
    /// 汇总指定解析模式的样本。
    Map<String, Object> summarizeMode(bool useAsync) {
      final rows = trials
          .where((trial) => trial.useAsync == useAsync)
          .map((trial) => trial.measurements(frames))
          .toList();
      return {
        'samples': rows,
        for (final field in [
          if (useAsync) ...[_dispatch, _decode, _record, _asyncWork],
          _syncWork,
          _raster,
        ])
          field: _percentiles(rows.map((row) => row[field]!)),
      };
    }

    return {'sync': summarizeMode(false), 'async': summarizeMode(true)};
  }

  /// 用共用统计器计算同一计量字段的分位数。
  Map<String, double> _percentiles(Iterable<int> microseconds) {
    final stats = DurationStats.fromDurations(
      microseconds.map((us) => Duration(microseconds: us)).toList(),
    );
    return {'p50': stats.p50Us, 'p90': stats.p90Us};
  }

  /// 保持连续帧，使等待中的占位帧可观测。
  @override
  Widget build(BuildContext context) {
    final trial = _trial;
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_status case final status?)
              Text(status)
            else
              const CircularProgressIndicator(),
            if (trial != null)
              SizedBox.square(dimension: 240, child: _Mount(trial)),
          ],
        ),
      ),
    );
  }
}

/// 在 build 中调用实际缓存入口，异步路径以 FutureBuilder 等待。
class _Mount extends StatelessWidget {
  /// 挂载本次试验。
  const _Mount(this.trial);

  /// 保存本次试验的绘制探针。
  final _Trial trial;

  /// 绘制空占位或缓存已录制的图。
  @override
  Widget build(BuildContext context) {
    final cache = RustXvgPictureCache.instance;
    if (!trial.useAsync) {
      return CustomPaint(
        painter: _Paint(trial, cache.getOrRender(trial.source)),
      );
    }
    return FutureBuilder<RustSvgPictureInfo>(
      future: cache.getOrRenderAsync(trial.source),
      builder: (context, snapshot) {
        if (snapshot.hasError && !trial.painted.isCompleted) {
          trial.painted.completeError(snapshot.error!, snapshot.stackTrace);
        }
        return CustomPaint(painter: _Paint(trial, snapshot.data));
      },
    );
  }
}

/// 绘制并标记本次试验首个占位帧和首个实际画面。
class _Paint extends CustomPainter {
  /// 当 [info] 为空时画空占位。
  const _Paint(this.trial, this.info);

  /// 接收首次绘制时间戳。
  final _Trial trial;

  /// 用实际录制结果绘制，等待期间为空。
  final RustSvgPictureInfo? info;

  /// 在 UI 绘制区间打点，稍后依引擎时间戳找对应光栅帧。
  @override
  void paint(Canvas canvas, Size size) {
    final now = developer.Timeline.now;
    trial.firstPaintAt ??= now;
    final picture = info;
    if (picture == null) return;
    final scale = math.min(
      size.width / picture.size.width,
      size.height / picture.size.height,
    );
    canvas.save();
    canvas.scale(scale);
    canvas.drawPicture(picture.picture);
    canvas.restore();
    if (!trial.painted.isCompleted) {
      trial.picturePaintAt = now;
      trial.painted.complete(picture);
    }
  }

  /// 只在样本或图片变化时要求重绘。
  @override
  bool shouldRepaint(_Paint oldDelegate) =>
      !identical(trial, oldDelegate.trial) ||
      !identical(info, oldDelegate.info);
}
