import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:luckdraw/capsule.dart';
import 'package:luckdraw/grid.dart';
import 'package:luckdraw/lots.dart';
import 'package:luckdraw/lotto.dart';
import 'package:luckdraw/number_wheel.dart';
import 'package:luckdraw/slot.dart';
import 'package:luckdraw/wheel.dart';

/// 标准基准画布边长，单位逻辑像素。
const double kBenchSize = 320;

/// 固定伪随机种子，保证各轮运动输入一致。
const int _seed = 46;

/// 源图片边长，与 TEST_STRATEGY §7.1 一致。
const int _imageSide = 128;

/// 转盘奖品数，也是准备图片的数量。
const int _wheelPrizes = 12;

/// 三列老虎机的奖品数。
const int _slotPrizes = 10;

/// 拉霸机场景标识，与独立真机测试的 reportKey 一致。
const String _leverScene = 'lever_steady';

/// 九宫格边长。
const int _gridSide = 3;

/// 奖品图片在画布中的逻辑边长。
const double _displayImageSide = 32;

/// 所有基准使用的明亮底色。
const Color _light = Color(0xFFFFE0B2);

/// 所有基准使用的强调色。
const Color _accent = Color(0xFFE65100);

/// 成对的基础填充。
const LuckyFill _lightFill = LuckyFill.color(_light);

/// 强调色填充。
const LuckyFill _accentFill = LuckyFill.color(_accent);

/// 每项基准共享的文字布局。
const List<LuckyText> _labels = [
  LuckyText('Prize', top: LuckyLength.px(50)),
  LuckyText('luckdraw', top: LuckyLength.px(70)),
];

/// 稳态记录长度，按 TEST_STRATEGY §7.1 为五秒。
const Duration kBenchSteadyDuration = Duration(seconds: 5);

/// RSS 采样前页面稳定时长。
const Duration kBenchSettleDuration = Duration(seconds: 2);

/// 各场景的准备完成信号与控制器生命周期，所有者必须调用 [dispose]。
class BenchScene {
  /// 关联真实玩法 Widget、命令、阶段监听和图片就绪信号。
  const BenchScene(
      this.widget, this.play, this.stop, this.phase, this.dispose, this.ready);

  /// 有界约束内显示的玩法。
  final Widget widget;

  /// 请求开始，成功时返回 true。
  final bool Function() play;

  /// 按固定目标停止；大乐透抽样也使用固定种子。
  final bool Function() stop;

  /// 当前控制器阶段。
  final ValueListenable<LuckyPhase> phase;

  /// 页面卸载后释放外部控制器。
  final VoidCallback dispose;

  /// 全部图片解析结束后完成。
  final Future<void> ready;
}

/// 在测量开始前生成无网络、无 assets 依赖的 128×128 PNG 奖品源图。
///
/// 返回独立的 provider，避免十二份奖品意外退化为一张共享图片。
Future<List<MemoryImage>> prepareBenchImages() async {
  final images = <MemoryImage>[];
  for (var index = 0; index < _wheelPrizes; index++) {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawColor(index.isEven ? _accent : _light, BlendMode.src);
    canvas.drawCircle(const Offset(_imageSide / 2, _imageSide / 2),
        (index + 1).toDouble(), Paint()..color = const Color(0xFF1A237E));
    final picture = recorder.endRecording();
    final image = await picture.toImage(_imageSide, _imageSide);
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) throw StateError('无法生成奖品源图');
      images.add(MemoryImage(
          bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes)));
    } finally {
      image.dispose();
      picture.dispose();
    }
  }
  return images;
}

