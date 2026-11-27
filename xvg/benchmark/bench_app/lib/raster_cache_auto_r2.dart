part of 'raster_cache_auto_bench.dart';

/// 第二轮临时文件目录，各批次共用相同的设备路径。
const _batchDirectory =
    '/sdcard/Android/data/com.example.bench_app/files/xvg-r2';

/// 同一文件的所有尺寸使用固定的拟合或留出划分。
typedef _Requested = ({String id, String split, List<String> sizes});

/// 一次启动的轮次、模式顺序和样本尺寸计划。
typedef _Batch = ({int round, int orderSeed, List<_Requested> samples});

/// 读取主机在构建完成之后推送的计划及输入。
Future<void> runRasterCacheAutoR2() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final plan = jsonDecode(
      File('$_batchDirectory/plan.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final batch = (
      round: plan['round'] as int,
      orderSeed: plan['order_seed'] as int,
      samples: [
        for (final raw in plan['samples'] as List<dynamic>)
          (
            id: raw['id'] as String,
            split: raw['split'] as String,
            sizes: List<String>.from(raw['sizes'] as List<dynamic>),
          ),
      ],
    );
    await RustLib.init();
    runApp(
      MaterialApp(
        home: _AutoBench(
          round: batch.round,
          samples: const [],
          clipArtwork: false,
          batch: batch,
        ),
      ),
    );
  } catch (error) {
    _batchStatus('error startup ${error.runtimeType}');
  }
}

/// 原子替换批次状态，供主机轮询。
void _batchStatus(String value) {
  (File(
    '$_batchDirectory/status.tmp',
  )..writeAsStringSync(value)).renameSync('$_batchDirectory/status.txt');
}

/// 返回旧样本的运行时内容，给外部插画使用固定匿名编号。
Future<Map<String, String>> _legacySources() async => {
  for (final sample in autoSamples(
    await File('$_batchDirectory/input/aurora.svg').readAsString(),
    await File('$_batchDirectory/input/legacy-014.svg').readAsString(),
  ))
    (sample.id == '233KB' ? 'legacy-014' : sample.id): sample.source,
};

/// 保持第一轮的采集窗口和帧计数，每批只测一次 spinner 基线。
Future<void> _runBatch(_AutoBenchState state, _Batch batch) async {
  final output = File('$_batchDirectory/frames.jsonl').openWrite();
  final random = math.Random(batch.orderSeed);
  var current = 'warmup';
  try {
    await Future<void>.delayed(const Duration(seconds: 2));
    await state._waitFor(() => state._frames.isNotEmpty);
    if (!state.mounted) return;
    final view = View.of(state.context);
    final dpr = view.devicePixelRatio;
    final screen = view.physicalSize / dpr;
    final widths = {'16': 16.0, '48': 48.0, '200': 200.0, 'full': screen.width};
    final baseline = await state._measure(
      mode: _Mode.baseline,
      source: '',
      artSize: Size.zero,
    );
    output.writeln(
      jsonEncode({
        'type': 'baseline',
        'end_ms': DateTime.now().millisecondsSinceEpoch,
        'dpr': dpr,
        'screen_width_px': view.physicalSize.width,
        'screen_height_px': view.physicalSize.height,
        'display_hz': view.display.refreshRate,
        ...baseline,
      }),
    );
    await output.flush();
    final legacy = batch.samples.any((sample) => sample.split == 'legacy')
        ? await _legacySources()
        : const <String, String>{};
    for (final sample in batch.samples) {
      current = sample.id;
      _batchStatus('running $current');
      final SvgScene scene;
      final String source;
      try {
        source = sample.split == 'legacy'
            ? legacy[sample.id]!
            : await File('$_batchDirectory/input/${sample.id}.svg')
                  .readAsString();
        scene = await parseSvgAsync(data: source);
      } catch (error) {
        for (final size in sample.sizes) {
          _writeCaseError(output, sample, size, 'parse', autoR2Error(error));
        }
        await output.flush();
        continue;
      }
      final features = autoR2Features(scene);
      try {
        if (scene.width <= 0 ||
            scene.height <= 0 ||
            (scene.paths.isEmpty && scene.images.isEmpty)) {
          for (final size in sample.sizes) {
            _writeCaseError(output, sample, size, 'parse', 'empty_scene');
          }
          await output.flush();
          continue;
        }
        await RustXvgPictureCache.instance.getOrRenderAsync(source);
        final sizes = [...sample.sizes]..shuffle(random);
        for (final key in sizes) {
          current = '${sample.id}/$key';
          _batchStatus('running $current');
          final width = widths[key]!;
          final size = Size(width, width * scene.height / scene.width);
          final modes = [_Mode.vector, _Mode.cached];
          if ((random.nextInt(2) + batch.round) % 2 == 0) {
            modes.setAll(0, modes.reversed.toList());
          }
          final start = DateTime.now().millisecondsSinceEpoch;
          final measurements = <Map<String, Object?>>[];
          _Mode? failedMode;
          try {
            for (final mode in modes) {
              failedMode = mode;
              measurements.add(
                await state._measure(mode: mode, source: source, artSize: size),
              );
            }
          } catch (error) {
            _writeCaseError(
              output,
              sample,
              key,
              failedMode!.name,
              autoR2Error(error),
            );
            await output.flush();
            continue;
          }
          output.writeln(
            jsonEncode({
              'type': 'case',
              'sample': sample.id,
              'split': sample.split,
              'size': key,
              'start_ms': start,
              'end_ms': DateTime.now().millisecondsSinceEpoch,
              'width_dp': size.width,
              'height_dp': size.height,
              'visible_px':
                  (size.width *
                          math.min(size.height, screen.height) *
                          dpr *
                          dpr)
                      .round(),
              'features': features,
              'measurements': measurements,
            }),
          );
          await output.flush();
        }
      } finally {
        RustXvgPictureCache.instance.clear();
      }
    }
    await output.close();
    state._finishRun();
    _batchStatus('done');
  } catch (error) {
    await output.close();
    state._finishRun();
    _batchStatus('error $current ${error.runtimeType}');
  }
}

/// 记录一个被跳过的组合，不输出 SVG 原文或本机路径。
void _writeCaseError(
  IOSink output,
  _Requested sample,
  String size,
  String stage,
  String reason,
) {
  output.writeln(
    jsonEncode({
      'type': 'skip',
      'sample': sample.id,
      'split': sample.split,
      'size': size,
      'stage': stage,
      'reason': reason,
      'end_ms': DateTime.now().millisecondsSinceEpoch,
    }),
  );
}
