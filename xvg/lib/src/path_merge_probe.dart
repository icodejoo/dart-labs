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
  int? startedUs,
  bool timedOut,
});

/// Paths that share paints and a compound fill rule. / 共用画笔和复合填充规则的路径。
typedef _PathMergeSample = (List<ui.Paint>, ui.PathFillType, List<ui.Path>);

/// Logical side length of one full probe tile. / 一侧完整探针的逻辑边长。
const _pathMergeTileEdge = 128;

/// Required quiet time before starting the probe. / 启动探针前要求的静止时长。
const _pathMergeQuietWindow = Duration(milliseconds: 200);

/// Poll interval while the first probe is pending. / 首次探针等待期间的轮询间隔。
const _pathMergePollInterval = Duration(milliseconds: 50);

/// Maximum wait after the first frame submission. / 首帧提交后的最长等待时间。
const _pathMergeWaitLimit = Duration(seconds: 3);

/// Largest channel difference accepted by the probe. / 探针允许的最大通道差。
const _pathMergeMaxDelta = 1;

/// Byte count of one premultiplied RGBA pixel. / 一个预乘 RGBA 像素的字节数。
const _rgbaPixelBytes = 4;

/// Bit width and mask of one RGBA channel. / 单个 RGBA 通道的位宽和掩码。
const _rgbaChannelBits = 8, _rgbaChannelMask = 0xff;

/// Number of horizontally adjacent RGBA tiles. / 横向并排的 RGBA 图块数量。
const _pathMergeTileCount = 2;

/// Returns the probe already started in this isolate. / 返回当前 isolate 已发起的探针。
@visibleForTesting
Future<
  ({
    bool allowed,
    Duration elapsed,
    double? dpr,
    int? maxDelta,
    int? startedUs,
    bool timedOut,
  })
>?
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

/// Checks whether GPU self-testing is useful on the current platform. / 预判当前平台是否需要 GPU 自检。
@visibleForTesting
bool debugShouldProbePathMerge({required bool shaderFilterSupported}) =>
    !kIsWeb &&
    // Windows Impeller defaults to SDFs, where ExpandRectToPixelMinimum changes single-rect coverage; opting out only forfeits merging. / Windows Impeller 默认启用 SDF，ExpandRectToPixelMinimum 会改变单矩形覆盖，手动关闭 SDF 也只会少用合并优化。
    defaultTargetPlatform != TargetPlatform.windows &&
    shaderFilterSupported;

/// Runs the probe from an idle event after a quiet window or the deadline. / 静止窗口或截止时间到达后，从帧外事件启动探针。
@visibleForTesting
Future<T> debugRunPathMergeWhenIdle<T>(
  SchedulerBinding scheduler,
  Future<T> Function(bool timedOut) probe, {
  Duration Function()? now,
}) async {
  await scheduler.endOfFrame;
  final readTime =
      now ?? (() => Duration(microseconds: developer.Timeline.now));
  final deadline = readTime() + _pathMergeWaitLimit;
  var lastFrame = scheduler.currentSystemFrameTimeStamp;
  Duration? quietSince;
  final result = Completer<T>();

  /// Observes activity without registering frame callbacks. / 观察帧活动，无需注册逐帧回调。
  void poll() {
    final time = readTime();
    final frame = scheduler.currentSystemFrameTimeStamp;
    if (frame != lastFrame) {
      quietSince = null;
      lastFrame = frame;
    }
    if (scheduler.hasScheduledFrame || scheduler.transientCallbackCount != 0) {
      quietSince = null;
    } else {
      quietSince ??= time;
    }
    final quiet = quietSince;
    final isQuiet = quiet != null && time - quiet >= _pathMergeQuietWindow;
    if (isQuiet || time >= deadline) {
      result.complete(Future.sync(() => probe(!isQuiet)));
      return;
    }
    final remaining = deadline - time;
    Timer(
      remaining < _pathMergePollInterval ? remaining : _pathMergePollInterval,
      poll,
    );
  }

  // A timer runs between frames even with a live ticker that starves Priority.idle. / Timer 在帧外执行，常驻 ticker 阻塞 Priority.idle 时也能兜底。
  Timer.run(poll);
  return result.future;
}

/// Checks the renderer and times one device-scale comparison. / 预判渲染器并记录一次设备像素自检的耗时。
Future<_PathMergeResult> _probePathMergeAfterFrame() async {
  if (!debugShouldProbePathMerge(
    shaderFilterSupported: !kIsWeb && ui.ImageFilter.isShaderFilterSupported,
  )) {
    return (
      allowed: false,
      elapsed: Duration.zero,
      dpr: null,
      maxDelta: null,
      startedUs: null,
      timedOut: false,
    );
  }
  final stopwatch = Stopwatch();
  double? dpr;
  int? maxDelta;
  int? startedUs;
  var timedOut = false;
  try {
    maxDelta = await debugRunPathMergeWhenIdle(SchedulerBinding.instance, (
      fallback,
    ) async {
      final dispatcher = ui.PlatformDispatcher.instance;
      final view = dispatcher.implicitView ?? dispatcher.views.firstOrNull;
      if (view == null) return null;
      final deviceScale = view.devicePixelRatio;
      dpr = deviceScale;
      timedOut = fallback;
      startedUs = developer.Timeline.now;
      stopwatch.start();
      developer.Timeline.instantSync(
        'xvg.pathMergeProbe.start',
        arguments: {'timedOut': timedOut},
      );
      return _measurePathMerge(deviceScale);
    });
    _pathMergePassed = maxDelta != null && maxDelta <= _pathMergeMaxDelta;
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
        'timedOut': timedOut,
      },
    );
  }
  return (
    allowed: _pathMergePassed,
    elapsed: stopwatch.elapsed,
    dpr: dpr,
    maxDelta: maxDelta,
    startedUs: startedUs,
    timedOut: timedOut,
  );
}

