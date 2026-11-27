part of 'raster_cache_auto_bench.dart';

/// 真机运行后才写入的自动模式复测目录。
const _automaticDirectory =
    '/sdcard/Android/data/com.example.bench_app/files/xvg-auto-mode';

/// 复用图标基准的滚动时长，并使用等时长的插画滚动对照。
const _scrollLeg = Duration(milliseconds: 900);

/// 每个模式使用相同的滚动路程和往返次数。
const _scrollCycles = 4;

/// 覆盖多屏的阈值附近插画列表项数。
const _illustrationCount = 36;

/// 滑动和单图场景的轮次与素材计划。
typedef _AutomaticRun = ({
  int round,
  List<(String, String)> illustrations,
  List<String> listSamples,
  bool overflowRecheck,
  bool scrollIcons,
});

/// 读取运行时计划，所有 SVG 输入均在 APK 建好后推送。
Future<void> runRasterCacheAutomatic() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final json = jsonDecode(
      File('$_automaticDirectory/plan.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final run = (
      round: json['round'] as int,
      illustrations: [
        for (final row in json['illustrations'] as List<dynamic>)
          (row[0] as String, row[1] as String),
      ],
      listSamples: List<String>.from(json['list_samples'] as List<dynamic>),
      overflowRecheck: json['overflow_recheck'] == true,
      scrollIcons: json['scroll_icons'] != false,
    );
    await RustLib.init();
    runApp(
      MaterialApp(
        home: _AutoBench(
          round: run.round,
          samples: const [],
          clipArtwork: false,
          automaticRun: run,
        ),
      ),
    );
  } catch (error) {
    _automaticStatus('error startup ${error.runtimeType}');
  }
}

/// 原子更新设备端进度文件。
void _automaticStatus(String value) {
  (File(
    '$_automaticDirectory/status.tmp',
  )..writeAsStringSync(value)).renameSync('$_automaticDirectory/status.txt');
}

/// 把 UI 提交时已驻留的块数关联到对应的 raster 帧。
List<Map<String, int>> _generationFrames(
  List<ui.FrameTiming> frames,
  List<(int, int)> submissions,
) {
  var index = 0;
  var tiles = 0;
  return [
    for (final frame in frames)
      () {
        final buildStart = _timestamp(frame, ui.FramePhase.buildStart);
        while (index < submissions.length &&
            submissions[index].$1 < buildStart) {
          tiles = submissions[index].$2;
          index++;
        }
        return {
          'raster_us': frame.rasterDuration.inMicroseconds,
          'tiles_before_submit': tiles,
        };
      }(),
  ];
}

/// 读取语料字符编码，沿用阈值基准的原生场景输入。
Future<String> _readAutomaticSvg(String id) async {
  if (id.startsWith('synthetic-')) {
    final parts = id.split('-');
    final variant = parts.skip(2).join('-');
    return syntheticAutoSvg(
      int.parse(parts[1]),
      blur: variant.startsWith('blur'),
      layers: variant.contains('layers'),
      gradients: variant.endsWith('grad'),
    );
  }
  final bytes = await File('$_automaticDirectory/input/$id.svg').readAsBytes();
  final header = latin1.decode(bytes.take(120).toList());
  return header.startsWith('<?xml') &&
          header.split('?>').first.toLowerCase().contains('iso-8859-1')
      ? latin1.decode(bytes)
      : utf8.decode(bytes);
}

/// 跑单图与滚动对照，每轮置换模式的先后顺序。
Future<void> _runAutomatic(_AutoBenchState state, _AutomaticRun run) async {
  final output = File('$_automaticDirectory/frames.jsonl').openWrite();
  var current = 'warmup';
  try {
    await Future<void>.delayed(const Duration(seconds: 2));
    await state._waitFor(() => state._frames.isNotEmpty);
    if (!state.mounted) return;
    final view = View.of(state.context);
    final screenWidth = view.physicalSize.width / view.devicePixelRatio;
    final cases = run.illustrations;
    final modes = run.overflowRecheck
        ? const [_Mode.vector, _Mode.automatic]
        : const [_Mode.vector, _Mode.cached, _Mode.automatic];
    for (var index = 0; index < cases.length; index++) {
      final (id, widthKey) = cases[index];
      current = id;
      _automaticStatus('running $id');
      final source = await _readAutomaticSvg(id);
      final info = await RustXvgPictureCache.instance.getOrRenderAsync(source);
      final width = widthKey == 'full' ? screenWidth : double.parse(widthKey);
      final size = Size(width, width / info.size.aspectRatio);
      for (var order = 0; order < modes.length; order++) {
        final mode = modes[(order + index + run.round - 1) % modes.length];
        current = '$id/${mode.name}';
        _automaticStatus('running $current');
        final result = await state._measure(
          mode: mode,
          source: source,
          artSize: size,
        );
        output.writeln(
          jsonEncode({
            'scenario': 'stationary',
            'sample': id,
            'size': widthKey,
            'paths': info.pathCount,
            'points': info.pointCount,
            'width_dp': width,
            'dpr': view.devicePixelRatio,
            'display_hz': view.display.refreshRate,
            ...result,
          }),
        );
        await output.flush();
      }
      RustXvgPictureCache.instance.clear();
    }
    final listSources = await Future.wait(
      run.listSamples.map(_readAutomaticSvg),
    );
    final listArt = [
      for (final source in listSources)
        (
          source,
          (await RustXvgPictureCache.instance.getOrRenderAsync(source)).size,
        ),
    ];
    final icons = run.scrollIcons ? generateIcons(1000) : const <String>[];
    for (final caseId in [
      if (run.scrollIcons) 'icons',
      if (listArt.isNotEmpty) ...['list-48', 'list-200'],
    ]) {
      final isIcons = caseId == 'icons';
      final width = isIcons ? 0.0 : double.parse(caseId.split('-').last);
      final vectorFirst = (run.round + caseId.length).isOdd;
      for (final mode
          in vectorFirst
              ? [_Mode.vector, _Mode.automatic]
              : [_Mode.automatic, _Mode.vector]) {
        current = '$caseId/${mode.name}';
        _automaticStatus('running $current');
        final result = await _measureScroll(
          state,
          mode,
          icons,
          listArt,
          iconsGrid: isIcons,
          illustrationWidth: width,
        );
        output.writeln(jsonEncode({'scenario': caseId, ...result}));
        await output.flush();
      }
      RustXvgPictureCache.instance.clear();
    }
    state._finishRun();
    _automaticStatus('done');
  } catch (error, stack) {
    debugPrint(
      'Auto mode benchmark failed at $current with ${error.runtimeType}',
    );
    debugPrintStack(stackTrace: stack);
    state._finishRun();
    _automaticStatus('error $current ${error.runtimeType}');
  } finally {
    // ignore: invalid_use_of_visible_for_testing_member
    debugXvgRasterCacheOverride = null;
    await output.close();
  }
}

