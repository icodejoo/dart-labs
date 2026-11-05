import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:countman/countman.dart';
import 'package:slide_countdown/slide_countdown.dart';
import 'package:stop_watch_timer/stop_watch_timer.dart';

/// Which countdown library/mode is currently mounted / being measured.
///
/// 当前挂载/正在测量的倒计时库/模式。
enum BenchLib {
  /// Nothing mounted — idle screen. / 空闲，未挂载任何库。
  idle,

  /// countman [CardCountdown] in [CountdownType.slide] mode. / countman 卡片滑动模式。
  countmanCard,

  /// 250ms 纯平移，与 slide_countdown 默认动画对等。
  countmanCardFair,

  /// 混合页：保留每张卡片自带的重绘边界。
  mixedPerCard,

  /// 混合页：关闭每卡边界，仅在卡片网格外共享一个边界。
  mixedGroupLayer,

  /// 混合页：关闭每卡边界，页面和网格均不加边界。
  mixedNoBoundary,

  /// 混合页：关闭每卡边界，一个边界包住卡片和全部静态内容。
  mixedWrapAll,

  /// 250ms 平移并缩放，不淡化，用于 Raster 特效归因。
  cardSlideScale,

  /// 250ms 平移并淡化，不缩放，用于 Raster 特效归因。
  cardSlideOpacity,

  /// 默认时长的整卡 flip 过渡，用于对比透视旋转成本。
  cardFlipDefault,

  /// 默认 calendar 过渡与默认时长；splitDigits 默认已为 false。
  countmanCardDefault,
  /// 默认 calendar 过渡，显示刷新上限 30fps。
  countmanCardDefault30,
  /// 50 个 TextCounter 持续滚动，不限帧；用于验证 fps 对共享 ticker 组件的真实出帧影响。
  counterFree,
  /// 50 个不限帧 TextCounter 被不透明路由覆盖，验证静音休眠。
  coveredCounter,
  /// 50 张默认 calendar 卡被不透明路由覆盖，验证静音休眠。
  coveredCard,
  /// 50 个 RingCountdown 持续刷新，作为 Ring 的真窗口基线。
  ringCountdown,
  /// 50 个 DialCountdown 持续刷新，作为 Dial 的真窗口基线。
  dialCountdown,
  /// 50 个 BarCountdown 持续刷新，作为 Bar 的真窗口基线。
  barCountdown,
  /// 同 counterFree，fps: 30。
  counter30,
  /// 同 counter30，改由全局限帧。
  counterGlobal30,
  /// 同 counter30，改由页面插件限帧。
  counterPlugin30,
  /// 50 个 precise 倒计时（毫秒显示逐帧更新），不限帧。
  preciseFree,
  /// 同 preciseFree，fps: 30。
  precise30,
  /// 同 precise30，改由全局限帧。
  preciseGlobal30,
  /// 同 precise30，改由页面插件限帧。
  precisePlugin30,

  /// 250ms 纯平移，各实例按 20ms 错开亚秒相位。
  countmanCardStaggered,

  /// 450ms 滑动，与原 countmanCard 的时长对等。
  slide450,

  /// 默认滑动，时长与首次挂载均按 20ms 错开亚秒相位。
  slideStaggered,

  /// The `slide_countdown` package's [SlideCountdown]. / slide_countdown 包。
  slide,

  /// countman [TextCountdown] (plain formatted text). / countman 文本模式。
  countmanText,

  /// `stop_watch_timer` package driving a plain [Text] via [StreamBuilder].
  /// stop_watch_timer 包 + StreamBuilder 驱动纯文本。
  stopWatch,
}

/// Number of concurrent countdown widgets rendered during a run.
///
/// 每轮并发渲染的倒计时组件数量。
const int kCount = 50;

/// Grid columns used to lay all [kCount] widgets on screen at once (so none
/// are scroll-culled and every instance actually paints each frame).
///
/// 网格列数：一屏排下全部 [kCount] 个组件，避免滚动裁剪导致部分实例不绘制。
const int kCols = 10;

/// Warm-up window ignored before stats collection starts (lets shaders /
/// first-frame jank settle).
///
/// 采集前忽略的预热时长（让着色器编译、首帧卡顿沉淀）。
const Duration kWarmup = Duration(seconds: 3);

/// Measurement window over which frame timings and RSS are sampled.
///
/// 实际采集帧耗时与 RSS 的测量时长。
const Duration kMeasure = Duration(seconds: 15);

