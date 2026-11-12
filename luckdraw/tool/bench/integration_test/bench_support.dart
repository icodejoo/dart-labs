import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show MaterialApp;
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:luckdraw/luckdraw.dart';

import '../lib/main.dart';
import '../metrics.dart';
import '../pending_metrics.dart';
import '../pending_scene.dart';

/// 帧回调可能批量延迟一秒，窗口外等待不进入指标。
const Duration _timingFlush = Duration(seconds: 2);

/// 等待阶段或图片就绪的最长时长。
const Duration _readyTimeout = Duration(seconds: 15);

/// 时间线 RPC 超时必须显式失败，不能无限等待采集服务。
const Duration _timelineTimeout = Duration(seconds: 45);

/// 阶段轮询周期，不改变控制器的真实时钟。
const Duration _pollInterval = Duration(milliseconds: 20);

/// 代表典型帧耗时的中位数分位点。
const double _medianFraction = 0.5;

/// 代表长尾帧耗时的分位点。
const double _tailFraction = 0.99;

/// 设备端采样报告字段。
const String kBenchSamples = 'bench_samples';

/// 创建只能在安卓 profile 运行的绑定，并启用真实连续帧。
IntegrationTestWidgetsFlutterBinding benchBinding() {
  if (!Platform.isAndroid || !kProfileMode) {
    throw StateError('基准仅允许安卓真机 --profile；禁止桌面或 debug 数据');
  }
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  return binding;
}

/// 等待真实 [duration] 并提交一帧；不用虚拟时间代替真机时长。
Future<void> _wait(WidgetTester tester, Duration duration) async {
  await Future<void>.delayed(duration);
  await tester.pump();
}

/// 持续驱动真实帧直到 [condition] 成立，否则带原因超时失败。
Future<void> _until(WidgetTester tester, bool Function() condition) async {
  final watch = Stopwatch()..start();
  while (!condition()) {
    if (watch.elapsed > _readyTimeout) throw TimeoutException('玩法未就绪或阶段未到达');
    await _wait(tester, _pollInterval);
  }
}

/// 装载真实页面，等图片解析完成并稳定；失败的图片也会让基准失败。
Future<void> _mount(WidgetTester tester, BenchScene scene) async {
  await tester.pumpWidget(benchShell(scene.widget));
  await scene.ready.timeout(_readyTimeout);
  await _wait(tester, kBenchSettleDuration);
  expect(tester.takeException(), isNull);
}

/// 记录 timeline 与同一时间窗口内的 FrameTiming，并把结果放入 reportData。
Future<void> _trace(IntegrationTestWidgetsFlutterBinding binding,
    WidgetTester tester, String key, Future<void> Function() action,
    {bool firstFrame = false}) async {
  await _wait(tester, _timingFlush);
  final frames = <BenchFrame>[];
  var start = 0;
  var end = 0;

  /// 暂存批量回调，测量完成后按真实时间窗口过滤。
  void onTimings(List<FrameTiming> timings) {
    for (final timing in timings) {
      frames.add(BenchFrame(
          timing.buildDuration.inMicroseconds,
          timing.rasterDuration.inMicroseconds,
          timing.timestampInMicroseconds(FramePhase.buildStart)));
    }
  }

  SchedulerBinding.instance.addTimingsCallback(onTimings);
  try {
    debugPrint('TRACE $key begin');
    await binding.traceAction(() async {
      start = developer.Timeline.now;
      await action();
      end = developer.Timeline.now;
    }, reportKey: key).timeout(_timelineTimeout);
    debugPrint('TRACE $key complete');
    await _wait(tester, _timingFlush);
  } finally {
    SchedulerBinding.instance.removeTimingsCallback(onTimings);
  }
  final measured = frames
      .where((f) => f.startMicros >= start && f.startMicros <= end)
      .toList();
  final builds = measured.map((f) => f.buildMicros).toList()..sort();
  final rasters = measured.map((f) => f.rasterMicros).toList()..sort();
  final combined = measured.map((f) => f.buildMicros + f.rasterMicros).toList()
    ..sort();

  /// 最近秩分位数；空帧由 summarizeFrames 明确拒绝。
  double percentile(List<int> values, double fraction) =>
      values[(values.length * fraction).ceil() - 1] /
      Duration.microsecondsPerMillisecond;

  final metrics = <String, Object?>{
    ...summarizeFrames(measured, tester.view.display.refreshRate),
    '50th_percentile_frame_build_time_millis':
        percentile(builds, _medianFraction),
    '99th_percentile_frame_build_time_millis':
        percentile(builds, _tailFraction),
    '50th_percentile_frame_rasterizer_time_millis':
        percentile(rasters, _medianFraction),
    '99th_percentile_frame_rasterizer_time_millis':
        percentile(rasters, _tailFraction),
    '50th_percentile_build_plus_raster_millis':
        percentile(combined, _medianFraction),
    '90th_percentile_build_plus_raster_millis': percentile(combined, 0.9),
    '99th_percentile_build_plus_raster_millis':
        percentile(combined, _tailFraction),
    'fps': measured.length * Duration.microsecondsPerSecond / (end - start),
    'elapsed_micros': end - start,
    if (firstFrame)
      kBenchFirstFrame:
          measured.first.buildMicros / Duration.microsecondsPerMillisecond,
    if (firstFrame) 'first_frame_source': 'FrameTiming.buildDuration',
  };
  binding.reportData ??= <String, dynamic>{};
  final samples = (binding.reportData![kBenchSamples] ??= <String, Object?>{})
      as Map<String, Object?>;
  samples[key] = metrics;
  expect(tester.takeException(), isNull);
}

