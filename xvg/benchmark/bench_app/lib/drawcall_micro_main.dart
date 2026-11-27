import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

const _side = 1080;
const _bounds = Rect.fromLTWH(0, 0, 1080, 1080);
const _ink = Color(0xff276bcd);
const _root =
    '/sdcard/Android/data/com.example.bench_app/files/xvg-drawcall-micro';
const _wait = Duration(milliseconds: 100);
const _timeout = Duration(seconds: 40);
const _phases = [
  FramePhase.vsyncStart,
  FramePhase.buildStart,
  FramePhase.rasterStart,
  FramePhase.rasterFinish,
];

enum _Shape { rect, quad, concave, cubic }

/// Paints a benchmark plan with dart:ui only. / 仅用 dart:ui 执行基准计划。
Future<void> main() async {
  final run = _Micro();
  try {
    await run.execute();
  } catch (error, stack) {
    run.file('error').writeAsStringSync('$error\n$stack');
    run.status('error');
    rethrow;
  }
}

/// Supplies identical physical-pixel locations to every mode. / 为各画法提供相同的物理像素坐标。
Float64List _centers(int count) {
  final columns = math.sqrt(count).ceil();
  final rows = (count / columns).ceil();
  final xy = Float64List(count * 2);
  for (var i = 0; i < count; i++) {
    xy[2 * i] = (i % columns + 0.5) * _side / columns;
    xy[2 * i + 1] = (i ~/ columns + 0.5) * _side / rows;
  }
  return xy;
}

/// Returns a centered rectangle with fractional edges. / 返回带分数像素边缘的居中矩形。
Rect _rect(double x, double y) => Rect.fromLTWH(x - 1.35, y - 1.2, 2.7, 2.4);

/// Rotates a non-rectangular trapezoid by 30 degrees. / 将非矩形梯形旋转 30 度。
List<Offset> _quad() {
  const points = [
    Offset(-1.25, -0.95),
    Offset(0.85, -0.95),
    Offset(1.3, 0.95),
    Offset(-1, 0.95),
  ];
  final angle = math.pi / 6;
  final cosine = math.cos(angle);
  final sine = math.sin(angle);
  return [
    for (final p in points)
      Offset(p.dx * cosine - p.dy * sine, p.dx * sine + p.dy * cosine),
  ];
}

final _quadPoints = _quad();

/// Appends a clockwise contour at the specified center. / 在给定中心追加一条顺时针轮廓。
void _append(Path path, _Shape shape, double x, double y) {
  switch (shape) {
    case _Shape.rect:
      path.addRect(_rect(x, y));
    case _Shape.quad:
      path.moveTo(x + _quadPoints.first.dx, y + _quadPoints.first.dy);
      for (var i = 1; i < _quadPoints.length; i++) {
        final p = _quadPoints[i];
        path.lineTo(x + p.dx, y + p.dy);
      }
      path.close();
    case _Shape.concave:
      const edge = 1.4;
      const elbow = -0.25;
      path
        ..moveTo(x - edge, y - edge)
        ..lineTo(x + elbow, y - edge)
        ..lineTo(x + elbow, y + elbow)
        ..lineTo(x + edge, y + elbow)
        ..lineTo(x + edge, y + edge)
        ..lineTo(x - edge, y + edge)
        ..close();
    case _Shape.cubic:
      const edge = 1.45;
      path
        ..moveTo(x, y - edge)
        ..cubicTo(x + 0.45, y - 1.05, x + edge, y - 0.2, x + edge, y + 0.5)
        ..cubicTo(x + edge, y + 1.8, x - edge, y + 1.8, x - edge, y + 0.5)
        ..cubicTo(x - edge, y - 0.2, x - 0.45, y - 1.05, x, y - edge)
        ..close();
  }
}

/// Records one picture, with zero grouping reserved for drawRect. / 录制一张图，组大小 0 代表直接 drawRect。
Picture _record(_Shape shape, Float64List xy, int group) {
  final recorder = PictureRecorder();
  final canvas = Canvas(recorder, _bounds);
  final paint = Paint()..color = _ink;
  if (group == 0) {
    for (var i = 0; i < xy.length; i += 2) {
      canvas.drawRect(_rect(xy[i], xy[i + 1]), paint);
    }
  } else {
    final stride = group * 2;
    for (var first = 0; first < xy.length; first += stride) {
      final path = Path();
      final end = math.min(first + stride, xy.length);
      for (var i = first; i < end; i += 2) {
        _append(path, shape, xy[i], xy[i + 1]);
      }
      canvas.drawPath(path, paint);
    }
  }
  return recorder.endRecording();
}

