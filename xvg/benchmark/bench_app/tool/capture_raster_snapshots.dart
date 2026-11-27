import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

/// Extracts Impeller snapshot slices from the running profile process. / 从运行中的 profile 进程提取 Impeller 快照切片。
Future<void> main(List<String> args) async {
  final uri = Uri.parse(stdin.readLineSync()!);
  final path = args.single;
  final service = await vmServiceConnectUri(
    uri.replace(scheme: 'ws', path: '${uri.path}ws').toString(),
  );
  await service.setVMTimelineFlags(['Embedder']);
  await File('$path.ready').writeAsString('ready');
  final output = File(path).openWrite();
  final seen = <(int, int)>{};
  const snapshot = 'DoMakeRasterSnapshot';
  var lower = 0;
  try {
    while (true) {
      final trace = await service.getVMTimeline(timeOriginMicros: lower);
      final active = <int, int>{};
      var last = lower;
      for (final value in trace.traceEvents ?? const <TimelineEvent>[]) {
        final event = value.json!;
        final time = event['ts'];
        if (time is! int) continue;
        if (time > last) last = time;
        if (event['name'] != snapshot) continue;
        final thread = event['tid'] as int;
        final phase = event['ph'];
        if (phase == 'B') active[thread] = time;
        final start = switch (phase) {
          'X' => time,
          'E' => active.remove(thread),
          _ => null,
        };
        if (start != null && seen.add((thread, start))) {
          final duration = phase == 'X' ? event['dur'] as int : time - start;
          output.writeln(jsonEncode([start, start + duration, thread]));
        }
      }
      await output.flush();
      final stop = File('$path.stop').existsSync();
      if (stop) break;
      if (last > lower + Duration.microsecondsPerSecond) {
        lower = last - Duration.microsecondsPerSecond;
      }
      await Future<void>.delayed(const Duration(milliseconds: 800));
    }
  } finally {
    await output.close();
    await service.dispose();
  }
}
