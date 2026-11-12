import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luckdraw/compat.dart';
import 'package:luckdraw/extend.dart';
import 'package:luckdraw/grid.dart';
import 'package:luckdraw/slot.dart';
import 'package:luckdraw/testing.dart';
import 'package:luckdraw/wheel.dart';

import '../support/golden_comparator.dart';

/// 数值允许的相对误差，来自 TEST_STRATEGY §6.5。
const double _relativeTolerance = 1e-9;

/// 首轮图像比较的设计上限；实测见 tool/parity/README.md。
const double _maxDiffRatio = 0.018;

/// 首轮图像比较的 RGBA 平均绝对误差上限。
const double _maxMeanError = 1.8;

/// 画布像素总数（180x180），用于把 DIAG 实测的差异像素数换算成占比。
const int _paritySurfacePixels = 32400;

/// 经区域分类和去文字验证的帧，仅保留实测值的百分之十余量。
const double _diagnosedHeadroom = 1.1;

/// 一个经诊断确认的帧：差异像素数与预乘 RGBA 均误的实测值。
typedef _MeasuredFrame = ({String layer, int diffPixels, double meanError});

/// DIAG / DIAG2 实测并经区域分类的帧。
///
/// - `text-heavy`：差异全部在文字区域，去文字后为 0（w04 帧 60）。
/// - `edge-aa`：文字光栅化差异加 reel 列边界处的 1 像素抗锯齿差异
///   （老虎机离屏位图复制与矢量裁剪回放的采样不同，几何位置无误）。
const Map<(String, String), _MeasuredFrame> _measuredFrames = {
  ('w04', '60'): (
    layer: 'text-heavy',
    diffPixels: 670,
    meanError: 1.3682253086419753
  ),
  ('s03', '60'): (layer: 'edge-aa', diffPixels: 775, meanError: 1.386404),
  ('s03', '240'): (layer: 'edge-aa', diffPixels: 733, meanError: 1.930154),
  ('s05', 'settled'): (layer: 'edge-aa', diffPixels: 638, meanError: 1.510694),
  ('s05', '240'): (layer: 'edge-aa', diffPixels: 638, meanError: 1.510694),
};

/// 返回 [id] 和关键帧 [label] 的容差；只放行经 DIAG / DIAG2 确认的帧。
///
/// 例如 `parityImageTolerance('w04', '60')` 返回 text-heavy 层，
/// `parityImageTolerance('s03', '240')` 返回 edge-aa 层；每帧上限为该帧
/// 实测值的 1.1 倍，且都不超过差异像素 4% / 均误 2.5，其余帧保持 1.8% / 1.8。
({String layer, double maxDiffRatio, double maxMeanError}) parityImageTolerance(
    String id, String label) {
  final measured = _measuredFrames[(id, label)];
  if (measured == null) {
    return (
      layer: 'standard',
      maxDiffRatio: _maxDiffRatio,
      maxMeanError: _maxMeanError
    );
  }
  return (
    layer: measured.layer,
    maxDiffRatio:
        measured.diffPixels / _paritySurfacePixels * _diagnosedHeadroom,
    maxMeanError: measured.meanError * _diagnosedHeadroom
  );
}

/// RGBA 每像素通道数。
const int _channels = 4;

/// 已知差异审计开关；只写 coverage 中的实测报告，不修改基线。
const bool _audit = bool.fromEnvironment('PARITY_AUDIT');

/// 读取 JSON 对象；错误格式立即失败，不补齐或修正基线。
Map<String, Object?> _readJson(String path) =>
    (jsonDecode(File(path).readAsStringSync()) as Map<String, Object?>);

/// 同一用例的上游输入和只读基线。
final class ParityCase {
  /// 按 [id] 读取两份 JSON。
  ParityCase(this.id)
      : data = _readJson('tool/parity/cases/$id.json'),
        baseline = _readJson('test/parity/baselines/$id/frames.json');

  /// 用例编号。
  final String id;

  /// 输入 JSON。
  final Map<String, Object?> data;

  /// 上游采样 JSON。
  final Map<String, Object?> baseline;

  /// 转换入口使用的原始配置。
  Map<String, Object?> get config => data['config']! as Map<String, Object?>;

  /// 逻辑尺寸。
  Size get size {
    final size = data['size']! as Map<String, Object?>;
    return Size((size['width']! as num).toDouble(),
        (size['height']! as num).toDouble());
  }

  /// 基线设备像素比。
  double get dpr => (data['dpr']! as num).toDouble();

  /// 严格顺序且耗尽即失败的随机源。
  SequenceRandom random() => SequenceRandom((data['random']! as List<Object?>)
      .map((value) => (value! as num).toDouble())
      .toList());

