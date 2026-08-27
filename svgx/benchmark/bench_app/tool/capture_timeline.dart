// Captures a real VM/Engine timeline from a running `flutter run --profile`
// session via the Dart VM Service protocol (the same data DevTools' timeline
// view visualizes), then summarizes which named slices dominate total time —
// used to find out where anim_fps's ~130ms/frame raster cost is actually
// going, instead of continuing to guess-and-check with more A/B toggles.
//
// Usage:
//   dart run tool/capture_timeline.dart <vm-service-uri> [captureSeconds] [outFile]
//
// <vm-service-uri> is the `http://127.0.0.1:PORT/TOKEN=/` URL `flutter run`
// prints as "A Dart VM Service ... is available at:". This script converts it
// to a websocket URI itself.
//
// 通过 Dart VM Service 协议（DevTools 时间线视图背后用的同一份数据），从一个
// 正在跑的 `flutter run --profile` 会话里抓取真实 VM/引擎时间线，汇总哪些
// 具名 slice 占用时间最多——用于查清 anim_fps 每帧 ~130ms raster 耗时到底花在
// 哪，而不是继续靠一个个 A/B 开关猜测。
//
// 用法：
//   dart run tool/capture_timeline.dart <vm-service-uri> [捕获秒数] [输出文件]
//
// <vm-service-uri> 是 `flutter run` 打印的 "A Dart VM Service ... is
// available at:" 那个 `http://127.0.0.1:端口/TOKEN=/` URL。本脚本自己转换成
// websocket URI。

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln(
      'Usage: dart run tool/capture_timeline.dart <vm-service-uri> '
      '[captureSeconds=25] [outFile=timeline.json]\n'
      '   or: dart run tool/capture_timeline.dart --summarize <jsonFile> '
      '(re-summarize an already-captured trace, no device needed)',
    );
    exit(64);
  }
  if (args[0] == '--summarize') {
    final saved =
        jsonDecode(await File(args[1]).readAsString()) as Map<String, dynamic>;
    _summarizeRaw((saved['traceEvents'] as List).cast<Map<String, dynamic>>());
    return;
  }
  final httpUri = Uri.parse(args[0]);
  final captureSeconds = args.length > 1 ? int.parse(args[1]) : 25;
  final outFile = args.length > 2 ? args[2] : 'timeline.json';

  // Flutter prints an http(s) observatory/DDS URL; the VM service protocol
  // itself speaks websocket at the same host/port/path with an `ws` scheme.
  //
  // Flutter 打印的是 http(s) 的 observatory/DDS URL；VM Service 协议本身在
  // 同一 host/port/path 下用 `ws` scheme 走 websocket。
  final wsUri = httpUri.replace(
    scheme: httpUri.scheme == 'https' ? 'wss' : 'ws',
    path: '${httpUri.path}ws',
  );

  stdout.writeln('Connecting to $wsUri ...');
  final service = await vmServiceConnectUri(wsUri.toString());

  final flags = await service.getVMTimelineFlags();
  final available = flags.availableStreams ?? const <String>[];
  stdout.writeln('Available timeline streams: $available');
  await service.setVMTimelineFlags(available);

  stdout.writeln(
    'Recording for ${captureSeconds}s — run the anim_fps benchmark now if '
    "it isn't already running...",
  );
  await Future<void>.delayed(Duration(seconds: captureSeconds));

  final timeline = await service.getVMTimeline();
  final events = timeline.traceEvents ?? const <dynamic>[];
  stdout.writeln('Captured ${events.length} raw trace events.');

  final rawEvents = [for (final e in events) (e as TimelineEvent).json!];
  final jsonOut = jsonEncode({'traceEvents': rawEvents});
  await File(outFile).writeAsString(jsonOut);
  stdout.writeln(
    'Wrote raw trace to $outFile (loadable in Perfetto/DevTools).',
  );

  _summarizeRaw(rawEvents);

  await service.dispose();
}

/// The coarse pipeline phases the framework/engine wrap their work in. A
/// slice's cost is attributed to the innermost of these on its stack, which is
/// what turns "BUILD cost 14ms" into "of BUILD's 14ms, this much was
/// `SvgXAnimated` and this much was `RenderObjectToWidgetAdapter`".
///
/// 框架/引擎用来包裹各阶段工作的粗粒度阶段名。每个 slice 的开销归属到其调用栈上
/// 最内层的这些阶段之一——正是这一步把"BUILD 花了 14ms"变成"BUILD 的 14ms 里，
/// 这么多是 `SvgXAnimated`，这么多是 `RenderObjectToWidgetAdapter`"。
const Set<String> _phaseNames = {
  'BUILD',
  'LAYOUT',
  'UPDATING COMPOSITING BITS',
  'PAINT',
  'COMPOSITING',
  'SEMANTICS',
  'FINALIZE TREE',
  'Animate',
  'Frame',
  'PipelineItem',
  'Rasterizer::DoDraw',
  'Rasterizer::DrawToSurfaces',
};

