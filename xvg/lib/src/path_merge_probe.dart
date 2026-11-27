part of 'rust_static_svg.dart';

/// 覆盖自动探针判定，供内部测试强制走任一条解析路径。
@visibleForTesting
bool? debugPathMergeOverride;

/// 本次自检的判定、计时及像素读回信息。
typedef _PathMergeResult = ({
  bool allowed,
  Duration elapsed,
  double? dpr,
  int? maxDelta,
});

/// 供内部测试和基准读取已发起的自检，无需另跑一遍。
@visibleForTesting
Future<({bool allowed, Duration elapsed, double? dpr, int? maxDelta})>?
get debugPathMergeProbeResult => _pathMergeProbe;

/// 进程 UI isolate 中唯一一次自检，期间继续使用独立绘制。
Future<_PathMergeResult>? _pathMergeProbe;

/// 记录真实像素对照是否通过。
bool _pathMergePassed = false;

/// 返回本次冷解析可用的合并策略。
bool get _allowPathMerge => debugPathMergeOverride ?? _pathMergePassed;

/// 与位图缓存共用复杂度门槛，在第一次达标 Picture 后发起自检。
bool _reachesPathThreshold(RustSvgPictureInfo info) =>
    info.pathCount >= xvgRasterMinPaths ||
    info.pointCount >= xvgRasterMinPoints;

/// 预判渲染器，等当前帧提交后用空闲任务自检并记录耗时。
Future<_PathMergeResult> _probePathMergeAfterFrame() async {
  if (kIsWeb || !ui.ImageFilter.isShaderFilterSupported) {
    return (allowed: false, elapsed: Duration.zero, dpr: null, maxDelta: null);
  }
  final stopwatch = Stopwatch();
  double? dpr;
  int? maxDelta;
  try {
    final scheduler = SchedulerBinding.instance;
    await scheduler.endOfFrame;
    await scheduler.scheduleTask(() async {
      stopwatch.start();
      final dispatcher = ui.PlatformDispatcher.instance;
      final view = dispatcher.implicitView ?? dispatcher.views.firstOrNull;
      if (view == null) return;
      final deviceScale = view.devicePixelRatio;
      dpr = deviceScale;
      maxDelta = await _measurePathMerge(deviceScale);
      _pathMergePassed = maxDelta! <= 1;
    }, Priority.idle);
  } catch (_) {
    // A failed readback leaves merging disabled. / 读回失败时保持关闭。
  } finally {
    stopwatch.stop();
    developer.Timeline.instantSync(
      'xvg.pathMergeProbe',
      arguments: {
        'allowed': _pathMergePassed,
        'elapsedUs': stopwatch.elapsedMicroseconds,
        'dpr': ?dpr,
        'maxDelta': ?maxDelta,
      },
    );
  }
  return (
    allowed: _pathMergePassed,
    elapsed: stopwatch.elapsed,
    dpr: dpr,
    maxDelta: maxDelta,
  );
}

