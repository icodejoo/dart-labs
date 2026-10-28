// ignore_for_file: avoid_relative_lib_imports
// 集成层：real_service
@Tags(['real'])
library;

import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';
import '../accept/bin/cli.dart' as cli;
import '../accept/lib/literals.dart';
import '../accept/lib/powerset.dart';
import '../accept/lib/probes.dart';

/// 注册本文件的集成层用例。
void main() {
  test('[Dioman.install] 17 插件单开、双开与全开真实服务验收', runRealPowerset,
      timeout: const Timeout(Duration(hours: 2)));

  test('[Dioman.install] 全部公开 API 的真实服务探针', () async {
    final evidence = await runApiProbes();
    expect(evidence.observations, isNotEmpty);
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('[Dioman.install] testkit 真实服务与 netem 场景矩阵', () async {
    final args = Platform.environment['DIOMAN_ACCEPT_ARGS']?.split(tkSpace) ??
        [
          '--jobs=1',
          '--networks=normal',
          '--styles=http',
          '--report=coverage/accept/normal-http.json'
        ];
    await cli.main(args);
    exitCode = 0;
    final reportPath = args
        .firstWhere((a) => a.startsWith(tkReport2))
        .substring(tkReport2.length);
    final results = (jsonDecode(File(reportPath).readAsStringSync())
        as Map)[tkResults] as List;
    expect(results, isNotEmpty);
    expect(results.where((r) => (r as Map)[tkStatus] == tkFailed), isEmpty,
        reason: '逐项失败原因见 $reportPath');
  }, timeout: const Timeout(Duration(hours: 2)));
}
