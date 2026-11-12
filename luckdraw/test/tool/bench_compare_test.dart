import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/bench/compare.dart';

/// 主包中预算文件的位置。
const String _budgetPath = 'tool/bench/budgets.json';

/// 被测试的纯 Dart 比较入口。
const String _comparePath = 'tool/bench/compare.dart';

/// 基准预算内已存在的场景，用于故意破坏测试输入。
const String _wheel = 'wheel_steady';

/// 用于结构测试的未知字段。
const String _unknown = 'unknown';

/// 读取真实预算；测试会独立获取新对象，避免修改相互污染。
Map<String, Object?> _budgets() =>
    jsonDecode(File(_budgetPath).readAsStringSync()) as Map<String, Object?>;

/// 创建含所有场景和刷新率的独立测量对象。
Map<String, Object?> _measurements() => {
      for (final entry in _budgets().entries)
        entry.key: <String, Object?>{
          ...entry.value! as Map<String, Object?>,
          kBenchRefreshRate: 60,
        },
    };

/// 创建真实命令行可读取的三轮合成报告，仅用于单测，不当作真机数据。
void _writeReports(Directory directory) {
  for (final entry in _measurements().entries) {
    for (var run = 0; run < kBenchRepetitions; run++) {
      File('${directory.path}/${entry.key}_$run.timeline_summary.json')
          .writeAsStringSync(jsonEncode({
        ...entry.value! as Map<String, Object?>,
        kBenchFrameCount: 300,
        'fps': kBenchDeliveryHz,
        'elapsed_micros': 5000000,
        kBenchRasterP99: 8,
        kBenchBuildP99: 2,
        kBenchCombinedP99: 10,
        kBenchRssCycles: kRssCycles,
        'rss_baseline': 1,
        'rss_pages': List.filled(kRssCycles, 1),
        'rss_blank': List.filled(kRssCycles, 1),
        kBenchReportKey: entry.key,
        kBenchRunId: '$run',
      }));
    }
  }
}

/// 使用当前 PATH 的 Dart 启动纯脚本，参数只包含测试生成的临时路径。
Future<ProcessResult> _compare(Directory directory,
        {List<String> options = const []}) =>
    Process.run(
        'dart',
        [
          'run',
          File(_comparePath).absolute.path,
          '--input=${directory.path}',
          '--budgets=${File(_budgetPath).absolute.path}',
          ...options,
        ],
        runInShell: Platform.isWindows);

