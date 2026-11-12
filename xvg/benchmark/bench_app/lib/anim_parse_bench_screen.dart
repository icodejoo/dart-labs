// Cold first-mount parsing benchmark (`LIB=anim_parse`), run on the UI isolate.
// Each file/path gets one warmup and seven measured parses. File I/O, UTF-8
// decoding, unique-comment insertion, cache clearing and node counting are
// outside the timer. Only the synchronous parser/cache entry point is timed.
// This measures a cold source in a warmed process, not process startup time.
//
// 冷首次挂载解析基准（`LIB=anim_parse`），运行在 UI isolate。每个文件、每条入口
// 预热一次后测七次。读文件、UTF-8 解码、插入唯一注释、清缓存、数节点均不计时，
// 只计同步解析/缓存入口耗时。测的是已预热进程中的冷源，不是进程启动耗时。
//
// Reproduce from benchmark/bench_app in PowerShell / 在该目录复现：
// Windows (third-party corpus stays outside the repository / 素材不入库):
//   $corpusDir = 'C:\Users\jelon\AppData\Local\Temp\claude\E--workspaces-dart-labs-xvg\93aa9a18-7032-40b5-84a7-7704e2b7f8bf\scratchpad\css_samples'
//   $reportFile = Join-Path $PWD 'build\anim_parse_report.txt'
//   $env:PATH = 'E:\workspaces\dart-labs-xvg\xvg\prebuilt\windows\x64;' + $env:PATH
//   flutter run -d windows --profile --dart-define=LIB=anim_parse "--dart-define=CORPUS_DIR=$corpusDir" "--dart-define=REPORT_FILE=$reportFile" --dart-define=AUTOEXIT=true
// Android (commands for the device operator / 以下由真机操作者执行):
//   flutter build apk --profile --dart-define=LIB=anim_parse --dart-define=AUTOEXIT=true --dart-define=REPORT_FILE=/sdcard/Android/data/com.example.bench_app/files/anim_parse_report.txt
//   adb -s 7NQBB23606003715 install -r build/app/outputs/flutter-apk/app-profile.apk
//   adb -s 7NQBB23606003715 shell am start -n com.example.bench_app/.MainActivity
//   adb -s 7NQBB23606003715 shell mkdir -p /sdcard/Android/data/com.example.bench_app/files/corpus_css
//   adb -s 7NQBB23606003715 push "$corpusDir/." /sdcard/Android/data/com.example.bench_app/files/corpus_css
//   adb -s 7NQBB23606003715 logcat -c
//   adb -s 7NQBB23606003715 shell am start -n com.example.bench_app/.MainActivity
//   adb -s 7NQBB23606003715 logcat -s flutter:I
//   adb -s 7NQBB23606003715 pull /sdcard/Android/data/com.example.bench_app/files/anim_parse_report.txt build/anim_parse_android_report.txt
// The first launch may report a missing corpus and exit; MainActivity already
// calls getExternalFilesDir(null), creating the owned parent directory. Wait
// for that launch to finish before mkdir/push. Pushing dir/. copies contents
// without adding another css_samples directory. No storage permission needed.
// Reports append; use a fresh REPORT_FILE for each run, or delimit by BEGIN/END.
//
// 首次启动无素材会明确报错退出；现有 MainActivity 调用 getExternalFilesDir(null)
// 创建属主正确的父目录。等首次运行退出后再 mkdir/push。推送目录末尾加 /. 只复制
// 内容，避免多嵌一层 css_samples；不需存储权限。报告追加写入，每轮可换 REPORT_FILE，
// 或用 BEGIN/END 分隔。AUTOEXIT 统一传 true，兼容 bool.fromEnvironment 的写法。

// ignore_for_file: implementation_imports

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:xvg/src/animation/svg_document_cache.dart';
import 'package:xvg/src/animation/svg_document_parser.dart';
import 'package:xvg/src/animation/svg_dom.dart';

import 'report_sink.dart';
import 'stats.dart';

/// External corpus directory, overridable without bundling assets.
///
/// 外部语料目录，可覆盖且不把素材打包进应用。
const String _corpusDir = String.fromEnvironment(
  'CORPUS_DIR',
  defaultValue: '/sdcard/Android/data/com.example.bench_app/files/corpus_css',
);

/// Untimed warmup count per file and parser entry point.
///
/// 每文件、每解析入口不计入结果的预热次数。
const int _warmups = 1;

/// Measured parse count per file and entry point.
///
/// 每文件、每解析入口的计时次数。
const int _trials = 7;

/// High-refresh frame budget, in microseconds.
///
/// 高刷新率帧预算，单位微秒。
const int _budget8_3Us = 8300;

/// Standard-refresh frame budget, in microseconds.
///
/// 标准刷新率帧预算，单位微秒。
const int _budget16_6Us = 16600;