/// One library's measured result.
///
/// 单个库的测量结果。
class BenchResult {
  BenchResult(this.lib);

  /// Which library produced this result. / 产生该结果的库。
  final BenchLib lib;

  /// Per-frame UI (build+layout) thread durations, in milliseconds.
  ///
  /// 每帧 UI（构建+布局）线程耗时（毫秒）。
  final List<double> uiMs = [];

  /// Per-frame raster (GPU) thread durations, in milliseconds.
  ///
  /// 每帧光栅（GPU）线程耗时（毫秒）。
  final List<double> rasterMs = [];

  /// RSS memory samples taken during the window, in megabytes.
  ///
  /// 测量窗口内采集的 RSS 内存样本（MB）。
  final List<double> rssMb = [];

  /// Wall-clock elapsed of the measurement window, in seconds. / 测量窗口真实耗时（秒）。
  double elapsedS = 0;

  /// Frames observed during the window. / 窗口内观测到的帧数。
  int get frames => uiMs.length;

  /// Average rendered FPS = frames / elapsed. / 平均渲染帧率。
  double get fps => elapsedS > 0 ? frames / elapsedS : 0;

  /// Percentile of a sorted-copy of [values]. / 取 [values] 的分位数。
  static double _p(List<double> values, double q) {
    if (values.isEmpty) return 0;
    final s = [...values]..sort();
    final i = ((s.length - 1) * q).round();
    return s[i];
  }

  double _avg(List<double> v) =>
      v.isEmpty ? 0 : v.reduce((a, b) => a + b) / v.length;

  /// Jank frames = max(ui, raster) over the 16.67 ms budget.
  ///
  /// 卡顿帧数：并行 UI、Raster 中任一线程耗时超过 16.67ms 预算。
  int get jankFrames {
    var n = 0;
    for (var i = 0; i < uiMs.length; i++) {
      if (uiMs[i] > 16.67 || rasterMs[i] > 16.67) n++;
    }
    return n;
  }

  /// Flatten to a JSON-friendly map for console logging. / 转成可打印的 JSON map。
  Map<String, Object> toJson() => {
        'lib': lib.name,
        'frames': frames,
        'elapsedS': double.parse(elapsedS.toStringAsFixed(2)),
        'fps': double.parse(fps.toStringAsFixed(1)),
        'uiMs_avg': double.parse(_avg(uiMs).toStringAsFixed(2)),
        'uiMs_p50': double.parse(_p(uiMs, .50).toStringAsFixed(2)),
        'uiMs_p90': double.parse(_p(uiMs, .90).toStringAsFixed(2)),
        'uiMs_p99': double.parse(_p(uiMs, .99).toStringAsFixed(2)),
        'rasterMs_avg': double.parse(_avg(rasterMs).toStringAsFixed(2)),
        'rasterMs_p90': double.parse(_p(rasterMs, .90).toStringAsFixed(2)),
        'rasterMs_p99': double.parse(_p(rasterMs, .99).toStringAsFixed(2)),
        // 保留字段名；口径由 ui+raster 改为 max(ui, raster) > 16.67ms。
        'jankFrames': jankFrames,
        'jankPct': frames == 0
            ? 0
            : double.parse((100 * jankFrames / frames).toStringAsFixed(1)),
        'rss_start_mb': rssMb.isEmpty
            ? 0
            : double.parse(rssMb.first.toStringAsFixed(1)),
        'rss_avg_mb': double.parse(_avg(rssMb).toStringAsFixed(1)),
        'rss_peak_mb': rssMb.isEmpty
            ? 0
            : double.parse(
                rssMb.reduce((a, b) => a > b ? a : b).toStringAsFixed(1)),
      };
}

/// A/B benchmark page: renders 50 concurrent slide countdowns from each
/// library in turn and reports FPS / frame-time / RSS. Run in profile mode
/// (`flutter run --profile -d windows`) for meaningful numbers.
///
/// A/B 基准页：依次渲染两个库各 50 个并发滑动倒计时，汇报 FPS / 帧耗时 / RSS。
/// 需在 profile 模式运行（`flutter run --profile -d windows`）才有意义。
class BenchmarkPage extends StatefulWidget {
  const BenchmarkPage({super.key});
  @override
  State<BenchmarkPage> createState() => _BenchmarkPageState();
}

class _BenchmarkPageState extends State<BenchmarkPage> {
  /// Currently mounted library. / 当前挂载的库。
  BenchLib _mounted = BenchLib.idle;

  /// True while a warmup+measure session is in progress. / 会话进行中。
  bool _running = false;

