import 'dart:convert';
import 'dart:io';

import 'metrics.dart';

export 'metrics.dart';

/// 从 JSON [file] 读取对象；非对象根节点抛出 [FormatException]。
Map<String, Object?> _readObject(File file) {
  final decoded = jsonDecode(file.readAsStringSync());
  if (decoded is! Map<String, Object?>) {
    throw FormatException('JSON 根节点必须是对象: ${file.path}');
  }
  return decoded;
}

/// 对保存窗口分类并比较预算；无设备操作，失败或不确定退出 1。
///
/// 兼容 `--input=<目录> --budgets=<文件> --rss-all-scenes`。默认分类，
/// 也接受 `--classify-windows`；`--output=<文件>` 保存结构化证据。
/// 默认仅比较冻结预算；`--calibrate` 显式生成首版标定建议，不写预算文件。
void main(List<String> args) {
  try {
    final benchDirectory = File.fromUri(Platform.script).parent;
    var input = Directory('${benchDirectory.path}/build');
    var budgets = File('${benchDirectory.path}/budgets.json');
    File? output;
    var rssAllScenes = false;
    Set<String>? selected;
    var calibrate = false;
    for (final arg in args) {
      if (arg == '--rss-all-scenes') {
        rssAllScenes = true;
      } else if (arg == '--calibrate') {
        calibrate = true;
      } else if (arg == '--classify-windows') {
        // 分类默认开启，显式开关便于命令自描述。
      } else if (arg.startsWith('--scenarios=')) {
        final names = arg.substring('--scenarios='.length).split(',');
        if (names.any((name) => !kBenchSchema.containsKey(name)) ||
            names.toSet().length != names.length) {
          throw const FormatException('scenarios 必须是非空、无重复的已知场景');
        }
        selected = names.toSet();
      } else if (arg.startsWith('--input=')) {
        input = Directory(arg.substring('--input='.length));
      } else if (arg.startsWith('--budgets=')) {
        budgets = File(arg.substring('--budgets='.length));
      } else if (arg.startsWith('--output=')) {
        output = File(arg.substring('--output='.length));
      } else {
        throw FormatException('未知参数: $arg');
      }
    }
    final limits = _readObject(budgets);
    final errors = validateStructure(limits, budgets: true);
    if (errors.isNotEmpty) throw FormatException(errors.join('\n'));
    final statusFile = File('${budgets.parent.path}/budgets.status.json');
    Map<String, Object?>? designTargets;
    Map<String, Object?>? floors;
    if (budgets.absolute.uri ==
            File('${benchDirectory.path}/budgets.json').absolute.uri &&
        statusFile.existsSync()) {
      final met2 = _readObject(statusFile)['met2'];
      if (met2 is Map<String, Object?>) {
        designTargets = met2['design_targets'] as Map<String, Object?>?;
        floors = met2['calibrated_floors'] as Map<String, Object?>?;
      }
    }
    final targetErrors = validateStructure(limits, budgets: true);
    if (targetErrors.isNotEmpty) {
      throw FormatException(targetErrors.join('\n'));
    }
    if (!input.existsSync()) throw const FormatException('没有真机采集目录');
    final grouped = <String, List<Map<String, Object?>>>{};
    final ids = <String, Set<String>>{};
    final references = <Map<String, Object?>>[];
    final files = input
        .listSync()
        .whereType<File>()
        .where((file) => file.path.endsWith('.timeline_summary.json'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    for (final file in files) {
      final data = _readObject(file);
      final key = data[kBenchReportKey];
      if (key == kBenchReference) {
        // 兼容旧参照；缺失交付数据只作未分类信息。
        references.add({
          ...data,
          kBenchClassification: data.containsKey(kBenchFps)
              ? !frameDeliveryPassed(data)
                  ? kBenchRealJank
                  : isBackpressureContaminated(data)
                      ? kBenchBackpressure
                      : kBenchClean
              : 'UNCLASSIFIED',
        });
        continue;
      }
      if (key is! String || !kBenchSchema.containsKey(key)) {
        throw FormatException('报告场景未知或缺失: ${file.path}');
      }
      final id = data[kBenchRunId];
      if (id is! String || id.isEmpty || !(ids[key] ??= {}).add(id)) {
        throw FormatException('报告 run_id 缺失或重复: ${file.path}');
      }
      if (key == 'memory_cycles' ||
          (rssAllScenes && kBenchSchema[key]!.contains(kBenchDroppedRatio))) {
        data.addAll(summarizeRss(data));
        stdout.writeln('INFO: $key / $id / $kBenchRssWarmup = '
            '${data[kBenchRssWarmup]} bytes（仅信息，不作门禁）');
      }
      (grouped[key] ??= []).add(data);
    }
    final assessments = <String, Object?>{};
    if (selected != null)
      stdout.writeln('INFO: 仅比较显式场景 ${selected.join(',')}；不代表全场景通过');
    for (final scenario in kBenchSchema.keys) {
      if (selected != null && !selected.contains(scenario)) continue;
      final result = assessScenario(scenario, grouped[scenario] ?? [],
          limits[scenario]! as Map<String, Object?>,
          designTargets: designTargets?[scenario] as Map<String, Object?>?,
          calibratedFloors: floors?[scenario] as Map<String, Object?>?,
          calibrate: calibrate,
          rssLimits: rssAllScenes &&
                  kBenchSchema[scenario]!.contains(kBenchDroppedRatio)
              ? limits['memory_cycles']! as Map<String, Object?>
              : null);
      assessments[scenario] = result;
      stdout.writeln('\n场景 $scenario | 窗口 | fps | 帧数完整比例 | 分类');
      for (final raw in result[kBenchWindows]! as List<Object?>) {
        final window = raw! as Map<String, Object?>;
        stdout.writeln('$scenario | ${window[kBenchRunId]} | '
            '${window[kBenchFps]} | ${window[kBenchDeliveryRatio]} | '
            '${window[kBenchClassification]}');
      }
      stdout.writeln('DELIVERY: $scenario | ${result[kBenchDeliveryPassed]} | '
          '未污染 ${result['clean_count']} / 污染 ${result['contaminated_count']}');
      stdout.writeln('场景 | 指标 | 中位数 | 上限 | 结论 | 原目标');
      final metrics = result[kBenchMetrics]! as Map<String, Object?>;
      for (final entry in metrics.entries) {
        final row = entry.value! as Map<String, Object?>;
        final actual = (row[kBenchMedian] as num?)?.toDouble();
        final limit = (row[kBenchLimit] as num?)?.toDouble();
        final unstable = row[kBenchStable] == false;
        if (unstable) {
          stderr.writeln('UNSTABLE: $scenario/${entry.key}: '
              '未污染窗口极差超出分类型稳定性容差');
        }
        stdout.writeln('$scenario | ${entry.key} | '
            '${actual?.toStringAsFixed(4) ?? "—"} | '
            '${limit?.toStringAsFixed(4) ?? "—"} | '
            '${unstable ? "UNSTABLE" : row[kBenchStatus]} | ${row[kBenchTarget]}'
            '${row[kBenchCalibrated] == true ? "（首版标定）" : ""}');
      }
      stdout.writeln('FRAME_BUDGET: $scenario | ${result[kBenchFrameBudget]}');
      stdout.writeln('DESIGN: $scenario | ${result[kBenchDesignStatus]}');
      stdout.writeln('SCENARIO: $scenario | ${result[kBenchStatus]}');
    }
    stdout.writeln('\n参照窗口（仅报告，不参与场景成本预算）');
    for (final reference in references) {
      stdout.writeln('${reference[kBenchRunId]} | '
          '${reference['actual_scene']} | ${reference[kBenchClassification]}');
    }
    if (output != null) {
      output.parent.createSync(recursive: true);
      output.writeAsStringSync('${const JsonEncoder.withIndent('  ').convert({
            'scenarios': assessments,
            'references': references,
          })}\n');
    }
    final passed = assessments.values.every((raw) {
      final status = (raw! as Map<String, Object?>)[kBenchStatus];
      return status == kBenchPass || status == kBenchInfo;
    });
    stdout.writeln(passed
        ? 'PASS: 全部性能预算通过（回归预算；INFO 不作门禁，不代表全部设计目标达成）'
        : 'FAIL: 存在超预算指标、不稳定或不确定项');
    if (!passed) exitCode = 1;
  } on Object catch (error) {
    stderr.writeln('FAIL: $error');
    exitCode = 1;
  }
}
