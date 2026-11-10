import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/bench/proc_cpu.dart';
import '../../tool/bench/response_writer.dart';

/// 验证 STEADY 归因、设备编排和入场 trace 的真实保存契约。
void main() {
  group('bench STEADY', () {
    test(
        'marks validated proc deltas explicitly valid for device orchestration',
        () {
      final snapshot = File('tool/bench/fixtures/proc_buffered_android16.txt')
          .readAsStringSync();
      final result = compareProcSnapshots(snapshot, snapshot, 5);
      expect(result['valid_cpu'], isTrue);
      expect(result['process_cpu_percent'], 0);
      expect(result['threads'], isNotEmpty);
      expect(() => compareProcSnapshots(snapshot, 'permission denied', 5),
          throwsFormatException);
    });

    test('attributes paired frames without nested double counting', () async {
      final result = await Process.run(
          'python', ['tool/bench/analyze_steady.py', '--self-test']);
      expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
      expect(result.stderr, contains('Ran 3 tests'));
      expect(result.stderr, contains('OK'));
    });

    test(
        'plans four instrumented scenes and proc wheel CPU with bounded starts',
        () async {
      final result = await Process.run('powershell', [
        '-NoProfile',
        '-File',
        'tool/bench/run_steady_device_checks.ps1',
        '-PlanOnly',
      ]);
      expect(result.exitCode, 0, reason: '${result.stderr}');
      final plan = jsonDecode(result.stdout as String) as Map<String, dynamic>;
      expect(plan['scenes'], [
        'slot_raster',
        'grid_steady',
        'lotto_draw',
        'lots_shaking',
        'cpu_wheel_steady'
      ]);
      expect(plan['rounds'], 3);
      expect(plan['max_starts'], 5);
      expect(plan['timeline'], isTrue);
      expect(plan['entry_trace'], isTrue);
      expect(plan['cpu_sampler'], 'proc_cpu_sampler.dart');
      expect(plan['settings_modified'], isFalse);
    });

    test('keeps slot entry trace separate from steady GC reference', () async {
      final directory = await Directory.systemTemp.createTemp('ld_steady_');
      addTearDown(() => directory.delete(recursive: true));
      const key = 'slot_raster_entry_reference';
      final timeline = <String, dynamic>{
        'traceEvents': <Map<String, Object?>>[
          {'name': 'luckdraw.raster.atlas', 'ph': 'X', 'ts': 10, 'dur': 123}
        ]
      };
      final paths = await saveBenchResponse(
          {
            key: timeline,
            'bench_samples': <String, dynamic>{
              key: <String, dynamic>{'frame_count': 1}
            }
          },
          directory,
          'steady-entry',
          (_) => {
                'frame_build_times': [123]
              });
      expect(paths, hasLength(1));
      final summary = jsonDecode(await File(paths.single).readAsString())
          as Map<String, dynamic>;
      expect(summary['actual_scene'], key);
      expect(summary['report_key'], 'reference_spin');
      expect(summary['frame_count'], 1);
      expect(summary.containsKey('extra_new_gen_gc_count'), isFalse);
      final saved = jsonDecode(
          await File('${directory.path}/${key}_steady-entry.timeline.json')
              .readAsString());
      expect(saved, timeline);
    });
  });
}
