// Frame build/raster duration collector, built on
// SchedulerBinding.addTimingsCallback. Same technique as the prior bingo
// benchmark's approach (collect FrameTiming, bucket into build vs raster).
//
// 基于 SchedulerBinding.addTimingsCallback 的帧 build/raster 耗时采集器，
// 采集技术沿用此前 bingo 基准的做法（收集 FrameTiming，拆分 build/raster）。

import 'dart:ui' show FramePhase;

import 'package:flutter/scheduler.dart';

import 'stats.dart';

/// Collects [FrameTiming] samples while [active], exposing build/raster
/// duration stats.
///
/// 在 [active] 期间采集 [FrameTiming] 样本，输出 build/raster 耗时统计。
class FrameTimingCollector {
  /// Registers the collector with [SchedulerBinding]. / 向 [SchedulerBinding] 注册采集器。
  FrameTimingCollector() {
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
  }

  bool _active = false;
  bool _everReceived = false;
  final List<Duration> _build = [];
  final List<Duration> _raster = [];
  // Engine-reported raster-finish timestamps for every collected frame, used
  // to compute a REAL (measured, not estimated-from-durations) FPS: each
  // entry marks when a frame was actually handed to the GPU/compositor, so
  // (frameCount-1) / (lastTimestamp-firstTimestamp) is the true observed
  // frame rate, not a simulation.
  //
  // 每帧引擎上报的光栅完成时间戳，用于计算真实（实测而非从耗时估算）FPS：
  // 每一项都是该帧真正交给 GPU/合成器的时刻，(帧数-1)/(末时间戳-首时间戳)
  // 就是实测帧率，而不是模拟值。
  final List<int> _rasterFinishUs = [];

  /// Starts/stops sample collection (samples outside the active window are
  /// dropped so warmup/idle frames don't skew results).
  ///
  /// 开始/停止采集样本（活跃窗口之外的样本会被丢弃，避免预热/空闲帧影响结果）。
  set active(bool value) => _active = value;

  /// Whether the engine's timing-report channel has delivered at least one
  /// callback, ever — regardless of [active]. On a real Android device the
  /// very first phase to run right after a cold install/launch can go
  /// several seconds (sometimes past an entire short measurement window)
  /// before `addTimingsCallback` starts actually firing (Impeller/engine
  /// warm-up on the reporting channel, not a rendering problem — frames are
  /// visibly painting). A caller can poll this before opening its real
  /// measurement window so "zero frames observed" from a cold first phase
  /// isn't misread as an actual zero-frame render.
  ///
  /// 引擎的帧上报通道是否已经交付过至少一次回调——与 [active] 无关。真机冷
  /// 安装/冷启动后，*第一个*运行的阶段可能要过好几秒（有时能盖过整个短观测
  /// 窗口）`addTimingsCallback` 才真正开始触发（是上报通道本身的
  /// Impeller/引擎预热，不是渲染问题——帧其实在正常绘制）。调用方可以在打开
  /// 真正的计时窗口前轮询这个标志，避免把"冷启动第一阶段测到 0 帧"误读成
  /// 真的一帧没画。
  bool get hasReceivedAnyTiming => _everReceived;

  void _onTimings(List<FrameTiming> timings) {
    _everReceived = true;
    if (!_active) return;
    for (final t in timings) {
      _build.add(Duration(microseconds: t.buildDuration.inMicroseconds));
      _raster.add(Duration(microseconds: t.rasterDuration.inMicroseconds));
      _rasterFinishUs.add(t.timestampInMicroseconds(FramePhase.rasterFinish));
    }
  }

  /// Real, measured average FPS over the collected window: actual frames
  /// handed to the GPU divided by the actual elapsed wall time between the
  /// first and last raster-finish timestamp (not assumed/simulated, and not
  /// derived from a fixed observation-duration constant).
  ///
  /// 采集窗口内实测的平均 FPS：实际交给 GPU 的帧数，除以首末光栅完成时间戳
  /// 之间的真实经过时间（不是假设值/模拟值，也不是从固定观测时长常量推算）。
  double get realAverageFps {
    if (_rasterFinishUs.length < 2) return 0;
    final elapsedUs = _rasterFinishUs.last - _rasterFinishUs.first;
    if (elapsedUs <= 0) return 0;
    return (_rasterFinishUs.length - 1) * 1e6 / elapsedUs;
  }

  /// Clears collected samples (call between scroll passes if desired).
  ///
  /// 清空已采集样本（如需可在每段滚动之间调用）。
  void reset() {
    _build.clear();
    _raster.clear();
    _rasterFinishUs.clear();
  }

  /// Build duration stats over collected samples. / 已采集样本的 build 耗时统计。
  DurationStats get buildStats => DurationStats.fromDurations(_build);

  /// Raster duration stats over collected samples. / 已采集样本的 raster 耗时统计。
  DurationStats get rasterStats => DurationStats.fromDurations(_raster);

  /// Total frame count observed. / 观测到的总帧数。
  int get frameCount => _build.length;

  /// Number of frames exceeding [budgetMs] build duration (missed-frame proxy).
  ///
  /// build 耗时超过 [budgetMs] 的帧数（作为掉帧的代理指标）。
  int framesOverBudget(double budgetMs) =>
      _build.where((d) => d.inMicroseconds / 1000.0 > budgetMs).length;

  /// Unregisters the callback. / 反注册回调。
  void dispose() {
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
  }
}

/// Blocks (bounded by [timeout]) until [collector] has received at least one
/// `addTimingsCallback` invocation, actively pumping frames via
/// [SchedulerBinding.scheduleFrame] while [pumpFrames] is true (needed when
/// the screen's content is otherwise static, e.g. a scroll grid before
/// scrolling starts; unnecessary — but harmless — when something is already
/// animating on its own, e.g. a ticking SMIL icon).
///
/// Call this once, right after warmup and before opening a benchmark's real
/// measurement window — see [FrameTimingCollector.hasReceivedAnyTiming] for
/// why this matters on a real device.
///
/// 阻塞（受 [timeout] 上限约束）直到 [collector] 收到至少一次
/// `addTimingsCallback` 回调，[pumpFrames] 为 true 时通过
/// [SchedulerBinding.scheduleFrame] 主动泵帧（当画面本身静止时需要，比如
/// 滚动网格开始滚动之前；如果已经有东西在自行动画（比如正在走的 SMIL
/// 图标），泵帧没必要但无害）。
///
/// 应在预热之后、打开基准真正的计时窗口之前调用一次——为什么这在真机上很
/// 重要见 [FrameTimingCollector.hasReceivedAnyTiming]。
Future<void> warmUpFrameTimingChannel(
  FrameTimingCollector collector, {
  Duration timeout = const Duration(seconds: 5),
  bool pumpFrames = true,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!collector.hasReceivedAnyTiming && DateTime.now().isBefore(deadline)) {
    if (pumpFrames) SchedulerBinding.instance.scheduleFrame();
    await Future<void>.delayed(const Duration(milliseconds: 16));
  }
}
