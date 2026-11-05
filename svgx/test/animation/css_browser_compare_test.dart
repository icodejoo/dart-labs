import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:svgx/src/animation/animated_svg_painter.dart';
import 'package:svgx/src/animation/svg_document_parser.dart';
import 'package:svgx/src/animation/svg_theme.dart';
import 'package:svgx/svgx.dart' show RustLib;
import 'package:xml/xml.dart';

/// 参考画布边长。
const _side = 256;

/// 每个像素的字节数。
const _channels = 4;

/// 参与指标的颜色通道数。
const _rgb = 3;

/// 像素差异阈值，严格大于才计数。
const _threshold = 32;

/// 块平均差异阈值。
const _blurThreshold = 24;

/// 块平均边长。
const _block = 4;

/// 不透明通道最大值。
const _opaque = 255;

/// 最多导出的三联图数。
const _worstCount = 20;

/// 白色背景标识。
const _white = '#ffffff';

/// 深灰背景标识。
const _dark = '#404040';

/// 清单文件名。
const _manifestName = 'manifest.json';

/// 深灰补采目录名。
const _darkDir = 'extra_dark_bg';

/// 样本路径环境变量。
const _samplesEnv = 'SVGX_CSS_SAMPLES';

/// 参考路径环境变量。
const _referenceEnv = 'SVGX_BROWSER_REF';

/// 门禁阈值环境变量。
const _limitEnv = 'SVGX_COMPARE_MAX_RATIO';

/// 像素差异占比字段。
const _ratioKey = 'diffRatio';

/// 平均绝对差字段。
const _meanKey = 'meanAbs';

/// 最大通道差字段。
const _maxKey = 'maxChannelDiff';

/// 块平均差异字段。
const _blurKey = 'blurDiffRatio';

/// 样本清单字段。
const _samplesKey = 'samples';

/// 逐帧结果字段。
const _framesKey = 'frames';

/// 输入文件字段。
const _fileKey = 'file';

/// 样本编号字段。
const _idKey = 'id';

/// 采集参数字段。
const _paramsKey = 'params';

/// 背景颜色字段。
const _backgroundKey = 'background';

/// 异常详情字段。
const _errorKey = 'error';

/// 全文件共用唯一一次原生初始化尝试。
Future<bool>? _initAttempt;

/// 原生加载失败详情。
String? _nativeError;

/// 初始化原生库，失败仍继续比较。
Future<bool> _nativeReady() => _initAttempt ??= RustLib.init()
    .then((_) => true)
    .catchError((Object error) {
      _nativeError = error.toString();
      return false;
    });

/// 连接外部输入或输出路径。
String _join(String directory, String name) => '$directory/$name';

/// 读取清单，不推测样本或时刻列表。
Map<String, dynamic> _manifest(String directory) =>
    jsonDecode(File(_join(directory, _manifestName)).readAsStringSync())
        as Map<String, dynamic>;

/// 缺少任一必需环境变量时标记当前用例跳过。
bool _hasInputs() {
  for (final key in [_samplesEnv, _referenceEnv]) {
    if ((Platform.environment[key] ?? '').isEmpty) {
      markTestSkipped('未设置 $key，跳过外部参考帧比较');
      return false;
    }
  }
  return true;
}

/// 读取固定尺寸图像的未预乘 RGBA，并验证底色完全不透明。
Future<Uint8List> _rgba(ui.Image image) async {
  if (image.width != _side || image.height != _side) {
    throw StateError('图像尺寸必须为 $_side×$_side');
  }
  final data = await image.toByteData(
    format: ui.ImageByteFormat.rawStraightRgba,
  );
  final bytes = data!.buffer.asUint8List(
    data.offsetInBytes,
    data.lengthInBytes,
  );
  for (var i = _rgb; i < bytes.length; i += _channels) {
    if (bytes[i] != _opaque) throw StateError('比较帧含非不透明像素');
  }
  return bytes;
}