/// 按 [key] 创建已有公开入口的真实玩法；未知场景抛 [ArgumentError]。
///
/// [images] 来自 [prepareBenchImages]，至少十二张。所有场景都显式持有控制器。
/// [wheelCacheMode] 覆盖转盘缓存策略；[wheelTexts]/[wheelImages] 用于独立消融。
BenchScene createBenchScene(String key, List<MemoryImage> images,
    {LuckyCacheMode? wheelCacheMode,
    bool wheelTexts = true,
    bool wheelImages = true}) {
  final ready = Completer<void>();

  /// 只完成一次图片就绪信号，允许配置重新触发回调。
  void onReady() {
    if (!ready.isCompleted) ready.complete();
  }

  /// 返回指定源图的统一显示尺寸配置。
  LuckyImage imageAt(int index) => LuckyImage(images[index],
      width: const LuckyLength.px(_displayImageSide),
      height: const LuckyLength.px(_displayImageSide));
  switch (key) {
    case 'wheel_steady_picture':
    case 'wheel_steady':
    case 'wheel_first_frame':
    case 'memory_cycles':
      final controller = WheelController(random: math.Random(_seed));
      return BenchScene(
          LuckyWheel(
              config: WheelConfig(prizes: [
                for (var i = 0; i < _wheelPrizes; i++)
                  WheelPrize(
                      background: i.isEven ? _lightFill : _accentFill,
                      texts: wheelTexts ? _labels : const [],
                      images: wheelImages ? [imageAt(i)] : const [],
                      weight: 1),
              ]),
              controller: controller,
              performance: LuckyPerformanceOptions(
                  cacheMode: wheelCacheMode ??
                      (key == 'wheel_steady_picture'
                          ? LuckyCacheMode.picture
                          : const LuckyPerformanceOptions().cacheMode)),
              onReady: onReady),
          controller.play,
          () => controller.stop(0),
          controller.phase,
          controller.dispose,
          ready.future);
    case 'grid_steady':
      final controller = GridController(random: math.Random(_seed));
      const cells = [
        (0, 0),
        (1, 0),
        (2, 0),
        (2, 1),
        (2, 2),
        (1, 2),
        (0, 2),
        (0, 1)
      ];
      return BenchScene(
          LuckyGrid(
              config: GridConfig(
                  rows: _gridSide,
                  cols: _gridSide,
                  prizes: [
                    for (final cell in cells)
                      GridPrize(
                          x: cell.$1,
                          y: cell.$2,
                          weight: 1,
                          texts: const [LuckyText('Prize')]),
                  ],
                  buttons: const [GridButton(x: 1, y: 1)],
                  style: const GridStyle(
                      cell: LuckyCellStyle(
                          background: LuckyFill.gradient(
                              LinearGradient(colors: [_light, _accent])),
                          shadow:
                              LuckyShadow(blur: 6, color: Color(0x66000000))))),
              controller: controller,
              onReady: onReady),
          controller.play,
          () => controller.stop(0),
          controller.phase,
          controller.dispose,
          ready.future);
    case 'slot_steady':
    case 'slot_raster':
    case _leverScene:
      final controller = SlotController(random: math.Random(_seed));
      final config = SlotConfig(prizes: [
        for (var i = 0; i < _slotPrizes; i++)
          SlotPrize(images: [imageAt(i)], weight: 1, background: _lightFill),
      ], reels: const [
        SlotReel(),
        SlotReel(),
        SlotReel()
      ]);
      if (key == _leverScene) {
        return BenchScene(
            LuckyLeverSlotMachine(
                config: config, controller: controller, onReady: onReady),
            controller.play,
            () => controller.stopEach(const [0, 1, 2]),
            controller.phase,
            controller.dispose,
            ready.future);
      }
      return BenchScene(
          LuckySlotMachine(
              config: SlotConfig(prizes: [
                for (var i = 0; i < _slotPrizes; i++)
                  SlotPrize(
                      images: [imageAt(i)], weight: 1, background: _lightFill),
              ], reels: const [
                SlotReel(),
                SlotReel(),
                SlotReel()
              ]),
              controller: controller,
              onReady: onReady,
              performance: LuckyPerformanceOptions(
                  cacheMode: key == 'slot_raster'
                      ? LuckyCacheMode.raster
                      : LuckyCacheMode.picture)),
          controller.play,
          () => controller.stop(0),
          controller.phase,
          controller.dispose,
          ready.future);
    case 'capsule_mixing':
      final controller = CapsuleController(random: math.Random(_seed));
      return BenchScene(
          LuckyCapsuleMachine(
              config: CapsuleConfig(
                  capsulesPerPrize: _gridSide,
                  prizes: List.generate(
                      _slotPrizes,
                      (_) => const CapsulePrize(
                          topFill: _lightFill,
                          bottomFill: _accentFill,
                          weight: 1))),
              controller: controller,
              onReady: onReady),
          controller.play,
          () => controller.stop(0),
          controller.phase,
          controller.dispose,
          ready.future);
    case 'number_wheel_spin':
      final controller = NumberWheelController(random: math.Random(_seed));
      return BenchScene(
          LuckyNumberWheel(
              config: NumberWheelConfig.range(0, 36),
              controller: controller,
              onReady: onReady),
          controller.play,
          () => controller.stop(0),
          controller.phase,
          controller.dispose,
          ready.future);
    case 'lots_shaking':
      final controller = LotsController(random: math.Random(_seed));
      return BenchScene(
          LuckyLots(
              config: LotsConfig(sticks: [
                for (var i = 0; i < _wheelPrizes; i++)
                  LotsStick(label: 'Stick $i', weight: 1),
              ]),
              controller: controller,
              onReady: onReady),
          controller.play,
          () => controller.stop(0),
          controller.phase,
          controller.dispose,
          ready.future);
    case 'lotto_draw':
      final controller = LottoController(random: math.Random(_seed));
      return BenchScene(
          LuckyLotto(
              config: LottoConfig.superLotto(),
              controller: controller,
              onReady: onReady),
          controller.play,
          controller.stop,
          controller.phase,
          controller.dispose,
          ready.future);
    default:
      throw ArgumentError.value(key, 'key', '未知基准场景');
  }
}

