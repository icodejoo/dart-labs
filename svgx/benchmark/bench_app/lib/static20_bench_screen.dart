// A deliberately minimal, apples-to-apples benchmark: render N icons (20 by
// default) in ONE static window — no scrolling, no lazy building, no viewport
// eviction — and report the three numbers a caller actually compares between
// libraries: wall time to a fully-painted window, process CPU time, and RSS.
// Every number is reported twice: once for the whole window, once divided by
// the icon count.
//
// Why this exists next to `bench_screen.dart`: the scrolling grid benchmark
// spent two days producing a wrong answer because the two libraries were not
// painting the same number of icons per frame (see doc/performance-benchmarks.md,
// deep-dive 14). This screen removes every mechanism that made that possible —
// nothing scrolls, nothing is built lazily, no cell is evicted for leaving a
// viewport — and it does not stop the clock until it has PROVEN every icon is
// painted, for both libraries, by the same rule. The window is then mounted and
// torn down N times purely to accumulate a measurable CPU total; each of those
// rounds renders from cold, and the report proves it did.
//
// 一个刻意最小化、口径对齐的基准：在**一个静态窗口**里渲染 N 个图标（默认 20）
// ——不滚动、不懒构建、不因滚出视口被驱逐——并报告调用方真正会拿来对比的三个
// 数字：窗口画满所需的墙钟时间、进程 CPU 时间、RSS。每个数字都给两个维度：整
// 窗口总值，以及除以图标数的单图标均值。
//
// 为什么它要和 `bench_screen.dart` 并存：滚动网格基准曾经花了两天得出一个错误
// 结论，原因是两个库每帧画出的图标数量根本不相等（见 doc/performance-benchmarks.md
// 深挖十四）。本页把导致那件事的机制全部去掉——不滚动、不懒构建、不因滚出视口
// 被驱逐——并且**用同一条规则证明每个图标都画出来了**之后才停表。窗口之后会被
// 挂载/卸载 N 次，纯粹是为了让 CPU 总量累积到可测；每一轮都是冷渲染，报告里
// 自带证明。

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:svgx/svgx.dart';

import 'bench_screen.dart' show BenchLib;
import 'frame_timing.dart';
import 'report_sink.dart';
import 'stats.dart';
import 'svg_gen.dart';

/// Kernel clock ticks per second, the unit `/proc/<pid>/stat` reports CPU time
/// in. 100 on every Android build (`getconf CLK_TCK`); hard-coding it keeps
/// the measurement dependency-free, and the report prints it so a reader can
/// check the assumption.
///
/// 内核时钟节拍频率，即 `/proc/<pid>/stat` 上报 CPU 时间所用的单位。Android 上
/// 恒为 100（`getconf CLK_TCK`）；硬编码它可以让测量不引入依赖，报告里会把它
/// 打印出来供核对。
const int _clockTicksPerSecond = 100;

/// Milliseconds of CPU time one clock tick represents. / 一个时钟节拍代表的 CPU 毫秒数。
const double _msPerTick = 1000.0 / _clockTicksPerSecond;

/// Process CPU time (user + system, all threads) in milliseconds, read from
/// `/proc/self/stat`. Returns null off Linux/Android.
///
/// This is the whole process, so the raster thread's work is included — which
/// is the point: a library that moves work off the UI thread has not made it
/// free, and a per-thread reading would hide that.
///
/// 进程 CPU 时间（用户态 + 内核态，含所有线程），单位毫秒，读自
/// `/proc/self/stat`。非 Linux/Android 返回 null。
///
/// 统计的是整个进程，因此 raster 线程的开销也算在内——这正是重点：把工作挪到
/// 别的线程并不等于工作消失了，只看单线程会把这部分藏起来。
///
/// Example:
/// ```dart
/// final before = readProcessCpuMs()!;
/// doWork();
/// print('cpu: ${readProcessCpuMs()! - before} ms');
/// ```
double? readProcessCpuMs() {
  if (!Platform.isAndroid && !Platform.isLinux) return null;
  try {
    final raw = File('/proc/self/stat').readAsStringSync();
    // The `comm` field is parenthesised and may contain spaces, so fields are
    // counted from after the LAST ')'.
    // `comm` 字段带括号且可能含空格，因此字段要从**最后一个** ')' 之后开始数。
    final fields = raw.substring(raw.lastIndexOf(')') + 1).trim().split(' ');
    // After `comm`, fields[0] is `state` (field 3), so utime (field 14) is
    // fields[11] and stime (field 15) is fields[12].
    // `comm` 之后 fields[0] 是 `state`（第 3 项），因此 utime（第 14 项）是
    // fields[11]，stime（第 15 项）是 fields[12]。
    final utime = int.parse(fields[11]);
    final stime = int.parse(fields[12]);
    return (utime + stime) * _msPerTick;
  } on Object {
    return null;
  }
}

