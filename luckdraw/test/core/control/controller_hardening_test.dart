import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luckdraw/extend.dart';
import 'package:luckdraw/testing.dart';

/// 用于区分事件参数顺序的列。
const int _reel = 2;

/// 用于区分事件参数顺序的奖品下标。
const int _index = 7;

/// 确定性的有效帧间隔。
const Duration _step = Duration(milliseconds: 16);

/// 最短旋转时间，恰为四个有效帧。
const Duration _minSpin = Duration(milliseconds: 64);

/// 无需玩法几何的最小布局。
final class _Layout extends LuckyLayout {
  /// 保存宿主尺寸。
  const _Layout(Size size) : super(size: size);

  /// 空盒子不绘制。
  @override
  bool get isEmpty => size.isEmpty;
}

/// 保存控制器实际传入的有效时间增量。
final class _Frame extends LuckyFrame {
  /// 累计运动毫秒数。
  double elapsed = 0;
}

/// 独立测试运动，不依赖任何内建玩法。
final class _Motion
    extends LuckyMotion<int, _Layout, _Frame, LuckyResult<int>> {
  /// 跨帧复用的快照。
  @override
  final _Frame frame = _Frame();

  /// 当前阶段。
  @override
  LuckyPhase get phase => frame.phase;

  /// 非零列，必须与下标区别。
  @override
  int get passedReel => _reel;

  /// 非零下标，必须与列区别。
  @override
  int get passedIndex => _index;

  /// 已接受的停止目标。
  int? target;

  /// 待控制器取走的结果。
  LuckyResult<int>? result;

  /// 本夹具不需要配置数据。
  @override
  void configure(int config, _Layout? layout) {}

  /// 开局清除运动数据。
  @override
  bool start() {
    if (!phase.canPlay) return false;
    reset();
    frame.phase = LuckyPhase.accelerating;
    return true;
  }

  /// 本批不需要待机慢转。
  @override
  bool idleSpin() => false;

  /// 作废当前运动。
  @override
  bool cancel() {
    if (!phase.isMoving) return false;
    frame.phase = LuckyPhase.idle;
    result = const LuckyResult.cancelled();
    return true;
  }

  /// 复位夹具，暂停原因仍由控制器独立管理。
  @override
  void reset() {
    frame.phase = LuckyPhase.idle;
    frame.elapsed = 0;
    target = null;
    result = null;
  }

  /// 非零增量发出条目事件，停止后的下一帧结算。
  @override
  int tick(double tMs, double dtMs) {
    if (!phase.isMoving || dtMs == 0) return LuckyMotionEvents.none;
    frame.elapsed += dtMs;
    if (target != null) {
      frame.phase = LuckyPhase.settled;
      result = LuckyResult(index: target, prize: _index);
      return LuckyMotionEvents.repaint | LuckyMotionEvents.phaseChanged;
    }
    return LuckyMotionEvents.repaint | LuckyMotionEvents.itemPassed;
  }

  /// 将结果所有权移交给控制器。
  @override
  LuckyResult<int>? takeResult() {
    final taken = result;
    result = null;
    return taken;
  }

  /// 接受目标，下一有效帧完成结算。
  bool stop(int index) {
    if (!phase.isMoving) return false;
    target = index;
    frame.phase = LuckyPhase.decelerating;
    return true;
  }
}

/// 暴露本批所需的类型化停止与异步命令。
final class _Controller
    extends LuckyController<int, _Layout, _Frame, LuckyResult<int>> {
  /// 注入独立运动。
  _Controller() : super(motion: _Motion());

  /// 检查停止命令是否已送达。
  _Motion get engine => motion as _Motion;

  /// 提交停止命令。
  bool stop(int index) => commitCommand(engine.stop(index));

  /// 使用真实控制器的异步目标与时间门限逻辑。
  Future<LuckyResult<int>> playUntil(FutureOr<int> Function() resolve) =>
      runPlayUntil(resolve, _minSpin, stop);

  /// 提供重置和取消所需的结果。
  @override
  LuckyResult<int> createCancelledResult() => const LuckyResult.cancelled();
}

/// 保存完整事件参数的宿主。
final class _Host implements LuckyControllerHost<LuckyResult<int>> {
  /// 可由测试直接推进的时钟。
  @override
  final ManualLuckyClock clock = ManualLuckyClock();

  /// 宿主接收到的列和下标。
  final List<(int, int)> passed = [];

  /// 记录参数顺序。
  @override
  void handleItemPassed(int reel, int index) => passed.add((reel, index));

  /// 本批不记录阶段。
  @override
  void handlePhaseChanged(LuckyPhase phase) {}

  /// 本批通过控制器读取结果。
  @override
  void handleResult(LuckyResult<int> result) {}

  /// 本批不记录开局次数。
  @override
  void handleStarted() {}
}

/// 将相同条目事件经过真实 Widget 宿主转发。
final class _Game extends LuckyGame<int, _Layout, _Frame, LuckyResult<int>> {
  /// 创建无资源的玩法。
  const _Game();

  /// 保留宿主尺寸。
  @override
  _Layout computeLayout(int config, LuckyLayoutInput input) =>
      _Layout(input.size);

  /// 不请求图片。
  @override
  List<LuckyImageRequest> collectImages(int config, _Layout layout) => const [];

  /// 创建同类型控制器。
  @override
  _Controller createController() => _Controller();

  /// 不绘制额外内容。
  @override
  _Renderer createDefaultRenderer() => const _Renderer();

