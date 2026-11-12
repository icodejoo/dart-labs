import 'dart:convert';
import 'dart:io';

import 'package:flutter_driver/flutter_driver.dart';
import 'package:integration_test/integration_test_driver.dart';

import '../response_writer.dart';

/// 先保存设备原始响应，再汇总；冷首帧可缺少完整 Raster。
Future<void> main() async {
  await integrationDriver(
      timeout: const Duration(minutes: 4),
      responseDataCallback: (data) async {
        if (data == null) throw const FormatException('设备未返回性能数据');
        final output =
            Directory(Platform.environment['BENCH_PERF_OUTPUT'] ?? 'build');
        final runId = DateTime.now().toUtc().microsecondsSinceEpoch.toString();
        await saveBenchResponse(
            data,
            output,
            runId,
            (timeline) => TimelineSummary.summarize(Timeline.fromJson(timeline))
                .summaryJson);
        final captures = data['perf_images'];
        if (captures is Map<String, dynamic>) {
          for (final entry in captures.entries) {
            await File('${output.path}/${entry.key}.png')
                .writeAsBytes(base64Decode(entry.value as String));
          }
          await File('${output.path}/capture_metadata.json').writeAsString(
              '${const JsonEncoder.withIndent('  ').convert(data['perf_capture_metadata'])}\n');
        }
      });
}