/// 通过引擎解码 PNG，释放编解码器。
Future<ui.Image> _decode(Uint8List png) async {
  final codec = await ui.instantiateImageCodec(png);
  try {
    return (await codec.getNextFrame()).image;
  } finally {
    codec.dispose();
  }
}

/// 从不透明 RGBA 创建图像，供三联图与无损回环验证使用。
Future<ui.Image> _fromRgba(Uint8List bytes) async {
  final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  final descriptor = ui.ImageDescriptor.raw(
    buffer,
    width: _side,
    height: _side,
    pixelFormat: ui.PixelFormat.rgba8888,
  );
  final codec = await descriptor.instantiateCodec();
  try {
    return (await codec.getNextFrame()).image;
  } finally {
    codec.dispose();
    descriptor.dispose();
    buffer.dispose();
  }
}

/// 计算 RGB 像素指标与不取整的块平均指标；忽略已验证不透明的 alpha。
Map<String, num> _compare(Uint8List reference, Uint8List actual) {
  const pixels = _side * _side;
  if (reference.length != pixels * _channels ||
      actual.length != reference.length) {
    throw ArgumentError('RGBA 缓冲区长度错误');
  }
  var differing = 0;
  var sum = 0;
  var maximum = 0;
  for (var i = 0; i < reference.length; i += _channels) {
    var changed = false;
    for (var c = 0; c < _rgb; c++) {
      final delta = (reference[i + c] - actual[i + c]).abs();
      sum += delta;
      maximum = math.max(maximum, delta);
      changed |= delta > _threshold;
    }
    if (changed) differing++;
  }
  var differingBlocks = 0;
  for (var y = 0; y < _side; y += _block) {
    for (var x = 0; x < _side; x += _block) {
      var changed = false;
      for (var c = 0; c < _rgb; c++) {
        var deltaSum = 0;
        for (var dy = 0; dy < _block; dy++) {
          for (var dx = 0; dx < _block; dx++) {
            final i = ((y + dy) * _side + x + dx) * _channels + c;
            deltaSum += reference[i] - actual[i];
          }
        }
        changed |= deltaSum.abs() > _blurThreshold * _block * _block;
      }
      if (changed) differingBlocks++;
    }
  }
  return {
    _ratioKey: differing / pixels,
    _meanKey: sum / (pixels * _rgb),
    _maxKey: maximum,
    _blurKey: differingBlocks / (pixels / (_block * _block)),
  };
}

/// 只忽略 painter 首次视口裁剪，其余操作完整转发；外层画布仍裁剪。
class _ViewportCanvas implements ui.Canvas {
  /// 包装一个真实画布。
  _ViewportCanvas(this.canvas, this.origin);

  /// 实际接收绘制命令的画布。
  final ui.Canvas canvas;

  /// 在 painter 完成适配变换后补偿 viewBox 原点。
  final ui.Offset origin;

  /// 首次 clipRect 是 painter 固定的 viewBox 裁剪。
  bool _firstClip = true;

  /// 跳过首次裁剪，其后保留原语义。
  @override
  void clipRect(
    ui.Rect rect, {
    ui.ClipOp clipOp = ui.ClipOp.intersect,
    bool doAntiAlias = true,
  }) {
    if (_firstClip) {
      _firstClip = false;
      canvas.translate(-origin.dx, -origin.dy);
      return;
    }
    canvas.clipRect(rect, clipOp: clipOp, doAntiAlias: doAntiAlias);
  }

  /// 转发路径裁剪。
  @override
  void clipPath(ui.Path path, {bool doAntiAlias = true}) =>
      canvas.clipPath(path, doAntiAlias: doAntiAlias);

  /// 转发矩形绘制（根背景色整面铺底用）。
  @override
  void drawRect(ui.Rect rect, ui.Paint paint) => canvas.drawRect(rect, paint);

  /// 转发路径绘制。
  @override
  void drawPath(ui.Path path, ui.Paint paint) => canvas.drawPath(path, paint);

  /// 转发 TextPainter 间接调用的文字绘制。
  @override
  void drawParagraph(ui.Paragraph paragraph, ui.Offset offset) =>
      canvas.drawParagraph(paragraph, offset);

