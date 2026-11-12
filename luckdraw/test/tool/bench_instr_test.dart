import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/bench/proc_cpu.dart';
import '../../tool/bench/response_writer.dart';

/// stat 合成夹具，字段位置与 Android16 原文一致；故意含空格和右括号。
String _stat(
        {String name = '1.ui (main)',
        int id = 123,
        int user = 10,
        int system = 5,
        int started = 99}) =>
    '$id ($name) S 1 2 3 4 5 6 7 8 9 10 $user $system 0 0 20 0 4 0 $started 0 0';

/// 完整快照，线程 comm 与 stat 的名字故意不同以验证读取 comm。
String _snapshot({int user = 10, int system = 5}) =>
    'HZ\t100\nPROCESS\t${_stat(user: user, system: system)}\n'
    'STAT\t${_stat(user: user, system: system)}\nCOMM\t123\t1.ui\n';

/// 只有一个冷窗口，原始 trace 故意没有 Raster 事件。
Map<String, dynamic> _response(
        {String key = 'wheel_first_frame', double value = 4}) =>
    {
      'bench_samples': <String, dynamic>{
        key: <String, dynamic>{'first_frame_ui_millis': value}
      },
      key: <String, dynamic>{
        'traceEvents': <Object?>[
          <String, Object?>{'name': 'luckdraw.wheel.layout', 'ph': 'B', 'ts': 1}
        ]
      },
    };