  /// Human-readable phase label shown in the app bar. / 顶栏显示的阶段文本。
  String _phase = 'idle';

  /// Result being filled by the active [SchedulerBinding] timings callback,
  /// or null when not collecting. / 正在采集的结果，未采集时为 null。
  BenchResult? _collecting;

  /// Finished results keyed by library, for the comparison table. / 完成的结果。
  final Map<BenchLib, BenchResult> _results = {};

  /// Registered frame-timings callback (kept to remove on dispose). / 帧回调引用。
  TimingsCallback? _timingsCb;

  /// Periodic RSS sampler. / RSS 周期采样定时器。
  Timer? _rssTimer;

  /// 仅在对应变体挂载期间持有配置与插件。
  /// 覆盖路由只静音底层组件；采集由仍挂载的页面 State 和 Timer 继续。
  Route<void>? _coverRoute;
  bool _usesGlobalFps = false;
  Counter? _counterPlugin30;
  Countdown? _countdownPlugin30;

  void _releaseFpsVariant() {
    if (_usesGlobalFps) {
      Countman.fps = null;
      _usesGlobalFps = false;
    }
    final counter = _counterPlugin30;
    _counterPlugin30 = null;
    if (counter != null) Countman.unuse(counter);
    final countdown = _countdownPlugin30;
    _countdownPlugin30 = null;
    if (countdown != null) Countman.unuse(countdown);
  }

  /// 单库模式优先取编译参数，为空时取进程环境变量；空值仍跑原 A/B 流程。
  /// 单库测量完成后退出，便于外部 CPU 采样；切换环境变量无需重编译。
  static final String _singleLib =
      const String.fromEnvironment('BENCH_LIB').isNotEmpty
          ? const String.fromEnvironment('BENCH_LIB')
          : Platform.environment['BENCH_LIB'] ?? '';