/// Label for the real animated-widget cache entry point.
///
/// 动画控件真实缓存入口的报告标签。
const String _cachePath = 'getOrParse';

/// Label for the direct parser entry point.
///
/// 直接解析入口的报告标签。
const String _directPath = 'parseAnimatedSvgDocument';

/// Closing root tag before which each unique cache-busting comment is placed.
///
/// 每次用于绕过缓存的唯一注释放在此根结束标签之前。
const String _svgClose = '</svg>';

/// One parser entry point's sample summary and root-tree node count.
///
/// 一个解析入口的采样汇总与根树节点数。
class _ParseTiming {
  /// Creates a measured result.
  ///
  /// 创建测量结果。
  const _ParseTiming(this.stats, this.nodes);

  /// Summary over the seven measured calls, excluding warmup.
  ///
  /// 七次计时调用的汇总，不含预热。
  final DurationStats stats;

  /// Nodes reachable through root.children, including the root itself.
  ///
  /// 从 root.children 可达的节点数，包含根节点自身。
  final int nodes;
}

/// Runs cold synchronous parsing and prints a line-oriented benchmark report.
///
/// 运行同步冷解析，并逐行输出基准报告。
class AnimParseBenchScreen extends StatefulWidget {
  /// Creates the first-parse benchmark screen.
  ///
  /// 创建首次解析基准屏幕。
  const AnimParseBenchScreen({super.key});

  /// Creates the runner state.
  ///
  /// 创建运行状态。
  @override
  State<AnimParseBenchScreen> createState() => _AnimParseBenchScreenState();
}

/// Keeps measurements on the UI isolate and yields between corpus files.
///
/// 在 UI isolate 测量，并在文件之间让出执行权。
class _AnimParseBenchScreenState extends State<AnimParseBenchScreen> {
  /// Unique comment serial shared by warmups and both measured paths.
  ///
  /// 预热及两条测量入口共用的唯一注释序号。
  int _sourceSerial = 0;

  /// Per-file cache-entry medians used for the corpus summary.
  ///
  /// 用于语料汇总的各文件缓存入口中位数。
  final List<Duration> _cacheMedians = [];

  /// Per-file direct-parser medians used for the corpus summary.
  ///
  /// 用于语料汇总的各文件直接解析中位数。
  final List<Duration> _directMedians = [];

  /// Number of corpus or file errors, producing a failed report and exit code.
  ///
  /// 语料或文件错误数，用于报告失败及非零退出码。
  int _errors = 0;

  /// Current progress, also visible when AUTOEXIT is disabled.
  ///
  /// 当前进度，在关闭 AUTOEXIT 时也可见。
  String _progress = 'Waiting for first frame';

