import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show FramePhase, FrameTiming;
import 'package:flutter/scheduler.dart';
import 'package:mova/mova.dart';
import '../main_coverage_api.dart' as c;

Future<int?> readInt(String path) async {
  try {
    return int.tryParse((await File(path).readAsString()).trim());
  } on FileSystemException {
    return null;
  }
}

/// Actual process counters; no assumed memory or power budget.
Future<Map<String, Object?>> metrics() async {
  final values = <String, Object?>{
    'rss': ProcessInfo.currentRss,
    'pid': pid,
    'threads': null,
    'handles': null,
    'cpuTicks': null,
  };
  try {
    if (Platform.isWindows) {
      final command =
          r'$probe=Get-Process -Id '
          '$pid'
          r'; [pscustomobject]@{threads=$probe.Threads.Count;handles=$probe.HandleCount;cpuTicks=$probe.TotalProcessorTime.Ticks}|ConvertTo-Json -Compress';
      final result = await Process.run('powershell.exe', [
        '-NoProfile',
        '-NonInteractive',
        '-WindowStyle',
        'Hidden',
        '-Command',
        command,
      ]);
      if (result.exitCode == 0) {
        values.addAll(
          Map<String, Object?>.from(jsonDecode('${result.stdout}') as Map),
        );
      } else {
        values['counterError'] = '${result.stderr}';
      }
    } else if (Platform.isAndroid || Platform.isLinux) {
      values['threads'] = await Directory('/proc/self/task').list().length;
      values['handles'] = await Directory('/proc/self/fd').list().length;
      final raw = await File('/proc/self/stat').readAsString();
      final fields = raw
          .substring(raw.lastIndexOf(')') + 2)
          .trim()
          .split(RegExp(r'\s+'));
      values['cpuTicks'] = int.parse(fields[11]) + int.parse(fields[12]);
    }
  } on Object catch (error) {
    values['counterError'] = '$error';
  }
  values['power'] = {
    'chargeCounter': await readInt(
      '/sys/class/power_supply/battery/charge_counter',
    ),
    'energyNow': await readInt('/sys/class/power_supply/battery/energy_now'),
    'currentNow': await readInt('/sys/class/power_supply/battery/current_now'),
    'voltageNow': await readInt('/sys/class/power_supply/battery/voltage_now'),
  };
  return values;
}

void sample(
  String id,
  Map<String, Object?> before,
  Map<String, Object?> after, {
  int? created,
  int? engineCount,
}) {
  final known = [
    'rss',
    'threads',
    'handles',
    'cpuTicks',
  ].every((k) => before[k] is int && after[k] is int);
  c.mark('CHECK', {
    'id': id,
    'origin': 'native-process-counters',
    'numbers': {
      'before': before,
      'after': after,
      'created': created,
      'engineCount': engineCount,
    },
    'pass': known
        ? (created == null || created <= 3) &&
              (engineCount == null || engineCount <= 3) &&
              (after['rss'] as int) > 0 &&
              (after['threads'] as int) > 0 &&
              (after['handles'] as int) > 0 &&
              (after['cpuTicks'] as int) >= (before['cpuTicks'] as int)
        : null,
  });
}

/// Covers disposal with real engine FrameTiming data, including delivery of
/// the first post-disposal frame. Deadlines only detect unavailable evidence.
class DisposeFrames {
  final frames = <FrameTiming>[];
  late final Ticker ticker;
  int end = 0;
  Completer<void>? delivered;
  void onTimings(List<FrameTiming> batch) {
    frames.addAll(batch);
    if (delivered != null &&
        !delivered!.isCompleted &&
        batch.any(
          (f) => f.timestampInMicroseconds(FramePhase.vsyncStart) >= end,
        )) {
      delivered!.complete();
    }
  }

