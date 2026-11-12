import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/treeshake/check_treeshake.dart';

/// 首轮实测报告的包内路径。
const String _reportPath = 'tool/treeshake/first_measurement.json';

/// B13c 补测报告，保留 B13b 首轮失败作为历史证据。
/// 在 F2 之后重新测量并重定预算的探针名。
const String _lotto = 'lotto_only';

const String _recheckPath = 'tool/treeshake/recheck_measurement.json';

/// 已登记预算的包内路径。
const String _budgetsPath = 'tool/treeshake/budgets.json';

/// Web 后端名。
const String _web = 'web';

/// APK 后端名。
const String _apk = 'apk';

/// 基线探针名。
const String _baseline = 'baseline';

/// 首轮失败、B13c 已补测的迁移转盘探针。
const String _compat = 'compat_wheel';

/// 仅转盘探针名。
const String _wheel = 'wheel_only';

/// 失败构建状态。
const String _failed = 'failed';

/// 真实构建状态字段。
const String _status = 'buildStatus';

/// 探针记录字段。
const String _probes = 'probes';

/// 原始字节数字段。
const String _raw = 'rawBytes';

/// GNU gzip 字节数字段。
const String _gzip = 'gzipBytes';

/// Dart gzip 字节数字段。
const String _dartGzip = 'dartGzipBytes';

/// GNU gzip 相对基线的增量字段。
const String _delta = 'deltaGzipBytes';

/// Dart gzip 相对基线的增量字段。
const String _dartDelta = 'deltaDartGzipBytes';

/// GNU gzip 独立校准的增量上限字段。
const String _gnuLimit = 'maxGnuDeltaGzipBytes';

/// 保留的包内源文件字段。
const String _sources = 'sources';

/// 保留的受检查符号字段。
const String _checkedNames = 'checkedNames';

/// 构建前可用物理内存字段，单位为 KiB。
const String _freeMemory = 'freeMemoryKiBBeforeBuild';

/// 临时工程已删除的证据字段。
const String _removed = 'temporaryProjectRemoved';

/// 真实构建命令耗时字段。
const String _buildMilliseconds = 'buildMilliseconds';

/// 源码与符号违规记录字段。
const String _violations = 'violations';

/// 预算安全系数，与 TEST_STRATEGY §8.3 一致。
const double _margin = 1.1;

/// 读取工具报告的 JSON 对象；非法结构通过强类型转换显式失败。
Map<String, Object?> _readJson(String path) =>
    jsonDecode(File(path).readAsStringSync()) as Map<String, Object?>;

/// 读取某一探针的真实测量记录。
Map<String, Object?> _record(Map<String, Object?> probes, String probe) =>
    probes[probe]! as Map<String, Object?>;

