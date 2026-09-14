// Benchmark for the `SvgImageProvider` family (StringSvgx et al.), the ONE
// code path in svgx affected by the `_supersample` constant in
// lib/src/svg_image_provider.dart — every other benchmark in this app uses
// SvgxStatic/SvgPicture.string, which never goes near it. svgx-vs-svgx only:
// flutter_svg has no equivalent offscreen-`toImage` ImageProvider, so there
// is nothing to compare against on the other side.
//
// Measures cold rasterization cost directly through `ImageProvider.resolve`
// (no widget tree needed — `loadImage` fires the same way whether or not the
// resulting image is ever painted), using the same per-round cache-busting
// XML-comment trick `static20_bench_screen.dart` uses, plus a Flutter
// `ImageCache` clear between rounds so cache hits from Flutter's OWN image
// cache don't mask the rasterization cost this benchmark exists to measure.
//
// `SvgImageProvider` 家族（StringSvgx 等）的基准——这是 svgx 里唯一受
// lib/src/svg_image_provider.dart 里 `_supersample` 常量影响的代码路径；本应用
// 其它所有基准都用 SvgxStatic/SvgPicture.string，完全碰不到它。仅 svgx 对
// svgx：flutter_svg 没有等价的离屏 `toImage` ImageProvider，另一侧无可比对象。
//
// 直接通过 `ImageProvider.resolve` 测冷光栅化开销（不需要组件树——不管光栅化
// 结果有没有被画出来，`loadImage` 都会触发一样），沿用
// `static20_bench_screen.dart` 的逐轮缓存击穿 XML 注释手法，并在每轮之间清空
// Flutter 自己的 `ImageCache`，避免 Flutter 自身图片缓存的命中掩盖了本基准要测
// 的光栅化开销。

import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:svgx/svgx.dart';

import 'report_sink.dart';
import 'static20_bench_screen.dart' show readProcessCpuMs, readVmRssBytes;
import 'stats.dart';
import 'svg_gen.dart';

/// Runs the `StringSvgx` cold-rasterization benchmark and prints one report.
///
/// Unlike [Static20BenchRunner] this has no widget tree to mount/unmount:
/// [ImageProvider.resolve] triggers `loadImage` on its own, so the whole
/// benchmark can run headless off a single [StatefulWidget] used only to get
/// a post-frame callback and a place to show status text.
///
/// 运行 `StringSvgx` 冷光栅化基准并打印一份报告。
///
/// 与 [Static20BenchRunner] 不同，这里没有组件树要挂载/卸载：
/// [ImageProvider.resolve] 自己就会触发 `loadImage`，因此整个基准可以在无界面
/// 状态下跑，用到 [StatefulWidget] 只是为了拿一个帧后回调和显示状态文字的地方。
///
/// Example:
/// ```dart
/// ImgProviderBenchRunner(itemCount: 20, rounds: 20, settleSeconds: 2);
/// ```
class ImgProviderBenchRunner extends StatefulWidget {
  /// Creates the runner. / 创建运行器。
  const ImgProviderBenchRunner({
    super.key,
    required this.itemCount,
    required this.rounds,
    this.settleSeconds = 2,
  });

  /// Icons rasterized per round. / 每轮光栅化的图标数。
  final int itemCount;

  /// Cold rounds to measure. / 要测量的冷渲染轮次数。
  final int rounds;

  /// Idle seconds before round 1, so a device's post-launch CPU boost window
  /// doesn't land inside the measured rounds — see
  /// [Static20BenchRunner.settleSeconds] for the same reasoning.
  ///
  /// 第 1 轮前的静置秒数，避免设备启动后的 CPU 加速窗口落进被测轮次——理由同
  /// [Static20BenchRunner.settleSeconds]。
  final int settleSeconds;

  @override
  State<ImgProviderBenchRunner> createState() => _ImgProviderBenchRunnerState();
}

class _ImgProviderBenchRunnerState extends State<ImgProviderBenchRunner> {
  late final List<String> _icons = generateIcons(widget.itemCount);
  final List<Duration> _roundDurations = <Duration>[];
  final List<double> _roundCpuMs = <double>[];
  String _status = 'warming up...';
  bool _done = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  /// Resolves [provider] to a decoded image and completes once, mirroring
  /// how `precacheImage` drives an [ImageProvider] without a widget.
  ///
  /// 把 [provider] 解析到一张已解码的图像，完成一次即返回——手法与
  /// `precacheImage` 在没有控件的情况下驱动 [ImageProvider] 相同。
  Future<void> _resolveOne(ImageProvider provider) {
    final completer = Completer<void>();
    late ImageStream stream;
    late ImageStreamListener listener;
    listener = ImageStreamListener(
      (image, synchronousCall) {
        if (!completer.isCompleted) completer.complete();
        stream.removeListener(listener);
      },
      onError: (error, stackTrace) {
        if (!completer.isCompleted) completer.completeError(error);
        stream.removeListener(listener);
      },
    );
    stream = provider.resolve(ImageConfiguration.empty);
    stream.addListener(listener);
    return completer.future.timeout(
      const Duration(seconds: 20),
      onTimeout: () => throw StateError('image never resolved'),
    );
  }