/// Resident set size in bytes read from `/proc/self/status`' `VmRSS`, as a
/// cross-check on [ProcessInfo.currentRss]. Returns null off Linux/Android.
///
/// 从 `/proc/self/status` 的 `VmRSS` 读到的常驻内存（字节），用于与
/// [ProcessInfo.currentRss] 交叉校验。非 Linux/Android 返回 null。
///
/// Example:
/// ```dart
/// print('rss=${readVmRssBytes()! / 1e6} MB');
/// ```
int? readVmRssBytes() {
  if (!Platform.isAndroid && !Platform.isLinux) return null;
  try {
    for (final line in File('/proc/self/status').readAsLinesSync()) {
      if (line.startsWith('VmRSS:')) {
        final kb = int.parse(
          line.split(RegExp(r'\s+')).firstWhere((t) => int.tryParse(t) != null),
        );
        return kb * 1024;
      }
    }
  } on Object {
    return null;
  }
  return null;
}

/// Which cache path the rounds exercise.
///
/// 本次轮次要跑的是哪条缓存路径。
enum Static20Mode {
  /// Every round renders from scratch: a per-round cache key and a cleared
  /// svgx LRU. This is the deep-dive-16 configuration.
  ///
  /// 每轮都从零渲染：每轮换一套缓存键，并清空 svgx 的 LRU。即深挖十六的配置。
  cold,

  /// Every round renders the SAME sources with no cache clearing, and nothing
  /// keeps the widgets alive between rounds. This is "scroll away and come
  /// back": svgx hits its LRU synchronously; flutter_svg's reference-counted
  /// `_livePictureCache` was dropped at unmount, so it re-hits only the
  /// lower-level `svg.cache` (compiled bytes) and still resolves asynchronously.
  ///
  /// 每轮渲染**同一批**源、不清缓存，且轮次之间没有任何东西持有这些控件。这就是
  /// "滚走再滚回来"：svgx 同步命中 LRU；flutter_svg 按引用计数的
  /// `_livePictureCache` 在卸载时已被丢弃，只能再命中下一层的 `svg.cache`
  /// （编译产物字节），依然是异步返回。
  hot,

  /// Like [hot], plus an offstage copy of every icon that stays mounted for the
  /// whole run. It exists to give flutter_svg its BEST hot path: the live
  /// picture's reference count never reaches zero, so remounting hits the
  /// in-memory `ui.Picture` synchronously, exactly like svgx's LRU.
  ///
  /// 同 [hot]，另外常驻挂载一份 offstage 的图标副本。它的作用是给 flutter_svg
  /// **最好情况**的热路径：live picture 的引用计数不会归零，重新挂载时同步命中
  /// 内存里的 `ui.Picture`，与 svgx 的 LRU 行为一致。
  hotPinned,
}

/// Runs the static N-icon window benchmark for [lib] and prints one report.
///
/// The window is mounted and torn down [rounds] times so the CPU counter (a
/// 10ms-granularity kernel tick) accumulates enough to be meaningful; round 1
/// is additionally reported on its own as the cold, first-ever render.
///
/// 对 [lib] 运行静态 N 图标窗口基准，并打印一份报告。
///
/// 窗口会被挂载/卸载 [rounds] 次，好让 CPU 计数器（内核 10ms 粒度节拍）累积到
/// 有意义的量级；第 1 轮另外单独上报，作为冷启动首次渲染的成本。
///
/// Example:
/// ```dart
/// Static20BenchRunner(lib: BenchLib.svgx, itemCount: 20, rounds: 20);
/// ```
class Static20BenchRunner extends StatefulWidget {
  /// Creates the runner. / 创建运行器。
  ///
  /// [lib] — library under test. / 被测库。
  /// [itemCount] — icons in the static window. / 静态窗口内的图标数。
  /// [rounds] — mount/measure/unmount repetitions. / 挂载-测量-卸载的重复轮次。
  /// [holdSeconds] — idle hold after the last round. / 末轮之后的静置秒数。
  /// [mode] — cold / hot / hotPinned cache path. / 冷、热、常驻热三条缓存路径。
  const Static20BenchRunner({
    super.key,
    required this.lib,
    required this.itemCount,
    required this.rounds,
    required this.holdSeconds,
    this.mode = Static20Mode.cold,
    this.settleSeconds = 2,
    this.sources,
  });