/// INSTR 纯解析与原始响应保存回归，不接触设备。
void main() {
  group('bench INSTR', () {
    test('actual buffered Android16 snapshots accept LF and Windows CRLF', () {
      // 检出时 autocrlf 可能已把夹具转成 CRLF，先归一化再构造 LF / CRLF 两种输入。
      final source = File('tool/bench/fixtures/proc_buffered_android16.txt')
          .readAsStringSync()
          .replaceAll('\r\n', '\n');
      for (final text in [source, source.replaceAll('\n', '\r\n')]) {
        final parsed = parseProcSnapshot(text);
        expect(parsed['hz'], 100);
        expect((parsed['process']! as ProcCpuStat).id, 15514);
        expect((parsed['names']! as Map<int, String>).values,
            containsAll(['Signal Catcher', '1.raster', '1.io']));
      }
    });
    test('parses actual Android16 thread snapshots including spaced comm', () {
      final snapshot = parseProcSnapshot(
          File('tool/bench/fixtures/proc_threads_android16.txt')
              .readAsStringSync());
      expect(snapshot['hz'], 100);
      final names = snapshot['names']! as Map<int, String>;
      expect(names.values, containsAll(['Signal Catcher', '1.raster', '1.io']));
      final process = snapshot['process']! as ProcCpuStat;
      expect(process.id, 8763);
      expect(process.user + process.system, 897);
    });
    test('buffered snapshots preserve counters and complete comm text', () {
      const comm = ' Signal Catcher (one)  ';
      final snapshot =
          'HZ\t100\nPROCESS\t${_stat()}\nTIDS\t123\nSTATS\n${_stat()}\nCOMMS\n$comm\n';
      final parsed = parseProcSnapshot(snapshot);
      expect((parsed['names']! as Map<int, String>)[123], comm);
      final legacy = parseProcSnapshot(
          _snapshot().replaceFirst('COMM\t123\t1.ui', 'COMM\t123\t$comm'));
      expect((legacy['names']! as Map<int, String>)[123], comm);
      expect((parsed['threads']! as Map<int, ProcCpuStat>)[123]!.user, 10);
      final result = compareProcSnapshots(
          snapshot, snapshot.replaceAll(' 10 5 ', ' 50 15 '), 5);
      expect(result['process_cpu_percent'], 10);
    });
    test('buffered snapshots reject changed thread sets and missing comm', () {
      final snapshot =
          'HZ\t100\nPROCESS\t${_stat()}\nTIDS\t123 456\nSTATS\n${_stat()}\nCOMMS\nSignal Catcher\n';
      expect(() => parseProcSnapshot(snapshot), throwsFormatException);
    });
    test('parses the actual Android16 proc stat fixture', () {
      final line = File('tool/bench/fixtures/proc_stat_android16.txt')
          .readAsStringSync();
      final stat = parseProcCpuStat(line);
      expect((stat.id, stat.name, stat.user, stat.system, stat.started),
          (4621, 'cat', 2, 2, 56064302));
    });
    test('parses Android16 stat with spaces and parentheses in comm', () {
      final stat = parseProcCpuStat(_stat());
      expect(stat.id, 123);
      expect(stat.name, '1.ui (main)');
      expect((stat.user, stat.system, stat.started), (10, 5, 99));
      expect(parseProcCpuStat(_stat(name: 'a) b ((x)')).name, 'a) b ((x)');
    });
    test('rejects malformed or negative stat counters explicitly', () {
      for (final value in [
        '',
        '12 (bad) S 1',
        _stat(user: -1),
        _stat().replaceFirst(' 99 ', ' nan ')
      ]) {
        expect(() => parseProcCpuStat(value), throwsFormatException);
      }
    });
    test('calculates single core percent from ticks and real host duration',
        () {
      expect(
          procCpuPercent(parseProcCpuStat(_stat()),
              parseProcCpuStat(_stat(user: 50, system: 15)), 5, 100),
          10);
      expect(
          procCpuPercent(parseProcCpuStat(_stat()),
              parseProcCpuStat(_stat(user: 1010)), 5, 100),
          200);
    });
    test('rejects PID reuse counter reversal and invalid duration', () {
      final before = parseProcCpuStat(_stat());
      for (final after in [
        _stat(id: 124),
        _stat(started: 100),
        _stat(user: 9)
      ]) {
        expect(() => procCpuPercent(before, parseProcCpuStat(after), 5, 100),
            throwsFormatException);
      }
      for (final seconds in [0.0, -1.0, double.nan]) {
        expect(() => procCpuPercent(before, before, seconds, 100),
            throwsFormatException);
      }
      expect(() => procCpuPercent(before, before, 5, 0), throwsFormatException);
    });
    test('reports process and named thread deltas without filling missing data',
        () {
      final report =
          compareProcSnapshots(_snapshot(), _snapshot(user: 50, system: 15), 5);
      expect(report['process_cpu_percent'], 10);
      expect(report['threads'], [
        <String, Object?>{'tid': 123, 'name': '1.ui', 'cpu_percent': 10.0}
      ]);
      expect(report['new_threads'], isEmpty);
      expect(report['exited_threads'], isEmpty);
    });
    test(
        'rejects permission errors incomplete snapshots and changed clock tick',
        () {
      expect(() => parseProcSnapshot('cat: Permission denied'),
          throwsFormatException);
      expect(
          () => parseProcSnapshot(_snapshot().replaceFirst('COMM\t', 'NO\t')),
          throwsFormatException);
      expect(
          () => compareProcSnapshots(
              _snapshot(), _snapshot().replaceFirst('100', '250'), 5),
          throwsFormatException);
    });
    test('saves raw response and timeline before a failing summary', () async {
      final directory = Directory.systemTemp.createTempSync('instr-response-');
      addTearDown(() => directory.deleteSync(recursive: true));
      final data = _response(key: 'grid_steady');
      await expectLater(
          saveBenchResponse(data, directory, 'fixture', (timeline) {
            expect(
                jsonDecode(File('${directory.path}/response_fixture.json')
                    .readAsStringSync()),
                data);
            expect(
                File('${directory.path}/grid_steady_fixture.timeline.json')
                    .existsSync(),
                isTrue);
            throw StateError(kBenchEmptyTimelineSummary);
          }),
          throwsStateError);
    });
    test('keeps cold FrameTiming when no complete Raster summary exists',
        () async {
      final directory = Directory.systemTemp.createTempSync('instr-cold-');
      addTearDown(() => directory.deleteSync(recursive: true));
      final paths = await saveBenchResponse(_response(), directory, 'fixture',
          (_) => throw StateError(kBenchEmptyTimelineSummary));
      final metrics = jsonDecode(File(paths.single).readAsStringSync())
          as Map<String, dynamic>;
      expect(metrics['first_frame_ui_millis'], 4);
      expect(metrics['sdk_summary_status'], 'unavailable');
      expect(
          metrics['sdk_summary_error'], contains(kBenchEmptyTimelineSummary));
      expect(
          metrics.containsKey('average_frame_rasterizer_time_millis'), isFalse);
    });
    test('does not mask cold windows without a valid measured first frame',
        () async {
      final directory = Directory.systemTemp.createTempSync('instr-invalid-');
      addTearDown(() => directory.deleteSync(recursive: true));
      await expectLater(
          saveBenchResponse(_response(value: 0), directory, 'fixture',
              (_) => throw StateError(kBenchEmptyTimelineSummary)),
          throwsStateError);
    });
    test('writes successful summaries with original metrics and response',
        () async {
      final directory = Directory.systemTemp.createTempSync('instr-success-');
      addTearDown(() => directory.deleteSync(recursive: true));
      final paths = await saveBenchResponse(_response(), directory, 'fixture',
          (_) => {'average_frame_build_time_millis': 7});
      final metrics = jsonDecode(File(paths.single).readAsStringSync())
          as Map<String, dynamic>;
      expect(metrics['average_frame_build_time_millis'], 7);
      expect(metrics['first_frame_ui_millis'], 4);
      expect(metrics['report_key'], 'wheel_first_frame');
      expect(metrics['run_id'], 'fixture');
    });
    test('does not hide unrelated cold timeline errors', () async {
      final directory = Directory.systemTemp.createTempSync('instr-errors-');
      addTearDown(() => directory.deleteSync(recursive: true));
      await expectLater(
          saveBenchResponse(_response(), directory, 'fixture',
              (_) => throw const FormatException('bad trace')),
          throwsFormatException);
      expect(
          File('${directory.path}/response_fixture.json').existsSync(), isTrue);
    });
    test('CPU frame summaries explicitly omit an unmeasured GC reference',
        () async {
      final directory = Directory.systemTemp.createTempSync('instr-cpu-');
      addTearDown(() => directory.deleteSync(recursive: true));
      final data = _response(key: 'wheel_steady')
        ..['cpu_scene'] = 'wheel_steady';
      final paths = await saveBenchResponse(
          data, directory, 'fixture', (_) => {'frame_count': 301});
      final metrics = jsonDecode(File(paths.single).readAsStringSync())
          as Map<String, dynamic>;
      expect(metrics['gc_reference_status'], 'not_measured_in_cpu_window');
      expect(metrics.containsKey('extra_new_gen_gc_count'), isFalse);
      expect(metrics['frame_count'], 301);
    });
  });
}