  /// Starts after the first frame so the window can show benchmark progress.
  ///
  /// 首帧后开始运行，让窗口先显示基准进度。
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_run()));
  }

  /// Emits one short logcat message and appends the same line to REPORT_FILE.
  ///
  /// 每次输出一条短 logcat 消息，并把同一行追加到 REPORT_FILE。
  void _emitLine(String line) => emitReport('$line\n');

  /// Counts the expanded render tree; separate mask/clip definitions are excluded.
  ///
  /// 统计展开后的渲染树；独立保存的 mask/clip 定义不计入。
  int _countNodes(SvgNode root) {
    var count = 0;
    final pending = <SvgNode>[root];
    while (pending.isNotEmpty) {
      final node = pending.removeLast();
      count++;
      pending.addAll(node.children);
    }
    return count;
  }

  /// Measures only parsing, with a fresh source and empty document cache each time.
  ///
  /// 每次使用新源串和空文档缓存，只测量解析过程。
  _ParseTiming _measure(
    String source,
    int closeOffset,
    SvgDocument Function(String) parse,
  ) {
    final samples = <Duration>[];
    late SvgDocument document;
    for (var i = 0; i < _warmups + _trials; i++) {
      final coldSource = source.replaceRange(
        closeOffset,
        closeOffset,
        '<!--anim_parse_r${_sourceSerial++}-->',
      );
      XvgDocumentCache.instance.clear();
      final watch = Stopwatch()..start();
      document = parse(coldSource);
      watch.stop();
      if (i >= _warmups) samples.add(watch.elapsed);
    }
    XvgDocumentCache.instance.clear();
    return _ParseTiming(
      DurationStats.fromDurations(samples),
      _countNodes(document.root),
    );
  }

  /// Reports a corpus/file error explicitly rather than a misleading zero result.
  ///
  /// 明确报告语料/文件错误，避免用零耗时掩盖失败。
  void _reportError(Object error, {String? file}) {
    _errors++;
    _emitLine('ERROR file=${jsonEncode(file)} message=${jsonEncode('$error')}');
  }

  /// Summarizes the distribution and sum of per-file medians for one entry point.
  ///
  /// 汇总一个入口的各文件中位数分布与总和。
  void _reportSummary(String path, List<Duration> medians) {
    if (medians.isEmpty) return;
    final stats = DurationStats.fromDurations(medians);
    final sumUs = medians.fold<int>(
      0,
      (sum, item) => sum + item.inMicroseconds,
    );
    final over8_3 = medians
        .where((d) => d.inMicroseconds > _budget8_3Us)
        .length;
    final over16_6 = medians
        .where((d) => d.inMicroseconds > _budget16_6Us)
        .length;
    _emitLine(
      'SUMMARY path=$path files=${medians.length} sum_us=$sumUs '
      'p50_us=${stats.p50Us.toInt()} p90_us=${stats.p90Us.toInt()} '
      'max_us=${stats.maxUs.toInt()} '
      'median_over_8.3ms=$over8_3 median_over_16.6ms=$over16_6',
    );
  }

  /// Loads external files, measures both entry points and always emits an END marker.
  ///
  /// 加载外部文件、测量两个入口，并始终输出 END 标记。
  Future<void> _run() async {
    _emitLine('=== BEGIN ANIM PARSE BENCH REPORT ===');
    _emitLine('corpus_dir=${jsonEncode(_corpusDir)}');
    _emitLine('warmups=$_warmups trials=$_trials unit=us isolate=UI');
    _emitLine(
      'cold=unique_comment_before_svg_close document_cache=empty_before_each_call',
    );
    _emitLine(
      'timed=entry_point_only excludes=io,decode,comment,cache_clear,node_count',
    );
    _emitLine(
      'nodes=root_tree_including_root excludes=separate_clipPaths_and_masks',
    );
    _emitLine(
      'summary=distribution_and_sum_of_file_medians percentiles=rounded_index',
    );
    try {
      final directory = Directory(_corpusDir);
      if (!await directory.exists()) {
        throw FileSystemException(
          'Corpus directory does not exist',
          _corpusDir,
        );
      }
      final files = await directory
          .list(followLinks: false)
          .where(
            (entry) =>
                entry is File && entry.path.toLowerCase().endsWith('.svg'),
          )
          .cast<File>()
          .toList();
      files.sort((a, b) => a.path.compareTo(b.path));
      if (files.isEmpty) {
        throw FileSystemException(
          'Corpus directory contains no *.svg files',
          _corpusDir,
        );
      }
      _emitLine('corpus_files=${files.length}');
      for (final file in files) {
        final name = file.uri.pathSegments.last;
        if (mounted) setState(() => _progress = name);
        await Future<void>.delayed(Duration.zero);
        try {
          final bytes = await file.readAsBytes();
          final source = utf8.decode(bytes);
          final closeOffset = source.lastIndexOf(_svgClose);
          if (closeOffset < 0)
            throw FormatException('Missing closing $_svgClose tag');
          final cached = _measure(
            source,
            closeOffset,
            (src) => XvgDocumentCache.instance.getOrParse(src).document,
          );
          final direct = _measure(
            source,
            closeOffset,
            parseAnimatedSvgDocument,
          );
          _cacheMedians.add(Duration(microseconds: cached.stats.p50Us.toInt()));
          _directMedians.add(
            Duration(microseconds: direct.stats.p50Us.toInt()),
          );
          _emitLine(
            'FILE name=${jsonEncode(name)} bytes=${bytes.length} nodes=${cached.nodes} '
            '${_cachePath}_median_us=${cached.stats.p50Us.toInt()} '
            '${_cachePath}_max_us=${cached.stats.maxUs.toInt()} '
            '${_directPath}_median_us=${direct.stats.p50Us.toInt()} '
            '${_directPath}_max_us=${direct.stats.maxUs.toInt()}',
          );
        } catch (error) {
          _reportError(error, file: name);
        } finally {
          XvgDocumentCache.instance.clear();
        }
      }
      _reportSummary(_cachePath, _cacheMedians);
      _reportSummary(_directPath, _directMedians);
    } catch (error) {
      _reportError(error);
    }
    _emitLine(
      'status=${_errors == 0 ? 'ok' : 'error'} measured_files=${_cacheMedians.length} errors=$_errors',
    );
    _emitLine('=== END ANIM PARSE BENCH REPORT ===');
    if (mounted)
      setState(
        () => _progress = _errors == 0 ? 'done' : 'failed: $_errors error(s)',
      );
    if (autoExitAfterReport) exit(_errors == 0 ? 0 : 1);
  }

  /// Shows the active file and leaves the final result visible without AUTOEXIT.
  ///
  /// 显示当前文件；未启用 AUTOEXIT 时保留最终状态。
  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(child: Center(child: Text('anim_parse: $_progress'))),
  );
}
