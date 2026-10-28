import 'literals.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';
import 'client.dart';
import 'common.dart';
import 'plugin_rules.dart';

/// 判定为"与 dioman 设计不适用"的场景及原因（原因必须以 `不适用：` 开头，
/// 汇总时据此不计入结论）。
///
/// dioman 的 mock 是传输层 adapter（[DiomanMockAdapter]），位于 cache / share
/// 之下：
/// - 回落的真实数据可被缓存，第二次直接命中缓存，不再探测 mock；
/// - 相同的并发请求先在 share 层合并，只发一次 mock 探测。
/// 这两个场景按"mock 在 cache/share 之上"的次数断言，与该设计必然不同。
const designDifferenceScenarios = <String, String>{
  'combo.cache-mock-fallback-cached-once':
      '不适用：dioman 的 mock 位于传输层，回落的真实数据会被缓存，第二次命中缓存，不再探测 mock',
  'combo.mock-share-fallback-single-flight':
      '不适用：dioman 的 mock 位于传输层，相同的并发请求先在 share 层合并，只发一次 mock 探测，'
          '场景按总命中次数控制 404 会错位',
};

/// 封装 ScenarioRun 测试夹具。
/// 一轮场景的解释器、观测与生命周期。
class ScenarioRun {
  /// 构造独立测试实例。
  /// 每项独立创建代理与隔离标识。
  ScenarioRun(this.scenario, this.network, this.style, this.runId);

  /// 场景定义。
  final Map<String, dynamic> scenario;

  /// 起始网络。
  final String network;

  /// 起始响应风格。
  final String style;

  /// 唯一轮次标识。
  final String runId;

  /// 服务旁路客户端。
  final server = ioClient(serverUrl);

  /// netem 控制客户端。
  final netem = ioClient(netemUrl);

  /// 被测客户端。
  ScenarioClient? client;

  /// 仅保存本轮创建的代理标识。
  String? proxyId;

  /// 本轮代理地址。
  String? proxyBase;

  /// 所有在途取消令牌。
  final active = <CancelToken>{};

  /// 每次原生批量取消实际命中的令牌数。
  final cancelAllCounts = <int>[];

  /// 后台步骤。
  final fired = <Future<void>>[];

  /// 请求最终事实。
  final records = <String, dynamic>{};

  /// 请求完成顺序。
  final order = <String>[];

  /// 失败原因。
  final failures = <String>[];

  /// 服务端最终观测。
  Map<String, dynamic> observation = {};

  /// 代理最终统计。
  Map<String, dynamic> proxyStats = {};

  /// 超时后停止解释新步骤。
  bool stopped = false;

  /// CPU 熔断命中后停止整个验收。
  bool cpuBlocked = false;

  /// 控制面或服务观测不可达时停止领取新场景。
  bool infrastructureUnavailable = false;

  /// stop 的测试实现。
  /// 中断本轮逻辑请求，不操作任何服务进程。
  void stop() {
    stopped = true;
    for (final token in active.toList()) {
      token.cancel('testkit interrupted');
    }
  }

  /// merge 的测试实现。
  /// 合并预期，嵌套字段递归覆盖。
  static Map<String, dynamic> merge(
          Map<String, dynamic> a, Map<String, dynamic> b) =>
      {
        ...a,
        for (final e in b.entries)
          e.key: e.value is Map && a[e.key] is Map
              ? merge(obj(a[e.key]), obj(e.value))
              : e.value,
      };

  /// expectation 的测试实现。
  /// 当前网络和风格的预期。
  Map<String, dynamic> get expectation {
    final all = obj(scenario[tkExpect]);
    var out = <String, dynamic>{};
    for (final key in ['*', '*@$style', network, '$network@$style']) {
      out = merge(out, obj(all[key]));
    }
    return out;
  }

  /// observe 的测试实现。
  /// 旁路读取本轮观测。
  Future<Map<String, dynamic>> observe() async =>
      obj(obj((await server.get<dynamic>('/t/runs/$runId',
              options: Options(headers: {runHeader: runId})))
          .data)[tkData]);

  /// bypass 的测试实现。
  /// 旁路环境准备请求，不经过被测插件链。
  Future<Map<String, dynamic>> bypass(String path,
      {dynamic data, String method = tkPOST}) async {
    final r = await server.request<dynamic>(path,
        data: data, options: Options(method: method, headers: client!.headers));
    if (logical(r) >= 400) throw StateError('旁路 $path 失败: ${r.data}');
    return obj(obj(r.data)[tkData]);
  }

