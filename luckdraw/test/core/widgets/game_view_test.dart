import 'dart:async';
import 'dart:ui' show PointerDeviceKind, SemanticsAction;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luckdraw/extend.dart';
import 'package:luckdraw/testing.dart';

import '../../support/fixtures.dart' as fixtures;
import '../../support/test_images.dart';

/// 测试帧间隔。
const Duration _step = Duration(milliseconds: 16);

/// 插件测试的布局。
final class _CounterLayout extends LuckyLayout {
  /// 保存盒子大小。
  const _CounterLayout(Size size) : super(size: size);

  /// 零尺寸没有内容。
  @override
  bool get isEmpty => size.isEmpty;
}

/// 插件测试的复用帧。
final class _CounterFrame extends LuckyFrame {
  /// 累计有效时间。
  double value = 0;
}

/// 用于验证 core 命令派发的最小状态机，不模拟任何内建玩法。
class _CounterMotion
    extends LuckyMotion<int, _CounterLayout, _CounterFrame, LuckyResult<int>> {
  /// 当前帧。
  @override
  final _CounterFrame frame = _CounterFrame();

  /// 当前阶段。
  @override
  LuckyPhase get phase => frame.phase;

  /// 跨过的列。
  @override
  int get passedReel => 0;

  /// 跨过的条目。
  @override
  int get passedIndex => frame.value.toInt();

  /// 当前配置。
  int configured = 0;

  /// 配置应用次数。
  int configurations = 0;

  /// 可变上限用于检查泛型控制器随已应用配置更新。
  Duration? frameLimit;

  /// 未指定上限时使用 core 的默认契约。
  @override
  Duration get maxFrameDelta => frameLimit ?? super.maxFrameDelta;

  /// 停止目标。
  int? target;

  /// 一次性结果。
  LuckyResult<int>? result;

  /// 阶段推进计数。
  int ticks = 0;

  /// 控制器回调重入测试入口。
  VoidCallback? duringTick;

  /// 为真时配置变更会让运动回到静止，模拟条目数变化的玩法。
  bool resetOnConfigure = false;

  /// 应用插件配置。
  @override
  void configure(int config, _CounterLayout? layout) {
    configured = config;
    configurations++;
    if (resetOnConfigure && phase.isMoving) frame.phase = LuckyPhase.idle;
  }

  /// 开始抽奖。
  @override
  bool start() {
    if (!phase.canPlay) return false;
    frame.phase = LuckyPhase.accelerating;
    ticks = 0;
    target = null;
    return true;
  }

  /// 开始待机慢转。
  @override
  bool idleSpin() {
    if (!phase.canPlay) return false;
    frame.phase = LuckyPhase.idleSpinning;
    return true;
  }

  /// 作废抽奖，待机慢转不产生结果。
  @override
  bool cancel() {
    if (!phase.isMoving || phase == LuckyPhase.decelerating) return false;
    if (phase != LuckyPhase.idleSpinning) {
      result = const LuckyResult.cancelled();
    }
    frame.phase = LuckyPhase.idle;
    return true;
  }

  /// 回到原点。
  @override
  void reset() {
    frame.value = 0;
    frame.phase = LuckyPhase.idle;
    target = null;
    result = null;
  }

  /// 每个有效 tick 原地修改帧，并返回事件位。
  @override
  int tick(double tMs, double dtMs) {
    duringTick?.call();
    if (!phase.isMoving || dtMs == 0) return LuckyMotionEvents.none;
    frame.value += dtMs;
    ticks++;
    final previous = phase;
    if (phase == LuckyPhase.accelerating) {
      frame.phase = LuckyPhase.cruising;
    } else if (phase == LuckyPhase.cruising && target != null) {
      frame.phase = LuckyPhase.decelerating;
    } else if (phase == LuckyPhase.decelerating) {
      frame.phase = LuckyPhase.settled;
      result = LuckyResult(index: target, prize: configured);
    }
    return LuckyMotionEvents.repaint |
        LuckyMotionEvents.itemPassed |
        (previous == phase
            ? LuckyMotionEvents.none
            : LuckyMotionEvents.phaseChanged) |
        (phase == LuckyPhase.settled
            ? LuckyMotionEvents.settled
            : LuckyMotionEvents.none);
  }

  /// 取走结果。
  @override
  LuckyResult<int>? takeResult() {
    final value = result;
    result = null;
    return value;
  }

  /// 设置目标，负数走作废语义。
  bool stop(int index) {
    if (index < 0) return cancel();
    if (phase != LuckyPhase.accelerating && phase != LuckyPhase.cruising) {
      return false;
    }
    target = index;
    return true;
  }
}

/// 插件作者实现的类型化控制器。
class _CounterController extends LuckyController<int, _CounterLayout,
    _CounterFrame, LuckyResult<int>> {
  /// 可注入假运动模型。
  _CounterController({_CounterMotion? engine})
      : super(motion: engine ?? _CounterMotion());

  /// 类型化测试模型。
  _CounterMotion get engine => motion as _CounterMotion;

  /// 直接同步测试阶段，用于验证宿主配置排队。
  void setPhase(LuckyPhase phase) {
    frame.phase = phase;
    commitCommand(true);
  }

  /// 停在给定目标。
  bool stop(int index) => commitCommand(engine.stop(index));

  /// 异步获取目标并等待最短有效时间。
  Future<LuckyResult<int>> playUntil(FutureOr<int> Function() resolve,
          {Duration minSpin = Duration.zero}) =>
      runPlayUntil(resolve, minSpin, stop);

  /// 类型化作废结果。
  @override
  LuckyResult<int> createCancelledResult() => const LuckyResult.cancelled();
}

/// 在停止校验时抛错，验证立即和延迟路径统一收尾。
final class _ThrowingController extends _CounterController {
  /// 模拟类型化停止的参数错误。
  @override
  bool stop(int index) => throw ArgumentError.value(index, 'index');
}

/// 验证老虎机可覆盖作废通知策略。
final class _SilentController extends _CounterController {
  /// 不向宿主报告取消。
  @override
  bool get shouldReportCancelled => false;
}

/// 测试可观测的低频构建与帧绘制数据。
final class _Probe {
  /// 布局次数。
  int layouts = 0;

  /// 渲染表面构建次数。
  int builds = 0;

  /// 真实绘制次数。
  int paints = 0;

  /// 最新渲染输入。
  LuckySurfaceData<int, _CounterLayout, _CounterFrame>? data;
}

/// 自定义后端，只通过扩展入口获得 SPI。
final class _CounterRenderer extends LuckyRenderer<int, _CounterLayout,
    _CounterFrame, LuckyResult<int>> {
  /// 注入观测器。
  const _CounterRenderer(this.probe);

  /// 观测器。
  final _Probe probe;

  /// 用帧通知驱动真实 CustomPainter。
  @override
  Widget buildSurface(BuildContext context,
      LuckySurfaceData<int, _CounterLayout, _CounterFrame> data) {
    probe.builds++;
    probe.data = data;
    return CustomPaint(
        painter: _CounterPainter(probe, data), willChange: data.isAnimating);
  }
}