  /// Explicit sources to render instead of [itemCount] generated MDI icons —
  /// used by the mask/gradient/clipPath cold-start deep-dive, which needs a
  /// small hand-written corpus rather than the icon set. When given, this
  /// list's length is the effective icon count everywhere in the report;
  /// [itemCount] is ignored. Null (the default) preserves every existing
  /// caller's behavior unchanged.
  ///
  /// 显式指定要渲染的源，代替按 [itemCount] 生成的 MDI 图标——供
  /// mask/gradient/clipPath 冷启动深挖使用，它需要一小批手写语料而非图标集。
  /// 给定时，报告里各处的"图标数"都是这份列表的长度，[itemCount] 被忽略。为
  /// null（默认）时不改变任何既有调用方的行为。
  final List<String>? sources;

  /// Cache path under test. / 被测的缓存路径。
  final Static20Mode mode;

  /// Seconds to idle before the first round. Deep-dive 15 measured this device
  /// pinning its big cores at 2.4GHz for the first 3~4 seconds after launch,
  /// then dropping to 0.8~1.8GHz, so a "round 1 vs round N" comparison only
  /// holds once this pushes every round past that boost window.
  ///
  /// 第一轮开始前的静置秒数。深挖十五实测本机启动后前 3~4 秒把大核钉在 2.4GHz、
  /// 之后回落到 0.8~1.8GHz，因此只有把所有轮次推出这个加速窗口，"第 1 轮 vs 第 N
  /// 轮"的对比才成立。
  final int settleSeconds;

  /// Library under test. / 被测库。
  final BenchLib lib;

  /// Icons rendered in the static window. / 静态窗口内渲染的图标数。
  final int itemCount;

  /// Mount/measure/unmount repetitions. / 挂载-测量-卸载的重复轮次。
  final int rounds;

  /// Idle hold after the last round, for the steady-state RSS reading.
  /// 末轮之后的静置秒数，用于读取稳态 RSS。
  final int holdSeconds;

  @override
  State<Static20BenchRunner> createState() => _Static20BenchRunnerState();
}

class _Static20BenchRunnerState extends State<Static20BenchRunner> {
  late final List<String> _icons =
      widget.sources ?? generateIcons(widget.itemCount);

  /// The icon sources the current round renders. Each round gets its own
  /// variants — the same drawings with a per-round XML comment before `</svg>`
  /// — because BOTH libraries key their picture caches on the source string.
  /// Without this, a library whose cache happens to survive the unmount silently
  /// measures a cache hit while the other measures a real render, which is
  /// exactly the trap deep-dive 14 fell into. A comment produces no geometry, so
  /// the rendering work is identical; only the cache key changes.
  ///
  /// 当前轮次渲染的图标源。每一轮用各自的变体——同样的图形，只在 `</svg>` 前加一
  /// 条带轮次号的 XML 注释——因为**两个库**都用源字符串作 picture 缓存的键。不这
  /// 么做的话，某个库的缓存若碰巧熬过了卸载，它测到的就是缓存命中而另一个测到的
  /// 是真实渲染，这正是深挖十四踩过的坑。注释不产生任何几何，渲染工作完全相同，
  /// 变的只有缓存键。
  late List<String> _sources = _icons;

  /// Indices whose icon is still showing a placeholder instead of real paint.
  /// Empty means the window is fully painted — the single rule both libraries
  /// are held to. svgx renders synchronously and never adds to it; flutter_svg
  /// adds one entry per cell that is still compiling in a background isolate.
  ///
  /// 仍在显示占位符、尚未真正绘制的图标下标集合。为空即表示窗口已画满——两个库
  /// 共用的这一条判定规则。svgx 同步渲染，从不往里加；flutter_svg 每个还在后台
  /// isolate 里编译的格子会占一项。
  final Set<int> _blank = <int>{};

  /// [_blank]'s counterpart for the offstage anchor used by
  /// [Static20Mode.hotPinned]; kept separate so the anchor's own first load
  /// cannot be mistaken for a measured round still painting.
  ///
  /// [Static20Mode.hotPinned] 用的 offstage 常驻副本对应的 [_blank]；单独一份，
  /// 免得把锚点自己的首次加载误判成被测轮次还没画完。
  final Set<int> _anchorBlank = <int>{};