  /// 转发图像绘制。
  @override
  void drawImageRect(
    ui.Image image,
    ui.Rect src,
    ui.Rect dst,
    ui.Paint paint,
  ) => canvas.drawImageRect(image, src, dst, paint);

  /// 转发状态保存。
  @override
  void save() => canvas.save();

  /// 转发离屏图层。
  @override
  void saveLayer(ui.Rect? bounds, ui.Paint paint) =>
      canvas.saveLayer(bounds, paint);

  /// 转发状态恢复。
  @override
  void restore() => canvas.restore();

  /// 转发平移。
  @override
  void translate(double dx, double dy) => canvas.translate(dx, dy);

  /// 转发缩放。
  @override
  void scale(double sx, [double? sy]) => canvas.scale(sx, sy);

  /// 转发旋转。
  @override
  void rotate(double radians) => canvas.rotate(radians);

  /// 转发矩阵。
  @override
  void transform(Float64List matrix4) => canvas.transform(matrix4);

  /// 新增绘图操作时明确报错，防止静默丢失命令。
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('未转发的 Canvas 操作：${invocation.memberName}');
}

/// 按 viewBox 优先的尺寸绘制，完整传递渐变、裁剪路径和遮罩。
Future<Uint8List> _render(
  SvgDocument document,
  ui.Size intrinsic,
  int time,
  String background, [
  ui.Offset origin = ui.Offset.zero,
]) async {
  final clock = ValueNotifier(Duration(milliseconds: time));
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  final bounds = ui.Rect.fromLTWH(0, 0, _side.toDouble(), _side.toDouble());
  canvas.clipRect(bounds);
  canvas.drawRect(
    bounds,
    ui.Paint()..color = ui.Color(background == _dark ? 0xff404040 : 0xffffffff),
  );
  try {
    AnimatedSvgPainter(
      root: document.root,
      intrinsicSize: intrinsic,
      clock: clock,
      theme: const SvgxTheme(),
      fit: BoxFit.contain,
      alignment: Alignment.center,
      gradients: document.gradients,
      clipPaths: document.clipPaths,
      masks: document.masks,
      backgroundColor: document.backgroundColor,
    ).paint(_ViewportCanvas(canvas, origin), bounds.size);
  } catch (_) {
    recorder.endRecording().dispose();
    rethrow;
  } finally {
    clock.dispose();
  }
  final picture = recorder.endRecording();
  try {
    final image = await picture.toImage(_side, _side);
    try {
      return await _rgba(image);
    } finally {
      image.dispose();
    }
  } finally {
    picture.dispose();
  }
}

/// 创建浏览器、svgx、红色差异高亮的三联图。
Future<ui.Image> _triptych(Uint8List reference, Uint8List actual) async {
  final diff = Uint8List.fromList(reference);
  for (var i = 0; i < diff.length; i += _channels) {
    final changed = List.generate(
      _rgb,
      (c) => (reference[i + c] - actual[i + c]).abs(),
    ).any((d) => d > _threshold);
    for (var c = 0; c < _rgb; c++) {
      diff[i + c] = changed
          ? (c == 0 ? _opaque : 0)
          : reference[i + c] ~/ _channels;
    }
  }
  final images = <ui.Image>[];
  final recorder = ui.PictureRecorder();
  try {
    for (final bytes in [reference, actual, diff]) {
      images.add(await _fromRgba(bytes));
    }
    final canvas = ui.Canvas(recorder);
    for (var i = 0; i < images.length; i++) {
      canvas.drawImage(
        images[i],
        ui.Offset((i * _side).toDouble(), 0),
        ui.Paint(),
      );
    }
    final picture = recorder.endRecording();
    try {
      return await picture.toImage(_rgb * _side, _side);
    } finally {
      picture.dispose();
    }
  } finally {
    for (final image in images) {
      image.dispose();
    }
  }
}