/// Captures all geometry at the original device pixel phase. / 按原设备像素相位一次性快照全部图形。
Future<int> _measurePathMerge(double dpr) {
  final (groups, clippedStroke) = developer.Timeline.timeSync(
    'xvg.pathMergeProbe.recordPaths',
    () => _buildPathMergeSamples(dpr),
  );
  final edge = (_pathMergeTileEdge * dpr).ceil();
  return _captureMergeProbe(groups, clippedStroke, dpr, edge);
}

/// Builds the geometry, including the standalone off-viewport stroke. / 构造探针图形，包括保持独立的视口外描边。
(List<_PathMergeSample>, (ui.Paint, ui.Path)) _buildPathMergeSamples(
  double dpr,
) {
  const thinTop = 4;
  final thinBottom = thinTop + 0.7 / dpr;
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
        'M4.17 ${thinTop}H22.17V${thinBottom}H4.17Z',
        'M28.17 ${thinTop}H46.17V${thinBottom}H28.17Z',
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
  return (groups, clippedStroke);
}

/// Draws both tiles with independent clips and reads them back together. / 两侧独立裁剪绘制，共用一次读回。
Future<int> _captureMergeProbe(
  List<_PathMergeSample> groups,
  (ui.Paint, ui.Path) clippedStroke,
  double dpr,
  int edge,
) async {
  final picture = developer.Timeline.timeSync(
    'xvg.pathMergeProbe.recordPicture',
    () {
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      final tile = ui.Rect.fromLTWH(0, 0, edge.toDouble(), edge.toDouble());
      // Both clips use the same integer-pixel origin phase. / 两侧裁剪保持相同的整数像素相位。
      canvas.save();
      canvas.clipRect(tile, doAntiAlias: false);
      canvas.scale(dpr);
      _drawMergeProbeTile(canvas, groups, clippedStroke, merged: false);
      canvas.restore();
      canvas.translate(edge.toDouble(), 0);
      canvas.clipRect(tile, doAntiAlias: false);
      canvas.scale(dpr);
      _drawMergeProbeTile(canvas, groups, clippedStroke, merged: true);
      return recorder.endRecording();
    },
  );
  final task = developer.TimelineTask();
  try {
    task.start('xvg.pathMergeProbe.toImage');
    final ui.Image image;
    try {
      image = await picture.toImage(edge * _pathMergeTileCount, edge);
    } finally {
      task.finish();
    }
    try {
      task.start('xvg.pathMergeProbe.toByteData');
      final ByteData data;
      try {
        data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      } finally {
        task.finish();
      }
      return developer.Timeline.timeSync<int>(
        'xvg.pathMergeProbe.compare',
        () => debugComparePathMergeTiles(data, edge, edge),
      );
    } finally {
      image.dispose();
    }
  } finally {
    picture.dispose();
  }
}

/// Draws one tile using the requested path policy. / 按指定路径策略绘制一侧探针。
void _drawMergeProbeTile(
  ui.Canvas canvas,
  List<_PathMergeSample> groups,
  (ui.Paint, ui.Path) clippedStroke, {
  required bool merged,
}) {
  final (stroke, path) = clippedStroke;
  canvas.drawPath(path, stroke);
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
}

/// Returns the largest channel delta between two side-by-side RGBA tiles. / 返回并排预乘 RGBA 两侧的最大通道差。
@visibleForTesting
int debugComparePathMergeTiles(ByteData rgba, int width, int height) {
  final tileRowBytes = width * _rgbaPixelBytes;
  final atlasRowBytes = tileRowBytes * _pathMergeTileCount;
  var maxDelta = 0;
  for (var row = 0; row < height; row++) {
    final rowStart = row * atlasRowBytes;
    final tileEnd = rowStart + tileRowBytes;
    for (var left = rowStart; left < tileEnd; left += _rgbaPixelBytes) {
      final a = rgba.getUint32(left, Endian.host);
      final b = rgba.getUint32(left + tileRowBytes, Endian.host);
      if (a == b) continue;
      for (var channel = 0; channel < _rgbaPixelBytes; channel++) {
        final shift = channel * _rgbaChannelBits;
        final delta =
            ((a >> shift & _rgbaChannelMask) - (b >> shift & _rgbaChannelMask))
                .abs();
        maxDelta = math.max(maxDelta, delta);
      }
    }
  }
  return maxDelta;
}