/// One named slice's accumulated cost, split into total (self+descendants) and
/// self (total minus direct children) time.
///
/// Why self time is the number that matters here: the old summarizer only
/// summed total time, which double-counts every level of nesting — `Frame`
/// necessarily "costs" more than everything inside it, and a widget high in the
/// tree bills for its whole subtree. A ranking by total time therefore always
/// reports the outermost slices, which is precisely the coarse answer the build
/// phase already had. Self time is additive across the whole trace (every
/// microsecond is charged to exactly one slice), so a self-time ranking is a
/// genuine "where did the time go" breakdown.
///
/// 一个具名 slice 累计的开销，分为 total（自身+全部后代）与 self（total 减去直接
/// 子级）两部分。
///
/// 为什么这里真正要看的是 self time：旧版汇总只累加 total，会把每一层嵌套重复
/// 计算——`Frame` 的"开销"必然大于它内部的一切，而树上层的控件要为它整个子树买
/// 单。因此按 total 排序永远只会报出最外层的 slice，而那恰恰就是 build 阶段本来
/// 就已经有的粗粒度答案。self time 在整条 trace 上是可加的（每一微秒都恰好记在
/// 一个 slice 上），所以按 self time 排序才是真正的"时间去哪了"分解。
class _SliceStat {
  double totalUs = 0;
  double selfUs = 0;
  int count = 0;
}

/// A slice currently open on a (pid, tid) stack, accumulating how much of its
/// span its direct children have claimed.
///
/// 当前在某个 (pid, tid) 栈上打开的 slice，累加其直接子级已经占去多少跨度。
class _OpenSlice {
  _OpenSlice(this.name, this.startTs, this.phase);

  final String name;
  final num startTs;

  /// Innermost enclosing phase at the moment this slice opened (this slice
  /// itself if it is a phase).
  ///
  /// 本 slice 打开那一刻最内层的包裹阶段（若本 slice 自己就是阶段，则是它自己）。
  final String phase;

  /// Summed duration of direct children, subtracted to get self time.
  ///
  /// 直接子级的耗时之和，用于减出 self time。
  double childUs = 0;
}