/// 将相离路径分别录制为独立绘制和同画笔复合绘制，对比预乘 RGBA。
Future<int> _measurePathMerge(double dpr) async {
  final thinHeight = 4 + 0.7 / dpr;
  final fill = ui.Paint();
  final stroke = ui.Paint()
    ..style = ui.PaintingStyle.stroke
    ..strokeWidth = 0.32 / dpr
    ..strokeCap = ui.StrokeCap.square
    ..strokeJoin = ui.StrokeJoin.bevel;
  // Match Rust's standalone off-viewport stroke. / 完全离开视口的描边在两侧均保持独立绘制。
  final clippedStroke = (
    stroke,
    parseSvgPathData('M${-0.33 / dpr} 17L${-0.31 / dpr} 18L${-0.33 / dpr} 19'),
  );
  final samples = [
    // Rect coverage expansion and tessellation. / 非整数薄矩形的最小覆盖扩边和厚矩形的镶嵌路线。
    (
      [fill],
      ui.PathFillType.nonZero,
      [
        'M4.17 4H22.17V${thinHeight}H4.17Z',
        'M28.17 4H46.17V${thinHeight}H28.17Z',
        'M54.19 4.31H78.61V12.78H54.19Z',
        'M88.19 5.33H112.61V13.78H88.19Z',
      ],
    ),
    // Line and edge clipping coverage. / 细直线和跨越画布边缘的亚像素描边。
    (
      [stroke],
      ui.PathFillType.nonZero,
      [
        'M52.27 22.03L75.67 24.18',
        'M85.27 23.03L108.67 25.18',
        'M${0.05 / dpr} 22L${0.14 / dpr} 23L${0.05 / dpr} 24',
        'M3 26L4 27L3 28',
      ],
    ),
    // Separate and compound scan conversion. / 凸三角、凹形和曲线的独立路径与复合扫描转换。
    (
      [fill],
      ui.PathFillType.nonZero,
      [
        'M4.53 34.07L18.71 35.18L9.04 46.55Z',
        'M4.53 88.07L18.71 89.18L9.04 100.55Z',
        'M4.23 54.37L44.71 57.37L43.71 59.41L12.02 59.41L23.02 71.81L4.23 70.81Z',
        'M74.23 55.69L114.71 58.69L113.71 60.73L82.02 60.73L93.02 73.13L74.23 72.13Z',
        'M35.27 34.05Q46.51 34.05 57.72 34.05V43.73H35.27Z',
        'M76.37 34.16C83.19 28.72 94.18 31.47 98.53 42.22L76.37 46.05Z',
      ],
    ),
    // Nested contours under both rules. / 同向嵌套轮廓检查奇偶与非零填充规则。
    for (final rule in ui.PathFillType.values)
      (
        [fill],
        rule,
        rule == ui.PathFillType.evenOdd
            ? [
                'M30.23 84.36h20v16h-20Z M33.51 88.74h12v8h-12Z',
                'M68.23 84.36h20v16h-20Z M71.51 88.74h12v8h-12Z',
              ]
            : [
                'M30.23 107.36h20v16h-20Z M33.51 111.74h12v8h-12Z',
                'M68.23 107.36h20v16h-20Z M71.51 111.74h12v8h-12Z',
              ],
      ),
    // Fill followed by stroke on compound contours. / 多轮廓先填后描时检查两次独立覆盖。
    (
      [fill, stroke],
      ui.PathFillType.evenOdd,
      [
        'M95.31 83.17h24v16h-24Z M99.53 86.37h12v8h-12Z',
        'M95.67 107.47h24v16h-24Z M100.23 111.17h12v8h-12Z',
      ],
    ),
  ];
  final groups = [
    for (final (paints, rule, paths) in samples)
      (
        paints,
        rule,
        [for (final d in paths) parseSvgPathData(d)..fillType = rule],
      ),
  ];
  final edge = (128 * dpr).ceil();
  final separate = await _captureMergeProbe(
    groups,
    clippedStroke,
    dpr,
    edge,
    merged: false,
  );
  final merged = await _captureMergeProbe(
    groups,
    clippedStroke,
    dpr,
    edge,
    merged: true,
  );
  var maxDelta = 0;
  for (var i = 0; i < separate.length; i++) {
    maxDelta = math.max(maxDelta, (separate[i] - merged[i]).abs());
  }
  return maxDelta;
}

/// 在设备像素大小的离屏画布上绘制探针，读回后释放图像和 Picture。
Future<Uint8List> _captureMergeProbe(
  List<(List<ui.Paint>, ui.PathFillType, List<ui.Path>)> groups,
  (ui.Paint, ui.Path) clippedStroke,
  double dpr,
  int edge, {
  required bool merged,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder)
    ..clipRect(
      ui.Rect.fromLTWH(0, 0, edge.toDouble(), edge.toDouble()),
      doAntiAlias: false,
    )
    ..scale(dpr);
  final (strokePaint, strokePath) = clippedStroke;
  canvas.drawPath(strokePath, strokePaint);
  for (final (paints, rule, paths) in groups) {
    if (merged) {
      final compound = ui.Path()..fillType = rule;
      for (final path in paths) {
        compound.addPath(path, ui.Offset.zero);
      }
      for (final paint in paints) {
        canvas.drawPath(compound, paint);
      }
    } else {
      for (final path in paths) {
        for (final paint in paints) {
          canvas.drawPath(path, paint);
        }
      }
    }
  }
  final picture = recorder.endRecording();
  try {
    final image = await picture.toImage(edge, edge);
    try {
      final data = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    } finally {
      image.dispose();
    }
  } finally {
    picture.dispose();
  }
}