/// 按线性插值计算分位数，空集返回空值。
double? _percentile(List<double> sorted, double fraction) {
  if (sorted.isEmpty) return null;
  final position = (sorted.length - 1) * fraction;
  final lower = position.floor();
  final upper = position.ceil();
  return sorted[lower] + (sorted[upper] - sorted[lower]) * (position - lower);
}

/// 构造不透明合成图，可平移棋盘或只改变指定色块。
Uint8List _synthetic({int shift = 0, int patch = 0, bool checker = false}) {
  final bytes = Uint8List(_side * _side * _channels);
  for (var y = 0; y < _side; y++) {
    for (var x = 0; x < _side; x++) {
      final i = (y * _side + x) * _channels;
      final value = checker
          ? (((x + shift) ~/ _block + y ~/ _block).isEven ? _opaque : 0)
          : (x < patch && y < patch ? _opaque : 0);
      for (var c = 0; c < _rgb; c++) {
        bytes[i + c] = value;
      }
      bytes[i + _rgb] = _opaque;
    }
  }
  return bytes;
}

/// 注册默认自检与按环境变量启用的参考帧比较。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('像素指标、块平均与三联图自检', () async {
    final base = _synthetic();
    expect(_compare(base, base).values, everyElement(0));
    expect(
      _compare(
        _synthetic(checker: true),
        _synthetic(checker: true, shift: 1),
      )[_ratioKey],
      greaterThan(0.2),
    );
    const patchSide = 10;
    final metrics = _compare(base, _synthetic(patch: patchSide));
    expect(metrics[_ratioKey], patchSide * patchSide / (_side * _side));
    expect(
      metrics[_meanKey],
      _opaque * patchSide * patchSide / (_side * _side),
    );
    expect(metrics[_maxKey], _opaque);
    expect(metrics[_blurKey], 9 / ((_side / _block) * (_side / _block)));
    final sparse = Uint8List.fromList(base);
    sparse[0] = _opaque;
    expect(_compare(base, sparse)[_blurKey], 0);
    final image = await _triptych(base, _synthetic(patch: patchSide));
    try {
      expect(image.width, _rgb * _side);
      expect(image.height, _side);
      final decoded = await _decode(
        (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer
            .asUint8List(),
      );
      expect(decoded.width, _rgb * _side);
      decoded.dispose();
    } finally {
      image.dispose();
    }
  });

  test('画布裁剪、非零原点与居中适配自检', () async {
    const origin = ui.Offset(10, 20);
    const intrinsic = ui.Size(100, 50);
    final document = parseAnimatedSvgDocument(
      '<svg width="800" height="800" viewBox="10 20 100 50">'
      '<rect x="10" y="10" width="100" height="60" fill="#000000"/>'
      '</svg>',
    );
    final pixels = await _render(document, intrinsic, 1, _white, origin);
    // 可见矩形从 y≈38 开始，包含上方 letterbox 区域。
    expect(pixels[(40 * _side + 128) * _channels], 0);
    expect(pixels[(30 * _side + 128) * _channels], _opaque);
    expect(pixels[(180 * _side + 128) * _channels], 0);
    expect(pixels[(200 * _side + 128) * _channels], _opaque);
  });

  test('浏览器 PNG 自比与 RGBA 无损回环', () async {
    if (!_hasInputs()) return;
    final directory = Platform.environment[_referenceEnv]!;
    final manifest = _manifest(directory);
    final sample =
        (manifest[_samplesKey] as List).first as Map<String, dynamic>;
    final frame =
        (sample[_framesKey] as Map<String, dynamic>).values.first
            as Map<String, dynamic>;
    final image = await _decode(
      await File(_join(directory, frame[_fileKey] as String)).readAsBytes(),
    );
    try {
      final bytes = await _rgba(image);
      expect(
        _compare(bytes, Uint8List.fromList(bytes)).values,
        everyElement(0),
      );
      final reconstructed = await _fromRgba(bytes);
      try {
        final png = await reconstructed.toByteData(
          format: ui.ImageByteFormat.png,
        );
        final decoded = await _decode(png!.buffer.asUint8List());
        try {
          expect(await _rgba(decoded), orderedEquals(bytes));
        } finally {
          decoded.dispose();
        }
      } finally {
        reconstructed.dispose();
      }
    } finally {
      image.dispose();
    }
  });

  test('SVGator CSS 浏览器逐帧比较', () async {
    if (!_hasInputs()) return;
    await _runComparison();
  }, timeout: const Timeout(Duration(minutes: 5)));
}