  bool _anchorMounted = false;

  final List<Duration> _roundDurations = <Duration>[];

  /// Process CPU milliseconds spent inside each round (mount → painted →
  /// unmount → settle). Sampled per round so the cold first round can be
  /// separated from the hot remainder.
  ///
  /// 每一轮（挂载 → 画满 → 卸载 → 静置）消耗的进程 CPU 毫秒。逐轮采样，好把冷的
  /// 第一轮与其后的热轮次分开看。
  final List<double> _roundCpuMs = <double>[];

  /// RSS in bytes at the end of each round. Flat after round 1 means the cache
  /// is holding, not re-allocating.
  ///
  /// 每轮结束时的 RSS(字节)。第 1 轮之后走平,说明缓存确实在起作用而不是反复分配。
  final List<int> _roundRssBytes = <int>[];

  /// svgx parse+record misses attributable to each round. In a hot run this
  /// must be [itemCount] for round 1 and 0 for every later round.
  ///
  /// 归属到每一轮的 svgx 解析+录制未命中次数。热路径运行中，第 1 轮必须等于
  /// [itemCount]，其后每轮必须为 0。
  final List<int> _roundMisses = <int>[];

  /// Placeholders constructed per round, the sampling-proof counterpart of
  /// [_blankPeaks]. 0 means the library resolved synchronously and no cell ever
  /// showed a placeholder.
  ///
  /// 每轮构造的占位符数量，[_blankPeaks] 的"不依赖采样"对应物。为 0 表示该库同步
  /// 返回，没有任何格子出现过占位符。
  final List<int> _roundProbeMounts = <int>[];

  int _probeMounts = 0;

  /// Frame build/raster durations over the whole measured window. Wall time
  /// alone cannot be compared between the two libraries: it is quantised by
  /// vsync and includes idle waiting, so a synchronous library sits on the
  /// ~16.7ms floor no matter how little work it does. Summed frame durations
  /// are actual work, and pair with the CPU counter as a cross-check.
  ///
  /// 整个被测窗口内的逐帧 build/raster 耗时。单看墙钟时间无法在两个库之间对比：
  /// 它被 vsync 量化、且包含空等，同步渲染的库无论做多少事都卡在 ~16.7ms 的地板
  /// 上。逐帧耗时之和才是真实工作量，并可与 CPU 计数器互相印证。
  final FrameTimingCollector _frameTiming = FrameTimingCollector();

  /// Peak number of still-unpainted cells seen in any one frame, per round.
  /// This is the benchmark proving itself: for an asynchronous library it must
  /// reach [itemCount] every round, otherwise that round hit a cache instead of
  /// rendering, and its timing is not comparable to a cold one.
  ///
  /// 每一轮中单帧内"尚未画出"格子数的峰值。这是基准的自证指标：异步渲染的库每
  /// 轮都必须达到 [itemCount]，否则那一轮是命中缓存而非真正渲染，其耗时与冷渲染
  /// 不可比。
  final List<int> _blankPeaks = <int>[];

  /// svgx-side counterpart of [_blankPeaks]: parse+record misses actually paid.
  /// Must be `rounds * itemCount` if every round really started cold.
  ///
  /// [_blankPeaks] 在 svgx 侧的对应物：实际付出的解析+录制未命中次数。若每轮确实
  /// 都从冷状态开始，它必须等于 `rounds * itemCount`。
  final List<Duration> _parseMisses = <Duration>[];

  int _blankPeakThisRound = 0;
  bool _gridMounted = false;
  String _status = 'warming up...';
  bool _done = false;

  double? _cpuBaselineMs;
  double? _cpuAfterRoundsMs;
  double? _cpuAfterHoldMs;
  double? _wallRoundsMs;
  double? _wallHoldMs;
  int? _rssBaselineBytes;
  int? _rssSteadyBytes;
  int _rssPeakBytes = 0;

