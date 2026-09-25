import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:mova/mova.dart';

/// Standalone, no-click acceptance test for the four still-unmeasured
/// 0.5.0 ad-orchestration checklist groups (A remainder / C / E / F). Every
/// number reported comes from real event timestamps ([MovaAdConfig.onAdEvent],
/// [MovaApi.progress], [MovaApi.states]) — never a wall-clock guess or a
/// seek-near-EOF trick, per this project's real-device-verification
/// convention.
///
/// Run with: `flutter run -t lib/main_ad_orchestration_verify.dart -d
/// DEVICE_ID`. Runs all four groups back to back and prints a
/// final summary; blocks until done (several minutes: group A alone opens
/// five fresh engines).
///
/// 针对 0.5.0 广告编排增强仍未测的四组 checklist（A 组剩余部分 / C / E / F）
/// 做的独立、无需点击的验收测试。每个数字都来自真实事件时间戳
/// （[MovaAdConfig.onAdEvent]、[MovaApi.progress]、[MovaApi.states]）——绝不是
/// 墙钟估算或临近 EOF 的 seek 技巧，遵循本项目的真机验证约定。
///
/// 运行：`flutter run -t lib/main_ad_orchestration_verify.dart -d <安卓设备id>`。
/// 四组依次自动跑完并打印总结；会阻塞直到全部完成（数分钟级，仅 A 组就要开五个
/// 独立引擎）。
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MovaEngine.ensureInitialized();
  runApp(const MaterialApp(home: _RunnerPage()));
}

/// Content source with a cache-busting query parameter so every fresh engine
/// hits the real network instead of a cached response — otherwise the
/// warm-up/readiness timings this test measures would be artificially fast.
///
/// 带缓存清除参数的正片源，使每个新引擎都走真实网络请求——否则本测试要测的
/// 预热/就绪耗时会被人为拉快。
MovaSource _content() => MovaSource(
      'https://user-images.githubusercontent.com/28951144/229373695-22f88f13-d18f-4288-9bf1-c3e078d83722.mp4'
      '?t=${DateTime.now().microsecondsSinceEpoch}',
      title: '正片',
    );

/// Ad source: the same MDN clip already used (and confirmed reachable on
/// this device's network) by the manual [AdOrchestrationDemoPage] and by the
/// 2026-09-23 B/D-group real-device runs recorded in CLAUDE.md.
///
/// 广告源：与手动 demo（[AdOrchestrationDemoPage]）以及 CLAUDE.md 记录的
/// 2026-09-23 B/D 组真机跑测同一条、已确认这台设备网络可达的 MDN 素材。
const _adUrl = 'https://interactive-examples.mdn.mozilla.net/media/cc0-videos/friday.mp4';

/// Prints to stderr/stdout (forwarded to the host terminal by `flutter run`)
/// and echoes on screen via [onLine].
///
/// 打印到 stderr/stdout（`flutter run` 会转发到宿主终端），并通过 [onLine]
/// 回显到屏幕。
void Function(String)? _onLine;
void _log(String line) {
  final stamped = '[+${DateTime.now().millisecondsSinceEpoch % 1000000}ms] $line';
  // ignore: avoid_print
  print(stamped);
  _onLine?.call(stamped);
}

/// Completes once [engine]'s progress shows playback actually advancing
/// (position past zero and not buffering) — see `main_seamless_test.dart`'s
/// doc comment for why this, not open()'s future, is the real start signal.
///
/// 一旦 [engine] 的进度显示播放真的在推进（位置过零且不在缓冲）就完成——为何
/// 用这个而非 open() 的 future 作为真实起播信号，见 `main_seamless_test.dart`
/// 的注释。
Future<void> _waitForRealPlayback(MovaApi engine) {
  final completer = Completer<void>();
  late final StreamSubscription<MovaProg> sub;
  sub = engine.progress.listen((p) {
    if (p.position > Duration.zero && !engine.state.buffering) {
      unawaited(sub.cancel());
      if (!completer.isCompleted) completer.complete();
    }
  });
  return completer.future;
}