  /// 配置差异不影响结构。
  @override
  bool isStructuralChange(int oldConfig, int newConfig) => false;

  /// 提供无障碍名称。
  @override
  String semanticsLabel(int config) => 'hardening';
}

/// 只提供表面的测试渲染器。
final class _Renderer
    extends LuckyRenderer<int, _Layout, _Frame, LuckyResult<int>> {
  /// 创建无状态表面。
  const _Renderer();

  /// 返回由宿主约束的空盒子。
  @override
  Widget buildSurface(
          BuildContext context, LuckySurfaceData<int, _Layout, _Frame> data) =>
      const SizedBox.expand();
}

/// 验证新局、暂停、边界、事件参数和释放的可观测契约。
void main() {
  late _Controller controller;
  late _Host host;
  setUp(() {
    controller = _Controller();
    host = _Host();
    controller.attach(host);
  });
  tearDown(() async {
    controller.dispose();
    host.clock.dispose();
    await Future<void>.value();
  });

  test('accepted new play clears the previous result before any frame', () {
    expect(controller.play(), isTrue);
    host.clock.tick(Duration.zero);
    expect(controller.stop(_index), isTrue);
    host.clock.advance(_step);
    final previous = controller.lastResult;
    expect(previous, isNotNull);
    expect(previous!.index, _index);
    expect(previous.cancelled, isFalse);
    expect(controller.phase.value, LuckyPhase.settled);
    expect(controller.play(), isTrue);
    expect(controller.lastResult, isNull);
    expect(controller.phase.value, LuckyPhase.accelerating);
    expect(controller.play(), isFalse);
    expect(controller.lastResult, isNull);
  });

  test('user pause alone immediately stops the clock and resume rebases time',
      () {
    expect(controller.play(), isTrue);
    host.clock.tick(Duration.zero);
    host.clock.advance(_step);
    final elapsed = controller.frame.elapsed;
    expect(elapsed, _step.inMilliseconds);
    expect(host.clock.isTicking, isTrue);
    expect(controller.pause(), isTrue);
    expect(host.clock.isTicking, isFalse);
    expect(controller.isPaused, isTrue);
    host.clock.advance(const Duration(seconds: 5));
    expect(controller.frame.elapsed, elapsed);
    expect(controller.resume(), isTrue);
    expect(host.clock.isTicking, isTrue);
    expect(controller.isPaused, isFalse);
    host.clock.advance(_step);
    expect(controller.frame.elapsed, elapsed);
    host.clock.advance(_step);
    expect(controller.frame.elapsed, elapsed + _step.inMilliseconds);
  });

  test('reset preserves lifecycle pause until the host explicitly resumes', () {
    expect(controller.play(), isTrue);
    expect(controller.pause(), isTrue);
    controller.pauseForLifecycle();
    controller.reset();
    expect(controller.phase.value, LuckyPhase.idle);
    expect(controller.isPaused, isTrue);
    expect(controller.resume(), isFalse);
    expect(host.clock.isTicking, isFalse);
    expect(controller.play(), isTrue);
    expect(host.clock.isTicking, isFalse);
    host.clock.advance(_step);
    expect(controller.frame.elapsed, 0);
    controller.resumeForLifecycle();
    expect(controller.isPaused, isFalse);
    expect(host.clock.isTicking, isTrue);
    host.clock.advance(_step);
    expect(controller.frame.elapsed, 0);
    host.clock.advance(_step);
    expect(controller.frame.elapsed, _step.inMilliseconds);
  });

  test('pending stop is applied on the frame exactly at minimum spin time',
      () async {
    final result = controller.playUntil(() => _index);
    await Future<void>.value();
    host.clock.tick(Duration.zero);
    host.clock.advanceFrames(3, step: _step);
    expect(controller.frame.elapsed,
        _minSpin.inMilliseconds - _step.inMilliseconds);
    expect(controller.engine.target, isNull);
    host.clock.advance(_step);
    expect(controller.frame.elapsed, _minSpin.inMilliseconds);
    expect(controller.engine.target, _index);
    expect(controller.phase.value, LuckyPhase.decelerating);
    host.clock.advance(_step);
    expect((await result).index, _index);
  });

  testWidgets('item passed preserves reel and index through host and widget',
      (tester) async {
    expect(controller.play(), isTrue);
    host.clock.tick(Duration.zero);
    host.clock.advance(_step);
    const expected = [(_reel, _index)];
    expect(host.passed, expected);
    controller.reset();
    controller.detach();
    final passed = <(int, int)>[];
    await tester.pumpWidget(Directionality(
        textDirection: TextDirection.ltr,
        child: LuckyGameView(
            game: const _Game(),
            config: _index,
            controller: controller,
            onItemPassed: (reel, index) => passed.add((reel, index)))));
    expect(controller.play(), isTrue);
    await tester.pump();
    await tester.pump(_step);
    expect(passed, expected);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('dispose releases the frame notifier after its scheduled microtask',
      () async {
    final frames = controller.frameListenable;
    var notifications = 0;

    /// 记录释放前可用的通知。
    void listener() => notifications++;
    frames.addListener(listener);
    expect(controller.play(), isTrue);
    expect(notifications, greaterThan(0));
    controller.dispose();
    await Future<void>.value();
    expect(host.clock.isTicking, isFalse);
    expect(() => frames.addListener(listener), throwsAssertionError);
    expect(controller.dispose, returnsNormally);
  });
}
