import 'dart:convert';
import 'dart:io';

import 'metrics.dart';
import 'pending_metrics.dart';

/// SDK 在冷窗口没有闭合 Raster 事件时抛出的实际错误文本。
const String kBenchEmptyTimelineSummary =
    'The TimelineSummary had no events to summarize.';

/// 汇总原始时间线；由 SDK 适配器或测试夹具提供。
typedef BenchTimelineSummary = Map<String, Object?> Function(
    Map<String, dynamic> timeline);

/// 先无损保存响应和时间线，再汇总；冷首帧失败时保留真实 FrameTiming。
///
/// [summarize] 返回 SDK 指标，稳态异常仍抛出。返回汇总文件路径列表。
Future<List<String>> saveBenchResponse(Map<String, dynamic> data,
    Directory output, String runId, BenchTimelineSummary summarize) async {
  await output.create(recursive: true);
  final encoder = const JsonEncoder.withIndent('  ');
  await File('${output.path}/response_$runId.json')
      .writeAsString('${encoder.convert(data)}\n');
  for (final entry in data.entries) {
    final value = entry.value;
    if (value is Map<String, dynamic> && value.containsKey('traceEvents')) {
      await File('${output.path}/${entry.key}_$runId.timeline.json')
          .writeAsString('${encoder.convert(value)}\n');
    }
  }
  final samples = data['bench_samples'];
  if (samples is! Map<String, dynamic>)
    throw const FormatException('设备未返回 FrameTiming/RSS');
  final paths = <String>[];
  for (final entry in data.entries) {
    final timeline = entry.value;
    if (timeline is! Map<String, dynamic> ||
        !timeline.containsKey('traceEvents')) continue;
    final key = entry.key;
    final reference = key.endsWith('_reference');
    if (!reference &&
        !kBenchSchema.containsKey(key) &&
        !kBenchExperimentScenes.contains(key) &&
        !kPendingFirstFrames.contains(key)) {
      throw FormatException('未知 reportKey: $key');
    }
    final sampled = samples[key];
    Map<String, Object?> summary;
    try {
      summary = summarize(timeline);
    } on Object catch (error) {
      if (error is! StateError ||
          error.message != kBenchEmptyTimelineSummary ||
          !kPendingFirstFrames.contains(key) ||
          sampled is! Map<String, dynamic> ||
          sampled['first_frame_ui_millis'] is! num ||
          (sampled['first_frame_ui_millis'] as num) <= 0) rethrow;
      summary = {
        'sdk_summary_status': 'unavailable',
        'sdk_summary_error': '$error'
      };
    }
    final metrics = <String, Object?>{
      ...summary,
      if (sampled is Map<String, dynamic>) ...sampled,
      kBenchReportKey: reference ? kBenchReference : key,
      kBenchRunId: runId,
      'actual_scene': key,
      'recorded_at': DateTime.now().toUtc().toIso8601String(),
      'device_model': Platform.environment['BENCH_DEVICE_MODEL'],
      'device_serial': Platform.environment['BENCH_DEVICE_SERIAL'],
    };
    if (data['cpu_scene'] == key) {
      metrics['gc_reference_status'] = 'not_measured_in_cpu_window';
    } else if (kBenchSchema[key]?.contains(kBenchExtraGc) ?? false) {
      final ref = data['${key}_reference'];
      if (ref is! Map<String, dynamic>)
        throw FormatException('缺少同轮 GC 参照: $key');
      final actual = countNewGenerationGc(_events(timeline));
      final baseline = countNewGenerationGc(_events(ref));
      metrics['new_gen_gc_count'] = actual;
      metrics['reference_new_gen_gc_count'] = baseline;
      metrics[kBenchExtraGc] = (actual - baseline).clamp(0, actual);
    }
    final path = '${output.path}/${key}_$runId.timeline_summary.json';
    await File(path).writeAsString('${encoder.convert(metrics)}\n');
    paths.add(path);
  }
  return paths;
}

/// 格式错误显式抛出，不能当空时间线。
List<Map<String, Object?>> _events(Map<String, dynamic> timeline) {
  final events = timeline['traceEvents'];
  if (events is! List<Object?>) throw const FormatException('缺少 timeline 事件');
  return events.cast<Map<String, Object?>>();
}