/// 连续往返滚动，保存每个调度帧的驻留块数和引擎逐帧实测值。
Future<Map<String, Object?>> _measureScroll(
  _AutoBenchState state,
  _Mode mode,
  List<String> icons,
  List<(String, Size)> art, {
  required bool iconsGrid,
  required double illustrationWidth,
}) async {
  // ignore: invalid_use_of_visible_for_testing_member
  debugXvgRasterCacheOverride = mode == _Mode.automatic
      ? null
      : XvgRasterCacheOverride.disabled;
  final scroll = ScrollController();
  final ticks = <int>[];
  final disposed = XvgRasterCache.disposedTileCount;
  var tracking = true;
  final scheduler = SchedulerBinding.instance;
  final refreshRate = View.of(state.context).display.refreshRate;

  /// 采样范围含首次挂载，以便发现预热期间的误开。
  void record(Duration _) {
    if (!tracking) return;
    ticks.add(XvgRasterCache.tileCount);
    scheduler.addPostFrameCallback(record);
  }

  scheduler.addPostFrameCallback(record);
  try {
    final grid = GridView.builder(
      controller: scroll,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 8,
      ),
      itemCount: icons.length,
      itemBuilder: (context, index) => Padding(
        padding: const EdgeInsets.all(4),
        child: StaticXvg(icons[index], width: 32, height: 32),
      ),
    );
    final list = ListView.builder(
      controller: scroll,
      itemCount: _illustrationCount,
      itemBuilder: (context, index) {
        final (source, size) = art[index % art.length];
        final height = illustrationWidth / size.aspectRatio;
        return SizedBox(
          height: math.max(illustrationWidth, height) + 8,
          child: Align(
            alignment: Alignment.topLeft,
            child: StaticXvg(source, width: illustrationWidth, height: height),
          ),
        );
      },
    );
    state._showArtwork(
      Positioned.fill(
        child: iconsGrid
            ? Scaffold(
                appBar: AppBar(title: const Text('1000 icons')),
                body: grid,
              )
            : list,
      ),
    );
    await scheduler.endOfFrame;
    await Future<void>.delayed(const Duration(milliseconds: 120));
    state._frames.clear();
    final start = developer.Timeline.now;
    final extent = scroll.position.maxScrollExtent;
    for (var cycle = 0; cycle < _scrollCycles; cycle++) {
      for (final offset in [extent, 0.0]) {
        await scroll.animateTo(
          offset,
          duration: _scrollLeg,
          curve: iconsGrid ? Curves.easeInOut : Curves.linear,
        );
      }
    }
    final end = developer.Timeline.now;
    await state._waitFor(
      () => state._frames.any((frame) => _vsync(frame) >= end),
    );
    final frames = state._frames.where((frame) {
      final vsync = _vsync(frame);
      return vsync >= start && vsync < end;
    }).toList();
    if (frames.length < _minFrames) throw StateError('Scroll timing missing');
    return {
      'mode': mode.name,
      'display_hz': refreshRate,
      'duration_us': end - start,
      'scroll_extent_dp': extent,
      'tiles_per_submit': ticks,
      'disposed_tiles_before_unmount':
          XvgRasterCache.disposedTileCount - disposed,
      'raster_us': [for (final f in frames) f.rasterDuration.inMicroseconds],
      'vsync_us': [for (final f in frames) _vsync(f) - _vsync(frames.first)],
    };
  } finally {
    tracking = false;
    await state._unmountArtwork();
    scroll.dispose();
  }
}
