import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/treeshake/apk_support.dart';
import '../../tool/treeshake/check_treeshake.dart';

/// 十个探针均须有真实构建证据和已校准预算。
const List<String> _probes = kTreeshakeProbes;

/// 首批构建的五个探针，保留原始调用的来源信息。
const List<String> _initialProbes = [
  _baseline,
  'wheel_only',
  'grid_only',
  'slot_only',
  'all_games'
];

/// APK2 逐项补测的单玩法和迁移探针。
const List<String> _supplementProbes = [
  'capsule_only',
  'number_wheel_only',
  'lots_only',
  'lotto_only',
  _compat,
];

/// APK 包体积预算字段。
const String _limit = 'maxLuckdrawBytes';

/// APK 实测文件路径。
const String _reportPath = 'tool/treeshake/apk_measurement.json';

/// 两个后端的预算文件路径。
const String _budgetPath = 'tool/treeshake/budgets.json';

/// 包大小字段。
const String _packageBytes = 'measuredLuckdrawBytes';

/// arm64 AOT 总大小字段。
const String _aotBytes = 'measuredDartAotBytes';

/// 每个探针的实测集合字段。
const String _probeKey = 'probes';

/// APK 后端字段。
const String _apk = 'apk';

/// 测量时间字段。
const String _date = 'measuredAt';

/// 原始及补测调用字段。
const String _invocation = 'invocation';

/// 源码快照摘要字段。
const String _libHash = 'libSha256';

/// APK2 补测来源字段。
const String _supplement = 'supplement';

/// 对照探针名称。
const String _baseline = 'baseline';

/// 保留源码字段。
const String _sources = 'sources';

/// 迁移转盘探针名称。
const String _compat = 'compat_wheel';

/// 源码与原始报告摘要的 SHA-256 形状。
const String _sha256Pattern = r'^[0-9a-f]{64}$';

/// 报告来源字段。
const String _reportHash = 'reportSha256';

/// 实际构建前的可用内存字段。
const String _freeMemory = 'freeMemoryKiBBeforeBuild';

/// 构建所需的最低空闲内存，单位 KiB。
const int _minimumFreeMemory = 4 * 1024 * 1024;

/// 临时工程清理结果字段。
const String _removed = 'temporaryProjectRemoved';

/// 源码和符号违规列表字段。
const String _violations = 'violations';

/// APK 流程文档路径。
const String _readmePath = 'tool/treeshake/README.md';

/// 读取受版本管理的 JSON 证据，不调用 Flutter 构建器。
Map<String, Object?> _read(String path) =>
    jsonDecode(File(path).readAsStringSync()) as Map<String, Object?>;

/// 返回某个探针的结构化记录。
Map<String, Object?> _record(Map<String, Object?> records, String probe) =>
    records[probe]! as Map<String, Object?>;