/// Runs the frame, snapshot and pixel stages independently. / 独立运行帧计时、快照和像素核对。
class _Micro {
  /// Supplies the engine's standalone view and callbacks. / 提供引擎的独立视图和回调。
  final dispatcher = PlatformDispatcher.instance;

  /// Holds shape centers shared by all trials at each count. / 保存各数量在试次间共用的形状中心。
  final _locations = <int, Float64List>{};

  /// Keeps the background equal for baseline and replay. / 让基线与重放共用同一个背景。
  late final Picture _background;

  /// Holds the spinner's pre-recorded arc. / 保存预录制的转圈圆弧。
  late final Picture _spinner;

  /// Holds the workload picture for the current replay window. / 保存当前重放窗口的负载图。
  Picture? _picture;

  /// Continues vsync requests during a replay window. / 控制重放窗口内的持续请求。
  bool _animating = false;

  /// Counts render submissions so the spinner angle always advances. / 统计提交次数以推进转圈角度。
  int _frame = 0;

  /// Resolves one file in the isolated device directory. / 定位设备隔离目录中的一个文件。
  File file(String name) => File('$_root/$name');

  /// Announces a state transition to the host. / 通知主机状态变化。
  void status(String value) {
    file('status.next').writeAsStringSync(value);
    file('status.next').renameSync(file('status').path);
  }

  /// Waits for the host to authorize a stage. / 等待主机放行一个阶段。
  Future<void> _waitFor(String name) async {
    final flag = file(name);
    while (!flag.existsSync()) {
      await Future<void>.delayed(_wait);
    }
  }

  /// Appends a completed trial to the device journal. / 向设备日志追加完成的试次。
  void _write(String name, Map<String, Object?> row) {
    file(name).writeAsStringSync('${jsonEncode(row)}\n', mode: FileMode.append);
  }

  /// Uses the engine's physical coordinate space and bypasses framework layers. / 直接用引擎物理坐标提交场景。
  void _draw(Duration timestamp) {
    final view = dispatcher.views.single;
    final builder = SceneBuilder()..addPicture(Offset.zero, _background);
    final picture = _picture;
    if (picture != null) {
      builder.addPicture(Offset.zero, picture, willChangeHint: true);
    }
    final angle = _frame++ * math.pi / 12;
    final cosine = math.cos(angle);
    final sine = math.sin(angle);
    builder.pushTransform(
      Float64List.fromList([
        cosine,
        sine,
        0,
        0,
        -sine,
        cosine,
        0,
        0,
        0,
        0,
        1,
        0,
        28,
        _side + 36,
        0,
        1,
      ]),
    );
    builder
      ..addPicture(Offset.zero, _spinner)
      ..pop();
    final scene = builder.build();
    view.render(scene);
    scene.dispose();
    if (_animating) dispatcher.scheduleFrame();
  }

  /// Collects rasterized frames after the build timestamp boundary. / 按构建时间边界收集已完成 raster 的帧。
  Future<List<List<int>>> _replay(
    Picture? picture,
    int warm,
    int samples,
  ) async {
    final rows = <List<int>>[];
    final done = Completer<void>();
    final start = Timeline.now;
    final needed = warm + samples;
    dispatcher.onReportTimings = (timings) {
      for (final timing in timings) {
        if (timing.timestampInMicroseconds(FramePhase.buildStart) < start) {
          continue;
        }
        if (rows.length == needed) break;
        rows.add([
          timing.frameNumber,
          for (final phase in _phases) timing.timestampInMicroseconds(phase),
          timing.pictureCacheCount,
          timing.layerCacheCount,
        ]);
      }
      if (rows.length == needed && !done.isCompleted) {
        _animating = false;
        done.complete();
      }
    };
    _picture = picture;
    _animating = true;
    dispatcher.scheduleFrame();
    try {
      await done.future.timeout(_timeout);
      return rows;
    } finally {
      _picture = null;
      _animating = false;
      dispatcher.onReportTimings = null;
    }
  }

  /// Records a workload with positions prepared outside the timed interval. / 录制负载，坐标准备在计时区间外。
  (Picture, int) _recordCase(Map<String, dynamic> trial) {
    final count = trial['count'] as int;
    final shape = _Shape.values.byName(trial['shape'] as String);
    final group = trial['group'] as int;
    final xy = _locations.putIfAbsent(count, () => _centers(count));
    final watch = Stopwatch()..start();
    final picture = _record(shape, xy, group);
    watch.stop();
    return (picture, watch.elapsedMicroseconds);
  }