/// 为 [key] 同轮记录五秒参照，便于比较 GC 次数；测完卸载 ticker。
Future<void> _reference(IntegrationTestWidgetsFlutterBinding binding,
    WidgetTester tester, String key) async {
  await tester.pumpWidget(benchShell(const BenchReference()));
  await _wait(tester, kBenchSettleDuration);
  await _trace(binding, tester, '${key}_reference',
      () => _wait(tester, kBenchSteadyDuration));
  await tester.pumpWidget(benchShell(const SizedBox.shrink()));
}

/// 采集真实玩法匀速五秒；大乐透先搅拌三秒再完整出球。
///
/// 可选 wheel 参数仅调整转盘消融配置，不改变采样窗口及报告字段。
Future<void> runSteadyBench(IntegrationTestWidgetsFlutterBinding binding,
    WidgetTester tester, String key,
    {LuckyCacheMode? wheelCacheMode,
    bool wheelTexts = true,
    bool wheelImages = true}) async {
  await _reference(binding, tester, key);
  final images = await prepareBenchImages();
  final scene = createBenchScene(key, images,
      wheelCacheMode: wheelCacheMode,
      wheelTexts: wheelTexts,
      wheelImages: wheelImages);
  final rssBaseline = ProcessInfo.currentRss;
  try {
    if (const bool.fromEnvironment('LUCKDRAW_STEADY_ENTRY') &&
        key == 'slot_raster') {
      await _trace(binding, tester, '${key}_entry_reference',
          () => _mount(tester, scene));
    } else {
      await _mount(tester, scene);
    }
    expect(scene.play(), isTrue);
    await _until(tester, () => scene.phase.value == LuckyPhase.cruising);
    await _trace(binding, tester, key, () async {
      if (key == 'lotto_draw' || key == 'lotto_physics') {
        await _wait(tester, const Duration(seconds: 3));
        expect(scene.stop(), isTrue);
        await _until(tester, () => scene.phase.value == LuckyPhase.settled);
      } else {
        await _wait(tester, kBenchSteadyDuration);
        expect(scene.phase.value, LuckyPhase.cruising);
      }
    });
    final samples = binding.reportData![kBenchSamples] as Map<String, Object?>;
    final metrics = samples[key]! as Map<String, Object?>;
    final rssAfter = ProcessInfo.currentRss;
    metrics['rss_steady_baseline'] = rssBaseline;
    metrics['rss_steady_after'] = rssAfter;
    metrics['rss_steady_delta_bytes'] =
        (rssAfter - rssBaseline).clamp(0, rssAfter);
  } finally {
    await tester.pumpWidget(benchShell(const SizedBox.shrink()));
    scene.dispose();
  }
  await runMemoryBench(binding, tester, sceneKey: key, trace: false);
}