/// Result of one A-group sample: the wait between the mid-roll becoming due
/// and the ad actually starting.
///
/// A 组单次采样的结果：中插到期与广告真正开始播放之间的等待时长。
class _AGroupSample {
  _AGroupSample(this.gap);
  final Duration gap;
}

/// Drives all four groups sequentially and reports a final summary.
///
/// 依次驱动四组测试并汇报最终总结。
class _RunnerPage extends StatefulWidget {
  const _RunnerPage();
  @override
  State<_RunnerPage> createState() => _RunnerPageState();
}

class _RunnerPageState extends State<_RunnerPage> {
  final List<String> _lines = [];
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _onLine = (line) {
      if (!mounted) return;
      setState(() {
        _lines.add(line);
        if (_lines.length > 200) _lines.removeAt(0);
      });
    };
    unawaited(_runAll());
  }

  Future<void> _runAll() async {
    _log('=== 0.5.0 ad-orchestration automated verification: starting ===');
    final aResults = await _runGroupA();
    final cResult = await _runGroupC();
    final eResult = await _runGroupE();
    final fResult = await _runGroupF();

    _log('=== SUMMARY ===');
    _log('A group (mid-roll wait-for-ready gap, n=${aResults.length}):');
    if (aResults.isNotEmpty) {
      final ms = aResults.map((r) => r.gap.inMilliseconds).toList();
      final min = ms.reduce(math.min);
      final max = ms.reduce(math.max);
      final avg = ms.reduce((a, b) => a + b) / ms.length;
      _log('  samples(ms): $ms');
      _log('  min=${min}ms max=${max}ms avg=${avg.toStringAsFixed(0)}ms');
    } else {
      _log('  NO SAMPLES CAPTURED — see failure lines above');
    }
    _log('C group (content smoothness during delay countdown): $cResult');
    _log('E group (duration-bounded ad reclaim timing): $eResult');
    _log('F group (ads/swap disabled baseline regression): $fResult');
    _log('=== DONE ===');
    if (mounted) setState(() => _done = true);
  }

  // ---------------------------------------------------------------------
  // Group A: mid-roll "wait for ready" gap, 5 samples.
  // ---------------------------------------------------------------------

  /// Runs [n] independent samples of the mid-roll wait-for-ready gap: the
  /// real interval between [MovaAdEventType.pending] (the instant
  /// `dueMidRoll` fires and the controller decides to insert the mid-roll)
  /// and [MovaAdEventType.started] (the instant the atomic swap has
  /// committed and the ad is actually on screen).
  ///
  /// Each sample opens a fresh engine so no state leaks between samples and
  /// every content fetch is a fresh network request.
  ///
  /// 对中插"等待就绪"间隔跑 [n] 次独立采样：[MovaAdEventType.pending]（
  /// `dueMidRoll` 命中、控制器决定插入中插的那一刻）到
  /// [MovaAdEventType.started]（原子切换已提交、广告真正上屏的那一刻）之间的
  /// 真实间隔。
  ///
  /// 每次采样都开一个全新引擎，样本之间不留状态，每次正片请求都是全新的网络
  /// 请求。
  Future<List<_AGroupSample>> _runGroupA({int n = 5}) async {
    _log('--- Group A: mid-roll wait-for-ready gap ($n samples) ---');
    final results = <_AGroupSample>[];
    for (var i = 1; i <= n; i++) {
      _log('A sample $i/$n: opening fresh engine');
      try {
        final sample = await _runOneAGroupSample(i);
        results.add(sample);
        _log('A sample $i/$n: gap = ${sample.gap.inMilliseconds}ms');
      } catch (e, st) {
        _log('A sample $i/$n FAILED: $e');
        _log(st.toString());
      }
    }
    return results;
  }

  Future<_AGroupSample> _runOneAGroupSample(int i) async {
    final pendingCompleter = Completer<DateTime>();
    final startedCompleter = Completer<DateTime>();
    final mid = MovaAdBreak(
      kind: MovaAdBreakKind.mid,
      source: const MovaSource(_adUrl),
      offset: const Duration(seconds: 3),
      // delay stays zero: this measures the *silent* readiness wait (the
      // 0.5.0 default mid-roll shape), not a visible countdown — that is
      // group C's job.
      //
      // delay 保持零：本组测的是*静默*就绪等待（0.5.0 中插的默认形态），不是
      // 可见倒计时——那是 C 组的任务。
      skippableAfter: const Duration(seconds: 2),
    );
    final opts = MovaOpts(
      ads: MovaAdConfig(
        enabled: true,
        breaks: [mid],
        onAdEvent: (e) {
          if (e.type == MovaAdEventType.pending && !pendingCompleter.isCompleted) {
            pendingCompleter.complete(DateTime.now());
          } else if (e.type == MovaAdEventType.started && !startedCompleter.isCompleted) {
            startedCompleter.complete(DateTime.now());
          } else if (e.type == MovaAdEventType.failed) {
            _log('  A sample $i: ad event failed: ${e.error}');
          }
        },
      ),
      swap: const MovaSwapConfig(enabled: true, trigger: MovaEagerWarm()),
    );
    final engine = MovaSwapEngine(engineFactory: () => createMovaEngine(options: opts));
    final controller = MovaAdController(engine, swap: engine);
    try {
      await controller.load(_content());
      await _waitForRealPlayback(engine);
      final pendingAt = await pendingCompleter.future.timeout(
        const Duration(seconds: 15),
        onTimeout: () => throw StateError('pending event never fired within 15s'),
      );
      final startedAt = await startedCompleter.future.timeout(
        const Duration(seconds: 15),
        onTimeout: () => throw StateError('started event never fired within 15s'),
      );
      return _AGroupSample(startedAt.difference(pendingAt));
    } finally {
      await controller.dispose();
      await engine.dispose();
    }
  }

  // ---------------------------------------------------------------------
  // Group C: content smoothness during the visible delay countdown.
  // ---------------------------------------------------------------------

  /// Samples [MovaApi.progress] every 250ms from the moment the mid-roll
  /// enters [MovaAdEventType.pending] (delay countdown starts) until it
  /// starts (delay elapsed + ad warmed up and committed), while the ad is
  /// warmed up in a shadow engine behind the still-playing content. Verifies
  /// position is monotonically non-decreasing and no sample-to-sample gap
  /// stalls for longer than the sample interval plus tolerance — the
  /// objective proxy for "no stutter" this task asked for, since true
  /// visual smoothness needs a human eye.
  ///
  /// 从中插进入 [MovaAdEventType.pending]（倒计时开始）到它真正开始播放
  /// （倒计时走完 + 广告预热就绪并提交）之间，每 250ms 采样一次
  /// [MovaApi.progress]（此时广告正在仍在播放的正片背后的影子引擎里预热）。
  /// 验证位置单调不减、且相邻采样间隔不出现超过采样周期加容差的卡顿——这是
  /// 本任务要求的"无卡顿"客观代理，真正的视觉流畅度仍需人眼判断。
  Future<String> _runGroupC() async {
    _log('--- Group C: content smoothness during delay countdown ---');
    const delay = Duration(seconds: 3);
    final mid = MovaAdBreak(
      kind: MovaAdBreakKind.mid,
      source: const MovaSource(_adUrl),
      offset: const Duration(seconds: 3),
      delay: delay,
      skippableAfter: const Duration(seconds: 2),
    );
    // Diagnostic record per sample: (elapsed ms since pending, position,
    // buffering, wall-clock). Kept separate from `samples` (position-only)
    // so the pass/fail logic below is unchanged; this is purely for
    // root-causing a suspected stall.
    //
    // 每次采样的诊断记录：（距 pending 的相对毫秒数、position、buffering、
    // 真实墙钟）。与只存 position 的 samples 分开，下面的判定逻辑不变；这份
    // 纯粹用来排查疑似卡顿的根因。
    final diag = <String>[];
    final samples = <Duration>[];
    final pendingCompleter = Completer<void>();
    final startedCompleter = Completer<void>();
    DateTime? pendingWallClock;
    DateTime? startedWallClock;
    final opts = MovaOpts(
      ads: MovaAdConfig(
        enabled: true,
        breaks: [mid],
        onAdEvent: (e) {
          if (e.type == MovaAdEventType.pending && !pendingCompleter.isCompleted) {
            pendingWallClock = DateTime.now();
            pendingCompleter.complete();
          } else if (e.type == MovaAdEventType.started && !startedCompleter.isCompleted) {
            startedWallClock = DateTime.now();
            startedCompleter.complete();
          }
        },
      ),
      swap: const MovaSwapConfig(enabled: true, trigger: MovaEagerWarm()),
    );
    final engine = MovaSwapEngine(engineFactory: () => createMovaEngine(options: opts));
    final controller = MovaAdController(engine, swap: engine);
    StreamSubscription<MovaProg>? sampleSub;
    try {
      await controller.load(_content());
      await _waitForRealPlayback(engine);
      sampleSub = engine.progress.listen((p) {
        samples.add(p.position);
        if (pendingWallClock != null) {
          final elapsedMs = DateTime.now().difference(pendingWallClock!).inMilliseconds;
          diag.add('  [+${elapsedMs}ms] pos=${p.position} buffering=${engine.state.buffering}');
        }
      });
      await pendingCompleter.future.timeout(const Duration(seconds: 15));
      _log('  pending fired at $pendingWallClock, sampling position every ~250ms until ad starts');
      // Sample explicitly on a timer too, so we get readings even if the
      // progress stream itself throttles below our interest, and so we bound
      // the wait.
      //
      // 额外用定时器显式采样，即便进度流本身的更新频率低于我们关心的间隔也能
      // 拿到读数，同时给等待设个上限。
      final deadline = DateTime.now().add(const Duration(seconds: 10));
      while (!startedCompleter.isCompleted && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 250));
        // Timer-driven diagnostic sample too, independent of whether the
        // progress stream itself emitted anything this tick — this is the
        // key data point for distinguishing "stream stopped forwarding"
        // (buffering=false, position frozen) from "genuinely stalled
        // decode" (buffering=true).
        //
        // 定时器驱动的诊断采样，不依赖 progress 流本轮是否真的发过事件——
        // 这是区分"流没转发"（buffering=false，position 冻结）与"真的解码
        // 卡住了"（buffering=true）的关键数据点。
        final elapsedMs = pendingWallClock == null
            ? -1
            : DateTime.now().difference(pendingWallClock!).inMilliseconds;
        diag.add('  [+${elapsedMs}ms timer] pos=${samples.isNotEmpty ? samples.last : null} '
            'buffering=${engine.state.buffering}');
      }
      await sampleSub.cancel();
      sampleSub = null;

      // Print the full diagnostic sequence to the terminal (not squeezed
      // into the final verdict string) so it can be inspected without
      // bloating the on-screen summary.
      //
      // 把完整诊断序列打到终端（不塞进最终 verdict 字符串），方便排查又不
      // 让屏幕总结变得臃肿。
      _log('  --- diagnostic sequence (${diag.length} entries) ---');
      for (final d in diag) {
        _log(d);
      }
      final pendingToStartedMs = (pendingWallClock != null && startedWallClock != null)
          ? startedWallClock!.difference(pendingWallClock!).inMilliseconds
          : null;
      final theoreticalMs = delay.inMilliseconds; // offset already elapsed by the time pending fires
      _log('  pending->started wall-clock gap = ${pendingToStartedMs}ms '
          '(theoretical delay = ${theoreticalMs}ms)');
      final bufferingSeen = diag.any((d) => d.contains('buffering=true'));
      _log('  buffering=true observed at any point during countdown: $bufferingSeen');

      if (samples.length < 3) {
        return 'INCONCLUSIVE — only ${samples.length} position samples captured';
      }
      var monotonic = true;
      var maxStallMs = 0;
      var lastDistinct = samples.first;
      var sameStreak = 0;
      for (var i = 1; i < samples.length; i++) {
        if (samples[i] < samples[i - 1]) monotonic = false;
        if (samples[i] == lastDistinct) {
          sameStreak++;
        } else {
          if (sameStreak > 0) {
            maxStallMs = math.max(maxStallMs, sameStreak * 250);
          }
          sameStreak = 0;
          lastDistinct = samples[i];
        }
      }
      final verdict = monotonic && maxStallMs < 1500
          ? 'PASS'
          : 'SUSPECT STALL';
      return '$verdict — monotonic=$monotonic maxObservedStallMs=$maxStallMs '
          'samples=${samples.length} (position from ${samples.first} to ${samples.last}) '
          'pendingToStartedMs=$pendingToStartedMs bufferingSeen=$bufferingSeen';
    } catch (e) {
      return 'FAILED: $e';
    } finally {
      await sampleSub?.cancel();
      await controller.dispose();
      await engine.dispose();
    }
  }

  // ---------------------------------------------------------------------
  // Group E: duration-bounded ad is reclaimed on time and does not wedge.
  // ---------------------------------------------------------------------

  /// Verifies [MovaAdBreak.duration] fires close to its configured value
  /// (measured started→completed on real [MovaAdEventType] timestamps, not
  /// the media's own timeline) and that the controller is not wedged
  /// afterwards (content position keeps advancing for a few more seconds).
  ///
  /// 验证 [MovaAdBreak.duration] 在接近配置值处触发（用真实
  /// [MovaAdEventType] 时间戳测 started→completed，不看素材自身时间轴），
  /// 以及事后控制器没有卡死（正片位置在之后几秒内继续推进）。
  Future<String> _runGroupE() async {
    _log('--- Group E: duration-bounded mid-roll reclaim timing ---');
    const configuredDuration = Duration(seconds: 5);
    final mid = MovaAdBreak(
      kind: MovaAdBreakKind.mid,
      // Reuse the content URL as the ad media: it is far longer than
      // configuredDuration, which is exactly the "even though the raw
      // material is much longer" scenario this group must exercise, and it
      // avoids a second dependency on the MDN CDN's own duration.
      //
      // 复用正片 URL 作为广告素材：远长于 configuredDuration，正是本组要
      // 验证的"即便原始素材长得多"场景，同时避免对 MDN CDN 自身时长再引入
      // 一层依赖。
      source: _content(),
      offset: const Duration(seconds: 3),
      duration: configuredDuration,
      skippableAfter: const Duration(seconds: 1),
    );
    DateTime? startedAt;
    DateTime? completedAt;
    final startedCompleter = Completer<void>();
    final completedCompleter = Completer<void>();
    final opts = MovaOpts(
      ads: MovaAdConfig(
        enabled: true,
        breaks: [mid],
        onAdEvent: (e) {
          if (e.type == MovaAdEventType.started && startedAt == null) {
            startedAt = DateTime.now();
            if (!startedCompleter.isCompleted) startedCompleter.complete();
          } else if (e.type == MovaAdEventType.completed && completedAt == null) {
            completedAt = DateTime.now();
            if (!completedCompleter.isCompleted) completedCompleter.complete();
          }
        },
      ),
      swap: const MovaSwapConfig(enabled: true, trigger: MovaEagerWarm()),
    );
    final engine = MovaSwapEngine(engineFactory: () => createMovaEngine(options: opts));
    final controller = MovaAdController(engine, swap: engine);
    var lastPos = Duration.zero;
    final posSub = engine.progress.listen((p) => lastPos = p.position);
    try {
      await controller.load(_content());
      await _waitForRealPlayback(engine);
      await startedCompleter.future.timeout(const Duration(seconds: 15));
      _log('  ad started at $startedAt, waiting for duration timer to reclaim it');
      await completedCompleter.future.timeout(
        configuredDuration + const Duration(seconds: 5),
        onTimeout: () => throw StateError('completed event never fired — looks wedged'),
      );
      final actual = completedAt!.difference(startedAt!);
      final deltaMs = (actual - configuredDuration).inMilliseconds;
      _log('  completed at $completedAt, actual slot length = ${actual.inMilliseconds}ms '
          '(configured ${configuredDuration.inMilliseconds}ms, delta ${deltaMs}ms)');
      // Confirm not wedged: content position must keep advancing afterwards.
      //
      // 确认没有卡死：事后正片位置必须继续推进。
      final posBefore = lastPos;
      await Future<void>.delayed(const Duration(seconds: 3));
      final posAfter = lastPos;
      final advanced = posAfter > posBefore;
      final verdict = deltaMs.abs() <= 800 && advanced ? 'PASS' : 'SUSPECT';
      return '$verdict — reclaimed after ${actual.inMilliseconds}ms '
          '(target ${configuredDuration.inMilliseconds}ms, delta ${deltaMs}ms), '
          'contentAdvancedAfterward=$advanced ($posBefore -> $posAfter)';
    } catch (e) {
      return 'FAILED: $e';
    } finally {
      await posSub.cancel();
      await controller.dispose();
      await engine.dispose();
    }
  }

  // ---------------------------------------------------------------------
  // Group F: ads/swap disabled — behaviour must be unchanged.
  // ---------------------------------------------------------------------

  /// Builds a controller with [MovaAdConfig.enabled] and
  /// [MovaSwapConfig.enabled] both false (breaks still configured, to prove
  /// they are genuinely ignored, not just empty), plays content for 8s, and
  /// asserts zero [MovaAdEvent]s fired, [MovaState.renderEpoch] never left 0
  /// (the swap engine documented as a pure passthrough when disabled), and
  /// content position advanced steadily — the baseline regression this group
  /// asked for.
  ///
  /// 构造一个 [MovaAdConfig.enabled] 与 [MovaSwapConfig.enabled] 均为
  /// false 的控制器（排期仍然配置着，用以证明它确实被忽略、而非本就是空的），
  /// 播放正片 8 秒，断言零 [MovaAdEvent] 触发、[MovaState.renderEpoch] 从未
  /// 离开过 0（文档记载的关闭态下切换引擎为纯直通），以及正片位置稳定推进——
  /// 本组要求的基线回归。
  Future<String> _runGroupF() async {
    _log('--- Group F: ads/swap disabled baseline regression ---');
    final adEvents = <MovaAdEventType>[];
    final mid = MovaAdBreak(
      kind: MovaAdBreakKind.mid,
      source: const MovaSource(_adUrl),
      offset: const Duration(seconds: 2),
    );
    final opts = MovaOpts(
      ads: MovaAdConfig(
        enabled: false,
        breaks: [mid],
        onAdEvent: (e) => adEvents.add(e.type),
      ),
      swap: const MovaSwapConfig(enabled: false),
    );
    final engine = MovaSwapEngine(engineFactory: () => createMovaEngine(options: opts));
    final controller = MovaAdController(engine, swap: engine);
    final epochs = <int>{};
    final sub = engine.states.listen((s) => epochs.add(s.renderEpoch));
    var lastPos = Duration.zero;
    final posSub = engine.progress.listen((p) => lastPos = p.position);
    try {
      await controller.load(_content());
      await _waitForRealPlayback(engine);
      final posBefore = lastPos;
      await Future<void>.delayed(const Duration(seconds: 8));
      final posAfter = lastPos;
      final advanced = posAfter > posBefore;
      final noAdEvents = adEvents.isEmpty;
      final epochStayedZero = epochs.every((e) => e == 0);
      final verdict = advanced && noAdEvents && epochStayedZero ? 'PASS' : 'SUSPECT';
      return '$verdict — adEventsFired=${adEvents.length} renderEpochsSeen=$epochs '
          'positionAdvanced=$advanced ($posBefore -> $posAfter)';
    } catch (e) {
      return 'FAILED: $e';
    } finally {
      await posSub.cancel();
      await sub.cancel();
      await controller.dispose();
      await engine.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                _done ? 'DONE — see log / terminal for summary' : 'running…',
                style: const TextStyle(color: Colors.white, fontSize: 16),
              ),
            ),
            Expanded(
              child: Container(
                color: Colors.black87,
                padding: const EdgeInsets.all(8),
                width: double.infinity,
                child: SingleChildScrollView(
                  reverse: true,
                  child: Text(
                    _lines.join('\n'),
                    style: const TextStyle(
                      color: Colors.greenAccent,
                      fontFamily: 'monospace',
                      fontSize: 11,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
