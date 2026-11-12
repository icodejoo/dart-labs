import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../tool/bench/metrics.dart';
import '../../tool/bench/pending_metrics.dart';
import '../../tool/bench/pending_scene.dart';

/// 夹具包名，故意包含点以检验正则转义。
const String _package = 'com.example.luckdraw_bench';

/// 读取明确标为合成数据的 Android16 输出。
String _fixture(String name) =>
    File('tool/bench/fixtures/$name.txt').readAsStringSync();

/// 创建七次完整 CPU 快照的合成时间/进程元数据。
Map<String, Object?> _cpu() => {
      'window_micros': 5010000,
      'before': <String, Object?>{'pid': 123},
      'after': <String, Object?>{'pid': 123},
      'samples': <Object?>[
        for (var index = 0; index < kPendingCpuSamples; index++)
          <String, Object?>{
            'pid': 123,
            'offset_micros': index * Duration.microsecondsPerSecond,
            'end_offset_micros':
                index * Duration.microsecondsPerSecond + 100000,
          },
      ],
    };

/// 注册不接触设备的 PEND 解析、编排与 CLI 回归。
void main() {
  group('bench PEND', () {
    testWidgets('builds blank and game cold pages with the same Scaffold shell',
        (tester) async {
      await tester.pumpWidget(MaterialApp(home: pendingFirstFramePage(null)));
      expect(find.byType(Scaffold), findsOneWidget);
      final blank = tester.widget<Scaffold>(find.byType(Scaffold)).body;
      expect(blank, isA<SizedBox>());
      expect((blank! as SizedBox).child, isNull);
      const key = ValueKey('pending-fixture');
      await tester.pumpWidget(MaterialApp(
          home: pendingFirstFramePage(const SizedBox.expand(key: key))));
      expect(find.byType(Scaffold), findsOneWidget);
      expect(tester.getSize(find.byKey(key)), const Size.square(320));
    });
    test('parses exact Android16 process CPU without matching subprocesses',
        () {
      final value =
          parsePendingCpuInfo(_fixture('cpuinfo_android16'), _package);
      expect(value.pid, 16782);
      expect(value.percent, 23.4);
      expect(
          parsePendingCpuInfo(
                  '-0% 8/$_package: removed\n+12.5% 9/$_package: 10% user',
                  _package)
              .percent,
          12.5);
      expect(
          parsePendingCpuInfo('125.0% 9/$_package: 100% user', _package)
              .percent,
          125);
    });
    test('rejects absent duplicate malformed and zero pid cpuinfo rows', () {
      for (final text in [
        '1% 5/comXexampleXluckdraw_bench: 1% user',
        '1% 5/$_package:worker: 1% user',
        'NaN% 5/$_package: 1% user',
        '${List.filled(400, '9').join()}% 5/$_package: 1% user',
        '1% 0/$_package: 1% user',
        '1% 5/$_package: 1% user\n1% 6/$_package: 1% user',
      ]) {
        expect(
            () => parsePendingCpuInfo(text, _package), throwsFormatException);
      }
    });
    test('parses toybox top thread roles and names containing spaces', () {
      final rows = parsePendingTop(_fixture('top_android16'));
      expect(rows, hasLength(4));
      expect(rows[1].tid, 16802);
      expect(rows[1].role, 'UI');
      expect(rows[1].percent, 17);
      expect(rows[2].role, 'Raster');
      expect(rows.last.name, 'Dart Worker');
      expect(rows.last.role, 'other');
    });
    test('supports TID CPU percent alternate headers and ANSI escapes', () {
      final rows = parsePendingTop('\x1b[2J${_fixture('top_tid')}');
      expect(rows.map((row) => row.tid), [16802, 16803]);
      expect(rows.map((row) => row.percent), [12.5, 3.5]);
      expect(rows.map((row) => row.role), ['UI', 'Raster']);
      expect(pendingThreadRole('io.flutter.ui'), 'UI');
      expect(pendingThreadRole('17.raster'), 'Raster');
      expect(pendingThreadRole('build.ui.worker'), 'other');
    });
    test('rejects missing top columns roles duplicate tids and invalid values',
        () {
      final valid = _fixture('top_tid');
      for (final text in [
        '',
        valid.replaceFirst('NAME', 'unknown'),
        valid.replaceFirst('CPU%', 'unknownCPU%'),
        valid.replaceFirst('UI', 'other'),
        valid.replaceFirst('16803', '16802'),
        valid.replaceFirst('12.5%', 'NaN'),
        valid.replaceFirst('12.5%', '-1'),
        '$valid\n16782',
      ]) {
        expect(() => parsePendingTop(text), throwsFormatException);
      }
    });
    test('validates all five CPU samples are within their one second slots',
        () {
      expect(() => validatePendingCpuWindow(_cpu()), returnsNormally);
      final changedPid = _cpu()..['after'] = <String, Object?>{'pid': 124};
      expect(() => validatePendingCpuWindow(changedPid), throwsFormatException);
      final short = _cpu()..['window_micros'] = 4999999;
      expect(() => validatePendingCpuWindow(short), throwsFormatException);
      final missing = _cpu()..['samples'] = <Object?>[];
      expect(() => validatePendingCpuWindow(missing), throwsFormatException);
      for (final field in ['pid', 'offset_micros', 'end_offset_micros']) {
        final data = _cpu();
        final sample =
            (data['samples']! as List<Object?>).first! as Map<String, Object?>;
        sample[field] = field == 'pid'
            ? 124
            : field == 'offset_micros'
                ? -1
                : 1000000;
        expect(() => validatePendingCpuWindow(data), throwsFormatException);
      }
    });
    test('calibrates cold frame medians and preserves signed increments', () {
      expect(pendingFirstFrameMedian([3, 1, 2]), 2);
      expect(pendingFirstFrameIncrement([40, 30, 50], [33, 32, 34]), -7);
      expect(pendingFirstFrameIncrement([1, 3, 2], [5, 7, 6]), 4);
    });
    test('rejects incomplete zero or nonfinite cold frame calibration', () {
      for (final values in <List<double>>[
        [],
        [1, 2],
        [1, 2, 3, 4],
        [0, 1, 2],
        [-1, 1, 2],
        [double.nan, 1, 2],
        [double.infinity, 1, 2],
      ]) {
        expect(() => pendingFirstFrameMedian(values), throwsFormatException);
      }
    });
    test(
        'caps attempts at five and supplements only insufficient clean windows',
        () {
      expect(pendingNeedsStart(0, 0, 0), isTrue);
      expect(pendingNeedsStart(3, 3, 1), isFalse);
      expect(pendingNeedsStart(3, 3, 1, retest: true), isTrue);
      expect(pendingNeedsStart(4, 3, 2, retest: true), isFalse);
      expect(pendingNeedsStart(5, 2, 0, retest: true), isFalse);
      expect(() => pendingNeedsStart(1, 2, 0), throwsFormatException);
      expect(() => pendingNeedsStart(2, 2, 3), throwsFormatException);
    });
    test('parses nested async trace events and joins engine frame identities',
        () async {
      final result = await Process.run(
          'python', ['tool/bench/analyze_frames.py', '--self-test']);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      expect('${result.stderr}', contains('OK'));
    });
    test(
        'retains all clean saved windows and separates current from historical spikes',
        () {
      final windows = (jsonDecode(
              File('tool/bench/results/pend_offline/frames.json')
                  .readAsStringSync()) as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(windows, hasLength(16));
      final expected = {
        'slot_raster': 5,
        'grid_steady': 8,
        'lotto_draw': 24,
        'lots_shaking': 0
      };
      for (final entry in expected.entries) {
        final current = windows.where((window) =>
            window['scenario'] == entry.key && window['formal'] == true);
        final spikes = current
            .expand((window) => window['frames']! as List<Object?>)
            .cast<Map<String, Object?>>()
            .where((frame) => frame['spike'] == true);
        expect(spikes.length, entry.value, reason: entry.key);
        expect(
            current
                .every((window) => (window['sha256']! as String).length == 64),
            isTrue);
      }
    });
    test(
        'parses PowerShell runner and lists a complete offline plan without device access',
        () async {
      final script =
          File('tool/bench/run_pending_device_checks.ps1').absolute.path;
      final syntax = await Process.run('pwsh', [
        '-NoProfile',
        '-Command',
        r'$tokens=$null; $errors=$null; [System.Management.Automation.Language.Parser]::ParseInput([IO.File]::ReadAllText($env:PEND_TEST_SCRIPT),[ref]$tokens,[ref]$errors) | Out-Null; if($errors.Count){$errors | Out-String | Write-Error; exit 1}'
      ], environment: {
        'PEND_TEST_SCRIPT': script
      });
      expect(syntax.exitCode, 0, reason: '${syntax.stderr}');
      final result = await Process.run('pwsh', [
        '-NoProfile',
        '-File',
        script,
        '-DeviceSerial',
        'OFFLINE_FIXTURE',
        '-ApplicationBinary',
        'does-not-exist.apk',
        '-PlanOnly'
      ]);
      expect(result.exitCode, 0, reason: '${result.stderr}');
      final plan = jsonDecode('${result.stdout}') as Map<String, Object?>;
      expect(plan['first_frames'], kPendingFirstFrames);
      expect(
          plan['cpu'], kPendingCpuScenes.map((scene) => 'cpu_$scene').toList());
      expect(plan['retests'], kPendingRetests);
      expect(plan['initial_starts'], 39);
      expect(plan['max_starts'], kPendingMaxStarts);
      expect(plan['settings_modified'], isFalse);
    });
    test(
        'assesses synthetic pending collection without claiming device success',
        () async {
      final directory =
          Directory.systemTemp.createTempSync('luckdraw_pend_assess_');
      addTearDown(() => directory.deleteSync(recursive: true));
      final records = <Map<String, Object?>>[];
      for (final scene in [
        ...kPendingFirstFrames,
        ...kPendingCpuScenes.map((scene) => 'cpu_$scene')
      ]) {
        for (var round = 0; round < kPendingRounds; round++) {
          final relative = '${scene}_$round';
          final location = Directory('${directory.path}/$relative')
            ..createSync();
          records.add({
            'scene': scene,
            'directory': relative,
            'valid': true,
            'binary_sha256': 'SYNTHETIC'
          });
          if (scene.startsWith('cpu_')) {
            Directory('${location.path}/cpu').createSync();
            File('${location.path}/cpu/cpu.json')
                .writeAsStringSync(jsonEncode(_cpu()));
          } else {
            File('${location.path}/sample.timeline_summary.json')
                .writeAsStringSync(jsonEncode({
              kBenchReportKey: scene,
              kBenchFirstFrame:
                  scene == kPendingFirstFrames.first ? 40.0 : 33.0,
            }));
          }
        }
      }
      var index = 0;
      for (final file in Directory('tool/bench/results/met2/comparison')
          .listSync()
          .whereType<File>()) {
        final data =
            jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
        final scene = data[kBenchReportKey];
        if (kPendingRetests.contains(scene)) {
          final relative = 'saved_${index++}';
          final location = Directory('${directory.path}/$relative')
            ..createSync();
          file.copySync('${location.path}/${file.uri.pathSegments.last}');
          records.add({
            'scene': scene,
            'directory': relative,
            'valid': true,
            'binary_sha256': 'SYNTHETIC'
          });
        }
      }
      File('${directory.path}/runs.json')
          .writeAsStringSync(jsonEncode(records));
      final result = await Process.run(
          'dart', ['run', 'tool/bench/assess_pending.dart', directory.path]);
      expect(result.exitCode, 1, reason: '${result.stderr}');
      final report = jsonDecode(
              File('${directory.path}/assessment.json').readAsStringSync())
          as Map<String, Object?>;
      expect(report, hasLength(13));
      expect(
          (report['wheel_first_frame']!
              as Map<String, Object?>)['increment_ms'],
          -7);
      expect(
          (report['blank_first_frame']!
              as Map<String, Object?>)['budget_passed'],
          isFalse);
      expect((report['slot_raster']! as Map<String, Object?>)['status'], '失败');
      expect(
          (report['lots_shaking']! as Map<String, Object?>)['status'], '不确定');
      expect(File('${directory.path}/REPORT.md').readAsStringSync(),
          contains('不等于达到最初设计目标'));
      final repeated = await Process.run(
          'dart', ['run', 'tool/bench/assess_pending.dart', directory.path]);
      expect(repeated.exitCode, 1);
      expect('${repeated.stderr}', contains('comparison 必须为空'));
    });
    test(
        'runs scoped MET2 comparison without requiring unrelated device reports',
        () async {
      final directory = Directory.systemTemp.createTempSync('luckdraw_pend_');
      addTearDown(() => directory.deleteSync(recursive: true));
      final saved = Directory('tool/bench/results/met2/comparison')
          .listSync()
          .whereType<File>();
      for (final file in saved) {
        final data =
            jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
        if (data[kBenchReportKey] == 'slot_raster') {
          file.copySync('${directory.path}/${file.uri.pathSegments.last}');
        }
      }
      final output = '${directory.path}/assessment.json';
      final result = await Process.run('dart', [
        'run',
        'tool/bench/compare.dart',
        '--input=${directory.path}',
        '--scenarios=slot_raster',
        '--output=$output'
      ]);
      expect(result.exitCode, 1);
      final report =
          jsonDecode(File(output).readAsStringSync()) as Map<String, Object?>;
      final scenes = report['scenarios']! as Map<String, Object?>;
      expect(scenes.keys, ['slot_raster']);
      expect((scenes['slot_raster']! as Map<String, Object?>)[kBenchStatus],
          kBenchFail);
      for (final selection in ['', 'unknown', 'slot_raster,slot_raster']) {
        final bad = await Process.run('dart',
            ['run', 'tool/bench/compare.dart', '--scenarios=$selection']);
        expect(bad.exitCode, 1);
        expect('${bad.stderr}', contains('scenarios'));
      }
    });
  });
}