/// 插件画笔，没有 widget 构建路径。
final class _CounterPainter extends CustomPainter {
  /// 绑定帧通知。
  _CounterPainter(this.probe, this.data) : super(repaint: data.frameListenable);

  /// 观测器。
  final _Probe probe;

  /// 渲染输入。
  final LuckySurfaceData<int, _CounterLayout, _CounterFrame> data;

  /// 验证绘制钩子包住全部内容。
  @override
  void paint(Canvas canvas, Size size) {
    data.hooks.beforeDraw?.call(canvas, size);
    probe.paints++;
    data.hooks.afterDraw?.call(canvas, size);
  }

  /// 布局和图片代际变化重绘。
  @override
  bool shouldRepaint(_CounterPainter oldDelegate) =>
      oldDelegate.data.layoutGeneration != data.layoutGeneration ||
      oldDelegate.data.images.generation != data.images.generation;
}

/// 包外插件：只使用 extend.dart 中的 luckdraw 符号。
class _CounterGame
    extends LuckyGame<int, _CounterLayout, _CounterFrame, LuckyResult<int>> {
  /// 创建插件并注入观测器。
  const _CounterGame(this.probe, {this.pan = false, this.requests = const []});

  /// 观测器。
  final _Probe probe;

  /// 是否启用拖动。
  final bool pan;

  /// 插件图片请求。
  final List<LuckyImageRequest> requests;

  /// 创建纯数据布局。
  @override
  _CounterLayout computeLayout(int config, LuckyLayoutInput input) {
    probe.layouts++;
    input.measurer.measure('测试', const TextStyle(fontSize: 12));
    return _CounterLayout(input.size);
  }

  /// 测试重叠命中。
  @override
  List<LuckyHit> hitTestAll(int config, _CounterLayout layout,
          _CounterFrame frame, Offset position) =>
      const [LuckyHit.button(0), LuckyHit.item(1)];

  /// 返回注入图片。
  @override
  List<LuckyImageRequest> collectImages(int config, _CounterLayout layout) =>
      requests;

  /// 创建宿主拥有的控制器。
  @override
  _CounterController createController() => _CounterController();

  /// 创建自定义后端。
  @override
  _CounterRenderer createDefaultRenderer() => _CounterRenderer(probe);

  /// 将配置变化视为结构变化。
  @override
  bool isStructuralChange(int oldConfig, int newConfig) =>
      oldConfig != newConfig;

  /// 默认语义标签。
  @override
  String semanticsLabel(int config) => '计数抽奖';

  /// 是否监听拖动。
  @override
  bool get wantsPanGestures => pan;
}

/// 验证 Game 默认的可选扩展点。
final class _DefaultSeamGame extends _CounterGame {
  /// 创建默认扩展点样例。
  const _DefaultSeamGame(super.probe);

  /// 调用基类默认命中。
  List<LuckyHit> defaultHit() => const _BareGame().hitTestAll(
      1, const _CounterLayout(Size(1, 1)), _CounterFrame(), Offset.zero);
}

/// 十位代表结构、个位代表外观的配置夹具。
final class _ShapeGame extends _CounterGame {
  /// 复用最小插件。
  const _ShapeGame(super.probe);

  /// 仅十位变化属于结构更新。
  @override
  bool isStructuralChange(int oldConfig, int newConfig) =>
      oldConfig ~/ 10 != newConfig ~/ 10;
}

/// 可区分身份的资源环境。
final class _ReviewBundle extends CachingAssetBundle {
  /// 本测试不需要真实资源字节。
  @override
  Future<ByteData> load(String key) async => ByteData(0);
}

/// 记录解析时收到的资源环境。
final class _ConfigProvider extends LuckyTestImageProvider {
  /// 注入可控图片流。
  _ConfigProvider(super.completer);

  /// 真实传入 provider 的 bundle。
  final List<AssetBundle?> bundles = [];

  /// 记录完整解析环境。
  @override
  Future<LuckyTestImageProvider> obtainKey(ImageConfiguration configuration) {
    bundles.add(configuration.bundle);
    return super.obtainKey(configuration);
  }
}

/// 最小插件，保留全部可选 SPI 的默认实现。
final class _BareGame
    extends LuckyGame<int, _CounterLayout, _CounterFrame, LuckyResult<int>> {
  /// 常量构造。
  const _BareGame();

  /// 返回简单布局。
  @override
  _CounterLayout computeLayout(int config, LuckyLayoutInput input) =>
      _CounterLayout(input.size);

  /// 没有图片。
  @override
  List<LuckyImageRequest> collectImages(int config, _CounterLayout layout) =>
      const [];

  /// 创建默认控制器。
  @override
  _CounterController createController() => _CounterController();

  /// 创建默认渲染器。
  @override
  _CounterRenderer createDefaultRenderer() => _CounterRenderer(_Probe());

  /// 不存在结构变化。
  @override
  bool isStructuralChange(int oldConfig, int newConfig) => false;

  /// 默认标签。
  @override
  String semanticsLabel(int config) => '默认插件';
}

/// 无头测试宿主，记录实际派发事件。
final class _Geometry
    implements LuckyItemGeometry<_CounterLayout, _CounterFrame> {
  /// 一个测试条目。
  @override
  int itemCount(_CounterLayout layout) => 1;

  /// 条目填满布局。
  @override
  Size itemSize(_CounterLayout layout, int index) => layout.size;

  /// 恒等变换。
  @override
  bool transformFor(
      _CounterLayout layout, _CounterFrame frame, int index, Matrix4 out) {
    out.setIdentity();
    return true;
  }
}

/// 无头测试宿主，记录实际派发事件。
final class _Host implements LuckyControllerHost<LuckyResult<int>> {
  /// 手动时间源。
  @override
  final ManualLuckyClock clock = ManualLuckyClock();

  /// 收到的结果。
  final List<LuckyResult<int>> results = [];

  /// 收到的阶段。
  final List<LuckyPhase> phases = [];

  /// 开始次数。
  int starts = 0;

  /// 跨条目次数。
  int passed = 0;

  /// 阶段回调重入入口。
  VoidCallback? onPhase;

  /// 开始回调重入入口。
  VoidCallback? onStarted;

  /// 跨条目回调重入入口。
  VoidCallback? onPassed;

  /// 结果回调重入入口。
  VoidCallback? onResult;

  /// 记录阶段。
  @override
  void handlePhaseChanged(LuckyPhase phase) {
    phases.add(phase);
    onPhase?.call();
  }

  /// 记录结果。
  @override
  void handleResult(LuckyResult<int> result) {
    results.add(result);
    onResult?.call();
  }