  /// Generates a GPU image and fences it with readback outside native timing. / 生成 GPU 图像，并在原生计时之外回读以确认完成。
  Future<void> _snapshot(Map<String, dynamic> trial) async {
    final (picture, _) = _recordCase(trial);
    final start = Timeline.now;
    final image = picture.toImageSync(_side, _side);
    final returned = Timeline.now;
    try {
      final rgba = await image.toByteData(format: ImageByteFormat.rawRgba);
      final end = Timeline.now;
      if (rgba?.lengthInBytes != _side * _side * 4) {
        throw StateError('Incomplete snapshot readback');
      }
      _write('snapshots.jsonl', {
        ...trial,
        'request_us': start,
        'handle_us': returned,
        'readback_us': end,
      });
    } finally {
      image.dispose();
      picture.dispose();
    }
  }

  /// Stores a PNG and its lossless raw RGBA for an untimed pixel comparison. / 保存 PNG 和无损 RGBA 以便在计时之外逐像素对比。
  Future<void> _capture(Map<String, dynamic> trial) async {
    final (picture, _) = _recordCase(trial);
    final image = picture.toImageSync(_side, _side);
    try {
      final rgba = (await image.toByteData(format: ImageByteFormat.rawRgba))!;
      final png = (await image.toByteData(format: ImageByteFormat.png))!;
      final name = trial['id'] as String;
      file('$name.rgba.z').writeAsBytesSync(
        zlib.encode(
          rgba.buffer.asUint8List(rgba.offsetInBytes, rgba.lengthInBytes),
        ),
      );
      file('$name.png').writeAsBytesSync(
        png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes),
      );
    } finally {
      image.dispose();
      picture.dispose();
    }
  }

  /// Loads the host plan and executes its stages in the specified order. / 读取主机计划并按给定顺序执行各阶段。
  Future<void> execute() async {
    final plan = jsonDecode(file('plan.json').readAsStringSync()) as Map;
    final trials = (plan['trials'] as List).cast<Map<String, dynamic>>();
    final captures = (plan['captures'] as List).cast<Map<String, dynamic>>();
    final warm = plan['warm'] as int;
    final samples = plan['samples'] as int;
    final bg = PictureRecorder();
    Canvas(bg).drawColor(const Color(0xfffafafa), BlendMode.src);
    _background = bg.endRecording();
    final spin = PictureRecorder();
    Canvas(spin).drawArc(
      Rect.fromCircle(center: Offset.zero, radius: 9),
      0,
      math.pi * 1.4,
      false,
      Paint()
        ..color = _ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    _spinner = spin.endRecording();
    dispatcher.onBeginFrame = _draw;
    dispatcher.scheduleFrame();
    status('ready');
    await _waitFor('start');
    final view = dispatcher.views.single;
    if (view.physicalSize.width < _side ||
        view.physicalSize.height < _side + 48) {
      throw StateError('Insufficient physical view size: ${view.physicalSize}');
    }
    if (trials.isNotEmpty) {
      _write('frames.jsonl', {
        'width': view.physicalSize.width,
        'height': view.physicalSize.height,
        'dpr': view.devicePixelRatio,
        'display_hz': view.display.refreshRate,
        'rasterizer': 'direct FlutterView.render',
      });
      final xy = _locations.putIfAbsent(1000, () => _centers(1000));
      final warmup = <Picture>[];
      try {
        for (final shape in _Shape.values) {
          for (final group in [1, 16]) {
            warmup.add(_record(shape, xy, group));
            await _replay(warmup.last, warm, 2);
          }
        }
        warmup.add(_record(_Shape.rect, xy, 0));
        await _replay(warmup.last, warm, 2);
      } finally {
        for (final picture in warmup) {
          picture.dispose();
        }
      }
      for (final (index, trial) in trials.indexed) {
        status('replay ${index + 1}/${trials.length}');
        final baseline = await _replay(null, warm, samples);
        final (picture, recordUs) = _recordCase(trial);
        try {
          final frames = await _replay(picture, warm, samples);
          _write('frames.jsonl', {
            ...trial,
            'record_us': recordUs,
            'baseline': baseline,
            'frames': frames,
          });
        } finally {
          picture.dispose();
        }
      }
      status('trace');
      await _waitFor('trace.start');
      for (final (index, trial) in trials.indexed) {
        status('snapshot ${index + 1}/${trials.length}');
        await _snapshot(trial);
      }
    }
    for (final trial in captures) {
      status('pixels ${trial['id']}');
      await _capture(trial);
    }
    status('done');
  }
}