  Future<void> _run() async {
    await Future<void>.delayed(Duration(seconds: widget.settleSeconds));

    for (var round = 0; round < widget.rounds; round++) {
      // Same trick as static20_bench_screen.dart: a per-round XML comment
      // changes the source string (hence the ImageProvider's `==`/hashCode
      // and Flutter's ImageCache key) without changing any geometry, so every
      // round is a genuine cache miss with identical rendering work.
      //
      // 与 static20_bench_screen.dart 相同的手法：每轮换一条 XML 注释改变源
      // 字符串（从而改变 ImageProvider 的 `==`/hashCode 与 Flutter ImageCache
      // 键），但不改变任何几何，因此每轮都是真实的缓存未命中，渲染工作量相同。
      final sources = [
        for (final icon in _icons)
          icon.replaceFirst('</svg>', '<!--r$round--></svg>'),
      ];
      setState(() => _status = 'round ${round + 1}/${widget.rounds}');
      final cpuStart = readProcessCpuMs() ?? 0;
      final watch = Stopwatch()..start();
      await Future.wait([
        for (final source in sources)
          _resolveOne(StringSvgx(source, width: 32, height: 32)),
      ]);
      watch.stop();
      _roundDurations.add(watch.elapsed);
      _roundCpuMs.add((readProcessCpuMs() ?? 0) - cpuStart);

      // Evict Flutter's own ImageCache so the next round's resolve() cannot
      // hit it — this benchmark measures rasterization, not Flutter's cache.
      // 清空 Flutter 自己的 ImageCache，让下一轮的 resolve() 不可能命中它——本
      // 基准测的是光栅化开销，不是 Flutter 缓存本身。
      PaintingBinding.instance.imageCache
        ..clear()
        ..clearLiveImages();
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }

    setState(() => _done = true);
    _printReport();
  }

  double _avg(Iterable<double> values) =>
      values.isEmpty ? 0.0 : values.reduce((a, b) => a + b) / values.length;

  void _printReport() {
    final n = widget.itemCount;
    final stats = DurationStats.fromDurations(_roundDurations);
    final cold = _roundDurations.isEmpty
        ? 0.0
        : _roundDurations.first.inMicroseconds / 1000.0;
    final warmRounds = _roundDurations.length > 1
        ? _roundDurations.sublist(1)
        : const <Duration>[];
    final warm = DurationStats.fromDurations(warmRounds);
    final cpuAvg = _avg(_roundCpuMs);

    final buf = StringBuffer()
      ..writeln(
        '=== IMGPROVIDER REPORT icons=$n rounds=${widget.rounds} '
        'settle=${widget.settleSeconds}s ===',
      )
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
      ..writeln(
        'round_ms_series=${_roundDurations.map((d) => (d.inMicroseconds / 1000).toStringAsFixed(1)).join(',')}',
      )
      ..writeln(
        'round_cpu_ms_series=${_roundCpuMs.map((c) => c.toStringAsFixed(0)).join(',')}',
      )
      ..writeln('cpu_per_round_avg_ms=${cpuAvg.toStringAsFixed(2)}')
      ..writeln('cpu_per_icon_ms=${(cpuAvg / n).toStringAsFixed(3)}')
      ..writeln(
        'rss_mb=${(ProcessInfo.currentRss / 1e6).toStringAsFixed(2)}',
      )
      ..writeln('vm_rss_mb=${((readVmRssBytes() ?? 0) / 1e6).toStringAsFixed(2)}')
      ..writeln('=== END IMGPROVIDER REPORT ===');
    for (final line in buf.toString().trimRight().split('\n')) {
      emitReport(line);
    }
    if (autoExitAfterReport) exit(0);
  }

  @override
  Widget build(BuildContext context) => Directionality(
        textDirection: TextDirection.ltr,
        child: ColoredBox(
          color: const Color(0xFFFFFFFF),
          child: Center(child: Text(_done ? 'done' : _status)),
        ),
      );
}