  /// 记录跨条目。
  @override
  void handleItemPassed(int reel, int index) {
    passed++;
    onPassed?.call();
  }

  /// 记录开始。
  @override
  void handleStarted() {
    starts++;
    onStarted?.call();
  }
}

/// 构建固定环境，宿主盒子保持宽松约束。
Widget _root(Widget child) => MediaQuery(
    data: const MediaQueryData(),
    child: Directionality(
        textDirection: TextDirection.ltr, child: Center(child: child)));

/// 验证插件宿主、稳态帧循环与控制器边界行为。
void main() {
  group('LuckyController regressions', () {
    for (final channel in ['phase', 'host', 'frame']) {
      test('settled $channel reset preserves the original result exactly once',
          () async {
        final controller = _CounterController();
        final host = _Host();
        controller.attach(host);
        controller.configure(8, null);
        addTearDown(controller.dispose);
        var resets = 0;

        /// 重置已结算的局次，模拟公开监听者中的合法命令。
        void resetSettled() {
          if (controller.frame.phase == LuckyPhase.settled) {
            resets++;
            controller.reset();
          }
        }

        if (channel == 'phase') controller.phase.addListener(resetSettled);
        if (channel == 'host') host.onPhase = resetSettled;
        if (channel == 'frame') {
          controller.frameListenable.addListener(resetSettled);
        }
        var completions = 0;
        LuckyResult<int>? result;
        final pending = controller.playUntil(() => 2).then((value) {
          completions++;
          result = value;
        });
        await Future<void>.delayed(Duration.zero);
        host.clock.advanceFrames(8);
        await Future<void>.delayed(Duration.zero);
        expect(resets, 1);
        expect(completions, 1);
        expect(result!.index, 2);
        expect(result!.prize, 8);
        expect(host.results, [result]);
        expect(controller.lastResult, same(result));
        expect(host.clock.isTicking, isFalse);
        await pending;
      });
    }
    test(
        'settled callback can start another pending draw without completing it early',
        () async {
      final controller = _CounterController();
      final host = _Host();
      controller.attach(host);
      controller.configure(8, null);
      addTearDown(controller.dispose);
      Future<LuckyResult<int>>? second;
      var completions = 0;
      host.onPhase = () {
        if (controller.phase.value == LuckyPhase.settled && second == null) {
          controller.reset();
          second = controller.playUntil(() => 3)
            ..then((_) {
              completions++;
            });
        }
      };
      final first = controller.playUntil(() => 2);
      await Future<void>.delayed(Duration.zero);
      host.clock.advanceFrames(5);
      expect((await first).index, 2);
      expect(completions, 0);
      await Future<void>.delayed(Duration.zero);
      host.clock.advanceFrames(8);
      expect((await second!).index, 3);
      expect(completions, 1);
      expect(host.results.map((value) => value.index), [2, 3]);
    });
    for (final delay in [0, 32]) {
      test(
          'stop errors with minSpin $delay complete the pending draw and stop the clock',
          () async {
        final controller = _ThrowingController();
        final host = _Host();
        controller.attach(host);
        controller.configure(8, null);
        addTearDown(controller.dispose);
        Object? failure;
        var completed = false;
        unawaited(controller
            .playUntil(() => 999, minSpin: Duration(milliseconds: delay))
            .then<void>((_) {
          completed = true;
        }, onError: (Object error) {
          failure = error;
          completed = true;
        }));
        await Future<void>.delayed(Duration.zero);
        expect(() => host.clock.advanceFrames(6), returnsNormally);
        await Future<void>.delayed(Duration.zero);
        expect(completed, isTrue);
        expect(failure, isArgumentError);
        expect(controller.phase.value, LuckyPhase.idle);
        expect(host.clock.isTicking, isFalse);
      });
    }
    test('stream cancellation dispatches a complete ordered phase sequence',
        () async {
      final controller = _CounterController();
      final host = _Host();
      controller.attach(host);
      addTearDown(controller.dispose);
      final phases = <LuckyPhase>[];
      final subscription = controller.phaseChanges.listen((phase) {
        phases.add(phase);
        if (phase == LuckyPhase.accelerating) controller.cancel();
      });
      addTearDown(subscription.cancel);
      expect(controller.play, returnsNormally);
      expect(phases, [LuckyPhase.accelerating, LuckyPhase.idle]);
      expect(host.phases, phases);
      expect(controller.phase.value, LuckyPhase.idle);
    });
    test('value listener cancellation never broadcasts an obsolete phase',
        () async {
      final controller = _CounterController();
      final host = _Host();
      controller.attach(host);
      addTearDown(controller.dispose);
      final values = <LuckyPhase>[];
      final stream = <LuckyPhase>[];
      final subscription = controller.phaseChanges.listen(stream.add);
      addTearDown(subscription.cancel);
      controller.phase.addListener(() {
        values.add(controller.phase.value);
        if (controller.phase.value == LuckyPhase.accelerating) {
          controller.cancel();
        }
      });
      controller.play();
      expect(values, [LuckyPhase.accelerating, LuckyPhase.idle]);
      expect(host.phases, [LuckyPhase.idle]);
      expect(stream, [LuckyPhase.idle]);
      expect(controller.phase.value, LuckyPhase.idle);
    });
    test('disposing from a synchronous phase stream safely closes the stream',
        () async {
      final controller = _CounterController();
      final host = _Host();
      controller.attach(host);
      final phases = <LuckyPhase>[];
      var done = false;
      final subscription = controller.phaseChanges.listen((phase) {
        phases.add(phase);
        controller.dispose();
      }, onDone: () {
        done = true;
      });
      addTearDown(subscription.cancel);
      expect(controller.play, returnsNormally);
      await Future<void>.delayed(Duration.zero);
      expect(phases, [LuckyPhase.accelerating]);
      expect(done, isTrue);
      expect(controller.isAttached, isFalse);
      expect(host.clock.isTicking, isFalse);
      controller.dispose();
    });
    test('reset preserves lifecycle pause while clearing the user pause', () {
      final controller = _CounterController();
      final host = _Host();
      controller.attach(host);
      addTearDown(controller.dispose);
      controller.play();
      controller.pause();
      controller.pauseForLifecycle();
      controller.reset();
      controller.play();
      host.clock.advanceFrames(3);
      expect(controller.isPaused, isTrue);
      expect(controller.resume(), isFalse);
      expect(host.clock.isTicking, isFalse);
      expect(controller.frame.value, 0);
      controller.resumeForLifecycle();
      host.clock.advanceFrames(3);
      expect(controller.frame.value, greaterThan(0));
    });
  });
  group('LuckyGameView', () {
    testWidgets(
        'successive structural and appearance updates defer the latest config until the old draw settles',
        (tester) async {
      final probe = _Probe();
      final game = _ShapeGame(probe);
      final controller = _CounterController();
      addTearDown(controller.dispose);

      /// 连续更新同一个宿主。
      Widget view(int config) => _root(LuckyGameView(
          game: game,
          config: config,
          controller: controller,
          width: 100,
          height: 100));
      await tester.pumpWidget(view(10));
      controller.play();
      controller.stop(0);
      for (var i = 0; i < 3; i++) {
        await tester.pump(_step);
      }
      expect(controller.phase.value, LuckyPhase.decelerating);
      final generation = probe.data!.layoutGeneration;
      await tester.pumpWidget(view(20));
      await tester.pumpWidget(view(21));
      expect(probe.data!.config, 10);
      expect(probe.data!.layoutGeneration, generation);
      expect(controller.engine.configured, 10);
      await tester.pump(_step);
      expect(controller.lastResult!.prize, 10);
      expect(probe.data!.config, 21);
      expect(controller.engine.configured, 21);
      await tester.pumpWidget(const SizedBox());
    });
    testWidgets('asset bundle changes reparse image requests without relayout',
        (tester) async {
      final probe = _Probe();
      final provider = _ConfigProvider(LuckyTestImageCompleter());
      final game = _CounterGame(probe, requests: [
        LuckyImageRequest(
            slot: const LuckyImageSlot('bundle', 0, 0),
            image: LuckyImage(provider),
            provider: provider)
      ]);
      final controller = _CounterController();
      addTearDown(controller.dispose);
      final first = _ReviewBundle();
      final second = _ReviewBundle();

      /// 只替换 DefaultAssetBundle。
      Widget view(AssetBundle bundle) => DefaultAssetBundle(
          bundle: bundle,
          child: _root(LuckyGameView(
              game: game,
              config: 1,
              controller: controller,
              width: 100,
              height: 100)));
      await tester.pumpWidget(view(first));
      final layouts = probe.layouts;
      final obtains = provider.bundles.length;
      await tester.pumpWidget(view(second));
      expect(provider.bundles.length, greaterThan(obtains));
      expect(provider.bundles.last, same(second));
      expect(probe.layouts, layouts);
      await tester.pumpWidget(const SizedBox());
    });
    testWidgets(
        'replacing a hidden controller transfers lifecycle pause and releases the old controller',
        (tester) async {
      final game = _CounterGame(_Probe());
      final first = _CounterController();
      final second = _CounterController();
      addTearDown(() {
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        tester.binding
            .handleAppLifecycleStateChanged(AppLifecycleState.inactive);
        tester.binding
            .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        first.dispose();
        second.dispose();
      });

      /// 在后台替换外部控制器。
      Widget view(_CounterController controller,
              {bool pauseWhenHidden = true}) =>
          _root(LuckyGameView(
              game: game,
              config: 1,
              controller: controller,
              performance:
                  LuckyPerformanceOptions(pauseWhenHidden: pauseWhenHidden),
              width: 100,
              height: 100));
      await tester.pumpWidget(view(first));
      first.play();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      expect(first.isPaused, isTrue);
      tester.binding.scheduleForcedFrame();
      await tester.pumpWidget(view(second));
      second.play();
      expect(second.isPaused, isTrue);
      expect(first.isPaused, isFalse);
      expect(tester.binding.transientCallbackCount, 0);
      tester.binding.scheduleForcedFrame();
      await tester.pumpWidget(view(second, pauseWhenHidden: false));
      expect(second.isPaused, isFalse);
      tester.binding.scheduleForcedFrame();
      await tester.pumpWidget(view(second));
      expect(second.isPaused, isTrue);
      first.attachHeadless(clock: ManualLuckyClock(), config: 1);
      expect(first.isPaused, isFalse);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      expect(second.isPaused, isFalse);
      await tester.pumpWidget(const SizedBox());
    });
    testWidgets('surface textScale matches measurement and recording scaling',
        (tester) async {
      final probe = _Probe();

      /// 在相同宿主中切换系统缩放策略。
      Widget view(LuckyTextScaling scaling) => _root(MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: LuckyGameView(
              game: _CounterGame(probe),
              config: 1,
              width: 100,
              height: 100,
              textScaling: scaling)));
      await tester.pumpWidget(view(LuckyTextScaling.none));
      expect(probe.data!.textScale.scale(12), 12);
      await tester.pumpWidget(view(LuckyTextScaling.system));
      expect(probe.data!.textScale.scale(12), 24);
      final measurer = TextPainterMeasurer(textScaler: probe.data!.textScale);
      const style = TextStyle(fontSize: 12);
      final painter = TextPainter(
          text: const TextSpan(text: '测试', style: style),
          textDirection: TextDirection.ltr,
          textScaler: probe.data!.textScale)
        ..layout();
      expect(measurer.measure('测试', style), painter.width);
      expect(measurer.baseline(style),
          painter.computeDistanceToActualBaseline(TextBaseline.alphabetic));
      measurer.dispose();
      painter.dispose();
    });
    late _Probe probe;
    late _CounterController controller;
    setUp(() {
      probe = _Probe();
      controller = _CounterController();
    });
    tearDown(() {
      controller.dispose();
    });
    testWidgets('hosts a custom game defined outside the package (plugin seam)',
        (tester) async {
      await tester.pumpWidget(_root(LuckyGameView(
          game: _CounterGame(probe),
          config: 7,
          controller: controller,
          width: 100,
          height: 100)));
      expect(controller.isAttached, isTrue);
      expect(probe.layouts, 1);
      expect(controller.play(), isTrue);
      expect(controller.stop(2), isTrue);
      for (var i = 0; i < 5; i++) {
        await tester.pump(_step);
      }
      expect(controller.phase.value, LuckyPhase.settled);
      expect(controller.lastResult!.index, 2);
      expect(probe.data!.config, 7);
      expect(probe.data!.performance, const LuckyPerformanceOptions());
      expect(probe.data!.devicePixelRatio, 1);
      expect(probe.data!.textDirection, TextDirection.ltr);
    });
    testWidgets('zero size paints nothing and does not throw', (tester) async {
      await tester.pumpWidget(_root(LuckyGameView(
          game: _CounterGame(probe),
          config: 1,
          controller: controller,
          width: 0,
          height: 0)));
      expect(probe.paints, 0);
      expect(probe.builds, 0);
      expect(tester.takeException(), isNull);
    });
    testWidgets('ticker runs only while the controller is moving',
        (tester) async {
      await tester.pumpWidget(_root(LuckyGameView(
          game: _CounterGame(probe),
          config: 1,
          controller: controller,
          width: 100,
          height: 100)));
      expect(tester.binding.transientCallbackCount, 0);
      controller.play();
      expect(tester.binding.transientCallbackCount, 1);
      controller.stop(0);
      for (var i = 0; i < 5; i++) {
        await tester.pump(_step);
      }
      expect(controller.phase.value, LuckyPhase.settled);
      expect(tester.binding.transientCallbackCount, 0);
    });
    testWidgets('pauses when the app is hidden and resumes on resumed',
        (tester) async {
      await tester.pumpWidget(_root(LuckyGameView(
          game: _CounterGame(probe),
          config: 1,
          controller: controller,
          width: 100,
          height: 100)));
      controller.play();
      await tester.pump(_step);
      await tester.pump(_step);
      final value = controller.frame.value;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      expect(controller.isPaused, isTrue);
      expect(tester.binding.transientCallbackCount, 0);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump(_step);
      expect(controller.frame.value, value);
      await tester.pump(_step);
      expect(controller.frame.value, value + 16);
    });
    testWidgets('steady spin triggers no widget rebuilds', (tester) async {
      await tester.pumpWidget(_root(LuckyGameView(
          game: _CounterGame(probe),
          config: 1,
          controller: controller,
          width: 100,
          height: 100)));
      controller.play();
      await tester.pump(_step);
      await tester.pump(_step);
      final builds = probe.builds;
      final paints = probe.paints;
      for (var i = 0; i < 10; i++) {
        await tester.pump(_step);
      }
      expect(probe.builds, builds);
      expect(probe.layouts, 1);
      expect(probe.paints, greaterThan(paints));
    });
    testWidgets('didUpdateWidget always uses the latest callbacks (#287)',
        (tester) async {
      var oldEnds = 0;
      var newEnds = 0;
      var passed = 0;
      var phases = 0;
      final game = _CounterGame(probe);
      await tester.pumpWidget(_root(LuckyGameView(
          game: game,
          config: 1,
          controller: controller,
          width: 100,
          height: 100,
          onEnd: (_) => oldEnds++)));
      controller.play();
      await tester.pumpWidget(_root(LuckyGameView(
          game: game,
          config: 1,
          controller: controller,
          width: 100,
          height: 100,
          onEnd: (_) => newEnds++,
          onItemPassed: (_, __) => passed++,
          onPhaseChanged: (_) => phases++)));
      controller.stop(0);
      for (var i = 0; i < 5; i++) {
        await tester.pump(_step);
      }
      expect(oldEnds, 0);
      expect(newEnds, 1);
      expect(passed, greaterThan(0));
      expect(phases, greaterThan(0));
    });
    testWidgets('swapping controllers detaches the old one', (tester) async {
      final game = _CounterGame(probe);
      final replacement = _CounterController();
      await tester.pumpWidget(_root(LuckyGameView(
          game: game,
          config: 1,
          controller: controller,
          width: 100,
          height: 100)));
      controller.play();
      await tester.pump(_step);
      await tester.pumpWidget(_root(LuckyGameView(
          game: game,
          config: 1,
          controller: replacement,
          width: 100,
          height: 100)));
      expect(controller.isAttached, isFalse);
      expect(replacement.isAttached, isTrue);
      await tester.pumpWidget(const SizedBox());
      replacement.dispose();
    });
    testWidgets(
        'dispose stops the ticker and completes pending playUntil as cancelled',
        (tester) async {
      await tester.pumpWidget(_root(LuckyGameView(
          game: _CounterGame(probe),
          config: 1,
          controller: controller,
          width: 100,
          height: 100)));
      final target = Completer<int>();
      final future = controller.playUntil(() => target.future);
      await tester.pumpWidget(const SizedBox());
      expect((await future).cancelled, isTrue);
      expect(controller.isAttached, isFalse);
      expect(tester.binding.transientCallbackCount, 0);
      target.complete(0);
      await tester.pump();
      expect(controller.lastResult, isNull);
    });
    testWidgets('reassemble invalidates render caches (hot reload)',
        (tester) async {
      await tester.pumpWidget(_root(LuckyGameView(
          game: _CounterGame(probe),
          config: 1,
          controller: controller,
          width: 100,
          height: 100)));
      final generation = probe.data!.layoutGeneration;
      tester
          .element(find.byWidgetPredicate((widget) => widget is LuckyGameView))
          // 直接驱动目标宿主的重载，避免绑定级重载等待测试帧。
          // ignore: invalid_use_of_protected_member
          .reassemble();
      await tester.pump();
      expect(probe.data!.layoutGeneration, greaterThan(generation));
      expect(probe.layouts, 2);
    });
    testWidgets('system font change invalidates text layout', (tester) async {
      await tester.pumpWidget(_root(LuckyGameView(
          game: _CounterGame(probe),
          config: 1,
          controller: controller,
          width: 100,
          height: 100)));
      final generation = probe.data!.layoutGeneration;
      await tester.binding.handleSystemMessage({'type': 'fontsChange'});
      await tester.pump();
      expect(probe.data!.layoutGeneration, greaterThan(generation));
      expect(probe.layouts, 2);
    });
    testWidgets('semantics exposes label, tap action and live result value',
        (tester) async {
      final semantics = tester.ensureSemantics();
      var starts = 0;
      await tester.pumpWidget(_root(LuckyGameView(
          game: _CounterGame(probe),
          config: 1,
          controller: controller,
          width: 100,
          height: 100,
          onStart: () => starts++,
          semanticsValueBuilder: (phase, result) =>
              result == null ? phase.name : '结果 ${result.index}')));
      expect(find.bySemanticsLabel('计数抽奖'), findsOneWidget);
      final node = tester.getSemantics(find.bySemanticsLabel('计数抽奖'));
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      node.owner!.performAction(node.id, SemanticsAction.tap);
      expect(starts, 1);
      controller.play();
      controller.stop(3);
      for (var i = 0; i < 5; i++) {
        await tester.pump(_step);
      }
      expect(tester.getSemantics(find.bySemanticsLabel('计数抽奖')).value, '结果 3');
      semantics.dispose();
    });
    testWidgets('lifecycle hooks fire in upstream order', (tester) async {
      final calls = <String>[];
      await tester.pumpWidget(_root(LuckyGameView(
          game: _CounterGame(probe),
          config: 1,
          controller: controller,
          width: 100,
          height: 100,
          hooks: LuckyHooks(
              beforeInit: () => calls.add('beforeInit'),
              beforeResize: () => calls.add('beforeResize'),
              afterResize: () => calls.add('afterResize'),
              afterInit: () => calls.add('afterInit'),
              beforeDraw: (_, __) => calls.add('beforeDraw'),
              afterDraw: (_, __) => calls.add('afterDraw'),
              afterStart: () => calls.add('afterStart')),
          onReady: () => calls.add('ready'))));
      expect(calls, [
        'beforeInit',
        'beforeResize',
        'afterResize',
        'afterInit',
        'ready',
        'beforeDraw',
        'afterDraw'
      ]);
      controller.play();
      expect(calls.last, 'afterStart');
    });
    testWidgets('onReady and afterInit fire once across relayouts',
        (tester) async {
      var ready = 0, init = 0;
      Widget build(double width) => _root(LuckyGameView(
          game: _CounterGame(probe),
          config: 1,
          controller: controller,
          width: width,
          height: 100,
          hooks: LuckyHooks(afterInit: () => init++),
          onReady: () => ready++));
      await tester.pumpWidget(build(100));
      await tester.pumpWidget(build(120));
      await tester.pumpWidget(build(140));
      expect((ready, init), (1, 1));
    });
    testWidgets(
        'without tap callbacks no gesture recognizer is attached (#153)',
        (tester) async {
      await tester.pumpWidget(_root(LuckyGameView(
          game: _CounterGame(probe),
          config: 1,
          controller: controller,
          width: 100,
          height: 100)));
      expect(find.byType(GestureDetector), findsNothing);
      expect(find.byType(RawGestureDetector), findsNothing);
    });
    testWidgets('resize keeps motion state and only recomputes layout (#146)',
        (tester) async {
      final game = _CounterGame(probe);
      await tester.pumpWidget(_root(LuckyGameView(
          game: game,
          config: 1,
          controller: controller,
          width: 100,
          height: 100)));
      controller.play();
      await tester.pump(_step);
      await tester.pump(_step);
      final frame = controller.frame;
      final value = frame.value;
      await tester.pumpWidget(_root(LuckyGameView(
          game: game,
          config: 1,
          controller: controller,
          width: 200,
          height: 120)));
      expect(controller.frame, same(frame));
      expect(controller.frame.value, value);
      expect(controller.phase.value, LuckyPhase.cruising);
      expect(probe.layouts, 2);
      expect(probe.data!.layout.size, const Size(200, 120));
    });
    testWidgets('tap pan and optional plugin seams use local events',
        (tester) async {
      final hits = <int>[];
      var starts = 0;
      await tester.pumpWidget(_root(LuckyGameView(
          game: _CounterGame(probe, pan: true),
          config: 1,
          controller: controller,
          width: 100,
          height: 100,
          onStart: () => starts++,
          onButtonTap: (index, phase) => hits.add(index),
          onItemTap: hits.add)));
      await tester.tap(find.byType(CustomPaint));
      await tester.pump();
      expect(hits, [0, 1]);
      expect(starts, 1);
      await tester.drag(find.byType(CustomPaint), const Offset(20, 20));
      final detector =
          tester.widget<GestureDetector>(find.byType(GestureDetector));
      detector.onPanUpdate!(DragUpdateDetails(
          globalPosition: const Offset(30, 30),
          localPosition: const Offset(30, 30)));
      final plugin = _DefaultSeamGame(probe);
      expect(plugin.defaultHit(), isEmpty);
      expect(plugin.itemGeometry, isNull);
      expect(const _BareGame().wantsPanGestures, isFalse);
      expect(const LuckyPanEvent(LuckyPanPhase.update, Offset.zero).phase,
          LuckyPanPhase.update);
      expect(
          const LuckyPanEvent(LuckyPanPhase.start, Offset.zero).localPosition,
          Offset.zero);
      final item = LuckyHit.item(hits.last);
      final button = LuckyHit.button(hits.first);
      expect(item.kind, LuckyHitKind.item);
      expect(button.index, 0);
      expect(item.index, 1);
      final layout = _CounterLayout(probe.data!.layout.size);
      final geometry = _Geometry();
      final overlay = LuckyItemOverlay(
          geometry: geometry,
          layout: layout,
          frame: controller.frame,
          frameListenable: controller.frameListenable,
          children: const [Text('预留条目')]);
      expect(overlay.geometry.itemCount(layout), 1);
      expect(overlay.geometry.itemSize(layout, 0), layout.size);
      expect(
          geometry.transformFor(
              layout, controller.frame, 0, Matrix4.identity()),
          isTrue);
      expect(overlay.layout, same(layout));
      expect(overlay.frame, same(controller.frame));
      expect(overlay.frameListenable, same(controller.frameListenable));
      expect(overlay.children, hasLength(1));
      await tester.pumpWidget(_root(overlay));
      expect(find.text('预留条目'), findsOneWidget, reason: 'T4.4 已实现动态条目叠加');
    });
    testWidgets(
        'owned controllers custom renderers environment and image errors are handled',
        (tester) async {
      final images = LuckyTestImageCompleter();
      final provider = LuckyTestImageProvider(images);
      final errors = <LuckyImageError>[];
      final game = _CounterGame(probe, requests: [
        LuckyImageRequest(
            slot: const LuckyImageSlot('test', 0, 0),
            image: LuckyImage(provider),
            provider: provider)
      ]);
      await tester.pumpWidget(_root(LuckyGameView(
          game: game,
          config: 1,
          renderer: _CounterRenderer(probe),
          width: 100,
          height: 100,
          onImageError: errors.add,
          textScaling: LuckyTextScaling.system)));
      images.fail(StateError('image'));
      await tester.pump();
      expect(errors.single.error, isA<StateError>());
      expect(probe.data!.images.isSettled, isTrue);
      await tester.pumpWidget(MediaQuery(
          data: const MediaQueryData(
              devicePixelRatio: 2, textScaler: TextScaler.linear(2)),
          child: Directionality(
              textDirection: TextDirection.rtl,
              child: Center(
                  child: LuckyGameView(
                      game: _CounterGame(probe),
                      config: 2,
                      width: 100,
                      height: 100,
                      alignment: Alignment.center,
                      textScaling: LuckyTextScaling.none,
                      performance: const LuckyPerformanceOptions(
                          pauseWhenHidden: false))))));
      expect(probe.data!.devicePixelRatio, 2);
      expect(probe.data!.textDirection, TextDirection.rtl);
      await tester.pumpWidget(_root(LuckyGameView(
          game: _CounterGame(probe),
          config: 3,
          width: 100,
          height: 100,
          textScaling: LuckyTextScaling.system)));
      expect(probe.data!.config, 3);
      final image =
          await fixtures.createLuckyTestImage(color: const Color(0xff123456));
      final cached = LuckyTestImageCompleter()..succeed(image);
      image.dispose();
      final cachedProvider = LuckyTestImageProvider(cached);
      final cachedGame = _CounterGame(probe, requests: [
        for (var index = 0; index < 2; index++)
          LuckyImageRequest(
              slot: LuckyImageSlot('cached', index, 0),
              image: LuckyImage(cachedProvider),
              provider: cachedProvider)
      ]);
      await tester.pumpWidget(_root(
          LuckyGameView(game: cachedGame, config: 4, width: 100, height: 100)));
      await tester.pump();
      expect(probe.data!.images.isSettled, isTrue);
      expect(
          probe.data!.images[const LuckyImageSlot('cached', 1, 0)], isNotNull);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    });
    for (final movingPhase in ['accelerating', 'cruising', 'decelerating']) {
      testWidgets('F2 structural updates queue during $movingPhase',
          (tester) async {
        final game = _CounterGame(probe);
        await tester.pumpWidget(_root(LuckyGameView(
            game: game,
            config: 1,
            controller: controller,
            width: 100,
            height: 100)));
        controller.play();
        controller.setPhase(LuckyPhase.values.byName(movingPhase));
        final value = controller.frame.value;
        await tester.pumpWidget(_root(LuckyGameView(
            game: game,
            config: 2,
            controller: controller,
            width: 100,
            height: 100)));
        expect(probe.data!.config, 1);
        expect(controller.frame.value, value);
        controller.reset();
        await tester.pump();
        await tester.pump();
        expect(probe.data!.config, 2);
        await tester.pumpWidget(const SizedBox());
      });
    }
    testWidgets('F2 structural updates apply immediately during idleSpinning',
        (tester) async {
      final game = _CounterGame(probe);
      await tester.pumpWidget(_root(LuckyGameView(
          game: game,
          config: 1,
          controller: controller,
          width: 100,
          height: 100)));
      controller.idleSpin();
      expect(controller.phase.value, LuckyPhase.idleSpinning);
      await tester.pumpWidget(_root(LuckyGameView(
          game: game,
          config: 2,
          controller: controller,
          width: 100,
          height: 100)));
      expect(probe.data!.config, 2);
      expect(controller.phase.value, LuckyPhase.idleSpinning);
      await tester.pumpWidget(const SizedBox());
    });
    testWidgets(
        'idleSpinning resumes when a structural update stops the motion',
        (tester) async {
      final game = _CounterGame(probe);
      await tester.pumpWidget(_root(LuckyGameView(
          game: game,
          config: 1,
          controller: controller,
          width: 100,
          height: 100)));
      controller.engine.resetOnConfigure = true;
      controller.idleSpin();
      await tester.pumpWidget(_root(LuckyGameView(
          game: game,
          config: 2,
          controller: controller,
          width: 100,
          height: 100)));
      expect(probe.data!.config, 2);
      expect(controller.phase.value, LuckyPhase.idleSpinning);
      await tester.pumpWidget(const SizedBox());
    });
    testWidgets(
        'structural updates keep old surface until deceleration settles',
        (tester) async {
      final game = _CounterGame(probe);
      await tester.pumpWidget(_root(LuckyGameView(
          game: game,
          config: 1,
          controller: controller,
          width: 100,
          height: 100)));
      controller.play();
      controller.stop(0);
      for (var i = 0; i < 3; i++) {
        await tester.pump(_step);
      }
      expect(controller.phase.value, LuckyPhase.decelerating);
      await tester.pumpWidget(_root(LuckyGameView(
          game: game,
          config: 2,
          controller: controller,
          width: 100,
          height: 100)));
      expect(probe.data!.config, 1);
      await tester.pump(_step);
      await tester.pump();
      expect(probe.data!.config, 2);
      expect(controller.lastResult!.prize, 1);
    });
    testWidgets('unbounded constraints require explicit dimensions',
        (tester) async {
      await tester.pumpWidget(_root(SingleChildScrollView(
          child: LuckyGameView(
              game: _CounterGame(probe), config: 1, controller: controller))));
      expect(tester.takeException(), isA<FlutterError>());
    });
    testWidgets('zero size ignores tap and pan events', (tester) async {
      var taps = 0;
      await tester.pumpWidget(_root(LuckyGameView(
          game: _CounterGame(probe, pan: true),
          config: 1,
          controller: controller,
          width: 0,
          height: 0,
          onStart: () => taps++)));
      final detector =
          tester.widget<GestureDetector>(find.byType(GestureDetector));
      detector.onTapUp!(TapUpDetails(kind: PointerDeviceKind.touch));
      detector.onPanStart!(DragStartDetails());
      expect(taps, 0);
    });
  });
  group('LuckyController', () {
    test('motion maxFrameDelta reaches the headless timeline', () {
      final controller = _CounterController();
      final clock = ManualLuckyClock();
      controller.engine.frameLimit = const Duration(milliseconds: 7);
      controller.attachHeadless(clock: clock, config: 1);
      expect(controller.play(), isTrue);
      clock.advanceFrames(2, step: const Duration(seconds: 1));
      expect(controller.frame.value, 7);
      controller.engine.frameLimit = const Duration(milliseconds: 3);
      clock.advance(const Duration(seconds: 1));
      expect(controller.frame.value, 10);
      controller.dispose();
      clock.dispose();
    });
    test(
        'headless commands phases streams and independent pauses preserve effective time',
        () async {
      final controller = _CounterController();
      final clock = ManualLuckyClock();
      final phases = <LuckyPhase>[];
      final subscription = controller.phaseChanges.listen(phases.add);
      controller.attachHeadless(clock: clock, config: 9);
      expect(controller.engine.configured, 9);
      expect(controller.random.nextDouble(), inInclusiveRange(0, 1));
      expect(controller.picker, isA<WeightedPrizePicker>());
      expect(() => controller.attach(_Host()), throwsStateError);
      expect(controller.pause(), isFalse);
      expect(controller.resume(), isFalse);
      expect(controller.play(), isTrue);
      expect(controller.play(), isFalse);
      clock.advanceFrames(2);
      expect(controller.phase.value, LuckyPhase.cruising);
      final value = controller.frame.value;
      expect(controller.pause(), isTrue);
      expect(controller.pause(), isFalse);
      controller.pauseForLifecycle();
      expect(controller.isPaused, isTrue);
      expect(controller.resume(), isTrue);
      expect(clock.isTicking, isFalse);
      clock.advanceFrames(10);
      controller.resumeForLifecycle();
      clock.advanceFrames(1);
      expect(controller.frame.value, value);
      clock.advanceFrames(1);
      expect(controller.frame.value, value + 16);
      controller.pause();
      controller.pauseForLifecycle();
      controller.resumeForLifecycle();
      expect(clock.isTicking, isFalse);
      controller.resume();
      expect(controller.stop(4), isTrue);
      clock.advanceFrames(4);
      expect(controller.lastResult!.index, 4);
      expect(clock.isTicking, isFalse);
      expect(
          phases,
          containsAllInOrder([
            LuckyPhase.accelerating,
            LuckyPhase.cruising,
            LuckyPhase.decelerating,
            LuckyPhase.settled
          ]));
      controller.idleSpin();
      expect(clock.isTicking, isTrue);
      expect(controller.cancel(), isTrue);
      expect(clock.isTicking, isFalse);
      controller.reset();
      expect(controller.frame.value, 0);
      await subscription.cancel();
      controller.dispose();
      clock.dispose();
    });
    test(
        'queued structural configuration applies after settlement and cancellation policies differ',
        () {
      final controller = _CounterController();
      final host = _Host();
      controller.attach(host);
      controller.configure(1, null);
      controller.play();
      controller.stop(2);
      host.clock.advanceFrames(3);
      expect(controller.phase.value, LuckyPhase.decelerating);
      controller.configure(2, null, structural: true);
      controller.configure(3, null);
      expect(controller.engine.configured, 1);
      host.clock.advanceFrames(1);
      expect(controller.engine.configured, 3);
      expect(host.results.single.prize, 1);
      controller.play();
      controller.cancel();
      expect(host.results.last.cancelled, isTrue);
      controller.play();
      controller.reset();
      expect(host.results.last.cancelled, isTrue);
      expect(host.starts, 3);
      expect(host.passed, greaterThan(0));
      final beforeReset = host.results.length;
      controller.idleSpin();
      controller.reset();
      expect(host.results.length, beforeReset + 1);
      expect(host.results.last.cancelled, isTrue);
      controller.dispose();
      final silent = _SilentController();
      final silentHost = _Host();
      silent.attach(silentHost);
      silent.play();
      silent.cancel();
      expect(silentHost.results, isEmpty);
      expect(silent.lastResult!.cancelled, isTrue);
      silent.dispose();
    });
    test(
        'playUntil waits for target and minimum effective spin then completes once',
        () async {
      final controller = _CounterController();
      final clock = ManualLuckyClock();
      controller.attachHeadless(clock: clock, config: 8);
      final target = Completer<int>();
      final result = controller.playUntil(() => target.future,
          minSpin: const Duration(milliseconds: 64));
      target.complete(6);
      await Future<void>.delayed(Duration.zero);
      clock.advanceFrames(3);
      expect(controller.engine.target, isNull);
      controller.pause();
      clock.advanceFrames(20);
      controller.resume();
      clock.advanceFrames(2);
      expect(controller.engine.target, isNull);
      clock.advanceFrames(2);
      expect(controller.engine.target, 6);
      clock.advanceFrames(3);
      expect((await result).index, 6);
      expect(controller.lastResult!.prize, 8);
      final immediate = controller.playUntil(() => 1);
      await Future<void>.delayed(Duration.zero);
      clock.advanceFrames(5);
      expect((await immediate).index, 1);
      controller.dispose();
    });
    test(
        'playUntil propagates resolver errors rejects overlap and cancels on dispose',
        () async {
      final controller = _CounterController();
      final clock = ManualLuckyClock();
      controller.attachHeadless(clock: clock, config: 1);
      final failure = controller.playUntil(() => throw StateError('resolve'));
      await expectLater(failure, throwsStateError);
      expect(controller.phase.value, LuckyPhase.idle);
      controller.play();
      await expectLater(controller.playUntil(() => 0), throwsStateError);
      controller.cancel();
      final target = Completer<int>();
      final pending = controller.playUntil(() => target.future);
      await expectLater(controller.playUntil(() => 0), throwsStateError);
      controller.dispose();
      expect((await pending).cancelled, isTrue);
      target.completeError(StateError('late'));
      await Future<void>.delayed(Duration.zero);
      await expectLater(controller.playUntil(() => 0), throwsStateError);
      expect(controller.play(), isFalse);
      expect(controller.cancel(), isFalse);
      expect(controller.idleSpin(), isFalse);
      expect(controller.pause(), isFalse);
      expect(controller.resume(), isFalse);
      controller.reset();
      controller.configure(2, null);
      controller.pauseForLifecycle();
      controller.resumeForLifecycle();
      expect(controller.stop(1), isFalse);
      expect(() => controller.attach(_Host()), throwsStateError);
      controller.dispose();
    });
    test(
        'failed stop completes pending call as cancelled and detach drops late targets',
        () async {
      final controller = _CounterController();
      final clock = ManualLuckyClock();
      controller.attachHeadless(clock: clock, config: 1);
      final waiting = Completer<int>();
      final future = controller.playUntil(() => waiting.future);
      controller.stop(0);
      clock.advanceFrames(3);
      expect(controller.phase.value, LuckyPhase.decelerating);
      waiting.complete(3);
      await Future<void>.delayed(Duration.zero);
      expect((await future).cancelled, isTrue);
      controller.reset();
      final late = Completer<int>();
      final pending = controller.playUntil(() => late.future);
      controller.detach();
      expect((await pending).cancelled, isTrue);
      late.complete(2);
      await Future<void>.delayed(Duration.zero);
      expect(controller.engine.target, isNull);
      controller.dispose();
    });
    test('dispose during a frame prevents further host callbacks', () async {
      final controller = _CounterController();
      final host = _Host();
      controller.attach(host);
      controller.play();
      host.clock.advanceFrames(1);
      controller.engine.duringTick = controller.dispose;
      host.clock.advanceFrames(1);
      expect(host.passed, 0);
      expect(host.results, isEmpty);
      expect(host.clock.isTicking, isFalse);
      final notifying = _CounterController();
      final notifyingHost = _Host();
      notifying.attach(notifyingHost);
      notifying.play();
      notifying.frameListenable.addListener(notifying.dispose);
      notifyingHost.clock.advanceFrames(2);
      expect(notifyingHost.passed, 0);
      expect(notifyingHost.clock.isTicking, isFalse);
      final phaseDisposal = _CounterController();
      final phaseHost = _Host();
      phaseDisposal.attach(phaseHost);
      phaseHost.onPhase = phaseDisposal.dispose;
      final subscription =
          phaseDisposal.phaseChanges.listen((_) => fail('销毁后不应发出阶段流'));
      phaseDisposal.play();
      expect(phaseHost.starts, 0);
      await subscription.cancel();
      final notifierDisposal = _CounterController();
      final notifierHost = _Host();
      notifierDisposal.attach(notifierHost);
      notifierDisposal.phase.addListener(notifierDisposal.dispose);
      notifierDisposal.play();
      expect(notifierHost.phases, isEmpty);
      final starting = _CounterController();
      final startingHost = _Host();
      starting.attach(startingHost);
      startingHost.onStarted = starting.dispose;
      var resolved = false;
      final pending = starting.playUntil(() {
        resolved = true;
        return 0;
      });
      expect((await pending).cancelled, isTrue);
      expect(resolved, isFalse);
      final resetting = _CounterController();
      final resettingHost = _Host();
      resetting.attach(resettingHost);
      resetting.play();
      resettingHost.onPhase = resetting.dispose;
      resetting.reset();
      expect(resettingHost.results, isEmpty);
      final passed = _CounterController();
      final passedHost = _Host();
      passed.attach(passedHost);
      passed.play();
      passedHost.onPassed = passed.dispose;
      passedHost.clock.advanceFrames(2);
      expect(passedHost.passed, 1);
      expect(passedHost.phases, [LuckyPhase.accelerating]);
      final finishing = _CounterController();
      final finishingHost = _Host();
      finishing.attach(finishingHost);
      finishing.play();
      finishingHost.onResult = finishing.dispose;
      finishing.cancel();
      expect(finishingHost.results, hasLength(1));
      expect(finishing.isAttached, isFalse);
    });
  });
}