/// 遍历两套清单、隔离帧异常，打印汇总并按需输出最坏帧。
Future<void> _runComparison() async {
  final env = Platform.environment;
  final samplesDirectory = env[_samplesEnv]!;
  final referenceDirectory = env[_referenceEnv]!;
  final output = env['SVGX_COMPARE_OUT'];
  final ids = env['SVGX_COMPARE_IDS']
      ?.split(',')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toSet();
  final limit = env[_limitEnv] == null ? null : double.parse(env[_limitEnv]!);
  if (limit != null && (!limit.isFinite || limit < 0 || limit > 1)) {
    throw ArgumentError('SVGX_COMPARE_MAX_RATIO 必须在 0～1 之间');
  }
  final native = await _nativeReady();
  final watch = Stopwatch()..start();
  final frames = <Map<String, dynamic>>[];
  final worst =
      <({Map<String, dynamic> frame, Uint8List reference, Uint8List actual})>[];
  final sizeChecks = <Map<String, dynamic>>[];
  final mainManifest = _manifest(referenceDirectory);
  final allowedIds = (mainManifest[_samplesKey] as List)
      .map((s) => s[_idKey] as String)
      .toSet();
  final directories = [referenceDirectory];
  final darkDirectory = _join(referenceDirectory, _darkDir);
  if (File(_join(darkDirectory, _manifestName)).existsSync()) {
    directories.add(darkDirectory);
  }
  final documents =
      <String, ({SvgDocument document, ui.Size size, ui.Offset origin})>{};
  for (final directory in directories) {
    final manifest = directory == referenceDirectory
        ? mainManifest
        : _manifest(directory);
    final background = (manifest[_paramsKey] as Map)[_backgroundKey] as String;
    if (background != _white && background != _dark) {
      throw StateError('未支持的底色 $background');
    }
    for (final sample in manifest[_samplesKey] as List) {
      final id = sample[_idKey] as String;
      if (!allowedIds.contains(id) || (ids != null && !ids.contains(id))) {
        continue;
      }
      for (final time in manifest[_paramsKey]['timesMs'] as List) {
        final frame = <String, dynamic>{
          _idKey: id,
          'timeMs': time,
          _backgroundKey: background,
        };
        frames.add(frame);
        try {
          if (!documents.containsKey(id)) {
            final source = await File(
              _join(samplesDirectory, sample[_fileKey] as String),
            ).readAsString();
            final document = parseAnimatedSvgDocument(source);
            await resolveImageNodes(document);
            final root = XmlDocument.parse(source).rootElement;
            final viewBox = root
                .getAttribute('viewBox')
                ?.trim()
                .split(RegExp(r'[\s,]+'))
                .map(double.parse)
                .toList();
            final intrinsic = viewBox == null
                ? ui.Size(document.width, document.height)
                : ui.Size(viewBox[2], viewBox[3]);
            final origin = viewBox == null
                ? ui.Offset.zero
                : ui.Offset(viewBox[0], viewBox[1]);
            if (sample['svg']['viewBoxPatchedTo'] != null) {
              final patched = parseAnimatedSvgDocument(
                source.replaceFirst(
                  '<svg',
                  '<svg viewBox="${sample['svg']['viewBoxPatchedTo']}"',
                ),
              );
              await resolveImageNodes(patched);
              final a = await _render(
                document,
                intrinsic,
                time as int,
                background,
              );
              final b = await _render(
                patched,
                ui.Size(patched.width, patched.height),
                time,
                background,
              );
              final check = _compare(a, b);
              if (check.values.any((v) => v != 0)) {
                throw StateError('补 viewBox 后结果不等价：$check');
              }
              sizeChecks.add({
                _idKey: id,
                'intrinsicWidth': intrinsic.width,
                'intrinsicHeight': intrinsic.height,
                'metrics': check,
              });
            }
            documents[id] = (
              document: document,
              size: intrinsic,
              origin: origin,
            );
          }
          final parsed = documents[id]!;
          final actual = await _render(
            parsed.document,
            parsed.size,
            time as int,
            background,
            parsed.origin,
          );
          final path = sample[_framesKey]['$time'][_fileKey] as String;
          final image = await _decode(
            await File(_join(directory, path)).readAsBytes(),
          );
          late Uint8List reference;
          try {
            reference = await _rgba(image);
          } finally {
            image.dispose();
          }
          frame.addAll(_compare(reference, actual));
          if (output != null && output.isNotEmpty) {
            worst.add((frame: frame, reference: reference, actual: actual));
            worst.sort(
              (a, b) => (b.frame[_ratioKey] as num).compareTo(
                a.frame[_ratioKey] as num,
              ),
            );
            if (worst.length > _worstCount) worst.removeLast();
          }
        } catch (error, stack) {
          frame[_errorKey] = error.toString();
          frame['stack'] = stack.toString();
        }
      }
    }
  }
  final valid = frames.where((f) => !f.containsKey(_errorKey)).toList();
  final ratios = valid.map((f) => f[_ratioKey] as double).toList()..sort();
  final worstBySample = <String, Map<String, dynamic>>{};
  for (final frame in valid) {
    final id = frame[_idKey] as String;
    if (!worstBySample.containsKey(id) ||
        (frame[_ratioKey] as double) >
            (worstBySample[id]![_ratioKey] as double)) {
      worstBySample[id] = frame;
    }
  }
  final errors = frames.where((f) => f.containsKey(_errorKey)).toList();
  final summary = <String, dynamic>{
    'frameCount': frames.length,
    'successfulFrames': valid.length,
    'median': _percentile(ratios, 0.5),
    'p90': _percentile(ratios, 0.9),
    'p99': _percentile(ratios, 0.99),
    'max': ratios.isEmpty ? null : ratios.last,
    'above3Percent': ratios.where((r) => r > 0.03).length,
    'above6Percent': ratios.where((r) => r > 0.06).length,
    'nativeAvailable': native,
    'nativeWarning': native ? null : '原生库不可用，结果可能失真：$_nativeError',
    'errorFrames': errors,
    'worstBySample': worstBySample,
    'viewBoxFallbackChecks': sizeChecks,
    'comparisonSeconds': watch.elapsedMilliseconds / 1000,
  };
  if (!native) debugPrint('!!! 原生库不可用，结果可能失真 !!! $_nativeError');
  debugPrint('浏览器逐帧比较汇总：${jsonEncode(summary)}', wrapWidth: 1024);
  if (output != null && output.isNotEmpty) {
    await Directory(output).create(recursive: true);
    for (var i = 0; i < worst.length; i++) {
      final entry = worst[i];
      final name =
          'worst_${i + 1}_${entry.frame[_idKey]}_t${entry.frame['timeMs']}.png';
      final image = await _triptych(entry.reference, entry.actual);
      try {
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(_join(output, name))
            .writeAsBytes(data!.buffer.asUint8List());
        entry.frame['triptych'] = name;
      } finally {
        image.dispose();
      }
    }
    await File(_join(output, 'compare_results.json')).writeAsString(
      const JsonEncoder.withIndent('  ')
          .convert({'summary': summary, _framesKey: frames}),
    );
  }
  if (limit != null) {
    expect(errors, isEmpty, reason: '门禁不能忽略异常帧');
    expect(valid, isNotEmpty, reason: '门禁不能比较空集');
    expect(
      valid.where((f) => (f[_ratioKey] as double) > limit).toList(),
      isEmpty,
      reason: '逐帧 diffRatio 超出门禁阈值 $limit',
    );
  }
}
