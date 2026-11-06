import 'dart:async';
import 'package:mova/mova.dart';
import 'package:mova/testing.dart';
import '../main_coverage_api.dart' as c;

Future<void> turn() => Future<void>.delayed(Duration.zero);
void measured(String id, Object? actual, Object? expected) {
  c.mark('CHECK', {
    'id': id,
    'pass': actual == expected,
    'actual': actual,
    'expected': expected,
    'origin': 'public-testing-kernel',
  });
}

Future<void> run() async {
  await seekRetry();
  await reportedErrors();
  for (final native in [false, true]) {
    for (final end in [
      'ended',
      'stopped',
      'failed',
      'abandoned',
      'truncated',
      'disabled',
    ]) {
      final k = MovaTestKernel(nativeRestartAvailable: native);
      final reports = <MovaReportEvent>[];
      final a = MovaEngine(
        kernel: k,
        options: MovaOpts(
          report: MovaReportConfig(
            qoe: true,
            minStall: Duration.zero,
            truncatedBelow: end == 'disabled' ? 0 : .9,
          ),
        ),
        reporter: MovaCallbackReporter(reports.add),
      );
      final prefix = 'F7.$native.$end';
      try {
        await a.open(const MovaSource('s00d://qoe', title: 'S00D qoe'));
        k.emitDuration(const Duration(seconds: 100));
        await turn();
        k.emitPlaying(true);
        await turn();
        if (end != 'abandoned') {
          // With native live, buffering/position must not land reporter TTFF.
          k.emitBuffering(true);
          await turn();
          k.emitBuffering(false);
          await turn();
          if (native) {
            measured(
              '$prefix.beforeRestart',
              reports.where((r) => r.name == MovaReportName.firstFrame).length,
              0,
            );
          }
          k.emitRestart();
          await turn();
          final frames = reports
              .where((r) => r.name == MovaReportName.firstFrame)
              .toList();
          measured('$prefix.firstFrameCount', frames.length, 1);
          if (frames.isNotEmpty) {
            final f = frames.single;
            c.mark('CHECK', {
              'id': '$prefix.firstFrame',
              'pass': f.params['signal'] == (native ? 'restart' : 'buffering'),
              'numbers': f.params,
              'sessionId': f.sessionId,
              'origin': 'public-testing-kernel',
            });
            measured(
              '$prefix.signal',
              f.params['signal'],
              native ? 'restart' : 'buffering',
            );
            measured('$prefix.ttffNumber', f.params['ttffMs'] is int, true);
            measured('$prefix.sessionId', f.sessionId?.isNotEmpty, true);
          }
          k.emitStalling(true);
          await turn();
          k.emitStalling(false);
          await turn();
          k.emitPosition(
            Duration(
              seconds: end == 'truncated' || end == 'disabled' ? 10 : 100,
            ),
          );
          await turn();
        }
        if (end == 'failed') {
          k.emitEndFile(MovaEndFileReason.error);
          await turn();
        }
        if (['ended', 'truncated', 'disabled'].contains(end)) {
          k.emitCompleted(true);
          await turn();
        }
        await a.dispose();
        await turn();
        final ends = reports
            .where((r) => r.name == MovaReportName.sessionEnd)
            .toList();
        measured('$prefix.endCount', ends.length, 1);
        if (ends.isNotEmpty) {
          final r = ends.single;
          c.mark('CHECK', {
            'id': '$prefix.summary',
            'pass':
                r.params['reason'] ==
                (end == 'truncated'
                    ? 'failed'
                    : end == 'disabled'
                    ? 'ended'
                    : end),
            'numbers': r.params,
            'sessionId': r.sessionId,
            'origin': 'public-testing-kernel',
          });
          measured(
            '$prefix.reason',
            r.params['reason'],
            end == 'truncated'
                ? 'failed'
                : end == 'disabled'
                ? 'ended'
                : end,
          );
          measured(
            '$prefix.stallCount',
            r.params['stallCount'],
            end == 'abandoned' ? 0 : 1,
          );
          measured(
            '$prefix.fields',
            [
              'watchedMs',
              'stallMs',
              'rebufferRate',
            ].every((key) => r.params[key] is num),
            true,
          );
          measured('$prefix.sessionId', r.sessionId?.isNotEmpty, true);
        }
        measured(
          '$prefix.truncated',
          reports.where((r) => r.params['code'] == 'truncated').length,
          end == 'truncated' ? 1 : 0,
        );
        for (final r in reports) {
          c.mark('S00D_REPORT', {
            'case': prefix,
            'name': r.name.value,
            'params': r.params,
            'sessionId': r.sessionId,
            'kindValue': r.kind.name,
            'priority': r.priority.name,
          });
        }
      } finally {
        await a.dispose();
      }
    }
  }
  final reports = <MovaReportEvent>[];
  final k = MovaTestKernel();
  final a = MovaEngine(
    kernel: k,
    options: const MovaOpts(
      report: MovaReportConfig(
        qoe: true,
        heartbeat: Duration(milliseconds: 10),
      ),
    ),
    reporter: MovaCallbackReporter(reports.add),
  );
  try {
    await a.open(const MovaSource('s00d://heartbeat'));
    k.emitPlaying(true);
    await turn();
    k.emitRestart();
    await turn();
    await c.until(() => reports.any((r) => r.name == MovaReportName.heartbeat));
    measured(
      'F7.heartbeat',
      reports.where((r) => r.name == MovaReportName.heartbeat).isNotEmpty,
      true,
    );
    const custom = MovaReportName.custom('s00d.custom');
    a.report(custom, params: {'probe': 17});
    measured(
      'N23.custom',
      reports.where((r) => r.name == custom).single.params['probe'],
      17,
    );
  } finally {
    await a.dispose();
  }
  for (final prefix in [
    'stream',
    'file',
    'ffmpeg',
    'vd',
    'ad',
    'cplayer',
    'other',
  ]) {
    for (final after in [false, true]) {
      final r = const MovaPrefixError().classify(
        'S00D error',
        subsystem: prefix,
        afterFirstFrame: after,
      );
      final expected = {
        'stream': true,
        'file': true,
        'ffmpeg': !after,
        'vd': false,
        'ad': false,
        'cplayer': true,
        'other': false,
      };
      measured('N23.policy.$prefix.$after', r.fatal, expected[prefix]);
    }
  }
}