/// 验证预算与真实测量证据一致，保留缺陷诊断而不伪造通过结果。
void main() {
  group('treeshake first measurement', () {
    test('web budgets match measured gzip deltas and apk remains uncalibrated',
        () {
      final report = _readJson(_reportPath);
      final budgetJson = _readJson(_budgetsPath);
      final budgets = parseBudgets(jsonEncode(budgetJson));
      final probes = report[_probes]! as Map<String, Object?>;
      final baseline = _record(probes, _baseline);
      expect(probes.keys.toSet(), kTreeshakeProbes.toSet());
      expect(report['measuredAt'], matches(r'^\d{4}-\d{2}-\d{2}T'));
      expect(report['gzipCommand'], 'gzip -9 -n -c main.dart.js');
      final recheckProbes =
          _readJson(_recheckPath)[_probes]! as Map<String, Object?>;
      for (final probe in kTreeshakeProbes) {
        // compat 首轮构建失败、lotto_only 在 F2 之后代码变大，二者都以 B13c 复测为准。
        final fromRecheck = probe == _compat || probe == _lotto;
        final measured = _record(fromRecheck ? recheckProbes : probes, probe);
        final comparisonBaseline =
            fromRecheck ? _record(recheckProbes, _baseline) : baseline;
        final entry = _record(budgetJson[_web]! as Map<String, Object?>, probe);
        final raw = measured[_raw]! as int;
        final gzip = measured[_gzip]! as int;
        final delta = measured[_delta]! as int;
        final dartDelta = measured[_dartDelta]! as int;
        expect(raw, greaterThan(0), reason: probe);
        expect(gzip, inInclusiveRange(1, raw), reason: probe);
        expect(measured['deltaRawBytes'],
            raw - (comparisonBaseline[_raw]! as int));
        expect(delta, gzip - (comparisonBaseline[_gzip]! as int),
            reason: probe);
        expect(
            dartDelta,
            (measured[_dartGzip]! as int) -
                (comparisonBaseline[_dartGzip]! as int));
        expect(budgets[_web]![probe], (dartDelta * _margin).ceil(),
            reason: probe);
        expect(entry[_gnuLimit], (delta * _margin).ceil(), reason: probe);
        expect(checkBudget(probe, delta, entry[_gnuLimit]! as int), isEmpty);
        expect(checkBudget(probe, dartDelta, budgets[_web]![probe]), isEmpty);
        expect(entry['measuredRawBytes'], raw);
        expect(entry['measuredGzipBytes'], gzip);
        expect(entry['measuredDeltaGzipBytes'], delta);
        expect(entry['measuredDartGzipBytes'], measured[_dartGzip]);
        expect(entry['measuredDeltaDartGzipBytes'], dartDelta);
        // 历史测试名保留给既有矩阵；APK2 已补齐十项实测，不允许空预算。
        expect(budgets[_apk]![probe], isNotNull, reason: probe);
      }
      expect(budgets[_web]![_baseline], 0);
    });

    test(
        'retained sources and checked symbols reproduce every recorded verdict',
        () {
      final report = _readJson(_reportPath);
      final probes = report[_probes]! as Map<String, Object?>;
      for (final probe in kTreeshakeProbes) {
        final measured = _record(probes, probe);
        expect(measured[_freeMemory], greaterThanOrEqualTo(3 * 1024 * 1024),
            reason: probe);
        expect(measured[_removed], isTrue, reason: probe);
        if (measured[_status] == _failed) {
          expect(probe, _compat);
          expect(measured['failureReason'],
              contains("Method not found: 'wheelFromLuckyCanvasConfig'"));
          expect(measured['missingSource'], 'lib/src/compat/wheel_compat.dart');
          expect(measured.containsKey(_sources), isFalse);
          expect(measured.containsKey(_violations), isFalse);
          continue;
        }
        final artifact = TreeshakeArtifact(
          sources:
              (measured[_sources]! as List<Object?>).cast<String>().toSet(),
          names: (measured[_checkedNames]! as List<Object?>)
              .cast<String>()
              .toSet(),
        );
        expect(checkProbe(probe, artifact),
            unorderedEquals(measured[_violations]! as List<Object?>),
            reason: probe);
        expect(measured[_buildMilliseconds], greaterThan(0), reason: probe);
      }
    });

    test('B13c real web rechecks reproduce source symbol and budget verdicts',
        () {
      final recheck = _readJson(_recheckPath);
      final probes = recheck[_probes]! as Map<String, Object?>;
      final budgets = parseBudgets(File(_budgetsPath).readAsStringSync());
      final baseline = _record(probes, _baseline);
      const expected = [_baseline, _compat, 'lotto_only', _wheel];
      expect(probes.keys, unorderedEquals(expected));
      for (final probe in expected) {
        final record = _record(probes, probe);
        final artifact = TreeshakeArtifact(
          sources: (record[_sources]! as List<Object?>).cast<String>().toSet(),
          names:
              (record[_checkedNames]! as List<Object?>).cast<String>().toSet(),
        );
        expect(record[_status], 'succeeded', reason: probe);
        expect(record[_violations], isEmpty, reason: probe);
        expect(checkProbe(probe, artifact), isEmpty, reason: probe);
        expect(record[_freeMemory], greaterThanOrEqualTo(3 * 1024 * 1024),
            reason: probe);
        expect(record[_removed], isTrue, reason: probe);
        expect(record[_buildMilliseconds], greaterThan(0), reason: probe);
        expect(
            record[_delta], (record[_gzip]! as int) - (baseline[_gzip]! as int),
            reason: probe);
        final dartDelta =
            (record[_dartGzip]! as int) - (baseline[_dartGzip]! as int);
        expect(record[_dartDelta], dartDelta, reason: probe);
        expect(checkBudget(probe, dartDelta, budgets[_web]![probe]),
            record['budgetViolations'],
            reason: probe);
        final budgetJson = _readJson(_budgetsPath);
        final entry = _record(budgetJson[_web]! as Map<String, Object?>, probe);
        expect(
            checkBudget(
                probe, record[_delta]! as int, entry[_gnuLimit]! as int),
            record['gnuBudgetViolations'],
            reason: probe);
        if (probe == _wheel) {
          expect(
              artifact.names.where((name) =>
                  name.contains('Lotto') || name.contains('CubicEasing')),
              isEmpty);
        }
      }
    });

    test('gzip size relationships reproduce both recorded compressor verdicts',
        () {
      final report = _readJson(_reportPath);
      final probes = report[_probes]! as Map<String, Object?>;
      final deltas = <String, int>{};
      final dartDeltas = <String, int>{};
      for (final probe in kTreeshakeProbes) {
        final measured = _record(probes, probe);
        if (measured[_status] == _failed) continue;
        deltas[probe] = measured[_delta]! as int;
        dartDeltas[probe] = measured[_dartDelta]! as int;
      }
      expect(checkSizeRelations(deltas), report['sizeRelationViolations']);
      expect(
          checkSizeRelations(dartDeltas), report['dartSizeRelationViolations']);
    });
  });
}