  @override
  void initState() {
    super.initState();
    if (widget.lib == BenchLib.svgx) {
      RustSvgxPictureCache.instance
        ..maximumSize = _icons.length + 50
        ..onParseMiss = _parseMisses.add;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  /// Completes on the first frame after which every cell is really painted.
  ///
  /// Deliberately does NOT call [SchedulerBinding.scheduleFrame] while waiting.
  /// Pumping frames would charge the asynchronous library (flutter_svg, whose
  /// cells are still compiling in a background isolate) for frames a real idle
  /// app would never draw, and the CPU reading is the whole point here. The
  /// callback chain sustains itself instead: whichever cell finishes next calls
  /// `setState`, which schedules the frame this callback rides on.
  ///
  /// 刻意**不**在等待期间调用 [SchedulerBinding.scheduleFrame]。主动泵帧会让异步
  /// 那一方（flutter_svg，格子还在后台 isolate 里编译）为真实空闲应用根本不会画
  /// 的帧买单，而 CPU 读数正是这里的重点。回调链靠自身维持：下一个完成的格子会
  /// 调 `setState`，本回调就搭在它调度的那一帧上。
  Future<void> _awaitFullyPainted({bool anchor = false}) {
    final completer = Completer<void>();
    void check(Duration _) {
      if (!mounted || completer.isCompleted) return;
      final rss = ProcessInfo.currentRss;
      if (rss > _rssPeakBytes) _rssPeakBytes = rss;
      if (!anchor && _blank.length > _blankPeakThisRound) {
        _blankPeakThisRound = _blank.length;
      }
      final ready = anchor
          ? _anchorMounted && _anchorBlank.isEmpty
          : _gridMounted && _blank.isEmpty;
      if (ready) {
        completer.complete();
        return;
      }
      WidgetsBinding.instance.addPostFrameCallback(check);
    }

    WidgetsBinding.instance.addPostFrameCallback(check);
    // Guard rail: a library that never resolves must fail the round loudly
    // rather than hang the unattended run forever.
    // 兜底：某个库若永远不完成，应让这一轮明确失败，而不是让无人值守的运行永久
    // 挂死。
    return completer.future.timeout(
      const Duration(seconds: 20),
      onTimeout: () => throw StateError('window never fully painted'),
    );
  }

  Future<void> _run() async {
    // Let the engine settle: first-frame/shader/surface setup must not land
    // inside the measured window.
    // 让引擎稳定下来：首帧/着色器/surface 的建立不能落进被测窗口。
    await Future<void>.delayed(Duration(seconds: widget.settleSeconds));

    await warmUpFrameTimingChannel(_frameTiming);

    // The pinned anchor must be fully loaded BEFORE the baseline is taken:
    // its own first render is setup, not part of any measured round.
    // 常驻锚点必须在取基线**之前**加载完毕：它自己的首次渲染属于准备工作，不算
    // 进任何被测轮次。
    if (widget.mode == Static20Mode.hotPinned) {
      setState(() {
        _status = 'pinning anchor';
        _anchorMounted = true;
      });
      await _awaitFullyPainted(anchor: true);
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }

    _cpuBaselineMs = readProcessCpuMs();
    _rssBaselineBytes = ProcessInfo.currentRss;
    _rssPeakBytes = _rssBaselineBytes!;
    _parseMisses.clear();
    _frameTiming.active = true;
    final roundsWatch = Stopwatch()..start();

    for (var round = 0; round < widget.rounds; round++) {
      // Both libraries start each round cold: flutter_svg's live picture cache
      // is reference-counted and drops its entry when the cell unmounts, so
      // svgx's LRU is cleared to match. Symmetry is the whole point of this
      // screen.
      //
      // 每一轮两个库都从冷状态开始：flutter_svg 的 live picture 缓存按引用计数，
      // 格子卸载即丢弃条目，因此这里把 svgx 的 LRU 也清掉以对齐。对称性正是本页
      // 存在的意义。
      //
      // In the hot modes none of that applies: the point is to keep whatever
      // each library cached and measure the second visit.
      // 热路径模式下则相反：重点就是保留两个库各自缓存下来的东西，测第二次访问。
      final cold = widget.mode == Static20Mode.cold;
      if (cold && widget.lib == BenchLib.svgx) {
        RustSvgxPictureCache.instance.clear();
        SvgxDocumentCache.instance.clear();
      }
      _blankPeakThisRound = 0;
      final cpuRoundStart = readProcessCpuMs() ?? 0;
      final missesRoundStart = _parseMisses.length;
      final probesRoundStart = _probeMounts;
      final roundSources = cold
          ? [
              for (final icon in _icons)
                icon.replaceFirst('</svg>', '<!--r$round--></svg>'),
            ]
          : _icons;
      setState(() {
        _status = 'round ${round + 1}/${widget.rounds}';
        _sources = roundSources;
        _gridMounted = true;
      });
      final watch = Stopwatch()..start();
      await _awaitFullyPainted();
      watch.stop();
      _roundDurations.add(watch.elapsed);
      _blankPeaks.add(_blankPeakThisRound);

      setState(() => _gridMounted = false);
      // Two frames + a beat so the unmount, the placeholder disposals and
      // flutter_svg's cache release all actually happen before the next round.
      // 两帧加一点余量，确保卸载、占位符销毁、flutter_svg 的缓存释放都在下一轮
      // 开始前真正发生。
      await Future<void>.delayed(const Duration(milliseconds: 250));
      _roundCpuMs.add((readProcessCpuMs() ?? 0) - cpuRoundStart);
      _roundRssBytes.add(ProcessInfo.currentRss);
      _roundMisses.add(_parseMisses.length - missesRoundStart);
      _roundProbeMounts.add(_probeMounts - probesRoundStart);
    }
    roundsWatch.stop();
    _wallRoundsMs = roundsWatch.elapsedMicroseconds / 1000.0;
    _cpuAfterRoundsMs = readProcessCpuMs();
    _frameTiming.active = false;

    // Final static window: mount once more and hold it, which is the scenario
    // the benchmark is named after — a window that just sits there.
    // 最终的静态窗口：再挂一次并保持，这正是本基准得名的场景——一个就这么摆着
    // 的窗口。
    setState(() {
      _status = 'holding static window';
      _gridMounted = true;
    });
    await _awaitFullyPainted();
    final holdWatch = Stopwatch()..start();
    final cpuBeforeHold = readProcessCpuMs();
    await Future<void>.delayed(Duration(seconds: widget.holdSeconds));
    holdWatch.stop();
    _wallHoldMs = holdWatch.elapsedMicroseconds / 1000.0;
    _cpuAfterHoldMs = readProcessCpuMs();
    if (cpuBeforeHold != null) _cpuAfterRoundsMs ??= cpuBeforeHold;
    _rssSteadyBytes = ProcessInfo.currentRss;

    setState(() {
      _done = true;
      _status = 'done';
    });
    _printReport(cpuBeforeHold);
  }

  /// Mean of [values], or 0 when empty. / [values] 的均值，空则为 0。
  double _avg(Iterable<double> values) =>
      values.isEmpty ? 0.0 : values.reduce((a, b) => a + b) / values.length;

  void _printReport(double? cpuBeforeHold) {
    final n = _icons.length;
    final stats = DurationStats.fromDurations(_roundDurations);
    final cold = _roundDurations.isEmpty
        ? 0.0
        : _roundDurations.first.inMicroseconds / 1000.0;
    final warmRounds = _roundDurations.length > 1
        ? _roundDurations.sublist(1)
        : const <Duration>[];
    final warm = DurationStats.fromDurations(warmRounds);

    final cpuRounds = (_cpuAfterRoundsMs ?? 0) - (_cpuBaselineMs ?? 0);
    final cpuPerRound = widget.rounds > 0 ? cpuRounds / widget.rounds : 0.0;
    final cpuHold = (_cpuAfterHoldMs ?? 0) - (cpuBeforeHold ?? 0);
    final rssDelta = (_rssSteadyBytes ?? 0) - (_rssBaselineBytes ?? 0);

    String mb(int bytes) => (bytes / 1e6).toStringAsFixed(2);

    final buildStats = _frameTiming.buildStats;
    final rasterStats = _frameTiming.rasterStats;
    final buildTotalMs = buildStats.avgUs * buildStats.count / 1000.0;
    final rasterTotalMs = rasterStats.avgUs * rasterStats.count / 1000.0;

    final buf = StringBuffer()
      ..writeln(
        '=== STATIC WINDOW REPORT lib=${widget.lib} icons=$n '
        'rounds=${widget.rounds} hold=${widget.holdSeconds}s '
        'settle=${widget.settleSeconds}s mode=${widget.mode.name} ===',
      )
      ..writeln('clk_tck=$_clockTicksPerSecond (cpu resolution ${_msPerTick}ms)')
      // --- total time / 总耗时 ---
      ..writeln('-- render wall time (mount -> every icon painted) --')
      ..writeln('cold_round_total_ms=${cold.toStringAsFixed(2)}')
      ..writeln('cold_round_per_icon_ms=${(cold / n).toStringAsFixed(3)}')
      ..writeln(
        'warm_rounds_avg_total_ms=${(warm.avgUs / 1000).toStringAsFixed(2)}',
      )
      ..writeln(
        'warm_rounds_avg_per_icon_ms='
        '${(warm.avgUs / 1000 / n).toStringAsFixed(3)}',
      )
      ..writeln('all_rounds: $stats')
      // --- round 1 (cold) vs rounds 2..N (hot), the point of MODE=hot ---
      // --- 第 1 轮(冷) vs 第 2..N 轮(热),MODE=hot 的核心口径 ---
      ..writeln('-- per-round breakdown (round 1 vs rounds 2..N) --')
      ..writeln('round1_cpu_ms=${(_roundCpuMs.isEmpty ? 0.0 : _roundCpuMs.first).toStringAsFixed(1)}')
      ..writeln('rounds2n_cpu_avg_ms=${_avg(_roundCpuMs.skip(1)).toStringAsFixed(2)}')
      ..writeln(
        'rounds2n_cpu_avg_per_icon_ms='
        '${(_avg(_roundCpuMs.skip(1)) / n).toStringAsFixed(3)}',
      )
      ..writeln('round_ms_series=${_roundDurations.map((d) => (d.inMicroseconds / 1000).toStringAsFixed(1)).join(',')}')
      ..writeln('round_cpu_ms_series=${_roundCpuMs.map((c) => c.toStringAsFixed(0)).join(',')}')
      ..writeln('round_rss_mb_series=${_roundRssBytes.map(mb).join(',')}')
      ..writeln('round_misses_series=${_roundMisses.join(',')}')
      ..writeln('round_blank_peak_series=${_blankPeaks.join(',')}')
      ..writeln('round_probe_mounts_series=${_roundProbeMounts.join(',')}')
      // --- work actually done, immune to vsync quantisation ---
      // --- 真实工作量，不受 vsync 量化影响 ---
      ..writeln('-- summed frame work over all rounds --')
      ..writeln('frames=${_frameTiming.frameCount}')
      ..writeln('build_total_ms=${buildTotalMs.toStringAsFixed(1)}')
      ..writeln('raster_total_ms=${rasterTotalMs.toStringAsFixed(1)}')
      ..writeln(
        'frame_work_per_round_ms='
        '${((buildTotalMs + rasterTotalMs) / widget.rounds).toStringAsFixed(2)}',
      )
      ..writeln(
        'frame_work_per_icon_ms='
        '${((buildTotalMs + rasterTotalMs) / widget.rounds / n).toStringAsFixed(3)}',
      )
      // --- did every round really render cold? / 每轮真的是冷渲染吗？---
      ..writeln('-- cold-render proof --')
      ..writeln(
        'blank_peak_per_round: min=${_blankPeaks.isEmpty ? 0 : _blankPeaks.reduce((a, b) => a < b ? a : b)} '
        'max=${_blankPeaks.isEmpty ? 0 : _blankPeaks.reduce((a, b) => a > b ? a : b)} '
        'rounds_with_full_blank=${_blankPeaks.where((p) => p == n).length}/${widget.rounds} '
        '(expected all rounds for an async library, 0 for a sync one)',
      )
      ..writeln(
        'svgx_parse_misses=${_parseMisses.length} '
        '(expected ${widget.rounds * n} in mode=cold, $n in a hot mode)',
      )
      ..writeln('svgx_parse: ${DurationStats.fromDurations(_parseMisses)}')
      // --- cpu / CPU 占用 ---
      ..writeln('-- process cpu time (user+sys, all threads) --')
      ..writeln('cpu_rounds_total_ms=${cpuRounds.toStringAsFixed(1)}')
      ..writeln('cpu_per_round_ms=${cpuPerRound.toStringAsFixed(2)}')
      ..writeln(
        'cpu_per_icon_ms=${(cpuPerRound / n).toStringAsFixed(3)}',
      )
      ..writeln(
        'cpu_pct_during_rounds='
        '${(_wallRoundsMs == null || _wallRoundsMs == 0 ? 0 : cpuRounds / _wallRoundsMs! * 100).toStringAsFixed(1)}%',
      )
      ..writeln('cpu_idle_hold_ms=${cpuHold.toStringAsFixed(1)}')
      ..writeln(
        'cpu_pct_during_hold='
        '${(_wallHoldMs == null || _wallHoldMs == 0 ? 0 : cpuHold / _wallHoldMs! * 100).toStringAsFixed(2)}%',
      )
      // --- rss / 内存 ---
      ..writeln('-- rss --')
      ..writeln('rss_baseline_mb=${mb(_rssBaselineBytes ?? 0)}')
      ..writeln('rss_static_window_mb=${mb(_rssSteadyBytes ?? 0)}')
      // Sampled only while a round was waiting to finish painting, so it is the
      // peak DURING the rounds, not over the whole run.
      // 只在某一轮等待画满期间采样，因此它是**轮次进行中**的峰值，不是整次运行的。
      ..writeln('rss_peak_during_rounds_mb=${mb(_rssPeakBytes)}')
      ..writeln('rss_delta_total_mb=${mb(rssDelta)}')
      ..writeln('rss_delta_per_icon_kb=${(rssDelta / n / 1024).toStringAsFixed(1)}')
      ..writeln('vm_rss_mb=${mb(readVmRssBytes() ?? 0)}')
      ..writeln('build: $buildStats')
      ..writeln('raster: $rasterStats')
      ..writeln('=== END STATIC WINDOW REPORT ===');
    // One line per call: Android's log pipeline truncates a single multi-KB
    // write, which silently cut this report off mid-word the first time.
    // 一行一次调用：Android 日志管道会截断单次数 KB 的写入——第一次就是这样把
    // 报告从半个词处静默切掉的。
    for (final line in buf.toString().trimRight().split('\n')) {
      emitReport(line);
    }
    if (autoExitAfterReport) exit(0);
  }

  @override
  void dispose() {
    _frameTiming.dispose();
    if (widget.lib == BenchLib.svgx) {
      RustSvgxPictureCache.instance.onParseMiss = null;
    }
    super.dispose();
  }

  /// One row-wrapped block of [sources], with unpainted cells registering into
  /// [blank]. Shared by the measured window and the pinned anchor so both hold
  /// the caches through the exact same widgets.
  ///
  /// 把 [sources] 排成一块自动换行的图标区，未画出的格子登记进 [blank]。被测窗口
  /// 与常驻锚点共用它，确保两者通过完全相同的控件持有缓存。
  Widget _iconWrap(List<String> sources, Set<int> blank) => Wrap(
        children: [
          for (var i = 0; i < sources.length; i++)
            Padding(
              padding: const EdgeInsets.all(4),
              child: widget.lib == BenchLib.svgx
                  ? SvgxStatic(sources[i], width: 32, height: 32)
                  : SvgPicture.string(
                      sources[i],
                      width: 32,
                      height: 32,
                      placeholderBuilder: (_) => _BlankProbe(
                        index: i,
                        blank: blank,
                        onMount: () => _probeMounts++,
                      ),
                    ),
            ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('static: ${widget.lib} ($_status)')),
      body: Stack(
        children: [
          // Offstage: built and therefore cache-holding, but never laid out or
          // painted, so it adds no per-frame cost to the measured window.
          // Offstage：会被 build（因而持住缓存），但不参与布局与绘制，不给被测窗口
          // 增加任何每帧成本。
          if (_anchorMounted)
            Offstage(child: _iconWrap(_icons, _anchorBlank)),
          if (_gridMounted)
            Align(
              alignment: Alignment.topLeft,
              child: _iconWrap(_sources, _blank),
            ),
        ],
      ),
      floatingActionButton: _done
          ? FloatingActionButton.extended(
              onPressed: () => exit(0),
              label: const Text('exit'),
            )
          : null,
    );
  }
}

/// A zero-paint stand-in that registers its cell as "not yet painted" while it
/// is mounted, so the runner can tell a real render from a placeholder.
///
/// 一个不绘制任何内容的占位控件，挂载期间把所属格子登记为"尚未画出"，让运行器
/// 能区分真实渲染与占位符。
class _BlankProbe extends StatefulWidget {
  const _BlankProbe({
    required this.index,
    required this.blank,
    required this.onMount,
  });

  final int index;
  final Set<int> blank;

  /// Fired once per construction. Counting constructions is strictly stronger
  /// evidence than sampling [blank] from a post-frame callback: a placeholder
  /// that appears and disappears between two samples is invisible to the peak,
  /// but still increments this.
  ///
  /// 每次构造触发一次。计数构造次数比在帧后回调里采样 [blank] 更硬：两次采样之间
  /// 一闪而过的占位符不会体现在峰值里，但一定会让这个计数加一。
  final VoidCallback onMount;

  @override
  State<_BlankProbe> createState() => _BlankProbeState();
}

class _BlankProbeState extends State<_BlankProbe> {
  @override
  void initState() {
    super.initState();
    widget.blank.add(widget.index);
    widget.onMount();
  }

  @override
  void dispose() {
    widget.blank.remove(widget.index);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      const SizedBox(width: 32, height: 32);
}