/// 从路由 push 到首帧完成记录冷页面的布局与 Picture 录制打点。
Future<void> runFirstFrameBench(
    IntegrationTestWidgetsFlutterBinding binding, WidgetTester tester) async {
  final images = await prepareBenchImages();
  final scene = createBenchScene('wheel_first_frame', images);
  final navigator = GlobalKey<NavigatorState>();
  await tester.pumpWidget(WidgetsApp(
      initialRoute: '/',
      color: const Color(0xFFFFFFFF),
      navigatorKey: navigator,
      pageRouteBuilder: <T>(settings, builder) => PageRouteBuilder<T>(
          settings: settings,
          pageBuilder: (c, a, b) => builder(c),
          transitionDuration: Duration.zero),
      home: const SizedBox.shrink()));
  try {
    await _trace(binding, tester, 'wheel_first_frame', () async {
      unawaited(navigator.currentState!.push<void>(PageRouteBuilder<void>(
          pageBuilder: (context, animation, secondaryAnimation) => Center(
              child:
                  SizedBox.square(dimension: kBenchSize, child: scene.widget)),
          transitionDuration: Duration.zero)));
      await tester.pump();
      await WidgetsBinding.instance.endOfFrame;
    }, firstFrame: true);
  } finally {
    await tester.pumpWidget(benchShell(const SizedBox.shrink()));
    scene.dispose();
  }
}

/// 同一冷 push 计时方式测空白与 wheel/grid/slot，三轮中位数只用于增量标定。
///
/// [key] 必须来自 [kPendingFirstFrames]；空白页面仅 Scaffold + 空 SizedBox。
Future<void> runPendingFirstFrameBench(
    IntegrationTestWidgetsFlutterBinding binding,
    WidgetTester tester,
    String key) async {
  if (!kPendingFirstFrames.contains(key)) throw ArgumentError.value(key);
  final images = await prepareBenchImages();
  final sceneKey = key.replaceFirst('_first_frame', '_steady');
  final scene =
      key == 'blank_first_frame' ? null : createBenchScene(sceneKey, images);
  final navigator = GlobalKey<NavigatorState>();
  await tester.pumpWidget(
      MaterialApp(navigatorKey: navigator, home: const SizedBox.shrink()));
  try {
    await _trace(binding, tester, key, () async {
      unawaited(navigator.currentState!.push<void>(PageRouteBuilder<void>(
          pageBuilder: (context, animation, secondaryAnimation) =>
              pendingFirstFramePage(scene?.widget),
          transitionDuration: Duration.zero)));
      await tester.pump();
      await WidgetsBinding.instance.endOfFrame;
    }, firstFrame: true);
  } finally {
    await tester.pumpWidget(benchShell(const SizedBox.shrink()));
    scene?.dispose();
  }
}

/// 借助窗口外建立的 adb reverse 握手，由主机采样器在稳态边界内读取 CPU。
///
/// [key] 必须来自 [kPendingCpuScenes]；乐透只测搅拌，完整开奖另走帧时复测。
Future<void> runPendingCpuBench(IntegrationTestWidgetsFlutterBinding binding,
    WidgetTester tester, String key) async {
  if (!kPendingCpuScenes.contains(key)) throw ArgumentError.value(key);
  final images = await prepareBenchImages();
  final scene = createBenchScene(key, images);
  Socket? socket;
  StreamIterator<String>? responses;
  try {
    await _mount(tester, scene);
    expect(scene.play(), isTrue);
    await _until(tester, () => scene.phase.value == LuckyPhase.cruising);
    socket = await Socket.connect(InternetAddress.loopbackIPv4, kPendingCpuPort,
        timeout: _readyTimeout);
    responses = StreamIterator(socket
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter()));

    /// 每一步必须有主机确认，采样错误不能当作完成。
    Future<void> exchange(String request, String expected) async {
      socket!.writeln(request);
      await socket.flush();
      if (!await responses!.moveNext().timeout(_readyTimeout) ||
          responses!.current != expected) {
        throw StateError('CPU 采样未确认 $request / $expected');
      }
    }

    await exchange('before', 'ready');
    await _trace(binding, tester, key, () async {
      await exchange('start', 'started');
      await _wait(tester, kBenchSteadyDuration);
      expect(scene.phase.value, LuckyPhase.cruising);
      await exchange('end', 'done');
    });
    binding.reportData!['cpu_scene'] = key;
  } finally {
    await responses?.cancel();
    socket?.destroy();
    await tester.pumpWidget(benchShell(const SizedBox.shrink()));
    scene.dispose();
  }
}

