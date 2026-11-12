import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_driver/flutter_driver.dart';
import 'package:integration_test/integration_test_driver.dart';

import 'file:///C:/ldp/luckdraw/tool/bench/metrics.dart';

/// 设备侧报告中 FrameTiming 与 RSS 样本的键。
const String _samplesKey = 'bench_samples';

/// 将原始 timeline 事件转换为可单测的纯 Dart 对象。
List<Map<String, Object?>> _events(Map<String, dynamic> timeline) {
  final events = timeline['traceEvents'];
  if (events is! List<Object?>) throw const FormatException('缺少 timeline 事件');
  return events.cast<Map<String, Object?>>();
}

/// 优先使用 SDK 的 GC 汇总键，缺失时回退到 timeline 新生代事件。
double _gc(Map<String, dynamic> timeline, Map<String, dynamic> summary) {
  final count = summary['new_gen_gc_count'];
  return count is num
      ? benchNumber(count, 'new_gen_gc_count')
      : countNewGenerationGc(_events(timeline)).toDouble();
}

/// 从 integrationDriver 接收每个 reportKey，保留原始 timeline 与标准汇总。
///
/// 每次运行使用唯一文件名；自定义的实际刷新率、掉帧率与 RSS 写回同一汇总。
Future<void> main() async {
  Directory.current = Platform.environment['BENCH_PERF_OUTPUT']!;
  await integrationDriver(
      timeout: const Duration(minutes: 4),
      responseDataCallback: (data) async {
        if (data == null) throw const FormatException('设备未返回性能数据');
        final captures = data['perf_images'];
        if (captures is Map<String, dynamic>) {
          final directory =
              Directory(Platform.environment['BENCH_PERF_OUTPUT']!);
          for (final entry in captures.entries) {
            await File('${directory.path}/${entry.key}.png')
                .writeAsBytes(base64Decode(entry.value as String));
          }
          await File('${directory.path}/capture_metadata.json').writeAsString(
              '${const JsonEncoder.withIndent('  ').convert(data['perf_capture_metadata'])}\n');
        }
        final samples = data[_samplesKey];
        if (samples is! Map<String, dynamic>) {
          throw const FormatException('设备未返回 FrameTiming/RSS');
        }
        final runId = DateTime.now().toUtc().microsecondsSinceEpoch.toString();
        final output = Directory('.');
        await output.create(recursive: true);
        for (final entry in data.entries) {
          final timeline = entry.value;
          if (timeline is! Map<String, dynamic> ||
              !timeline.containsKey('traceEvents')) {
            continue;
          }
          final key = entry.key;
          final reference = key.endsWith('_reference');
          final scenario = reference ? kBenchReference : key;
          if (!reference && !kBenchSchema.containsKey(scenario)) {
            throw FormatException('未知 reportKey: $key');
          }
          final summary =
              TimelineSummary.summarize(Timeline.fromJson(timeline));
          final name = '${key}_$runId';
          await summary.writeTimelineToFile(name,
              destinationDirectory: output.path, includeSummary: true);
          final metrics = <String, Object?>{
            ...summary.summaryJson,
            kBenchReportKey: scenario,
            kBenchRunId: runId,
            'actual_scene': key,
            'recorded_at': DateTime.now().toUtc().toIso8601String(),
            'device_model': Platform.environment['BENCH_DEVICE_MODEL'],
            'device_serial': Platform.environment['BENCH_DEVICE_SERIAL'],
          };
          final sampled = samples[key];
          if (sampled is Map<String, dynamic>) metrics.addAll(sampled);
          if (kBenchSchema[scenario]?.contains(kBenchExtraGc) ?? false) {
            final ref = data['${key}_reference'];
            if (ref is! Map<String, dynamic>) {
              throw FormatException('缺少同轮 GC 参照: $key');
            }
            final refSummary =
                TimelineSummary.summarize(Timeline.fromJson(ref));
            final actualGc = _gc(timeline, summary.summaryJson);
            final referenceGc = _gc(ref, refSummary.summaryJson);
            metrics['new_gen_gc_count'] = actualGc;
            metrics['reference_new_gen_gc_count'] = referenceGc;
            metrics[kBenchExtraGc] = math.max(0, actualGc - referenceGc);
          }
          if (scenario == 'wheel_first_frame' &&
              _events(timeline)
                  .any((event) => event['name'] == 'luckdraw.layout')) {
            metrics['layout_record_millis'] =
                firstFrameMillis(_events(timeline));
          }
          final file = File('${output.path}/$name.timeline_summary.json');
          await file.writeAsString(
              const JsonEncoder.withIndent('  ').convert(metrics));
        }
      });
}