/// 核对 APK 真实证据、源码隔离和预算，不将解析器夹具冒充构建。
void main() {
  group('treeshake apk measurement', () {
    test('recorded APK probes reproduce source symbol and budget verdicts', () {
      final report = _read(_reportPath);
      final records = report[_probeKey]! as Map<String, Object?>;
      final budgets = parseBudgets(File(_budgetPath).readAsStringSync());
      expect(records.keys, unorderedEquals(_probes));
      for (final probe in _probes) {
        final record = _record(records, probe);
        final artifact = TreeshakeArtifact(
          sources: (record[_sources]! as List<Object?>).cast<String>().toSet(),
          names: (record['names']! as List<Object?>).cast<String>().toSet(),
          luckdrawBytes: record[_packageBytes]! as int,
        );
        expect(record['buildStatus'], 'succeeded', reason: probe);
        expect(record[_violations], isEmpty, reason: probe);
        expect(checkProbe(probe, artifact), isEmpty, reason: probe);
        expect(
            checkBudget(probe, artifact.luckdrawBytes!, budgets[_apk]![probe]),
            isEmpty,
            reason: probe);
        expect(record[_aotBytes], greaterThan(artifact.luckdrawBytes!),
            reason: probe);
        expect(record[_freeMemory], greaterThanOrEqualTo(_minimumFreeMemory),
            reason: probe);
        expect(record[_removed], isTrue, reason: probe);
        expect(record[_reportHash], matches(_sha256Pattern), reason: probe);
      }
    });

    test('APK budgets equal measured package bytes times safety margin', () {
      final report = _read(_reportPath);
      final records = report[_probeKey]! as Map<String, Object?>;
      final budgetEntries = _read(_budgetPath)[_apk]! as Map<String, Object?>;
      for (final probe in kTreeshakeProbes) {
        final budget = _record(budgetEntries, probe);
        final record = _record(records, probe);
        expect(budget[_limit], isNotNull, reason: probe);
        expect(budget[_packageBytes], record[_packageBytes], reason: probe);
        expect(budget[_aotBytes], record[_aotBytes], reason: probe);
        expect(budget[_date], record[_date] ?? report[_date], reason: probe);
        expect(budget[_limit], apkBudgetBytes(record[_packageBytes]! as int),
            reason: probe);
      }
      expect(_record(budgetEntries, _baseline)[_limit], 0);
    });

    test(
        'recorded invocation and report provenance match the arm64 command plan',
        () {
      final report = _read(_reportPath);
      final plan = apkBuildCommands('/tmp/probe');
      expect(report['buildCommand'], 'flutter ${plan.last.join(' ')}');
      expect(report[_invocation],
          'dart run tool/treeshake/check_treeshake.dart --backend=apk --probe=${_initialProbes.join(',')}');
      expect(report[_date], startsWith('2026-11-10'));
      expect(report['reportLocation'], contains('.flutter-devtools'));
      final readme = File(_readmePath).readAsStringSync();
      expect(readme, contains('APK 实测记录'));
      expect(readme, contains(report[_invocation]));
      expect(report[_libHash], matches(_sha256Pattern));
    });

    test('remaining APK probes retain only their own game and explicit compat',
        () {
      final records = _read(_reportPath)[_probeKey]! as Map<String, Object?>;
      for (final probe in _supplementProbes) {
        final record = _record(records, probe);
        final sources = (record[_sources]! as List<Object?>).cast<String>();
        final zones = sources
            .map((source) => source.split('/src/').last.split('/').first)
            .toSet();
        final expectedGame = probe == _compat
            ? 'wheel'
            : probe.substring(0, probe.length - '_only'.length);
        expect(
            zones,
            unorderedEquals(
                ['core', expectedGame, if (probe == _compat) 'compat']),
            reason: probe);
        expect(record[_packageBytes], greaterThan(0), reason: probe);
      }
    });

    test('APK2 provenance preserves each invocation and rebuilt baseline', () {
      final report = _read(_reportPath);
      final supplement = report[_supplement]! as Map<String, Object?>;
      final records = report[_probeKey]! as Map<String, Object?>;
      final baselines = supplement['baselineRechecks']! as Map<String, Object?>;
      final invocations = supplement['invocations']! as List<Object?>;
      expect(baselines.keys, unorderedEquals(_supplementProbes));
      expect(invocations, hasLength(_supplementProbes.length));
      expect(supplement[_libHash], matches(_sha256Pattern));
      expect(supplement[_libHash], report[_libHash]);
      expect(supplement['gradleWorkersMax'], 2);
      final readme = File(_readmePath).readAsStringSync();
      for (final probe in _supplementProbes) {
        final record = _record(records, probe);
        final baseline = _record(baselines, probe);
        final invocation =
            'dart run tool/treeshake/check_treeshake.dart --backend=apk --probe=$probe --update-budgets';
        expect(invocations, contains(invocation), reason: probe);
        expect(record[_invocation], invocation, reason: probe);
        expect(readme, contains(invocation), reason: probe);
        expect(record[_libHash], supplement[_libHash], reason: probe);
        expect(DateTime.tryParse(record[_date]! as String), isNotNull,
            reason: probe);
        expect(baseline[_packageBytes], 0, reason: probe);
        expect(baseline[_aotBytes], greaterThan(0), reason: probe);
        expect(baseline[_sources], isEmpty, reason: probe);
        expect(baseline[_violations], isEmpty, reason: probe);
        expect(baseline[_reportHash], matches(_sha256Pattern), reason: probe);
        expect(baseline[_freeMemory], greaterThanOrEqualTo(_minimumFreeMemory),
            reason: probe);
        expect(baseline[_removed], isTrue, reason: probe);
      }
    });
  });
}