/// 注册预算结构自检、预算比较和命令行端到端单测。
void main() {
  group('bench structure', () {
    test('real budgets cover every available scenario with finite limits', () {
      expect(validateStructure(_budgets(), budgets: true), isEmpty);
      expect(kBenchSchema, hasLength(11));
      expect(_budgets().keys.toSet(), kBenchSchema.keys.toSet());
      expect(
          (_budgets()['memory_cycles']!
              as Map<String, Object?>)[kBenchRssDelta],
          lessThanOrEqualTo(12 * 1024 * 1024));
      expect(
          (_budgets()['memory_cycles']!
              as Map<String, Object?>)[kBenchRssGrowth],
          kBenchRssSteadyLimit);
    });
    test('uses approved UI limits without changing raster or dropped targets',
        () {
      final budgets = _budgets();
      for (final entry in const {
        'wheel_steady': 1.0,
        'number_wheel_spin': 1.3,
        'capsule_mixing': 2.0,
        'lotto_draw': 2.5,
        'grid_steady': 1.2,
      }.entries) {
        final limits = budgets[entry.key]! as Map<String, Object?>;

        expect(limits[kBenchDroppedRatio], 0.005);
        final status = jsonDecode(
                File('tool/bench/budgets.status.json').readAsStringSync())
            as Map<String, Object?>;
        final met = status['met'] as Map<String, Object?>?;
        final targets = met?['targets'] as Map<String, Object?>?;
        final original = targets?[entry.key] as Map<String, Object?>?;
        expect((original ?? limits)[kBenchBuildMean], entry.value);
        expect(
            (original ?? limits)[kBenchRasterMean],
            entry.key == 'lotto_draw'
                ? 6
                : entry.key == 'grid_steady'
                    ? 4
                    : 5);
      }
      expect((budgets['memory_cycles']! as Map<String, Object?>).keys,
          isNot(contains(kBenchRssWarmup)));
    });
    test('rejects missing unknown and nonobject scenarios', () {
      final data = _budgets()..remove(_wheel);
      expect(validateStructure(data, budgets: true).join(), contains(_wheel));
      data[_wheel] = 1;
      data[_unknown] = {};
      final errors = validateStructure(data, budgets: true).join();
      expect(errors, contains(_wheel));
      expect(errors, contains(_unknown));
    });
    test('rejects missing invalid and misspelled budget metrics', () {
      final data = _budgets();
      final wheel = data[_wheel]! as Map<String, Object?>;
      wheel.remove(kBenchBuildMean);
      wheel[kBenchBuildP90] = double.infinity;
      wheel[_unknown] = 1;
      final errors = validateStructure(data, budgets: true).join();
      expect(errors, contains(kBenchBuildMean));
      expect(errors, contains(kBenchBuildP90));
      expect(errors, contains(_unknown));
    });
    test('allows diagnostic fields only in measurements', () {
      final data = _measurements();
      expect(validateStructure(data, budgets: false), isEmpty);
      expect(validateStructure(data, budgets: true), isNotEmpty);
    });
  });
  group('bench compareToBudget', () {
    test('accepts equality and reports every budget item', () {
      final rows = compareToBudget(_measurements(), _budgets());
      expect(rows, hasLength(56));
      expect(rows.every((row) => row.passed), isTrue);
      expect(rows.first.scenario, _wheel);
      expect(rows.first.actual, rows.first.limit);
    });
    test('reports an excess as a failed comparison', () {
      final data = _measurements();
      final budgets = _budgets();
      final limit = benchNumber(
          (budgets[_wheel]! as Map<String, Object?>)[kBenchBuildMean],
          kBenchBuildMean);
      final actual = limit + 0.1;
      (data[_wheel]! as Map<String, Object?>)[kBenchBuildMean] = actual;
      final failures =
          compareToBudget(data, budgets).where((row) => !row.passed).toList();
      expect(failures, hasLength(1));
      expect(failures.single.metric, kBenchBuildMean);
      expect(failures.single.actual, actual);
      expect(failures.single.limit, limit);
    });
    test('uses the 120hz limit and preserves tighter configured limits', () {
      final data = _measurements();
      final wheel = data[_wheel]! as Map<String, Object?>;
      wheel[kBenchRefreshRate] = 120;
      wheel[kBenchDroppedRatio] = kBenchHighRefreshDropLimit;
      final standardBudgets = _budgets();
      (standardBudgets[_wheel]! as Map<String, Object?>)[kBenchDroppedRatio] =
          kBenchHighRefreshDropLimit / 2;
      expect(compareToBudget(data, standardBudgets).every((r) => r.passed),
          isTrue);
      final budgets = _budgets();
      (budgets[_wheel]! as Map<String, Object?>)[kBenchDroppedRatio] = 0.001;
      final row = compareToBudget(data, budgets).singleWhere(
          (r) => r.scenario == _wheel && r.metric == kBenchDroppedRatio);
      expect(row.limit, 0.002);
      expect(row.passed, isFalse);
      wheel[kBenchRefreshRate] = 90;
      expect(
          compareToBudget(data, standardBudgets).any((r) => !r.passed), isTrue);
    });
    test('rejects invalid data and missing or zero refresh rate', () {
      expect(() => compareToBudget({}, _budgets()), throwsFormatException);
      final data = _measurements();
      final wheel = data[_wheel]! as Map<String, Object?>;
      wheel.remove(kBenchRefreshRate);
      expect(() => compareToBudget(data, _budgets()), throwsFormatException);
      wheel[kBenchRefreshRate] = 0;
      expect(() => compareToBudget(data, _budgets()), throwsFormatException);
    });
  });
  group('bench cli', () {
    late Directory directory;
    setUp(() {
      directory = Directory.systemTemp.createTempSync('luckdraw_bench_test_');
    });
    tearDown(() {
      directory.deleteSync(recursive: true);
    });
    test(
        'reports uncertain costs and informational first frame in classified output',
        () async {
      _writeReports(directory);
      for (var run = 0; run < kBenchMinimumCleanWindows; run++) {
        final file =
            File('${directory.path}/${_wheel}_$run.timeline_summary.json');
        final data =
            jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
        file.writeAsStringSync(jsonEncode({
          ...data,
          kBenchRasterP90: kBenchBackpressureP90,
          kBenchRasterMean: 16.7,
        }));
      }
      final output = File('${directory.path}/assessment.json');
      final result = await _compare(directory,
          options: ['--classify-windows', '--output=${output.path}']);
      expect(result.exitCode, 1);
      expect(result.stdout, contains('SCENARIO: wheel_steady | UNCERTAIN'));
      expect(result.stdout, contains('SCENARIO: wheel_first_frame | INFO'));
      final data =
          jsonDecode(output.readAsStringSync()) as Map<String, Object?>;
      final scenarios = data['scenarios']! as Map<String, Object?>;
      final wheel = scenarios[_wheel]! as Map<String, Object?>;
      expect(wheel['delivery_passed'], isTrue);
      expect(wheel['clean_count'], 1);
      expect(wheel['contaminated_count'], 2);
    });
    test(
        'keeps complete costs but fails a real jank window in classified output',
        () async {
      _writeReports(directory);
      final file = File('${directory.path}/${_wheel}_0.timeline_summary.json');
      final data = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
      file.writeAsStringSync(jsonEncode({...data, 'fps': 58.9}));
      final result = await _compare(directory, options: ['--classify-windows']);
      expect(result.exitCode, 1);
      expect(result.stdout, contains('REAL_JANK'));
      expect(result.stdout, contains('SCENARIO: wheel_steady | FAIL'));
    });
    test('recomputes all scene RSS and keeps warmup informational', () async {
      _writeReports(directory);
      for (final file in directory.listSync().whereType<File>()) {
        final data =
            jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
        file.writeAsStringSync(jsonEncode({
          ...data,
          'rss_pages': List.filled(kRssCycles, 1),
          'rss_blank': List.filled(kRssCycles, 10000001),
          kBenchRssGrowth: 99999999,
        }));
      }
      final result = await _compare(directory, options: ['--rss-all-scenes']);
      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(result.stdout, contains('rss_warmup_bytes = 10000000.0'));
      expect(result.stdout,
          contains('wheel_steady | rss_steady_growth_bytes | 0.0000'));
    });
    test('fails steady RSS excess while preserving unstable frame diagnostics',
        () async {
      _writeReports(directory);
      for (final file in directory.listSync().whereType<File>()) {
        final data =
            jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
        file.writeAsStringSync(jsonEncode({
          ...data,
          'rss_blank': [1, 2, 3, 4, kBenchRssSteadyLimit + 2],
        }));
      }
      final file = File('${directory.path}/${_wheel}_0.timeline_summary.json');
      final data = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
      file.writeAsStringSync(jsonEncode({...data, kBenchRasterMean: 100}));
      final result = await _compare(directory, options: ['--rss-all-scenes']);
      expect(result.exitCode, 1);
      expect(result.stderr, contains('极差'));
      expect(result.stdout, contains('UNSTABLE'));
      expect(result.stdout, contains('1572865.0000 | 1572864.0000 | FAIL'));
    });
    test('passes three complete stable runs and ignores reference diagnostics',
        () async {
      _writeReports(directory);
      File('${directory.path}/reference.timeline_summary.json')
          .writeAsStringSync(jsonEncode({kBenchReportKey: kBenchReference}));
      final result = await _compare(directory);
      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(result.stdout, contains('PASS: 全部性能预算通过'));
      expect(result.stdout, contains('中位数'));
    });
    test('fails empty or incomplete collections instead of reporting success',
        () async {
      var result = await _compare(directory);
      expect(result.exitCode, 1);
      expect(result.stderr, contains('三次'));
      _writeReports(directory);
      File('${directory.path}/${_wheel}_0.timeline_summary.json').deleteSync();
      result = await _compare(directory);
      expect(result.exitCode, 1);
      expect(result.stderr, contains('三次'));
    });
    test('fails duplicate run ids and unknown scenarios', () async {
      _writeReports(directory);
      final file = File('${directory.path}/${_wheel}_0.timeline_summary.json');
      final original =
          jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
      file.writeAsStringSync(jsonEncode({...original, kBenchRunId: '1'}));
      expect((await _compare(directory)).stderr, contains('重复'));
      file.writeAsStringSync(
          jsonEncode({...original, kBenchReportKey: _unknown}));
      expect((await _compare(directory)).stderr, contains('未知'));
    });
    test('fails missing metrics invalid frame counts and malformed json',
        () async {
      _writeReports(directory);
      final file = File('${directory.path}/${_wheel}_0.timeline_summary.json');
      final original =
          jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
      final missing = {...original}..remove(kBenchBuildMean);
      file.writeAsStringSync(jsonEncode(missing));
      expect((await _compare(directory)).exitCode, 1);
      file.writeAsStringSync(jsonEncode({...original, kBenchFrameCount: 0}));
      expect((await _compare(directory)).stderr, contains('没有有效帧'));
      file.writeAsStringSync('[]');
      expect((await _compare(directory)).stderr, contains('根节点'));
    });
    test('fails noisy runs and stable over budget runs', () async {
      _writeReports(directory);
      final file = File('${directory.path}/${_wheel}_0.timeline_summary.json');
      final original =
          jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
      file.writeAsStringSync(jsonEncode({...original, kBenchBuildMean: 4}));
      expect((await _compare(directory)).stderr, contains('极差'));
      for (var run = 0; run < kBenchRepetitions; run++) {
        final report =
            File('${directory.path}/${_wheel}_$run.timeline_summary.json');
        final data =
            jsonDecode(report.readAsStringSync()) as Map<String, Object?>;
        report.writeAsStringSync(jsonEncode({...data, kBenchBuildMean: 4}));
      }
      final result = await _compare(directory);
      expect(result.exitCode, 1);
      expect(result.stdout, contains('FAIL: 存在超预算指标'));
    });
  });
}