  /// setNetwork 的测试实现。
  /// 新建或切换自己拥有的代理。
  Future<void> setNetwork(dynamic value) async {
    if (value == tkDns) {
      client?.dio.options.baseUrl = tkHttpNonexistentInvalid47080;
      return;
    }
    final profile = value == tkFlap ? tkOffline : value;
    if (proxyId == null) {
      final p = obj((await netem.post<dynamic>(tkProxies,
              data: {tkUpstream: upstream, tkProfile: profile}))
          .data);
      proxyId = '${p[tkId]}';
      proxyBase = 'http://127.0.0.1:${p[tkPort]}';
      final journal = File(tkAcceptResultsProxiesNdjson);
      journal.parent.createSync(recursive: true);
      journal.writeAsStringSync(
          '${jsonEncode({
                tkRunId: runId,
                tkCreated: p,
                tkControl: netemUrl,
                tkUpstream: upstream
              })}\n',
          mode: FileMode.append);
    } else {
      await netem.put<dynamic>('/proxies/$proxyId', data: {tkProfile: profile});
    }
    if (value == tkFlap) {
      await netem.post<dynamic>('/proxies/$proxyId/schedule', data: [
        {'at_ms': 1500, tkProfile: tkNormal}
      ]);
    }
    client?.dio.options.baseUrl = proxyBase!;
  }

  /// probe 的测试实现。
  /// 对探测能力提供真实连通性输入。
  Future<void> probe(CancelToken token) async {
    final c = client!;
    if (!c.plugins.containsKey(tkOffline)) return;
    final d = ioClient(c.dio.options.baseUrl,
        budget: network == tkFlap ? flapProbeBudget : defaultBudget);
    try {
      await d.get<dynamic>(
          obj(c.plugins[tkOffline])[tkProbe] as String? ?? tkTPing,
          options: Options(headers: c.headers),
          cancelToken: token);
      c.online = true;
    } on DioException {
      c.online = false;
    } finally {
      d.close(force: true);
    }
    c.connectivity.add(c.online);
  }

  /// request 的测试实现。
  /// 发起一个逻辑请求，错误记录为事实，映射错误仍向上传播。
  Future<void> request(Map<String, dynamic> spec, String suffix) async {
    final c = client!;
    final id = '${spec[tkId]}$suffix';
    final options = obj(spec[tkOptions]);
    final extra = c.extras(options, id);
    if (stopped || serviceBlocked) return;
    var token = CancelToken();
    active.add(token);
    final requestStyle = c.style;
    final rec = <String, dynamic>{tkId: id, tkStyle: requestStyle};
    final before = obj(obj(expectation[tkResults])[id]).containsKey(tkFromCache)
        ? await observe()
        : null;
    Timer? cancelTimer;
    Timer? budgetTimer;
    var budgetExpired = false;
    final pluginTotal = obj(c.plugins[tkTimeout])[tkTotalMs];
    final total =
        pluginTotal == null ? null : options[tkTimeoutMs] ?? pluginTotal;
    // 无外部取消时钟、探测或共享跟随者时，由插件注入并登记 token。
    final nativeCancel = c.plugins.containsKey(tkCancel) &&
        !c.plugins.containsKey(tkOffline) &&
        !c.plugins.containsKey(tkShare) &&
        total == null &&
        spec[tkCancelAfterMs] == null;
    if (nativeCancel) {
      extra[tkAcceptOnToken] = (CancelToken registered) {
        active.remove(token);
        token = registered;
        active.add(token);
      };
    } else {
      c.handle.plugin<DiomanCancel>()?.track(token);
    }
    if (total != null) {
      budgetTimer = Timer(ms(total as num), () {
        budgetExpired = true;
        token.requestOptions?.extra[tkAcceptBudgetExpired] = true;
        token.cancel('testkit total budget');
      });
    }
    if (spec[tkCancelAfterMs] != null) {
      cancelTimer = Timer(ms(spec[tkCancelAfterMs] as num),
          () => token.cancel('testkit cancel'));
    }
    try {
      await probe(token);
      final r = await c.dio.request<dynamic>(spec[tkPath] as String,
          queryParameters: obj(spec[tkQuery]),
          data: spec['body'],
          cancelToken: nativeCancel ? null : token,
          options: Options(
              method: spec[tkMethod] as String? ?? tkGET,
              headers: {...c.headers, ...obj(spec['headers'])},
              extra: extra,
              receiveTimeout: options[tkTimeoutMs] == null
                  ? null
                  : ms(options[tkTimeoutMs] as num)));
      var data = r.data;
      if (data is Map &&
          data.containsKey(tkCode) &&
          data[tkCode] == 0 &&
          data.containsKey(tkData)) {
        data = data[tkData];
      }
      rec.addAll({tkOk: true, tkData: data, tkStatus: r.statusCode});
    } catch (e) {
      rec.addAll({
        tkOk: false,
        tkError: classify(e, authTag: c.tags[id], budgetExpired: budgetExpired),
        tkMessage: '$e'
      });
      if (e is DioException &&
          e.response?.statusCode == 503 &&
          '${e.response?.data}'.toLowerCase().contains('cpu')) {
        cpuBlocked = true;
      }
    } finally {
      cancelTimer?.cancel();
      budgetTimer?.cancel();
      active.remove(token);
      if (!nativeCancel) c.handle.plugin<DiomanCancel>()?.untrack(token);
      records[id] = rec;
      order.add(id);
    }
    if (before != null) {
      final after = await observe();
      rec[tkReached] =
          (after[tkTotal] as int? ?? 0) > (before[tkTotal] as int? ?? 0);
    }
  }

  /// step 的测试实现。
  /// 解释契约全部十六种 step，组合步骤递归执行。
  Future<void> step(Map<String, dynamic> s, [String suffix = tkEmpty]) async {
    if (stopped || serviceBlocked) return;
    if (s.length != 1) throw StateError('step 必须只有一个键');
    final k = s.keys.single;
    final v = s[k];
    final c = client!;
    switch (k) {
      case tkRequest:
        await request(obj(v), suffix);
      case 'sequence':
        for (final x in v as List) {
          await step(obj(x), suffix);
        }
      case tkParallel:
        await Future.wait((v as List).map((x) => step(obj(x), suffix)));
      case 'fire':
        fired.add(
            step(obj(v), suffix).catchError((Object error, StackTrace stack) {
          failures.add('fire 步骤失败: $error\n$stack');
        }));
      case 'repeat':
        final r = obj(v);
        for (var i = 0; i < (r['times'] as int); i++) {
          await step(
              obj(r['step']), r['id_suffix'] == false ? suffix : '$suffix#$i');
        }
      case tkWait:
        await pause(v as num);
      case tkLogin:
        final spec = obj(v);
        c.tokens.user = spec[tkUser] as String? ?? tkDioman;
        c.tokens.accept(await bypass(loginPath,
            data: {...spec, tkUsername: c.tokens.user}));
      case tkExpireLocal:
        final expired = await bypass(loginPath,
            data: {tkUsername: c.tokens.user, 'access_ttl_ms': 1});
        c.tokens.replace('Bearer ${expired[tkAccessToken]}', c.tokens.refresh);
        await pause(30);
      case 'set_token':
        c.tokens.mutate(obj(v));
      case 'logout':
        await bypass('/t/auth/logout',
            data: {tkRefreshToken: c.tokens.refresh});
        c.tokens.clear();
      case 'revoke':
        await bypass('/t/auth/revoke', data: {
          tkUsername: obj(v)[tkUser] ?? c.tokens.user,
          tkScope: obj(v)[tkScope] ?? 'all'
        });
      case tkCancelAll:
        await pause(obj(v)['after_ms'] as num? ?? 0);
        cancelAllCounts.add(c.handle.plugin<DiomanCancel>()?.cancelAll() ?? 0);
      case 'clear_cache':
        await c.handle.plugin<DiomanCache>()?.clear();
      case tkNetwork:
        await setNetwork(v);
      case tkStyle:
        c.style = v as String;
      case 'server_reset':
        await bypass('/t/runs/$runId', method: tkDELETE);
      default:
        throw StateError('未知 step: $k');
    }
  }

  /// checkLocal 的测试实现。
  /// 校验全部请求、客户端事件、顺序与持续时间。
  void checkLocal(int duration) {
    final exp = expectation;
    final c = client!;
    for (final e in obj(exp[tkResults]).entries) {
      final actual = obj(records[e.key]);
      final wanted = obj(e.value);
      if (actual.isEmpty) {
        failures.add('${e.key}: 缺少请求结果');
        continue;
      }
      if (wanted.containsKey(tkOk) && wanted[tkOk] != actual[tkOk]) {
        failures
            .add('${e.key}: 预期 ok=${wanted[tkOk]}，实际 ${jsonEncode(actual)}');
      }
      if (wanted.containsKey(tkError)) {
        final errors = wanted[tkError] is List
            ? wanted[tkError] as List
            : [wanted[tkError]];
        final match = errors.any((x) {
          final expected = '$x'.startsWith('status:')
              ? '${actual[tkStyle] == tkHttp ? tkHttp : tkBusiness}:${'$x'.substring(7)}'
              : x;
          return actual[tkOk] == false &&
              (expected == 'any' || expected == actual[tkError]);
        });
        if (!match) {
          failures
              .add('${e.key}: 预期错误 $errors，实际 ${actual[tkError] ?? tkEmpty5}');
        }
      }
      if (wanted.containsKey(tkData) &&
          !subset(actual[tkData], wanted[tkData])) {
        failures.add('${e.key}: data 子集不符');
      }
      if (wanted.containsKey(tkHit) &&
          obj(obj(actual[tkData])[tkMeta])[tkHit] != wanted[tkHit]) {
        failures.add(
            '${e.key}: hit 不符，实际 ${obj(obj(actual[tkData])[tkMeta])[tkHit]}，预期 ${wanted[tkHit]}');
      }
      if (wanted.containsKey(tkFromCache) &&
          actual[tkReached] != !(wanted[tkFromCache] as bool)) {
        failures.add('${e.key}: from_cache 无服务端证据或不符');
      }
    }
    if (exp[tkOrder] != null && !subset(order, exp[tkOrder])) {
      failures.add('order=${jsonEncode(order)}，预期 ${jsonEncode(exp[tkOrder])}');
    }
    range(failures, tkDurationMs, duration, exp[tkDurationMs]);
    final events = eventSnapshot();
    for (final e in obj(exp[tkClient]).entries) {
      if (e.key == tkLoading) {
        if (!subset(c.loadingEvents, e.value)) {
          failures.add('loading=${c.loadingEvents}，预期 ${e.value}');
        }
      } else {
        range(failures, 'client.${e.key}', events[e.key] as num, e.value);
      }
    }
    if (active.isNotEmpty) failures.add('pending_after=${active.length}');
    var balance = 0;
    for (final value in c.loadingEvents) {
      balance += value ? 1 : -1;
      if (balance < 0 || balance > 1) {
        failures.add('loading 事件未成对');
        break;
      }
    }
    if (balance != 0) failures.add('loading 结束时未关闭');
  }

  /// eventSnapshot 的测试实现。
  /// 保留事件次数与完整序列。
  Map<String, dynamic> eventSnapshot() => {
        tkCancelAll: cancelAllCounts,
        tkLoading: client!.loadingEvents,
        tkNotify: client!.notices.length,
        'messages': client!.notices,
        tkRefresh: client!.refreshCount,
        tkExpired: client!.expiredCount,
        tkDenied: client!.deniedCount,
        tkPendingAfter: active.length,
      };

  /// checkServer 的测试实现。
  /// 校验服务端统计，返回错误以支持等待延迟落账。
  List<String> checkServer(Map<String, dynamic> obs) {
    final out = <String>[];
    final wanted = obj(expectation[tkServer]);
    for (final e in wanted.entries) {
      if (e.key == tkByKey || e.key == 'by_path') {
        for (final item in obj(e.value).entries) {
          range(out, 'server.${e.key}.${item.key}',
              obj(obs[e.key])[item.key] as num? ?? 0, item.value);
        }
      } else {
        final count = e.key == tkAborted
            ? (obs[tkLog] as List? ?? [])
                .where((x) => obj(x)[tkAborted] == true)
                .length
            : obs[e.key] as num? ?? 0;
        range(out, 'server.${e.key}', count, e.value);
      }
    }
    return out;
  }

  /// execute 的测试实现。
  /// 执行、断言并在 finally 中关闭仅属于自己的代理。
  Future<Map<String, dynamic>> execute() async {
    final watch = Stopwatch()..start();
    final result = <String, dynamic>{
      tkScenario: scenario[tkId],
      tkNetwork: network,
      tkStyle: style,
      tkAdapter: tkIo,
      tkRunId: runId
    };
    final missing =
        (scenario[tkRequires] as List).where((x) => !capabilities.contains(x));
    final excluded = !(scenario[tkNetworks] as List).contains(network) ||
        !(scenario[tkStyles] as List? ?? [tkHttp, tkBusiness]).contains(style);
    // 未声明的格子仍按"未声明"记，只有声明过的格子才标设计差异。
    final designDifference =
        excluded ? null : designDifferenceScenarios['${scenario[tkId]}'];
    if (missing.isNotEmpty ||
        expectation[tkSkip] != null ||
        designDifference != null ||
        excluded) {
      server.close(force: true);
      netem.close(force: true);
      return {
        ...result,
        tkStatus: tkSkipped,
        tkReasons: [
          missing.isNotEmpty
              ? 'skipped: missing ${missing.first}'
              // 主动注入的 429/503 不再跳过：ServiceGuardAdapter 按注入标记放行，
              // 真实限流/熔断仍整轮停止（2026-10-28 决定）。
              : expectation[tkSkip] ??
                  designDifference ??
                  '场景未声明此网络或风格；不推断未定义的正确预期'
        ]
      };
    }
    try {
      await setNetwork(network);
      client = ScenarioClient(scenario, runId,
          network == tkDns ? tkHttpNonexistentInvalid47080 : proxyBase!, style);
      if ('${scenario[tkId]}'.startsWith(tkPlugins2)) {
        result[tkRules] = verifyPluginRules(client!);
      }
      final bodyWatch = Stopwatch()..start();
      final body = () async {
        for (final s in scenario[tkSteps] as List) {
          await step(obj(s));
        }
        for (var i = 0; i < fired.length; i++) {
          await fired[i];
        }
      }();
      try {
        await body.timeout(ms(scenario[tkTimeoutMs] as num? ?? 20000));
      } on TimeoutException {
        stopped = true;
        failures.add('场景总超时');
        for (final t in active.toList()) {
          t.cancel('run timeout');
        }
        await body.timeout(ms(12000));
      }
      final duration = bodyWatch.elapsedMilliseconds;
      await pause(
          (obj(client!.plugins[tkLoading])[tkDelayCloseMs] as num? ?? 0) + 40);
      checkLocal(duration);
      final deadline = DateTime.now().add(ms(1500));
      while (true) {
        observation = await observe();
        final f = checkServer(observation);
        if (f.isEmpty || DateTime.now().isAfter(deadline)) {
          failures.addAll(f);
          break;
        }
        await pause(50);
      }
      result['events'] = eventSnapshot();
      result['records'] = records;
      result[tkOrder] = order;
      result[tkPlugins] = client!.handle.plugins.map((p) => p.name).toList();
    } catch (e, st) {
      if (e is DioException &&
          e.type == DioExceptionType.connectionError &&
          {serverUrl, netemUrl}.contains(e.requestOptions.uri.origin)) {
        infrastructureUnavailable = true;
      }
      failures.add('执行器: $e\n$st');
    } finally {
      stopped = true;
      for (final t in active.toList()) {
        t.cancel(tkTeardown);
      }
      if (client != null) await client!.dispose();
      if (proxyId != null) {
        try {
          proxyStats =
              obj((await netem.get<dynamic>('/proxies/$proxyId/stats')).data);
          await netem.delete<dynamic>('/proxies/$proxyId');
          File(tkAcceptResultsProxiesNdjson).writeAsStringSync(
              '${jsonEncode({tkRunId: runId, tkDeleted: proxyId})}\n',
              mode: FileMode.append);
        } catch (e) {
          failures.add('代理清理失败: $e');
        }
      }
      if (client != null) {
        final deadline = DateTime.now().add(ms(2000));
        try {
          do {
            observation = await observe();
            if (observation[tkInflight] == 0) break;
            await pause(50);
          } while (DateTime.now().isBefore(deadline));
          if (observation[tkInflight] != 0) {
            failures.add('服务端 inflight=${observation[tkInflight]}');
          }
        } catch (e) {
          infrastructureUnavailable = true;
          failures.add('最终观测失败: $e');
        }
      }
      server.close(force: true);
      netem.close(force: true);
    }
    return {
      ...result,
      tkStatus: failures.isEmpty ? tkPassed : tkFailed,
      tkReasons: failures,
      tkDurationMs: watch.elapsedMilliseconds,
      tkServer: observation,
      'netem': proxyStats,
      tkCpuBlocked: cpuBlocked || serviceBlocked,
      tkInfrastructureUnavailable: infrastructureUnavailable,
      'proxyId': proxyId
    };
  }
}