  Future<void> run(Future<void> Function() dispose) async {
    SchedulerBinding.instance.addTimingsCallback(onTimings);
    ticker = Ticker((_) {})..start();
    try {
      await SchedulerBinding.instance.endOfFrame;
      final start =
          SchedulerBinding.instance.currentSystemFrameTimeStamp.inMicroseconds;
      await dispose();
      await SchedulerBinding.instance.endOfFrame;
      end =
          SchedulerBinding.instance.currentSystemFrameTimeStamp.inMicroseconds;
      delivered = Completer<void>();
      if (frames.any(
        (f) => f.timestampInMicroseconds(FramePhase.vsyncStart) >= end,
      )) {
        delivered!.complete();
      }
      try {
        await delivered!.future.timeout(const Duration(seconds: 10));
      } on TimeoutException {
        /* Unknown coverage, never a successful duration. */
      }
      final window = frames.where((f) {
        final stamp = f.timestampInMicroseconds(FramePhase.vsyncStart);
        return stamp >= start && stamp <= end;
      }).toList();
      final spans = window.map((f) => f.totalSpan.inMicroseconds).toList();
      final stamps =
          frames
              .map((f) => f.timestampInMicroseconds(FramePhase.vsyncStart))
              .toSet()
              .toList()
            ..sort();
      final previous = stamps.where((v) => v <= start).toList();
      final following = stamps.where((v) => v >= end).toList();
      final coveredStart = previous.isNotEmpty;
      final coveredEnd = following.isNotEmpty && delivered!.isCompleted;
      final covered = <int>{
        if (coveredStart) previous.last,
        ...stamps.where((v) => v >= start && v <= end),
        if (coveredEnd) following.first,
      }.toList()..sort();
      final gaps = <int>[
        for (var i = 1; i < covered.length; i++) covered[i] - covered[i - 1],
      ];
      c.mark('CHECK', {
        'id': 'F13.disposeFrames',
        'origin': 'flutter-native-frame-timings',
        'numbers': {
          'startVsyncUs': start,
          'endVsyncUs': end,
          'coveredThroughEnd': delivered!.isCompleted,
          'coveredThroughStart': coveredStart,
          'frameVsyncUs': covered,
          'frameGapsUs': gaps,
          'gapCount': gaps.length,
          'frameCount': spans.length,
          'frameSpansUs': spans,
          'maxFrameUs': spans.isEmpty
              ? null
              : spans.reduce((a, b) => a > b ? a : b),
        },
        'pass': !coveredStart || !coveredEnd || spans.isEmpty || gaps.isEmpty
            ? null
            : gaps.every((n) => n < 100000),
      });
    } finally {
      ticker.dispose();
      SchedulerBinding.instance.removeTimingsCallback(onTimings);
    }
  }
}

Future<void> audioResources() async {
  final reports = <MovaReportEvent>[];
  final positions = <int>[];
  final a = createMovaEngine(
    audioOnly: true,
    preciseFirstFrame: true,
    options: const MovaOpts(report: MovaReportConfig(qoe: true)),
    reporter: MovaCallbackReporter(reports.add),
  );
  final sub = a.progress.listen(
    (p) => positions.add(p.position.inMilliseconds),
  );
  c.observe(a);
  c.screen.value = a;
  try {
    final before = await metrics();
    await a.open(c.source());
    await c.until(() => positions.where((p) => p > 0).length >= 10);
    final after = await metrics();
    sample('F12.audioCounters', before, after);
    final starts = reports
        .where((r) => r.name == MovaReportName.sessionStart)
        .toList();
    c.mark('CHECK', {
      'id': 'F9.nativeAudio',
      'origin': 'native-audio-only',
      'numbers': {
        'renderHandleNull': a.renderHandle == null,
        'width': a.state.width,
        'height': a.state.height,
        'playing': a.state.playing,
        'positions': positions,
        'progressSamples': positions.length,
        'sessionAudioOnly': starts.isEmpty
            ? null
            : starts.single.params['audioOnly'],
      },
      'pass': starts.isEmpty
          ? null
          : a.renderHandle == null &&
                a.state.width == 0 &&
                a.state.height == 0 &&
                a.state.playing &&
                starts.single.params['audioOnly'] == true,
    });
    c.mark('S00D_POWER', {
      'before': before['power'],
      'after': after['power'],
      'missing': '需可读电荷/能量计与受控对照；进程 RSS/CPU 不等于设备耗电。',
    });
  } finally {
    await sub.cancel();
    await a.dispose();
    c.screen.value = null;
  }
}