  /// 全部逐帧样本。
  List<Map<String, Object?>> get frames =>
      (baseline['frames']! as List<Object?>).cast<Map<String, Object?>>();

  /// 脚本动作。
  List<Map<String, Object?>> get script =>
      (data['script']! as List<Object?>).cast<Map<String, Object?>>();

  /// 关键帧标签与元数据。
  Map<String, Object?> get keyframes =>
      baseline['keyframes']! as Map<String, Object?>;
}

/// 将公开阶段映射成上游 step；settled 与 idle 都是零。
int _step(LuckyPhase phase) => switch (phase) {
      LuckyPhase.accelerating => 1,
      LuckyPhase.cruising => 2,
      LuckyPhase.decelerating => 3,
      _ => 0,
    };

/// 具有确定性时钟的类型擦除测试会话。
abstract interface class ParitySession {
  /// 正常结果首次可见的帧，取消不计为正常结束。
  int? get resultFrame;

  /// 正常结果的奖品下标，未中奖返回 null。
  int? get resultIndex;

  /// 当前关键数值的独立快照，列表必须拷贝以免后续帧覆盖。
  Map<String, Object?> snapshot();

  /// 在指定上游帧动作之前执行命令，再 tick 到基线时间。
  void advance(Map<String, Object?> frame);

  /// 在 pump 前准备全部图片，资源错误立即失败。
  Future<void> prepareImages();

  /// 构建生产渲染器的 surface，布局、帧和图片与数值会话共用。
  Widget surface();

  /// 释放控制器、时钟和图片解析器。
  void dispose();
}

/// 保留实际泛型约束的无头会话；不重写或复制玩法公式。
final class _Session<
    C extends Object,
    L extends LuckyLayout,
    F extends LuckyFrame,
    R extends LuckyResult<Object?>> implements ParitySession {
  /// 使用真实配置、策略及控制器创建布局并挂接手动时钟。
  _Session(this.input, this.config, this.game, this.controller, this.values,
      this.stop) {
    final environment =
        LuckyLayoutInput.headless(input.size, devicePixelRatio: input.dpr);
    layout = game.computeLayout(config, environment);
    environment.measurer.dispose();
    controller.attachHeadless(clock: clock, config: config, layout: layout);
  }

  /// 原始用例。
  final ParityCase input;

  /// compat 转换产生的配置。
  final C config;

  /// 生产策略。
  final LuckyGame<C, L, F, R> game;

  /// 生产控制器。
  final LuckyController<C, L, F, R> controller;

  /// 玩法特有数值读取。
  final Map<String, Object?> Function() values;

  /// 保留上游停止参数形状的类型化命令。
  final void Function(Object? index) stop;

  /// 确定性原始时钟。
  final ManualLuckyClock clock = ManualLuckyClock();

  /// 只计算一次的实际布局。
  late final L layout;

  /// 图片变化通知，仅驱动实际 surface。
  final ChangeNotifier imageChanges = ChangeNotifier();

  /// 图片准备完成信号。
  late final Completer<void> ready = Completer<void>();

  /// 生产图片解析器，保持 naturalSize 和解码行为。
  late final LuckyImageResolver images = LuckyImageResolver(
      onChanged: imageChanges.notifyListeners,
      onError: (error) => ready.completeError(StateError('$error')),
      onReady: () {
        if (!ready.isCompleted) ready.complete();
      });

  /// 实测结果回调的帧，用于 DEV-06 对齐。
  @override
  int? resultFrame;

  /// 当前局是否接收过停止命令；上游提前停止会先把 step 置二。
  bool _stopRequested = false;

  @override
  int? get resultIndex => controller.lastResult?.index;

  @override
  Map<String, Object?> snapshot() => {
        'step':
            controller.phase.value == LuckyPhase.accelerating && _stopRequested
                ? 2
                : _step(controller.phase.value),
        ...values(),
      };

  @override
  void advance(Map<String, Object?> frame) {
    final number = frame['frame']! as int;
    for (final action in input.script.where((a) => a['frame'] == number)) {
      if (action['action'] == 'play') {
        _stopRequested = false;
        expect(controller.play(), isTrue, reason: '${input.id} play');
      } else {
        stop(action['index']);
        _stopRequested = true;
      }
    }
    clock.tick(Duration(milliseconds: (frame['timeMs']! as num).round()));
    if (resultFrame == null && controller.phase.value == LuckyPhase.settled) {
      resultFrame = number;
    }
  }

  @override
  Future<void> prepareImages() async {
    images.update(
        game.collectImages(config, layout),
        ImageConfiguration(size: input.size, devicePixelRatio: input.dpr),
        input.dpr);
    await ready.future.timeout(const Duration(seconds: 15));
  }

  @override
  Widget surface() => game.createDefaultRenderer().buildSurface(
      TestWidgetsFlutterBinding.instance.rootElement!,
      LuckySurfaceData(
          config: config,
          layout: layout,
          layoutGeneration: 1,
          frame: controller.frame,
          frameListenable: controller.frameListenable,
          images: images,
          imagesListenable: imageChanges,
          layers: const [],
          hooks: const LuckyHooks(),
          devicePixelRatio: input.dpr,
          textDirection: TextDirection.ltr,
          performance: const LuckyPerformanceOptions(),
          isAnimating: true));

  @override
  void dispose() {
    controller.dispose();
    clock.dispose();
    images.dispose();
    imageChanges.dispose();
  }
}

