// ignore_for_file: avoid_relative_lib_imports
// test/accept/lib 是仓库内执行器源码，按目标目录使用相对导入。
import 'dart:convert';
import 'dart:io';
import '../lib/common.dart';
import '../lib/literals.dart';

/// readJson 的测试辅助入口。
/// 读取可选的 JSON 对象，不制造不存在的运行证据。
Map<String, dynamic> readJson(String path) => File(path).existsSync()
    ? obj(jsonDecode(File(path).readAsStringSync()))
    : {};

/// 本轮逐项日志复核后的分层定位，不把执行器时序问题归咎于库。
const failureResolutions = {
  'cancel.single': [tkEmpty2, 'scenarios/cancel.json：连接拒绝与主动取消竞态，保留零命中及资源释放断言'],
  'combo.flap-share-cache-loading': [
    tkEmpty2,
    'scenarios/combos.json：flap 不固定 loading 次数，缓存命中允许不显示'
  ],
  'loading.delay-fast-never-shows': [
    tkEmpty2,
    'scenarios/loading.json：offline/DNS 不保证在显示延迟内完成，只要求成对关闭'
  ],
  'network.flap-no-retry': [
    tkEmpty2,
    'scenarios/network.json：增加小于离线窗口的连接预算，防止系统 TCP 重试跨窗'
  ],
  'retry.flap-no-retry-then-ok': [
    tkEmpty2,
    'scenarios/retry.json：retry.max=0 与短连接预算共同确定恢复前失败'
  ],
  'offline.flap-recovers': [
    tkEmpty3,
    'test/accept/lib/runner.dart：flap 的宿主探测预算缩短为 500ms，在离线窗口内采样'
  ],
  'retry.401-goes-refresh-first': [
    tkEmpty3,
    'test/accept/bin/cli.dart：移除逐项重编码完整历史报告，避免阻塞事件循环使新令牌过期'
  ],
  'share.end-last-wins': [
    tkEmpty3,
    'test/accept/bin/cli.dart：改为增量 NDJSON，避免阻塞使后续调用错过首发在途窗口'
  ],
  'timeout.connect-blackhole': [
    tkEmpty2,
    'scenarios/timeout.json：代理接受 TCP 连接，改验连接成功后接收超时'
  ],
};