/// 真正 push/pop [kRssCycles] 次，每次页面及空白页稳定两秒后采样进程 RSS。
///
/// 所有样本写入报告；控制器在 pop 完成后释放，禁止通过强制 GC 美化数据。
/// [sceneKey] 指定真实玩法，默认转盘专用 memory_cycles；[trace] 为 false 时
/// 仅追加 RSS 原值，不覆盖该玩法此前采集的五秒性能 timeline。
Future<void> runMemoryBench(
    IntegrationTestWidgetsFlutterBinding binding, WidgetTester tester,
    {String sceneKey = 'memory_cycles', bool trace = true}) async {
  final images = await prepareBenchImages();
  final navigator = GlobalKey<NavigatorState>();
  await tester.pumpWidget(WidgetsApp(
      initialRoute: '/',
      color: const Color(0xFFFFFFFF),
      navigatorKey: navigator,
      pageRouteBuilder: <T>(settings, builder) => PageRouteBuilder<T>(
          settings: settings,
          pageBuilder: (c, a, b) => builder(c),
          transitionDuration: Duration.zero),
      home: const SizedBox.shrink()));
  await _wait(tester, kBenchSettleDuration);
  final baseline = ProcessInfo.currentRss;
  final pageRss = <int>[];
  final blankRss = <int>[];

  /// 每个页面和空白页真实稳定两秒，覆盖完整的挂载与卸载过程。
  Future<void> collect() async {
    for (var cycle = 0; cycle < kRssCycles; cycle++) {
      final scene = createBenchScene(sceneKey, images);
      final popped = navigator.currentState!.push<void>(PageRouteBuilder<void>(
          pageBuilder: (context, animation, secondaryAnimation) => Center(
              child:
                  SizedBox.square(dimension: kBenchSize, child: scene.widget)),
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero));
      try {
        await tester.pump();
        await scene.ready.timeout(_readyTimeout);
        expect(scene.play(), isTrue);
        await _wait(tester, kBenchSettleDuration);
        pageRss.add(ProcessInfo.currentRss);
      } finally {
        navigator.currentState!.pop();
        await tester.pump();
        await popped;
        scene.dispose();
      }
      await _wait(tester, kBenchSettleDuration);
      blankRss.add(ProcessInfo.currentRss);
      debugPrint('RSS $sceneKey cycle=${cycle + 1}/$kRssCycles '
          'page=${pageRss.last} blank=${blankRss.last}');
    }
  }

  if (trace) {
    await binding.traceAction(collect, reportKey: sceneKey);
  } else {
    await collect();
  }
  final maximum = pageRss.reduce((a, b) => a > b ? a : b);
  binding.reportData ??= <String, dynamic>{};
  final samples = (binding.reportData![kBenchSamples] ??= <String, Object?>{})
      as Map<String, Object?>;
  samples[sceneKey] = {
    ...?samples[sceneKey] as Map<String, Object?>?,
    kBenchRssDelta: (maximum - baseline).clamp(0, maximum),
    kBenchRssWarmup: (blankRss.first - baseline).clamp(0, blankRss.first),
    kBenchRssGrowth: (blankRss.last - blankRss.first).clamp(0, blankRss.last),
    kBenchRssCycles: kRssCycles,
    'rss_baseline': baseline,
    'rss_pages': pageRss,
    'rss_blank': blankRss,
  };
  expect(pageRss, hasLength(kRssCycles));
  expect(blankRss, hasLength(kRssCycles));
  expect(tester.takeException(), isNull);
}
