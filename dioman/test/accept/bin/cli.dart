// ignore_for_file: avoid_relative_lib_imports
// test/accept/lib 是仓库内执行器源码，按目标目录使用相对导入。
import '../lib/literals.dart';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import '../lib/common.dart';
import '../lib/runner.dart';

/// arguments 的测试辅助入口。
/// 读取命令行参数，所有未知参数均报错。
Map<String, String> arguments(List<String> args) {
  final out = <String, String>{};
  for (final arg in args) {
    final pair = arg.replaceFirst(RegExp(r'^--'), tkEmpty).split(tkEquals);
    if (pair.length != 2 ||
        !{tkTestkit, tkNetworks, tkStyles, tkFilter, tkReport, tkJobs}
            .contains(pair[0])) {
      throw ArgumentError(
          '用法: dart run test/accept/bin/cli.dart --networks=normal --styles=http --filter=前缀 --report=coverage/accept/normal.json');
    }
    out[pair[0]] = pair[1];
  }
  return out;
}

/// main 的测试辅助入口。
/// 有界并发执行场景，输出每项唯一结论并持久化完整证据。
Future<void> main(List<String> args) async {
  final opts = arguments(args);
  final health = ioClient(serverUrl);
  try {
    await health.get<dynamic>(tkTPing,
        options: Options(headers: {
          runHeader:
              'dioman-preflight-${DateTime.now().microsecondsSinceEpoch}-$pid'
        }));
  } finally {
    health.close(force: true);
  }
  final probe = ioClient(netemUrl);
  try {
    await probe.get<dynamic>(tkPresets);
  } finally {
    probe.close(force: true);
  }
  final root = opts[tkTestkit] ?? tkEWorkspacesApiWsDemoTestkit;
  final files = Directory('$root/scenarios')
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith(tkJson))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  final results = <Map<String, dynamic>>[];
  final session = 'dioman-${DateTime.now().microsecondsSinceEpoch}-$pid';
  final report = File(opts[tkReport] ?? 'coverage/accept/latest.json');
  await report.parent.create(recursive: true);
  var cpuBlocked = false;
  var infrastructureUnavailable = false;
  final activeRuns = <ScenarioRun>{};
  final plan = <(Map<String, dynamic>, String, String)>[];
  for (final file in files) {
    final scenarios = jsonDecode(await file.readAsString()) as List;
    for (final raw in scenarios) {
      final s = obj(raw);
      // --filter 可用逗号分隔多个子串，命中任意一个即选中。
      if (opts[tkFilter] != null &&
          !opts[tkFilter]!
              .split(tkComma)
              .any((part) => '${s[tkId]}'.contains(part))) {
        continue;
      }
      for (final n in matrixNetworks) {
        if (opts[tkNetworks] != null &&
            !opts[tkNetworks]!.split(tkComma).contains(n)) {
          continue;
        }
        for (final style in [tkHttp, tkBusiness]) {
          if (opts[tkStyles] != null &&
              !opts[tkStyles]!.split(tkComma).contains(style)) {
            continue;
          }
          plan.add((s, n, style));
        }
      }
    }
  }
  var next = 0;
  final jobs = int.parse(opts[tkJobs] ?? tk1);
  if (jobs < 1 || jobs > 4) throw ArgumentError('jobs 仅允许 1..4');

  /// 一个工作协程顺序领取场景；不会启动其他 agent。
  /// worker 的测试辅助入口。
  Future<void> worker() async {
    while (next < plan.length &&
        !cpuBlocked &&
        !infrastructureUnavailable &&
        !serviceBlocked) {
      final seq = next++;
      final (s, n, style) = plan[seq];
      final execution = ScenarioRun(s, n, style, '$session-$seq');
      activeRuns.add(execution);
      final result = await execution.execute();
      activeRuns.remove(execution);
      results.add(result);
      stdout.writeln(
          '${result[tkStatus]} ${s[tkId]} $n@$style ${result[tkReasons]}');
      File('${report.path}.ndjson').writeAsStringSync(
          '${jsonEncode({tkSession: session, ...result})}\n',
          mode: FileMode.append);
      if (result[tkCpuBlocked] == true || serviceBlocked) {
        cpuBlocked = true;
      }
      if (result[tkInfrastructureUnavailable] == true) {
        infrastructureUnavailable = true;
      }
      if (cpuBlocked || infrastructureUnavailable) {
        for (final other in activeRuns) {
          other.stop();
        }
        break;
      }
    }
  }

  await Future.wait(List.generate(jobs, (_) => worker()));
  report.writeAsStringSync(const JsonEncoder.withIndent(tkJsonIndent).convert({
    tkSession: session,
    tkResults: results,
    tkPlanned: plan.length,
    tkExecuted: results.length,
    tkInterrupted: cpuBlocked || infrastructureUnavailable,
    'remaining': plan.length - results.length,
  }));
  final counts = {
    for (final status in [tkPassed, tkFailed, tkSkipped])
      status: results.where((r) => r[tkStatus] == status).length
  };
  stdout.writeln(jsonEncode(counts));
  if (cpuBlocked) stderr.writeln('检测到服务端 429/503 或 CPU 熔断，按要求停止；未重启服务。');
  if (infrastructureUnavailable) stderr.writeln('业务或控制服务不可达，已中断；未启动或重启服务。');
  if (counts[tkFailed]! > 0 || cpuBlocked) exitCode = 1;
}
