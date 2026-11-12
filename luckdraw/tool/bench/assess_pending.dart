import 'dart:convert';
import 'dart:io';

import 'metrics.dart';
import 'pending_metrics.dart';

/// 把 JSON 对象按 UTF-8 读入；结构错误保留明确异常。
Map<String, Object?> _object(File file) =>
    jsonDecode(file.readAsStringSync()) as Map<String, Object?>;

/// 汇总本轮独立目录；首帧和 CPU 仅标定，帧时调用唯一 MET2 比较器。
///
/// 用法 `dart run assess_pending.dart <results/pending>`；不访问设备，不改预算。
Future<void> main(List<String> args) async {
  try {
    if (args.length != 1) throw const FormatException('需要本轮结果目录');
    final directory = Directory(args.single);
    final records =
        jsonDecode(File('${directory.path}/runs.json').readAsStringSync())
            as List<Object?>;
    final report = <String, Object?>{};
    final firstFrames = <String, List<double>>{};
    final comparison = Directory('${directory.path}/comparison')
      ..createSync(recursive: true);
    if (comparison.listSync().isNotEmpty) {
      throw const FormatException('comparison 必须为空，防止混入历史采集');
    }
    for (final scene in [
      ...kPendingFirstFrames,
      ...kPendingCpuScenes.map((scene) => 'cpu_$scene'),
      ...kPendingRetests,
    ]) {
      final attempts = records
          .cast<Map<String, Object?>>()
          .where((row) => row['scene'] == scene)
          .toList();
      final valid = attempts.where((row) => row['valid'] == true).toList();
      if (attempts.length > kPendingMaxStarts ||
          valid.length < kPendingRounds ||
          attempts.any((row) =>
              row['binary_sha256'] != attempts.first['binary_sha256'])) {
        throw FormatException('$scene 轮次不足、超过启动上限或 APK 身份不一致');
      }
      final summaries = <Map<String, Object?>>[];
      for (final attempt in valid) {
        final location = Directory('${directory.path}/${attempt['directory']}');
        if (scene.startsWith('cpu_')) {
          final cpu = _object(File('${location.path}/cpu/cpu.json'));
          validatePendingCpuWindow(cpu);
          summaries.add(cpu);
        } else {
          final files = location
              .listSync()
              .whereType<File>()
              .where((file) =>
                  file.path.endsWith('.timeline_summary.json') &&
                  _object(file)[kBenchReportKey] == scene)
              .toList();
          if (files.length != 1) throw FormatException('$scene 每轮必须有唯一汇总');
          summaries.add(_object(files.single));
          if (kPendingRetests.contains(scene)) {
            files.single.copySync(
                '${comparison.path}/${files.single.uri.pathSegments.last}');
          }
        }
      }
      if (kPendingFirstFrames.contains(scene)) {
        final values = summaries
            .map(
                (data) => benchNumber(data[kBenchFirstFrame], kBenchFirstFrame))
            .toList();
        firstFrames[scene] = values;
        report[scene] = {
          'status': '已标定',
          'median_ms': pendingFirstFrameMedian(values),
          'samples_ms': values,
          'budget_passed': false,
          'note': '仅建立实测基线，无批准增量预算，不表示达标'
        };
      } else if (scene.startsWith('cpu_')) {
        report[scene] = {
          'status': '已标定',
          'rounds': summaries,
          'note': '进程与线程CPU原生采样；无批准CPU预算，不表示达标'
        };
      }
    }
    for (final scene in kPendingFirstFrames.skip(1)) {
      (report[scene]! as Map<String, Object?>)['increment_ms'] =
          pendingFirstFrameIncrement(
              firstFrames[kPendingFirstFrames.first]!, firstFrames[scene]!);
    }
    final bench = File.fromUri(Platform.script).parent;
    final result = await Process.run(Platform.resolvedExecutable, [
      'run',
      '${bench.path}/compare.dart',
      '--input=${comparison.path}',
      '--scenarios=${kPendingRetests.join(',')}',
      '--rss-all-scenes',
      '--output=${directory.path}/frame_assessment.json',
    ]);
    await File('${directory.path}/compare.stdout.log')
        .writeAsString('${result.stdout}');
    await File('${directory.path}/compare.stderr.log')
        .writeAsString('${result.stderr}');
    if (result.exitCode != 0 && result.exitCode != 1)
      throw StateError('比较器异常退出');
    final frames =
        _object(File('${directory.path}/frame_assessment.json'))['scenarios']!
            as Map<String, Object?>;
    for (final entry in frames.entries) {
      final value = entry.value! as Map<String, Object?>;
      report[entry.key] = {
        ...value,
        'status': switch (value[kBenchStatus]) {
          kBenchPass =>
            value[kBenchDesignStatus] == kBenchCalibratedDesign ? '已标定' : '通过',
          kBenchUncertain => '不确定',
          _ => '失败',
        }
      };
    }
    await File('${directory.path}/assessment.json').writeAsString(
        '${const JsonEncoder.withIndent('  ').convert(report)}\n');
    final lines = <String>['# 待真机检查结果', '', '| 项目 | 结论 |', '| --- | --- |'];
    for (final entry in report.entries) {
      final status = (entry.value! as Map<String, Object?>)['status'];
      stdout.writeln('${entry.key}: $status');
      lines.add('| ${entry.key} | $status |');
    }
    lines.add('\n已标定表示建立实测基线或通过既有回归预算，不等于达到最初设计目标。详见 assessment.json。');
    await File('${directory.path}/REPORT.md')
        .writeAsString('${lines.join('\n')}\n');
    exitCode = result.exitCode;
  } on Object catch (error) {
    stderr.writeln('失败: $error');
    exitCode = 1;
  }
}