class DropSeekKernel extends MovaTestKernel {
  DropSeekKernel(this.drops);
  final int drops;
  final targets = <int>[];
  @override
  Future<void> seek(Duration position) async {
    await super.seek(position);
    targets.add(position.inMilliseconds);
    if (targets.length > drops) {
      emitPosition(position);
    } else {
      emitPosition(Duration.zero);
    }
  }
}

class ScriptTimer implements Timer {
  ScriptTimer(this.callback);
  final void Function() callback;
  bool active = true;
  int ticks = 0;
  @override
  bool get isActive => active;
  @override
  int get tick => ticks;
  @override
  void cancel() {
    active = false;
  }

  void fire() {
    if (!active) {
      return;
    }
    active = false;
    ticks++;
    callback();
  }
}

Future<void> seekRetry() async {
  for (final drops in [0, 1, 2, 100]) {
    final timers = <ScriptTimer>[];
    await runZoned(
      () async {
        Future<void> microtasks() async {
          for (var i = 0; i < 40; i++) {
            await Future<void>.value();
          }
        }

        final k = DropSeekKernel(drops);
        final a = MovaEngine(kernel: k);
        final progress = <int>[];
        final sub = a.progress.listen(
          (p) => progress.add(p.position.inMilliseconds),
        );
        try {
          await a.open(const MovaSource('s00d://drop-seek'));
          a.hideControls(); // Cancel the unrelated controls timer.
          k.emitDuration(const Duration(seconds: 100));
          await microtasks();
          await a.seek(const Duration(seconds: 12));
          await microtasks();
          var dispatched = 0;
          while (timers.any((t) => t.isActive) && dispatched < 64) {
            final next = timers.firstWhere((t) => t.isActive);
            next.fire();
            dispatched++;
            await microtasks();
          }
          final settled = !timers.any((t) => t.isActive);
          final expectedCalls = drops < 3 ? drops + 1 : 3;
          c.mark('CHECK', {
            'id': 'A7.retry.$drops',
            'pass': settled && k.targets.length == expectedCalls,
            'actual': List.of(k.targets),
            'expected': List.filled(expectedCalls, 12000),
            'origin': 'public-testing-kernel',
            'numbers': {
              'drops': drops,
              'calls': k.targets.length,
              'progress': progress,
              'settled': settled,
              'dispatchedTimers': dispatched,
            },
          });
        } finally {
          await sub.cancel();
          await a.dispose();
        }
      },
      zoneSpecification: ZoneSpecification(
        createTimer: (self, parent, zone, duration, callback) {
          final timer = ScriptTimer(callback);
          timers.add(timer);
          return timer;
        },
      ),
    );
  }
}

class LogKernel extends MovaTestKernel {
  LogKernel() : super(nativeRestartAvailable: true);
  final lines = StreamController<MovaLogLine>.broadcast();
  @override
  Stream<MovaLogLine> get logs => lines.stream;
  @override
  Future<void> dispose() async {
    await lines.close();
    await super.dispose();
  }
}

Future<void> reportedErrors() async {
  const codes = {
    'stream': 'stream',
    'file': 'file',
    'ffmpeg': 'network',
    'vd': 'decode.video',
    'ad': 'decode.audio',
    'cplayer': 'player',
    'other': 'unknown',
  };
  for (final prefix in codes.keys) {
    for (final after in [false, true]) {
      final k = LogKernel();
      final reports = <MovaReportEvent>[];
      final a = MovaEngine(
        kernel: k,
        options: const MovaOpts(report: MovaReportConfig(qoe: true)),
        reporter: MovaCallbackReporter(reports.add),
      );
      try {
        await a.open(const MovaSource('s00d://error-report'));
        await turn();
        if (after) {
          k.emitRestart();
          await turn();
        }
        k.lines.add(
          MovaLogLine(prefix: prefix, level: 'error', text: 'S00D failure'),
        );
        await turn();
        k.emitError('S00D failure');
        await turn();
        final errors = reports
            .where((r) => r.name == MovaReportName.error)
            .toList();
        final fatal =
            prefix == 'stream' ||
            prefix == 'file' ||
            prefix == 'cplayer' ||
            (prefix == 'ffmpeg' && !after);
        final r = errors.isEmpty ? null : errors.last;
        c.mark('CHECK', {
          'id': 'N23.error.$prefix.$after',
          'origin': 'public-testing-kernel',
          'numbers': {
            'count': errors.length,
            'params': r?.params,
            'kindValue': r?.kind.name,
            'priority': r?.priority.name,
            'sessionId': r?.sessionId,
          },
          'pass': r == null
              ? null
              : errors.length == 1 &&
                    r.params['fatal'] == fatal &&
                    r.params['code'] == codes[prefix],
        });
      } finally {
        await a.dispose();
      }
    }
  }
}
