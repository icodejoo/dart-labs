// ignore_for_file: avoid_relative_lib_imports
// test/accept/lib 是仓库内执行器源码，按目标目录使用相对导入。
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import '../lib/common.dart';
import '../lib/runner.dart';
import '../lib/literals.dart';

/// main 的测试辅助入口。
/// 只执行方法清单明确列出的格子；历史全场景缺声明审计仍独立保留。
Future<void> main() async {
  final session =
      'dioman-methods-${DateTime.now().microsecondsSinceEpoch}-$pid';
  final health = ioClient(serverUrl);
  final control = ioClient(netemUrl);
  try {
    await health.get<dynamic>(tkTPing,
        options: Options(headers: {runHeader: session}));
    await control.get<dynamic>(tkPresets,
        options: Options(headers: {runHeader: session}));
  } finally {
    health.close(force: true);
    control.close(force: true);
  }
  final plan =
      jsonDecode(File(tkAcceptResultsPluginMatrixPlanJson).readAsStringSync())
          as List;
  final scenarios = <dynamic>[];
  for (final file in Directory('$tkEWorkspacesApiWsDemoTestkit/scenarios')
      .listSync()
      .whereType<File>()) {
    if (file.path.endsWith(tkJson)) {
      scenarios.addAll(jsonDecode(file.readAsStringSync()) as List);
    }
  }
  final byId = {
    for (final scenario in scenarios) obj(scenario)[tkId]: obj(scenario)
  };
  final report = File('coverage/accept/plugin-matrix-final.json');
  report.parent.createSync(recursive: true);
  final journal = File('${report.path}.ndjson').openWrite();
  final results = <Map<String, dynamic>>[];
  var interrupted = false;
  var sequence = 0;
  var planned = 0;
  for (final raw in plan) {
    planned += (obj(raw)[tkNetworks] as List).length *
        (obj(raw)[tkStyles] as List? ?? [tkHttp, tkBusiness]).length;
  }
  try {
    for (final raw in plan) {
      final item = obj(raw);
      for (final network in item[tkNetworks] as List) {
        for (final style in (item[tkStyles] as List? ?? [tkHttp, tkBusiness])
            .cast<String>()) {
          final result = await ScenarioRun(byId[item[tkScenario]]!,
                  network as String, style, '$session-${sequence++}')
              .execute();
          result[tkMethod] = item[tkMethod];
          results.add(result);
          journal.writeln(jsonEncode(result));
          await journal.flush();
          stdout.writeln(
              '${result[tkStatus]} ${item[tkScenario]} $network@$style');
          if (serviceBlocked ||
              result[tkInfrastructureUnavailable] == true ||
              result[tkCpuBlocked] == true) {
            interrupted = true;
            throw StateError('服务要求停止；详情见最后一条真实执行证据');
          }
        }
      }
    }
  } finally {
    await journal.close();
    final counts = <String, int>{};
    for (final result in results) {
      counts.update(result[tkStatus] as String, (n) => n + 1,
          ifAbsent: () => 1);
    }
    report
        .writeAsStringSync(const JsonEncoder.withIndent(tkJsonIndent).convert({
      tkSession: session,
      tkPlanned: planned,
      tkExecuted: results.length,
      tkInterrupted: interrupted,
      tkCounts: counts,
      tkResults: results,
    }));
    stdout.writeln(jsonEncode(counts));
    if (interrupted || (counts[tkFailed] ?? 0) > 0) exitCode = 1;
  }
}
