import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

/// 本轮独立真机证据目录，不读取其它批次的合成样本。
const String _results = 'tool/bench/results/pending';

/// 读取已保存的实测审计对象，缺失证据直接失败。
Map<String, dynamic> _read(String path) =>
    jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

/// 核对 DEVFIN 实测与文档预算，失败采集不能静默变成性能通过。
void main() {
  group('bench DEVFIN', () {
    test('retains device identity fresh responses and every failed attempt',
        () {
      final audit = _read('$_results/audit.json');
      final session = audit['session'] as Map<String, dynamic>;
      expect(session['model'], 'V2417');
      expect(session['serial'], '10AE9K17UE0011S');
      expect(session['android'], '16');
      expect(session['phone_settings_modified'], isFalse);
      final started = DateTime.parse(session['started_at'] as String);
      final scenes = audit['scenes'] as Map<String, dynamic>;
      final raw = jsonDecode(File('$_results/runs.json').readAsStringSync())
          as List<dynamic>;
      var attempts = 0;
      for (final value in scenes.values) {
        final rows = value as List<dynamic>;
        expect(rows.length, inInclusiveRange(3, 5));
        attempts += rows.length;
        for (final value in rows) {
          final row = value as Map<String, dynamic>;
          expect(row['binary_sha256'], session['binary_sha256']);
          expect(DateTime.parse(row['started_at'] as String).isBefore(started),
              isFalse);
          final original = raw
              .cast<Map<String, dynamic>>()
              .singleWhere((source) => source['directory'] == row['directory']);
          expect(row['valid'], original['valid']);
          expect(row['error'], original['error']);
          if (row['device_metrics'] case final Map<String, dynamic> metrics) {
            expect(metrics['fps'] as num, greaterThan(0));
            expect(metrics['frame_count'] as num, greaterThan(0));
          }
          if (row.containsKey('device_response_at')) {
            final response =
                DateTime.parse(row['device_response_at'] as String);
            expect(response.isBefore(started), isFalse);
            final file = row['device_response_file'];
            expect(file, isA<String>());
            // 原始 response 单个 20MB 以上，已被 .gitignore 排除；本机有原件时再核对非空。
            final raw = File('$_results/$file');
            if (raw.existsSync()) expect(raw.lengthSync(), greaterThan(0));
          }
        }
      }
      expect(attempts, raw.length);
      expect(scenes, hasLength(13));
    });

    test('freezes signed cold frame increments without claiming design success',
        () {
      final cold =
          _read('$_results/audit.json')['cold_frames'] as Map<String, dynamic>;
      final status = _read('tool/bench/budgets.status.json')['devfin']
          as Map<String, dynamic>;
      final budgets =
          status['first_frame_increment_budgets_ms'] as Map<String, dynamic>;
      final blank = (cold['blank_first_frame']
          as Map<String, dynamic>)['median_ms'] as num;
      for (final scene in const [
        'wheel_first_frame',
        'grid_first_frame',
        'slot_first_frame'
      ]) {
        final row = cold[scene] as Map<String, dynamic>;
        final primary = row['primary_samples_ms'] as List<dynamic>;
        final all = row['all_samples_ms'] as List<dynamic>;
        expect(primary, all.take(3).toList());
        expect(primary, hasLength(3));
        final values = primary.cast<num>().toList()..sort();
        final increment = values[1] - blank;
        final budget = (increment * 1.1 * 1000 - 1e-9).ceil() / 1000;
        expect(row['increment_ms'], closeTo(increment, 1e-9));
        expect(budgets[scene], closeTo(budget, 1e-9));
        expect(row['original_design_target_ms'], 4);
        expect(row['gap_to_design'], closeTo(increment / 4 - 1, 1e-9));
        if (increment > 4) expect(row['status'], contains('未达设计目标'));
      }
    });

    test('keeps missing native CPU rounds uncertain instead of zero percent',
        () {
      final cpu = _read('$_results/audit.json')['cpu'] as Map<String, dynamic>;
      expect(cpu, hasLength(5));
      for (final value in cpu.values) {
        final row = value as Map<String, dynamic>;
        final count = row['valid_rounds'] as int;
        expect(row['round_medians'], hasLength(count));
        if (count < 3) {
          expect(row['status'], contains('不确定'));
          expect(row['errors'], isNotEmpty);
        }
        if (count == 0) expect(row['medians'], isNull);
      }
    });

    test('reports every clean window headroom failure with frozen gates', () {
      final report = _read('$_results/frame_assessment.json');
      final scenes = report['scenarios'] as Map<String, dynamic>;
      expect(scenes, hasLength(4));
      for (final value in scenes.values) {
        final scene = value as Map<String, dynamic>;
        final windows = scene['windows'] as List<dynamic>;
        expect(windows.length, inInclusiveRange(3, 5));
        var failures = 0;
        for (final value in windows) {
          final row = value as Map<String, dynamic>;
          final fps = row['fps'] as num;
          final count = row['frame_count'] as num;
          final elapsed = row['elapsed_micros'] as num;
          expect(fps, greaterThan(0));
          final delivery = fps >= 59 && count >= 0.98 * elapsed / 1e6 * 60;
          expect(row['delivery_passed'], delivery);
          if (!delivery) failures++;
          if (row['backpressure_contaminated'] == true) continue;
          final combined =
              row['99th_percentile_build_plus_raster_millis'] as num;
          final ui = row['99th_percentile_frame_build_time_millis'] as num;
          if (math.max(combined / 12, ui / 4) > 1) failures++;
        }
        if (failures > 0) expect(scene['status'], 'FAIL');
      }
    });
  });
}