  @override
  void initState() {
    super.initState();
    // Auto-start one second after first frame so a bare `flutter run
    // --profile` produces results with no manual click.
    //
    // 首帧后 1 秒自动开跑，`flutter run --profile` 无需手动点击即可出结果。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future<void>.delayed(const Duration(seconds: 1), () {
        if (!mounted) return;
        switch (_singleLib) {
          case 'countmanCard':
            _runSingle(BenchLib.countmanCard);
          case 'countmanCardFair':
            _runSingle(BenchLib.countmanCardFair);
          case 'mixedPerCard':
            _runSingle(BenchLib.mixedPerCard);
          case 'mixedGroupLayer':
            _runSingle(BenchLib.mixedGroupLayer);
          case 'mixedNoBoundary':
            _runSingle(BenchLib.mixedNoBoundary);
          case 'mixedWrapAll':
            _runSingle(BenchLib.mixedWrapAll);
          case 'cardSlideScale':
            _runSingle(BenchLib.cardSlideScale);
          case 'cardSlideOpacity':
            _runSingle(BenchLib.cardSlideOpacity);
          case 'cardFlipDefault':
            _runSingle(BenchLib.cardFlipDefault);
          case 'countmanCardDefault30':
            _runSingle(BenchLib.countmanCardDefault30);
          case 'coveredCounter':
            _runSingle(BenchLib.coveredCounter);
          case 'coveredCard':
            _runSingle(BenchLib.coveredCard);
          case 'counterFree':
            _runSingle(BenchLib.counterFree);
          case 'ringCountdown':
            _runSingle(BenchLib.ringCountdown);
          case 'dialCountdown':
            _runSingle(BenchLib.dialCountdown);
          case 'barCountdown':
            _runSingle(BenchLib.barCountdown);
          case 'counter30':
            _runSingle(BenchLib.counter30);
          case 'counterGlobal30':
            _runSingle(BenchLib.counterGlobal30);
          case 'counterPlugin30':
            _runSingle(BenchLib.counterPlugin30);
          case 'preciseFree':
            _runSingle(BenchLib.preciseFree);
          case 'precise30':
            _runSingle(BenchLib.precise30);
          case 'preciseGlobal30':
            _runSingle(BenchLib.preciseGlobal30);
          case 'precisePlugin30':
            _runSingle(BenchLib.precisePlugin30);
            break;
          case 'countmanCardDefault':
            _runSingle(BenchLib.countmanCardDefault);
          case 'countmanCardStaggered':
            _runSingle(BenchLib.countmanCardStaggered);
          case 'slide450':
            _runSingle(BenchLib.slide450);
          case 'slideStaggered':
            _runSingle(BenchLib.slideStaggered);
          case 'slide':
            _runSingle(BenchLib.slide);
          case 'countmanText':
            _runSingle(BenchLib.countmanText);
          case 'stopWatch':
            _runSingle(BenchLib.stopWatch);
          default:
            _runAll();
        }
      });
    });
  }

  /// Measure a single [lib] then exit the process (isolated-run mode).
  ///
  /// 只测单个 [lib]，随后退出进程（隔离运行模式）。
  Future<void> _runSingle(BenchLib lib) async {
    setState(() => _running = true);
    try {
      await _runOne(lib);
    } finally {
      // 单库退出前先卸载并恢复配置，不能依赖进程退出触发 dispose。
      if (mounted) setState(() => _mounted = BenchLib.idle);
      _releaseFpsVariant();
    }
    debugPrint('BENCH_DONE ${lib.name}');
    // Give stdout a moment to flush, then terminate. / 等 stdout 刷新后退出。
    await Future<void>.delayed(const Duration(milliseconds: 300));
    exit(0);
  }

  @override
  void dispose() {
    if (_timingsCb != null) {
      SchedulerBinding.instance.removeTimingsCallback(_timingsCb!);
    }
    _rssTimer?.cancel();
    _releaseFpsVariant();
    super.dispose();
  }

  /// Run both libraries back-to-back, then leave the comparison on screen.
  ///
  /// 依次跑完两个库，最后在屏上保留对比结果。
  Future<void> _runAll() async {
    if (_running) return;
    setState(() {
      _running = true;
      _results.clear();
    });
    for (final lib in [
      BenchLib.countmanCard,
      BenchLib.slide,
      BenchLib.countmanText,
      BenchLib.stopWatch,
    ]) {
      await _runOne(lib);
      await _cooldown();
    }
    // Unmount and print the final comparisons. / 卸载并打印最终对比。
    setState(() {
      _mounted = BenchLib.idle;
      _phase = 'done';
      _running = false;
    });
    _printComparison();
  }

  /// Idle gap between the two libraries so the previous one's tickers fully
  /// tear down before the next mounts. / 两库之间的空闲间隔，确保上一个完全卸载。
  Future<void> _cooldown() async {
    _releaseFpsVariant();
    setState(() {
      _mounted = BenchLib.idle;
      _phase = 'cooldown';
    });
    await Future<void>.delayed(const Duration(seconds: 2));
  }

  /// Mount [lib], warm up, then collect frame timings + RSS over [kMeasure].
  ///
  /// 挂载 [lib]，预热，然后在 [kMeasure] 窗口内采集帧耗时 + RSS。
  Future<void> _runOne(BenchLib lib) async {
    // 切换时先清理上一变体，再在组件挂载前配置限帧来源。
    _releaseFpsVariant();
    switch (lib) {
      case BenchLib.counterGlobal30:
      case BenchLib.preciseGlobal30:
        _usesGlobalFps = true;
        Countman.fps = 30;
      case BenchLib.counterPlugin30:
        _counterPlugin30 = Counter(name: 'bench-counter-plugin30', fps: 30);
        Countman.use(_counterPlugin30!);
      case BenchLib.precisePlugin30:
        _countdownPlugin30 = Countdown(
            name: 'bench-countdown-plugin30', interval: 0, fps: 30);
        Countman.use(_countdownPlugin30!);
      default:
        break;
    }
    // Mount widgets. / 挂载组件。
    setState(() {
      _mounted = lib;
      _phase = '${lib.name}: warmup';
    });
    if (lib == BenchLib.coveredCounter || lib == BenchLib.coveredCard) {
      await Future<void>.delayed(const Duration(seconds: 1));
      if (!mounted) return;
      final route = MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => const Scaffold(
          backgroundColor: Color(0xFF202639),
          body: Center(child: Text('Covered benchmark')),
        ),
      );
      _coverRoute = route;
      // MaterialPageRoute 默认 opaque 且 maintainState；底层 State/采集 Timer 不销毁。
      Navigator.of(context).push<void>(route);
      await Future<void>.delayed(kWarmup - const Duration(seconds: 1));
    } else {
      await Future<void>.delayed(kWarmup);
    }

    final result = BenchResult(lib);
    _collecting = result;
    final stopwatch = Stopwatch()..start();

    // Frame timings callback: one call may batch several frames. / 帧耗时回调。
    _timingsCb = (List<FrameTiming> timings) {
      final r = _collecting;
      if (r == null) return;
      for (final t in timings) {
        r.uiMs.add(t.buildDuration.inMicroseconds / 1000.0);
        r.rasterMs.add(t.rasterDuration.inMicroseconds / 1000.0);
      }
    };
    SchedulerBinding.instance.addTimingsCallback(_timingsCb!);

    // RSS sampler every 200 ms. / 每 200ms 采样一次 RSS。
    _sampleRss(result);
    _rssTimer = Timer.periodic(
        const Duration(milliseconds: 200), (_) => _sampleRss(result));

    setState(() => _phase = '${lib.name}: measuring');
    await Future<void>.delayed(kMeasure);

    // Stop collection. / 停止采集。
    stopwatch.stop();
    result.elapsedS = stopwatch.elapsedMilliseconds / 1000.0;
    _rssTimer?.cancel();
    _rssTimer = null;
    SchedulerBinding.instance.removeTimingsCallback(_timingsCb!);
    _timingsCb = null;
    _collecting = null;

    _results[lib] = result;
    // Print immediately so it's captured even if the run is interrupted. / 立即打印。
    debugPrint('BENCH ${jsonEncode(result.toJson())}');
    final cover = _coverRoute;
    _coverRoute = null;
    if (cover != null && cover.isActive && mounted) {
      Navigator.of(context).removeRoute(cover);
    }
    setState(() {});
  }

  /// Append one RSS sample (resident set size) in MB. / 采集一个 RSS 样本（MB）。
  void _sampleRss(BenchResult r) {
    // ProcessInfo.currentRss is the OS resident set size in bytes; available
    // on desktop/mobile (not web). / currentRss 为进程常驻内存字节数，桌面可用。
    final bytes = ProcessInfo.currentRss;
    r.rssMb.add(bytes / (1024 * 1024));
  }

  /// Print a compact side-by-side comparison to the console. / 打印并排对比。
  void _printComparison() {
    final cc = _results[BenchLib.countmanCard];
    final sl = _results[BenchLib.slide];
    if (cc != null && sl != null) {
      debugPrint('BENCH_COMPARE_CARD ${jsonEncode({
            'countman_card': cc.toJson(),
            'slide_countdown': sl.toJson(),
          })}');
    }
    final ct = _results[BenchLib.countmanText];
    final sw = _results[BenchLib.stopWatch];
    if (ct != null && sw != null) {
      debugPrint('BENCH_COMPARE_TEXT ${jsonEncode({
            'countman_text': ct.toJson(),
            'stop_watch_timer': sw.toJson(),
          })}');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF101014),
      appBar: AppBar(
        backgroundColor: const Color(0xFF101014),
        // Forced dark app bar → light foreground so the title stays visible
        // under a light theme (default foreground follows the theme).
        //
        // 强制深色 AppBar → 浅色前景，使标题在浅色主题下仍可见。
        foregroundColor: Colors.white,
        title: Text('Countdown Bench · $kCount 并发 · $_phase'),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: FilledButton.icon(
              onPressed: _running ? null : _runAll,
              icon: const Icon(Icons.play_arrow),
              label: Text(_running ? 'running…' : 'Run A/B'),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_results.isNotEmpty) _resultsTable(),
          Expanded(child: _isMixed ? _mixedPage() : _grid()),
        ],
      ),
    );
  }

  /// 当前是否使用相同布局的混合页面变体。
  bool get _isMixed =>
      _mounted == BenchLib.mixedPerCard ||
      _mounted == BenchLib.mixedGroupLayer ||
      _mounted == BenchLib.mixedNoBoundary ||
      _mounted == BenchLib.mixedWrapAll;

  /// 卡片和静态区共用父 Column，只按变体放置显式重绘边界。
  Widget _mixedPage() {
    final cards = _mixedGrid(
      count: kCount,
      columns: kCols,
      cellBuilder: (i) => Center(child: _cell(i)),
    );
    final page = Column(
      children: [
        Expanded(
          flex: 2,
          // 正确共享：边界仅包卡片网格，不含下方静态内容。
          child: _mounted == BenchLib.mixedGroupLayer
              ? RepaintBoundary(child: cards)
              : cards,
        ),
        Expanded(
          flex: 3,
          // 静态区不加边界，120 个单元全部在屏内参与绘制。
          child: _mixedGrid(
            count: 120,
            columns: 12,
            cellBuilder: _mixedStaticCell,
          ),
        ),
      ],
    );
    // 错误共享：整页边界会随卡片动画重录静态区；无边界组向页面上传。
    // 每卡组仅依赖 CardCountdown 自带边界，其余组均关闭每卡边界。
    return _mounted == BenchLib.mixedWrapAll
        ? RepaintBoundary(child: page)
        : page;
  }

  /// 用非滚动行列平铺，避免视口裁剪和 GridView 自动边界干扰对比。
  Widget _mixedGrid({
    required int count,
    required int columns,
    required Widget Function(int) cellBuilder,
  }) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        children: [
          for (var row = 0; row < (count + columns - 1) ~/ columns; row++)
            Expanded(
              child: Row(
                children: [
                  for (var col = 0; col < columns; col++)
                    Expanded(
                      child: row * columns + col < count
                          ? cellBuilder(row * columns + col)
                          : const SizedBox.shrink(),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// 每个静态单元包含文字、图标及渐变圆角（不带模糊阴影，避免 Raster 被静态内容压满而淹没差异）。
  Widget _mixedStaticCell(int i) {
    return Container(
      margin: const EdgeInsets.all(2),
      padding: const EdgeInsets.symmetric(horizontal: 3),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF34476B), Color(0xFF202639)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Row(
        children: [
          const Icon(Icons.insights, size: 12, color: Colors.cyanAccent),
          const SizedBox(width: 2),
          Expanded(
            child: Text(
              '内容 $i',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 9, color: Colors.white70),
            ),
          ),
        ],
      ),
    );
  }

  /// The 50-widget grid for whichever library is mounted. / 挂载库的 50 组件网格。
  Widget _grid() {
    if (_mounted == BenchLib.idle) {
      return const Center(
        child: Text('Press "Run A/B" to benchmark\n(profile mode recommended)',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white38)),
      );
    }
    return GridView.count(
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: kCols,
      padding: const EdgeInsets.all(8),
      mainAxisSpacing: 6,
      crossAxisSpacing: 6,
      childAspectRatio: 1.4,
      children: [
        for (var i = 0; i < kCount; i++) Center(child: _cell(i)),
      ],
    );
  }

  /// 第 [i] 个倒计时；原组仅整秒错开，Staggered 组额外错开亚秒相位。
  Widget _cell(int i) {
    // 4–8 min range, staggered by index. / 4–8 分钟区间，按下标错开。
    final staggered = _mounted == BenchLib.countmanCardStaggered ||
        _mounted == BenchLib.slideStaggered;
    final dur = Duration(
      minutes: 4 + (i % 5),
      seconds: i % 60,
      milliseconds: staggered ? i * 20 : 0,
    );
    const ts = TextStyle(
        fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white);
    switch (_mounted) {
      case BenchLib.countmanCard:
        return CardCountdown(
          to: dur,
          showHours: false,
          labels: null,
          style: const CardCountdownStyle(
            transitionType: CountdownType.slide,
            scaleEffect: SlideEffect.both,
            opacityEffect: SlideEffect.both,
            cardWidth: 30,
            cardHeight: 40,
            unitGap: 4,
            textStyle: ts,
          ),
        );
      case BenchLib.countmanCardFair:
      case BenchLib.countmanCardStaggered:
      case BenchLib.mixedPerCard:
      case BenchLib.mixedGroupLayer:
      case BenchLib.mixedNoBoundary:
      case BenchLib.mixedWrapAll:
        return CardCountdown(
          to: dur,
          // 仅每卡组保留默认边界；共享组和无边界组关闭每卡边界。
          repaintBoundary: !_isMixed || _mounted == BenchLib.mixedPerCard,
          duration: const Duration(milliseconds: 250),
          showHours: false,
          labels: null,
          style: const CardCountdownStyle(
            transitionType: CountdownType.slide,
            scaleEffect: SlideEffect.none,
            opacityEffect: SlideEffect.none,
            cardWidth: 30,
            cardHeight: 40,
            unitGap: 4,
            textStyle: ts,
          ),
        );
      case BenchLib.cardSlideScale:
      case BenchLib.cardSlideOpacity:
        return CardCountdown(
          to: dur,
          duration: const Duration(milliseconds: 250),
          showHours: false,
          labels: null,
          style: CardCountdownStyle(
            transitionType: CountdownType.slide,
            scaleEffect: _mounted == BenchLib.cardSlideScale
                ? SlideEffect.both
                : SlideEffect.none,
            opacityEffect: _mounted == BenchLib.cardSlideOpacity
                ? SlideEffect.both
                : SlideEffect.none,
            cardWidth: 30,
            cardHeight: 40,
            unitGap: 4,
            textStyle: ts,
          ),
        );
      case BenchLib.cardFlipDefault:
        return CardCountdown(
          to: dur,
          showHours: false,
          labels: null,
          style: const CardCountdownStyle(
            transitionType: CountdownType.flip,
            cardWidth: 30,
            cardHeight: 40,
            unitGap: 4,
            textStyle: ts,
          ),
        );
      case BenchLib.coveredCard:
      case BenchLib.countmanCardDefault:
      case BenchLib.countmanCardDefault30:
        return CardCountdown(
          fps: _mounted == BenchLib.countmanCardDefault30 ? 30 : null,
          to: dur,
          showHours: false,
          labels: null,
          style: const CardCountdownStyle(
            cardWidth: 30,
            cardHeight: 40,
            unitGap: 4,
            textStyle: ts,
          ),
        );
      case BenchLib.slide:
      case BenchLib.slide450:
      case BenchLib.slideStaggered:
        final slide = SlideCountdown(
          duration: dur,
          slideDirection: SlideDirection.down,
          slideAnimationDuration: Duration(
              milliseconds: _mounted == BenchLib.slide450 ? 450 : 250),
          // days/hours are zero for a 4–8 min duration and auto-hidden by
          // showZeroValue:false → renders MM:SS, matching countman above.
          //
          // 4–8 分钟时长下天/时为零，showZeroValue:false 自动隐藏 → 显示 MM:SS。
          separatorType: SeparatorType.symbol,
          style: ts,
        );
        // 第三方按挂载时刻启动整秒定时器，需额外错开首次挂载才会错相。
        return _mounted == BenchLib.slideStaggered
            ? _StaggeredMount(
                delay: Duration(milliseconds: i * 20), child: slide)
            : slide;
      case BenchLib.coveredCounter:
      case BenchLib.counterFree:
      case BenchLib.counter30:
        return TextCounter(
          to: 1e9,
          duration: const Duration(minutes: 5),
          curve: Curves.linear,
          fps: _mounted == BenchLib.counter30 ? 30 : null,
          style: TextCounterStyle(textStyle: ts),
        );
      case BenchLib.ringCountdown:
        return SizedBox(width: 56, height: 56, child: RingCountdown(to: dur));
      case BenchLib.dialCountdown:
        return SizedBox(width: 56, height: 56, child: DialCountdown(to: dur));
      case BenchLib.barCountdown:
        return SizedBox(width: 90, height: 12, child: BarCountdown(to: dur));
      case BenchLib.counterGlobal30:
        return TextCounter(
          to: 1e9,
          duration: const Duration(minutes: 5),
          curve: Curves.linear,
          style: TextCounterStyle(textStyle: ts),
        );
      case BenchLib.counterPlugin30:
        return TextCounter(
          to: 1e9,
          duration: const Duration(minutes: 5),
          curve: Curves.linear,
          plugin: _counterPlugin30!,
          style: TextCounterStyle(textStyle: ts),
        );
      case BenchLib.preciseFree:
      case BenchLib.precise30:
        return TextCountdown(
          to: dur,
          precise: true,
          formatter: CountdownFormat.msMillis,
          fps: _mounted == BenchLib.precise30 ? 30 : null,
          style: TextCountdownStyle(textStyle: ts),
        );
      case BenchLib.preciseGlobal30:
        return TextCountdown(
          to: dur,
          precise: true,
          formatter: CountdownFormat.msMillis,
          style: TextCountdownStyle(textStyle: ts),
        );
      case BenchLib.precisePlugin30:
        return TextCountdown(
          to: dur,
          precise: true,
          formatter: CountdownFormat.msMillis,
          plugin: _countdownPlugin30!,
          style: TextCountdownStyle(textStyle: ts),
        );
      case BenchLib.countmanText:
        return TextCountdown(to: dur, formatter: CountdownFormat.ms, style: TextCountdownStyle(textStyle: ts));
      case BenchLib.stopWatch:
        return _StopWatchCell(duration: dur, style: ts);
      case BenchLib.idle:
        return const SizedBox.shrink();
    }
  }

  /// Comparison table shown once both runs finish. / 两轮跑完后的对比表。
  Widget _resultsTable() {
    final a = _results[BenchLib.countmanCard];
    final b = _results[BenchLib.slide];
    TextStyle st(Color c) =>
        TextStyle(color: c, fontSize: 12, fontFamily: 'monospace');
    Widget row(String label, String? av, String? bv) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 8),
          child: Row(children: [
            SizedBox(width: 130, child: Text(label, style: st(Colors.white54))),
            SizedBox(
                width: 110,
                child: Text(av ?? '—', style: st(Colors.cyanAccent))),
            SizedBox(
                width: 110,
                child: Text(bv ?? '—', style: st(Colors.orangeAccent))),
          ]),
        );
    String? f(BenchResult? r, String k) =>
        r == null ? null : '${r.toJson()[k]}';
    return Container(
      color: const Color(0xFF17171D),
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          row('metric', 'countman', 'slide_countdown'),
          const Divider(height: 8, color: Colors.white12),
          row('FPS', f(a, 'fps'), f(b, 'fps')),
          row('frames', f(a, 'frames'), f(b, 'frames')),
          row('UI ms avg', f(a, 'uiMs_avg'), f(b, 'uiMs_avg')),
          row('UI ms p90', f(a, 'uiMs_p90'), f(b, 'uiMs_p90')),
          row('UI ms p99', f(a, 'uiMs_p99'), f(b, 'uiMs_p99')),
          row('raster ms avg', f(a, 'rasterMs_avg'), f(b, 'rasterMs_avg')),
          row('raster ms p99', f(a, 'rasterMs_p99'), f(b, 'rasterMs_p99')),
          row('jank frames', f(a, 'jankFrames'), f(b, 'jankFrames')),
          row('jank %', f(a, 'jankPct'), f(b, 'jankPct')),
          row('RSS avg MB', f(a, 'rss_avg_mb'), f(b, 'rss_avg_mb')),
          row('RSS peak MB', f(a, 'rss_peak_mb'), f(b, 'rss_peak_mb')),
        ],
      ),
    );
  }
}