/// 仅通过转盘 compat 入口创建实际转盘会话。
ParitySession wheelParitySession(ParityCase input) {
  final result = wheelFromLuckyCanvasConfig(input.config,
      options: LuckyCanvasCompatOptions.strictUpstream());
  expect(result.warnings, isEmpty);
  final controller = WheelController(random: input.random());
  return _Session(
      input,
      result.config,
      const WheelGame(),
      controller,
      () => {'rotateDeg': controller.frame.rotateDeg},
      (index) => controller.stop(index as int?));
}

/// 仅通过九宫格 compat 入口创建实际九宫格会话。
ParitySession gridParitySession(ParityCase input) {
  final result = gridFromLuckyCanvasConfig(input.config,
      options: LuckyCanvasCompatOptions.strictUpstream());
  expect(result.warnings, isEmpty);
  final controller = GridController(random: input.random());
  return _Session(
      input,
      result.config,
      const GridGame(),
      controller,
      () => {'currIndex': controller.frame.currIndex},
      (index) => controller.stop(index as int?));
}

/// 仅通过老虎机 compat 入口创建实际老虎机会话。
ParitySession slotParitySession(ParityCase input) {
  final result = slotFromLuckyCanvasConfig(input.config,
      options: LuckyCanvasCompatOptions.strictUpstream());
  expect(result.warnings, isEmpty);
  final controller = SlotController(random: input.random());
  return _Session(
      input,
      result.config,
      const SlotGame(),
      controller,
      () => {'scroll': List<double>.of(controller.frame.scroll)},
      (index) => index is List<Object?>
          ? controller.stopEach(index.cast<int>())
          : controller.stop(index as int?));
}

/// 比较全部数值和阶段，审计时将每个超差原值写入隔离报告。
void expectParitySequence(ParityCase input, ParitySession session) {
  final differences = <Map<String, Object?>>[];
  var exactDifferences = 0;
  var maxAbsoluteError = 0.0;
  void compare(int frame, String key, num actual, num expected) {
    if (actual != expected) exactDifferences++;
    maxAbsoluteError =
        math.max(maxAbsoluteError, (actual - expected).abs().toDouble());
    if ((actual - expected).abs() >
        _relativeTolerance * math.max(1, expected.abs())) {
      differences.add({
        'case': input.id,
        'frame': frame,
        'quantity': key,
        'upstream': expected,
        'ours': actual
      });
    }
  }

  for (final frame in input.frames) {
    session.advance(frame);
    final actual = session.snapshot();
    for (final entry in actual.entries) {
      final expected = frame[entry.key];
      if (entry.value is num) {
        compare(frame['frame']! as int, entry.key, entry.value! as num,
            expected! as num);
      } else {
        final values = entry.value! as List<double>;
        final upstream = expected! as List<Object?>;
        expect(values.length, upstream.length);
        final previous = (frame['frame']! as int) - 1;
        final starts = frame['stopScroll'] as List<Object?>?;
        final previousStarts = previous < 0
            ? null
            : input.frames[previous]['stopScroll'] as List<Object?>?;
        final firstDeceleration = starts != null &&
            starts.isNotEmpty &&
            (previousStarts == null || previousStarts.isEmpty);
        for (var i = 0; i < values.length; i++) {
          // TEST_STRATEGY §6.3：U-06 唯一豁免帧必须等于上游 stopScroll。
          compare(frame['frame']! as int, '${entry.key}[$i]', values[i],
              (firstDeceleration ? starts[i] : upstream[i])! as num);
        }
      }
    }
  }
  if (_audit) {
    File('coverage/${input.id}-differences.json').writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(differences));
    File('coverage/${input.id}-numeric-summary.json')
        .writeAsStringSync(jsonEncode({
      'frames': input.frames.length,
      'exactDifferences': exactDifferences,
      'maxAbsoluteError': maxAbsoluteError
    }));
  }
  final cancelled = input.script.any((action) =>
      action['action'] == 'stop' &&
      action['index'] is num &&
      (action['index']! as num) < 0);
  if (!cancelled && input.baseline['settledFrame'] != null) {
    expect(session.resultFrame, input.baseline['settledFrame']);
    final events = input.baseline['events']! as List<Object?>;
    if (events.isNotEmpty) {
      final event = events.single! as Map<String, Object?>;
      expect(session.resultFrame, (event['frame']! as int) - 1);
      expect(session.resultIndex, event['resultIndex']);
    }
  }
  expect(differences, isEmpty,
      reason:
          '${input.id}: ${differences.length} differences; first=${differences.take(3).toList()}');
}