/// main 的测试辅助入口。
/// 汇总实际运行、未执行项、逐 API 证据与独立的 lcov 指标。
void main(List<String> args) {
  final matrixFile = args.isEmpty ? tkAcceptResultsAllInitialJson : args.first;
  final sources = args.isEmpty ? [matrixFile] : args;
  final observed = [
    for (final source in sources)
      ...(readJson(source)[tkResults] as List? ?? []).map(obj)
  ];
  final keys = {
    for (final r in observed)
      '${r[tkScenario]}@${r[tkNetwork]}@${r[tkStyle]}': r
  };
  final actual = keys.values.toList();
  final plan = <Map<String, dynamic>>[];
  var declaredCombinations = 0;
  for (final file in Directory(r'E:\workspaces\api-ws-demo\testkit\scenarios')
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith(tkJson))) {
    for (final raw in jsonDecode(file.readAsStringSync()) as List) {
      final s = obj(raw);
      declaredCombinations += (s[tkNetworks] as List).length *
          (s[tkStyles] as List? ?? [tkHttp, tkBusiness]).length;
      for (final n in matrixNetworks) {
        for (final style in [tkHttp, tkBusiness]) {
          final key = '${s[tkId]}@$n@$style';
          plan.add(keys[key] ??
              {
                tkScenario: s[tkId],
                tkNetwork: n,
                tkStyle: style,
                tkAdapter: tkIo,
                tkStatus: tkSkipped,
                tkReasons: ['未执行：验收中断或报告未包含此项；不计为能力缺失']
              });
        }
      }
    }
  }
  final counts = {
    for (final status in [tkPassed, tkFailed, tkSkipped])
      status: plan.where((r) => r[tkStatus] == status).length
  };
  final previousFailures =
      (readJson(tkAcceptResultsAllInitialJson)[tkResults] as List? ?? [])
          .map(obj)
          .where((r) => r[tkStatus] == tkFailed)
          .toList();
  final rechecks = [
    for (final previous in previousFailures)
      {
        tkScenario: previous[tkScenario],
        tkNetwork: previous[tkNetwork],
        tkStyle: previous[tkStyle],
        'previous_run_id': previous[tkRunId],
        tkCurrent: keys[
            '${previous[tkScenario]}@${previous[tkNetwork]}@${previous[tkStyle]}'],
      }
  ];
  final triage = [
    for (final failed
        in (readJson('test/accept/results/all-resume.json')[tkResults] as List? ??
                [])
            .map(obj)
            .where((r) => r[tkStatus] == tkFailed))
      {
        tkScenario: failed[tkScenario],
        tkNetwork: failed[tkNetwork],
        tkStyle: failed[tkStyle],
        'original_run_id': failed[tkRunId],
        tkReasons: failed[tkReasons],
        'layer': failureResolutions[failed[tkScenario]]?.first ?? '尚未定位',
        'resolution': failureResolutions[failed[tkScenario]]?.last,
        tkCurrent: keys[
            '${failed[tkScenario]}@${failed[tkNetwork]}@${failed[tkStyle]}'],
      }
  ];
  File(tkAcceptResultsFailureTriageJson).writeAsStringSync(
      const JsonEncoder.withIndent(tkJsonIndent).convert(triage));
  final evidence = readJson(tkAcceptResultsApiEvidenceJson);
  final hits = obj(evidence[tkHits]);
  final serverObservations = (evidence[tkObservations] as List? ?? [])
      .map(obj)
      .where((o) => obj(o[tkServer])[tkLog] is List)
      .toList();
  final serverVerified = serverObservations.isNotEmpty &&
      (obj(serverObservations.last[tkServer])[tkLog] as List).isNotEmpty;
  final inventory =
      (jsonDecode(File(tkAcceptApiInventoryJson).readAsStringSync()) as List)
          .map(obj)
          .toList();
  final covered = inventory
      .where((r) => serverVerified && hits.containsKey(r[tkApi]))
      .length;
  final apiReport = {
    tkDeclared: inventory.length,
    tkVerified: evidence.isEmpty ? null : covered,
    tkPercent: evidence.isEmpty ? null : 100 * covered / inventory.length,
    tkReason: evidence.isEmpty ? '专用真实服务 API 探针尚未完成，不从普通场景或单测行覆盖推断 100%' : null,
    tkItems: [
      for (final r in inventory)
        {
          ...r,
          'evidence': hits[r[tkApi]] ?? [],
          'run_id': evidence[tkRunId],
          'server_log': serverVerified
              ? 'api-evidence.json#/observations/${(evidence[tkObservations] as List).length - 1}/server/log'
              : null,
          tkScope: '真实服务探针中的构造、读取或调用覆盖；metadata/兼容 API 不独立产生 HTTP 请求',
          tkVerified: serverVerified && hits.containsKey(r[tkApi])
        }
    ],
  };
  var linesFound = 0;
  var linesHit = 0;
  final lcov = File('coverage/final-local.info');
  if (lcov.existsSync()) {
    for (final line in lcov.readAsLinesSync()) {
      if (!line.startsWith('DA:')) continue;
      final fields = line.substring(3).split(tkComma);
      linesFound++;
      if (int.parse(fields[1]) > 0) linesHit++;
    }
  }
  final report = {
    'generated_at': DateTime.now().toIso8601String(),
    'matrix_source': matrixFile,
    'matrix_reruns': sources.skip(1).toList(),
    'real_executed': actual.where((r) => r[tkStatus] != tkSkipped).length,
    'matrix_counts': counts,
    tkExecuted: actual.length,
    tkPlanned: plan.length,
    'matrix_complete': actual.length == plan.length,
    'declared_combinations': declaredCombinations,
    'skipped_unlisted_combinations': plan.length - declaredCombinations,
    'skipped_declared_combinations':
        counts[tkSkipped]! - (plan.length - declaredCombinations),
    'verification': readJson('test/accept/results/verification.json'),
    'proxy_cleanup': readJson('test/accept/results/proxy-cleanup.json'),
    'prior_failure_recheck': {
      'previous_failed': previousFailures.length,
      tkCounts: {
        for (final status in [tkPassed, tkFailed, tkSkipped])
          status: rechecks
              .where((r) => obj(r[tkCurrent])[tkStatus] == status)
              .length
      },
      tkItems: rechecks,
    },
    'failure_triage': tkAcceptResultsFailureTriageJson,
    'baseline': {
      tkSource: tkAcceptResultsNormalHttpFinalJson,
      tkNote: '历史正常网络 HTTP 基线；新加的 17 插件场景及最后裸令牌修正尚未真实复验',
      tkCounts: {
        for (final status in [tkPassed, tkFailed, tkSkipped])
          status: (readJson(tkAcceptResultsNormalHttpFinalJson)[tkResults]
                      as List? ??
                  [])
              .where((r) => obj(r)[tkStatus] == status)
              .length
      }
    },
    tkPublicApi: {
      tkDeclared: inventory.length,
      tkVerified: apiReport[tkVerified],
      tkPercent: apiReport[tkPercent],
      'complete': evidence.isNotEmpty && covered == inventory.length
    },
    tkUnitLineCoverage: {
      tkSource: lcov.path,
      'found': linesFound,
      tkHit: linesHit,
      tkPercent: linesFound == 0 ? null : 100 * linesHit / linesFound,
      tkNote: '此项来自库级测试，不能代替真实 api-ws-demo 的公开选项覆盖率'
    },
    'real_powerset': readJson(tkAcceptResultsPowersetSummaryJson),
    'runs': plan,
  };
  const encoder = JsonEncoder.withIndent(tkJsonIndent);
  File('coverage/accept/api-coverage.json')
      .writeAsStringSync(encoder.convert(apiReport));
  File('coverage/accept/audit.json').writeAsStringSync(encoder.convert(report));
  stdout.writeln(jsonEncode({
    tkCounts: counts,
    tkExecuted: actual.length,
    tkPlanned: plan.length,
    tkApi: report[tkPublicApi],
    tkUnitLineCoverage: report[tkUnitLineCoverage]
  }));
}