/// Sums slice durations by (thread, phase, name) with self-time attribution,
/// then prints per-phase breakdowns ranked by self time.
///
/// Handles both complete ('X', carries `dur`) and begin/end ('B'/'E', paired
/// per (pid,tid) stack) events, and reads 'M' metadata events so threads are
/// labelled `io.flutter.ui` / `io.flutter.raster` instead of raw tids — without
/// that, UI-thread and raster-thread work land in the same bucket and a build
/// attribution is impossible.
///
/// Caveat, stated rather than papered over: an 'X' event's own nested children
/// cannot be recovered from the flat list (there is no end marker to pair
/// against), so an 'X' slice's self time is reported as its full duration. The
/// framework's build/layout/paint instrumentation is all 'B'/'E' (it goes
/// through `dart:developer`'s `Timeline.startSync`), so this only affects
/// engine-side C++ slices.
///
/// 按 (线程, 阶段, 名称) 累加 slice 耗时并做 self-time 归因，然后按 self time
/// 排序打印每个阶段的分解。
///
/// 同时处理 complete 事件（'X'，自带 `dur`）与 begin/end 事件（'B'/'E'，按
/// (pid,tid) 栈配对），并读取 'M' 元数据事件，使线程显示为 `io.flutter.ui` /
/// `io.flutter.raster` 而非裸 tid——没有这一步，UI 线程与 raster 线程的工作会落进
/// 同一个桶，也就无从谈起 build 归因。
///
/// 需要如实说明的局限：'X' 事件自身的嵌套子级无法从平铺列表中还原（没有配对的
/// 结束标记），因此 'X' slice 的 self time 按其完整耗时上报。框架的
/// build/layout/paint 埋点全部是 'B'/'E'（走 `dart:developer` 的
/// `Timeline.startSync`），所以这只影响引擎侧的 C++ slice。
///
/// [events] — raw Chrome-trace-format events. / 原始 Chrome trace 格式事件。
void _summarizeRaw(List<Map<String, dynamic>> events) {
  // thread label per '$pid:$tid', from 'M'/thread_name metadata events.
  // 每个 '$pid:$tid' 的线程名，来自 'M'/thread_name 元数据事件。
  final threadNames = <String, String>{};
  for (final e in events) {
    if (e['ph'] == 'M' && e['name'] == 'thread_name') {
      final args = e['args'];
      if (args is Map && args['name'] is String) {
        threadNames['${e['pid']}:${e['tid']}'] = args['name'] as String;
      }
    }
  }

  // (thread, phase) -> name -> stat.
  final byPhase = <String, Map<String, _SliceStat>>{};
  final stacks = <String, List<_OpenSlice>>{};

  void record(
    String thread,
    String phase,
    String name,
    double dur,
    double self,
  ) {
    final bucket = byPhase.putIfAbsent('$thread | $phase', () => {});
    final stat = bucket.putIfAbsent(name, _SliceStat.new);
    stat
      ..totalUs += dur
      ..selfUs += self
      ..count += 1;
  }

  for (final e in events) {
    final ph = e['ph'] as String?;
    if (ph != 'X' && ph != 'B' && ph != 'E') continue;
    final name = e['name'] as String? ?? '(unnamed)';
    final ts = e['ts'] as num? ?? 0;
    final key = '${e['pid']}:${e['tid']}';
    final thread = threadNames[key] ?? 'tid $key';
    final stack = stacks[key] ??= <_OpenSlice>[];
    switch (ph) {
      case 'B':
        final phase = _phaseNames.contains(name)
            ? name
            : (stack.isEmpty ? '(no phase)' : stack.last.phase);
        stack.add(_OpenSlice(name, ts, phase));
      case 'E':
        if (stack.isEmpty) break;
        final open = stack.removeLast();
        final dur = (ts - open.startTs).toDouble();
        if (stack.isNotEmpty) stack.last.childUs += dur;
        record(thread, open.phase, open.name, dur, dur - open.childUs);
      case 'X':
        final dur = (e['dur'] as num? ?? 0).toDouble();
        if (stack.isNotEmpty) stack.last.childUs += dur;
        final phase = _phaseNames.contains(name)
            ? name
            : (stack.isEmpty ? '(no phase)' : stack.last.phase);
        record(thread, phase, name, dur, dur);
    }
  }

  // Phases are printed most-expensive first, by summed self time, so the
  // heaviest phase's breakdown is at the top instead of buried.
  // 阶段按 self time 之和从大到小打印，使最重阶段的分解排在最上而不是被埋掉。
  final phaseKeys = byPhase.keys.toList()
    ..sort((a, b) => _sumSelf(byPhase[b]!).compareTo(_sumSelf(byPhase[a]!)));

  stdout.writeln(
    '\n=== Self-time breakdown per (thread | phase), phases ranked by self time ===\n'
    'self_ms = time charged to this slice alone (children subtracted); it is\n'
    'additive, so a phase block\'s rows sum to that phase\'s cost.',
  );
  for (final phaseKey in phaseKeys) {
    final bucket = byPhase[phaseKey]!;
    final phaseSelfMs = _sumSelf(bucket) / 1000;
    if (phaseSelfMs < 0.5) continue; // noise floor / 噪声底噪
    stdout.writeln(
      '\n--- $phaseKey — ${phaseSelfMs.toStringAsFixed(2)} ms self total ---',
    );
    stdout.writeln(
      '${'name'.padRight(46)} ${'self_ms'.padLeft(9)} ${'pct'.padLeft(6)} '
      '${'total_ms'.padLeft(9)} ${'count'.padLeft(8)} ${'self_us/ea'.padLeft(11)}',
    );
    final rows = bucket.entries.toList()
      ..sort((a, b) => b.value.selfUs.compareTo(a.value.selfUs));
    for (final row in rows.take(18)) {
      final s = row.value;
      final pct = phaseSelfMs > 0 ? s.selfUs / 1000 / phaseSelfMs * 100 : 0;
      stdout.writeln(
        '${row.key.padRight(46)} '
        '${(s.selfUs / 1000).toStringAsFixed(2).padLeft(9)} '
        '${pct.toStringAsFixed(1).padLeft(5)}% '
        '${(s.totalUs / 1000).toStringAsFixed(2).padLeft(9)} '
        '${s.count.toString().padLeft(8)} '
        '${(s.selfUs / s.count).toStringAsFixed(2).padLeft(11)}',
      );
    }
  }
}

/// Total self time across every slice in [bucket], in microseconds.
///
/// [bucket] 中所有 slice 的 self time 之和（微秒）。
double _sumSelf(Map<String, _SliceStat> bucket) =>
    bucket.values.fold<double>(0, (sum, s) => sum + s.selfUs);