/// 错开子组件的首次挂载；等待最长 980ms，完全落在预热窗口内。
class _StaggeredMount extends StatefulWidget {
  const _StaggeredMount({required this.delay, required this.child});

  /// 从网格挂载开始计算的亚秒相位偏移。
  final Duration delay;

  /// 延迟挂载的倒计时组件。
  final Widget child;

  @override
  State<_StaggeredMount> createState() => _StaggeredMountState();
}

/// 持有一次性挂载定时器，后续父级重建不重新等待。
class _StaggeredMountState extends State<_StaggeredMount> {
  /// 首次挂载定时器，卸载时取消。
  Timer? _timer;

  /// 相位等待完成后持续显示子组件。
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _ready = widget.delay == Duration.zero;
    if (!_ready) {
      _timer = Timer(widget.delay, () => setState(() => _ready = true));
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _ready ? widget.child : const SizedBox.shrink();
}

/// A single `stop_watch_timer` countdown cell: owns one [StopWatchTimer] in
/// count-down mode, starts it on mount and disposes it on unmount, and renders
/// the remaining time as plain [Text] via a [StreamBuilder]. Fifty of these =
/// fifty independent stream-driven timers (the whole point of the comparison
/// against countman's single shared ticker).
///
/// 单个 stop_watch_timer 倒计时单元：持有一个倒计时模式的 [StopWatchTimer]，挂载时启动、
/// 卸载时释放，用 [StreamBuilder] 把剩余时间渲染成纯 [Text]。50 个即 50 个各自独立的
/// 流驱动定时器（正是与 countman 单一共享 ticker 对比的核心）。
class _StopWatchCell extends StatefulWidget {
  const _StopWatchCell({required this.duration, required this.style});

  /// Countdown length for this cell. / 本单元的倒计时时长。
  final Duration duration;

  /// Text style for the rendered time. / 渲染时间的文本样式。
  final TextStyle style;

  @override
  State<_StopWatchCell> createState() => _StopWatchCellState();
}

class _StopWatchCellState extends State<_StopWatchCell> {
  /// The per-cell count-down timer. / 本单元的倒计时器。
  late final StopWatchTimer _timer;

  @override
  void initState() {
    super.initState();
    _timer = StopWatchTimer(
      mode: StopWatchMode.countDown,
      presetMillisecond: widget.duration.inMilliseconds,
    );
    _timer.onStartTimer();
  }

  @override
  void dispose() {
    _timer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: _timer.rawTime,
      initialData: _timer.rawTime.value,
      builder: (context, snap) {
        final value = snap.data ?? widget.duration.inMilliseconds;
        // MM:SS to match the other cells. / MM:SS，与其它单元对齐。
        final display = StopWatchTimer.getDisplayTime(
          value,
          hours: false,
          minute: true,
          second: true,
          milliSecond: false,
        );
        return Text(display, style: widget.style);
      },
    );
  }
}