/// 五秒旋转参照，使用与玩法相同的页面外壳。
class BenchReference extends StatefulWidget {
  /// 创建不依赖 luckdraw 的参照动画。
  const BenchReference({super.key});

  /// 创建并拥有动画控制器。
  @override
  State<BenchReference> createState() => _BenchReferenceState();
}

/// 参照动画控制器的生命周期。
class _BenchReferenceState extends State<BenchReference>
    with SingleTickerProviderStateMixin {
  /// 整个参照页面共用的旋转控制器。
  late final AnimationController _rotation;

  /// 挂载后持续旋转。
  @override
  void initState() {
    super.initState();
    _rotation =
        AnimationController(vsync: this, duration: const Duration(seconds: 1))
          ..repeat();
  }

  /// 仅平移已有矩形纹理。
  @override
  Widget build(BuildContext context) => Center(
      child: RotationTransition(
          turns: _rotation,
          child: const SizedBox.square(
              dimension: 80, child: ColoredBox(color: _accent))));

  /// 页面离开时停止 ticker。
  @override
  void dispose() {
    _rotation.dispose();
    super.dispose();
  }
}

/// 为测量页提供与空白页一致的 MediaQuery、方向和尺寸约束。
Widget benchShell(Widget child) => WidgetsApp(
    color: _light,
    builder: (context, _) =>
        Center(child: SizedBox.square(dimension: kBenchSize, child: child)));

/// 根据 SCENARIO 启动可手动检查的场景页面；正式采集使用 integration_test。
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final images = await prepareBenchImages();
  const key = String.fromEnvironment('SCENARIO', defaultValue: 'wheel_steady');
  runApp(BenchPreview(scenario: key, images: images));
}

/// 手动预览会自动开始，卸载时释放控制器；内存场景由集成测试执行。
class BenchPreview extends StatefulWidget {
  /// [scenario] 必须是公开的场景报告键。
  const BenchPreview({super.key, required this.scenario, required this.images});

  /// 场景选择器。
  final String scenario;

  /// 在测量外预生成的 PNG provider。
  final List<MemoryImage> images;

  /// 创建独立的预览状态。
  @override
  State<BenchPreview> createState() => _BenchPreviewState();
}

/// 手动预览拥有的真实玩法会话。
class _BenchPreviewState extends State<BenchPreview> {
  /// 当前场景，参照页不需要玩法控制器。
  BenchScene? _scene;

  /// 生成玩法页面并在首帧挂载后开始。
  @override
  void initState() {
    super.initState();
    if (widget.scenario != 'reference_spin') {
      final scene = createBenchScene(widget.scenario, widget.images);
      _scene = scene;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) scene.play();
      });
    }
  }

  /// 使用与集成测试一致的页面外壳。
  @override
  Widget build(BuildContext context) =>
      benchShell(_scene?.widget ?? const BenchReference());

  /// 释放调用方拥有的控制器。
  @override
  void dispose() {
    _scene?.dispose();
    super.dispose();
  }
}
