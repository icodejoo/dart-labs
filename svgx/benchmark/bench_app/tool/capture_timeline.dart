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

  final rawEvents = [
    for (final e in events) (e as TimelineEvent).json!,
  ];
  final jsonOut = jsonEncode({'traceEvents': rawEvents});
  await File(outFile).writeAsString(jsonOut);
  stdout.writeln('Wrote raw trace to $outFile (loadable in Perfetto/DevTools).');

  _summarizeRaw(rawEvents);

  await service.dispose();
}

/// Sums durations by event name — handles both complete ('X', has `dur`
/// directly) and begin/end ('B'/'E', paired by (pid,tid) stack) events —
/// then prints the top time-consuming names.
///
/// 按事件名累加耗时——同时处理 complete 事件（'X'，自带 `dur`）与
/// begin/end 事件（'B'/'E'，按 (pid,tid) 栈配对），然后打印耗时最高的
/// 具名事件。
void _summarizeRaw(List<Map<String, dynamic>> events) {
  final totalsUs = <String, double>{};
  final counts = <String, int>{};
  // Stack of (name, startTs) per (pid, tid), for B/E pairing.
  // 按 (pid, tid) 维护的 (名称, 起始时间戳) 栈，用于 B/E 配对。
  final stacks = <String, List<MapEntry<String, num>>>{};

  void record(String name, num durUs) {
    totalsUs[name] = (totalsUs[name] ?? 0) + durUs;
    counts[name] = (counts[name] ?? 0) + 1;
  }

  for (final e in events) {
    final name = e['name'] as String? ?? '(unnamed)';
    final ph = e['ph'] as String?;
    final ts = e['ts'] as num? ?? 0;
    final pid = e['pid'];
    final tid = e['tid'];
    final key = '$pid:$tid';
    switch (ph) {
      case 'X':
        final dur = e['dur'] as num? ?? 0;
        record(name, dur);
      case 'B':
        (stacks[key] ??= []).add(MapEntry(name, ts));
      case 'E':
        final stack = stacks[key];
        if (stack != null && stack.isNotEmpty) {
          final start = stack.removeLast();
          record(start.key, ts - start.value);
        }
      default:
      // Instant/metadata/counter events carry no duration — skipped.
      // 瞬时/元数据/计数器事件没有持续时间——跳过。
    }
  }

  final sorted = totalsUs.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));

  stdout.writeln('\n=== Top time-consuming named slices (self+children time summed across all occurrences) ===');
  stdout.writeln(
    '${'name'.padRight(50)} ${'total_ms'.padLeft(10)} ${'count'.padLeft(8)} ${'avg_us'.padLeft(10)}',
  );
  for (final entry in sorted.take(40)) {
    final n = counts[entry.key]!;
    final totalMs = entry.value / 1000;
    final avgUs = entry.value / n;
    stdout.writeln(
      '${entry.key.padRight(50)} ${totalMs.toStringAsFixed(2).padLeft(10)} '
      '${n.toString().padLeft(8)} ${avgUs.toStringAsFixed(1).padLeft(10)}',
    );
  }
}