/// 解码 PNG 并复制通道，释放所有 native 图片资源。
Future<({int width, int height, ByteData data})> _decode(
    Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final image = (await codec.getNextFrame()).image;
  codec.dispose();
  try {
    return (
      width: image.width,
      height: image.height,
      data: (await image.toByteData())!
    );
  } finally {
    image.dispose();
  }
}

/// 对每张真实 surface 截图量化误差，并调用生产容差比较器验证。
Future<void> expectParityKeyframes(
    WidgetTester tester, ParityCase input, ParitySession session) async {
  final metrics = <Map<String, Object?>>[];
  final boundaryKey = GlobalKey();
  await tester.runAsync(session.prepareImages);
  await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
          child: RepaintBoundary(
              key: boundaryKey,
              child: SizedBox.fromSize(
                  size: input.size,
                  child: Builder(builder: (_) => session.surface()))))));
  Future<void> capture(String label, Map<String, Object?> metadata) async {
    final tolerance = parityImageTolerance(input.id, label);
    final comparator = LuckyToleranceComparator(
        File('test/parity/parity_support.dart').absolute.uri,
        maxDiffRatio: tolerance.maxDiffRatio,
        maxMeanError: tolerance.maxMeanError);
    await tester.pump();
    final boundary = boundaryKey.currentContext!.findRenderObject()!
        as RenderRepaintBoundary;
    final png = (await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: input.dpr);
      try {
        return (await image.toByteData(format: ui.ImageByteFormat.png))!
            .buffer
            .asUint8List();
      } finally {
        image.dispose();
      }
    }))!;
    final relative = 'baselines/${input.id}/${metadata['file']}';
    if (_audit) {
      File('coverage/${input.id}-${metadata['file']}').writeAsBytesSync(png);
    }
    final result = await tester.runAsync(() async {
      final actual = await _decode(png);
      final expected =
          await _decode(File('test/parity/$relative').readAsBytesSync());
      expect(actual.width, expected.width);
      expect(actual.height, expected.height);
      var different = 0;
      var error = 0;
      for (var offset = 0;
          offset < actual.data.lengthInBytes;
          offset += _channels) {
        var differs = false;
        for (var channel = 0; channel < _channels; channel++) {
          final delta = (actual.data.getUint8(offset + channel) -
                  expected.data.getUint8(offset + channel))
              .abs();
          error += delta;
          differs |= delta > kLuckyPixelTolerance;
        }
        if (differs) different++;
      }
      return <String, Object?>{
        'case': input.id,
        'label': label,
        'frame': metadata['frame'],
        'diffRatio': different / (actual.width * actual.height),
        'meanError': error / actual.data.lengthInBytes
      };
    });
    metrics.add(result!);
    if (!_audit) {
      expect(
          await tester
              .runAsync(() => comparator.compare(png, Uri.parse(relative))),
          isTrue);
    }
  }

  try {
    await capture('0', input.keyframes['0']! as Map<String, Object?>);
    for (final frame in input.frames) {
      session.advance(frame);
      for (final entry
          in input.keyframes.entries.where((entry) => entry.key != '0')) {
        final metadata = entry.value! as Map<String, Object?>;
        if (metadata['frame'] == frame['frame']) {
          await capture(entry.key, metadata);
        }
      }
    }
    if (_audit) {
      File('coverage/${input.id}-images.json').writeAsStringSync(
          const JsonEncoder.withIndent('  ').convert(metrics));
    }
    expect(metrics, hasLength(input.keyframes.length));
    expect(metrics.every((m) {
      final tolerance = parityImageTolerance(input.id, m['label']! as String);
      return (m['diffRatio']! as double) <= tolerance.maxDiffRatio &&
          (m['meanError']! as double) <= tolerance.maxMeanError;
    }), isTrue, reason: '$metrics');
  } finally {
    await tester.pumpWidget(const SizedBox.shrink());
  }
}
