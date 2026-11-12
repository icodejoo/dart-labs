import 'dart:async';
import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';
import 'package:flutter/material.dart';
import 'scenario_runtime.dart';
import 'token_manager.dart';

/// 演示传输的可观察延迟。
const _transferDelay = Duration(milliseconds: 600);

/// 取消及 deadline 使用的短预算。
const _shortDelay = Duration(milliseconds: 200);

/// JSON 示例的数据字段。
const _value = 'value';

/// 业务协议的状态码字段。
const _code = 'code';

/// 业务协议的数据字段。
const _data = 'data';

/// 分页查询字段。
const _page = 'page';

/// 排序查询字段。
const _sort = 'sort';

/// 升序排序值。
const _ascending = 'asc';

/// 用户标识字段。
const _id = 'id';

/// 环境配置使用的开发地址。
const _development = 'https://dev.example.invalid';

/// 环境配置使用的生产地址。
const _production = 'https://prod.example.invalid';

/// 场景定义，文案与实际执行使用同一份清单。
class DemoScenario {
  /// 保存双语标题、说明、可复制代码与执行器。
  const DemoScenario(this.id, this.title, this.description, this.code, this.run,
      {this.replayable = true});

  /// 测试与卡片使用的稳定标识。
  final String id;

  /// 双语标题。
  final DemoText title;

  /// 双语说明。
  final DemoText description;

  /// 当前公开 API 的调用片段。
  final String code;

  /// 使用独立资源容器执行演示。
  final Future<void> Function(DemoSession) run;

  /// 静态安装配置无需重放，其余请求演进均可重放。
  final bool replayable;
}

/// 一个导航页面的文案与场景集合。
class DemoGroup {
  /// 保存稳定导航标识和场景集合。
  const DemoGroup(
      this.id, this.title, this.description, this.icon, this.scenarios);

  /// URL hash 使用的页面标识。
  final String id;

  /// 双语页面标题。
  final DemoText title;

  /// 双语页面简介。
  final DemoText description;

  /// 导航图标。
  final IconData icon;

  /// 本页演示卡片。
  final List<DemoScenario> scenarios;
}

/// 将原来一页的场景按职责归组，合并 key 与缓存并补充当前 API。
const demoGroups = [
  DemoGroup(
      'requests',
      DemoText('Requests & results', '请求与结果'),
      DemoText(
          'Shape a request and inspect its result. All responses stay in memory.',
          '整形请求、读取结果；所有响应均来自内存后端。'),
      Icons.swap_horiz_rounded,
      [
        DemoScenario(
            'repath',
            DemoText('Path rewrite', '路径替换'),
            DemoText('Expand {id}, :id and [id]; remove consumed query values.',
                '支持 {id}、:id 和 [id]，移除已消费的查询参数。'),
            "// plugins: [const DiomanRepath()]\nawait api.send<dynamic>('GET', '/users/{id}', query: {'id': 42});",
            _repath),
        DemoScenario(
            'filter',
            DemoText('Query filter', '参数过滤'),
            DemoText('Drop null and blank strings; preserve zero and false.',
                '过滤 null 和空字符串，保留 0 与 false。'),
            "// plugins: [const DiomanFilter()]\nawait api.send<dynamic>('GET', '/items', query: {'q': '', 'limit': null, 'page': 0, 'active': false});",
            _filter),
        DemoScenario(
            'mock',
            DemoText('Inline mock', '内联 Mock'),
            DemoText('METHOD:path routes answer before cache and share.',
                'METHOD:path 路由先于缓存与共享返回。'),
            "// plugins: [DiomanMock(routes: {'GET:/items': (_) => [1, 2]})]\nawait api.get<List<dynamic>>('/items');",
            _mock),
        DemoScenario(
            'result',
            DemoText('HTTP & business result', 'HTTP 与业务结果'),
            DemoText('send returns metadata; request throws expected failures.',
                'send 返回元数据，request 对可预期失败抛出结果。'),
            "final result = await api.send<dynamic>('GET', '/items');\nprint([result.ok, result.status, result.code, failureOf(result)?.kind]);",
            _result),
        DemoScenario(
            'decode',
            DemoText('Decode & raw', '解码与原始响应'),
            DemoText('Decode after success; native transport data is opt-in.',
                '成功后执行 decode，raw 原始传输数据按需开启。'),
            "final value = await api.get<int>('/items', decode: (data) => (data as Map)['value'] as int);\nfinal result = await api.send<dynamic>('GET', '/items', call: const DiomanCall(raw: true));",
            _decode),
      ]),
  DemoGroup(
      'policies',
      DemoText('Request policies', '请求策略'),
      DemoText(
          'Observe cache hits, shared requests, retry attempts and token refresh.',
          '观察缓存命中、共享传输、重试与凭证刷新。'),
      Icons.tune_rounded,
      [
        DemoScenario(
            'cache',
            DemoText('Cache & canonical keys', '缓存与规范化 key'),
            DemoText(
                'Parameter order shares a key; new values send again. Enable per call.',
                '参数顺序不影响 key，参数值变化会重发；按调用启用。'),
            "// plugins: [const DiomanCache()]\nfinal call = DiomanCall(options: {DiomanCache.option: const Duration(minutes: 1)});\nawait api.send<dynamic>('GET', '/items', call: call);",
            _cache),
        DemoScenario(
            'share',
            DemoText('Concurrent sharing', '并发共享'),
            DemoText(
                'Three concurrent callers share one transport with policy start.',
                'start 策略让三个并发调用共享一次传输。'),
            "// plugins: [const DiomanShare()]\nfinal call = DiomanCall(options: {DiomanShare.option: DiomanSharePolicy.start});\nawait Future.wait(List.generate(3, (_) => api.send<dynamic>('GET', '/items', call: call)));",
            _share),
        DemoScenario(
            'retry',
            DemoText('Retry attempts', '失败重试'),
            DemoText(
                'Two HTTP 500 responses, then success; demo uses a short custom delay.',
                '两次 HTTP 500 后成功；本例显式缩短等待。'),
            "// plugins: [const DiomanRetry(max: 2)]\n// Defaults: exponential delay from 300ms, delayMax 10s, Retry-After cap 60s.\nawait api.send<dynamic>('GET', '/items');",
            _retry),
        DemoScenario(
            'auth',
            DemoText('401 token refresh', '401 凭证刷新'),
            DemoText(
                'Refresh the TokenManager once, then resend with the new token.',
                '刷新 TokenManager 凭证，再使用新凭证重发。'),
            "// plugins: [DiomanAuth(tokenManager: tokens,\n//   onRefresh: (store, _) => store.setTokens(accessToken: 'renewed'),\n//   onAccessExpired: (store, _) => store.clear())]\nawait api.send<dynamic>('GET', '/items');",
            _auth),
      ]),
  DemoGroup(
      'lifecycle',
      DemoText('Request lifecycle', '请求生命周期'),
      DemoText(
          'Replay the loading, cancellation, offline queue and whole-request deadline.',
          '重放加载、取消、离线排队与整个逻辑请求的截止时间。'),
      Icons.timelapse_rounded,
      [
        DemoScenario(
            'loading',
            DemoText('Shared loading', '共享加载状态'),
            DemoText('Three active calls share one visible true → false cycle.',
                '三个活跃调用共用一次 true → false 显示周期。'),
            "// plugins: [DiomanLoading(onChanged: (visible) {})]\nprint(api.plugin<DiomanLoadingApi>()?.activeCount);",
            _loading),
        DemoScenario(
            'cancel',
            DemoText('Cancel all', '取消全部请求'),
            DemoText(
                'Cancel three in-flight calls and inspect their failure markers.',
                '取消三个在途调用，读取各自的失败标记。'),
            "api.cancelAll('left page');\n// failureOf(result)?.kind == DiomanFailureKind.cancel",
            _cancel),
        DemoScenario(
            'offline',
            DemoText('Offline queue', '离线队列'),
            DemoText(
                'Hold a request until an in-memory connectivity event resumes it.',
                '请求离线排队，收到内存连通事件后恢复。'),
            "// plugins: [DiomanOffline(isOnline: () => online, onConnectivityChanged: events.stream)]\nawait api.send<dynamic>('GET', '/items', call: DiomanCall(options: {DiomanOffline.option: const DiomanOfflineOptions(maxWait: Duration(seconds: 2))}));",
            _offline),
        DemoScenario(
            'deadline',
            DemoText('Whole-request deadline', '整体请求截止时间'),
            DemoText(
                'A 200ms call budget overrides 2s; the same 600ms transfer then succeeds.',
                '200ms 调用预算覆盖默认 2s；恢复默认后同样的 600ms 传输成功。'),
            "// Dioman(dio: dio, deadline: const Duration(seconds: 2))\nfinal result = await api.send<dynamic>('GET', '/items', call: const DiomanCall(deadline: Duration(milliseconds: 200)));\nprint(failureOf(result)?.reason); // deadline",
            _deadline),
      ]),
  DemoGroup(
      'pipeline',
      DemoText('Pipeline & diagnostics', '管线与诊断'),
      DemoText(
          'Inspect setup, timeout configuration, circuit state and final notifications.',
          '检查安装配置、阶段超时、熔断状态与最终通知。'),
      Icons.account_tree_outlined,
      [
        DemoScenario(
            'envs',
            DemoText('Environment setup', '环境配置'),
            DemoText(
                'Only the first matching EnvRule merges into BaseOptions during setup.',
                '安装时只合并第一个匹配的 EnvRule。'),
            "// plugins: [DiomanEnvs([EnvRule(rule: () => true, config: BaseOptions(baseUrl: 'https://dev.example.invalid'))])]\nprint(api.dio.options.baseUrl);",
            _envs,
            replayable: false),
        DemoScenario(
            'timeout',
            DemoText('Timeout configuration', '阶段超时配置'),
            DemoText(
                'Inspect receiveTimeout for a supplied tier; this is no real network test.',
                '检查指定网络等级的 receiveTimeout；不代表真实网络超时验证。'),
            "// plugins: [DiomanTimeout(probe: () => NetworkQuality.good)]\nawait api.get<dynamic>('/items', call: DiomanCall(options: {DiomanTimeout.option: const DiomanTimeoutOptions(timeouts: {NetworkQuality.good: DiomanTimeouts(receive: Duration(seconds: 3))})}));",
            _timeout),
        DemoScenario(
            'breaker',
            DemoText('Circuit breaker', '熔断保护'),
            DemoText(
                'The first HTTP 500 opens the circuit; the next call skips transport.',
                '首次 HTTP 500 打开熔断器，后续调用不再传输。'),
            "// plugins: [const DiomanBreaker(failureThreshold: 1)]\nprint(api.plugin<DiomanBreakerApi>()?.bucketCount);",
            _breaker),
        DemoScenario(
            'notify',
            DemoText('Final notification', '最终失败通知'),
            DemoText(
                'Two failed calls, one notice: silent suppresses the second notification.',
                '两次失败仅通知一次，silent 抑制第二次通知。'),
            "// plugins: [DiomanNotify(notify: (message, result) {})]\nawait api.send<dynamic>('GET', '/items', call: const DiomanCall(silent: true));",
            _notify),
        DemoScenario(
            'trace',
            DemoText('Custom trace & debug', '自定义追踪与调试'),
            DemoText(
                'Observe outer-stage entry, final result and installed stage order.',
                '观察 outer 阶段入口、最终结果和安装后的阶段顺序。'),
            "// DemoTrace extends DiomanPlugin; setup returns a per-client instance.\n// handle(ctx, next) observes await next() without replacing the result.\nprint(api.inspect());",
            _trace),
      ]),
];

/// 使用三种当前占位符语法，观察传输看到的最终路径。
Future<void> _repath(DemoSession s) async {
  final api = s.client(
      plugins: [const DiomanRepath()],
      respond: (request) {
        s.log('Transport path', '传输路径',
            '${request.uri.path} ?${request.uri.query}');
        return demoJson({_id: 42});
      });
  for (final path in ['/users/{id}', '/users/:id', '/users/[id]']) {
    await api.send<dynamic>(demoMethod, path, query: {_id: 42});
  }
}

/// 观察过滤后的查询参数，确认 0 与 false 被保留。
Future<void> _filter(DemoSession s) async {
  final api = s.client(
      plugins: [const DiomanFilter()],
      respond: (request) {
        s.log('Filtered query', '过滤后的查询', request.queryParameters);
        return demoJson([]);
      });
  await api.send<dynamic>(demoMethod, demoPath,
      query: {'q': '', 'limit': null, _page: 0, 'active': false});
}

/// 演示三种内联路由，命中后不会进入真实传输。
Future<void> _mock(DemoSession s) async {
  final api = s.client(plugins: [
    DiomanMock(routes: {
      '$demoMethod:$demoPath': (_) => [1, 2],
      'POST:$demoPath': (request) => request.data,
      'DELETE:$demoPath': (request) => Response<dynamic>(
          requestOptions: RequestOptions(path: request.path), statusCode: 204),
    })
  ]);
  final list = await api.get<List<dynamic>>(demoPath);
  final created =
      await api.post<Map<String, dynamic>>(demoPath, data: {_id: 3});
  final deleted = await api.send<dynamic>('DELETE', demoPath);
  s.log('GET / POST / DELETE', '查询 / 创建 / 删除',
      '$list / $created / ${deleted.status}');
}

/// 对比 HTTP 状态、业务码及没有内核失败标记的业务失败。
Future<void> _result(DemoSession s) async {
  var count = 0;
  final api = s.client(
      respond: (_) => demoJson({
            _code: count++ == 0 ? 0 : 10001,
            _data: {_id: 1},
          }));
  final success = await api.send<dynamic>(demoMethod, demoPath);
  s.log('Success: HTTP / code / data', '成功：HTTP / 业务码 / 数据',
      '${success.status} / ${success.code} / ${success.data}');
  final failure = await api.send<dynamic>(demoMethod, demoPath);
  s.log(
      'Business failure: ok / HTTP / code / kernel marker',
      '业务失败：ok / HTTP / 业务码 / 内核标记',
      '${failure.ok} / ${failure.status} / ${failure.code} / ${failureOf(failure)}');
  try {
    await api.request<dynamic>(demoMethod, demoPath);
  } on DiomanResponse catch (result) {
    s.log(
        'request throws the expected result', 'request 抛出可预期的结果', result.code);
  }
}

/// 成功后解码，比较默认结果与开启 raw 的原生对象归属。
Future<void> _decode(DemoSession s) async {
  final api = s.client();
  final value = await api.get<int>(demoPath,
      decode: (data) => (data as Map)[_value] as int);
  final lean = await api.send<dynamic>(demoMethod, demoPath);
  final raw = await api.send<dynamic>(demoMethod, demoPath,
      call: const DiomanCall(raw: true));
  s.log(
      'Decoded value / default raw / opted-in raw HTTP',
      '解码值 / 默认 raw / 开启 raw 后的 HTTP',
      '$value / ${lean.raw} / ${raw.raw?.statusCode}');
}

/// 合并 key 与缓存演示，参数乱序命中，参数改值重新发送。
Future<void> _cache(DemoSession s) async {
  var hits = 0;
  final api = s.client(
      plugins: [const DiomanCache()],
      respond: (_) {
        hits++;
        return demoJson({_value: hits});
      });
  final call =
      DiomanCall(options: {DiomanCache.option: const Duration(minutes: 1)});
  for (final query in [
    {_sort: _ascending, _page: 1},
    {_page: 1, _sort: _ascending},
    {_page: 2, _sort: _ascending},
  ]) {
    await api.send<dynamic>(demoMethod, demoPath, query: query, call: call);
    s.log('Server calls so far', '累计后端调用次数', hits);
  }
  await api.plugin<DiomanCacheApi>()!.clear();
  await api.send<dynamic>(demoMethod, demoPath, call: call);
  s.log('After clearing cache', '清空缓存后', hits);
}

/// 并发请求显式启用 start 策略，仅访问一次内存后端。
Future<void> _share(DemoSession s) async {
  var hits = 0;
  final api = s.client(
      plugins: [const DiomanShare()],
      respond: (_) async {
        hits++;
        await s.wait(_transferDelay);
        return demoJson({_value: 42});
      });
  s.log('Three callers started', '三个调用开始等待');
  final call =
      DiomanCall(options: {DiomanShare.option: DiomanSharePolicy.start});
  final results = await Future.wait(List.generate(
      3, (_) => api.send<dynamic>(demoMethod, demoPath, call: call)));
  s.log('Callers / transports', '调用数 / 传输数', '${results.length} / $hits');
}

/// 两次服务器失败后成功，显式配置演示等待而不误述默认退避。
Future<void> _retry(DemoSession s) async {
  var attempts = 0;
  final api = s.client(
      plugins: [DiomanRetry(max: 2, delay: (_, __, ___) => _shortDelay)],
      respond: (_) {
        attempts++;
        final status = attempts <= 2 ? 500 : 200;
        s.log('Attempt / HTTP status', '尝试次数 / HTTP 状态', '$attempts / $status');
        return demoJson({_value: attempts}, status: status);
      });
  final result = await api.send<dynamic>(demoMethod, demoPath);
  s.log('Final success', '最终成功', result.ok);
}

/// 401 刷新后观察新 Authorization 头，不将示例凭证打印到日志。
Future<void> _auth(DemoSession s) async {
  final tokens = InMemoryTokenManager(access: 'expired');
  var refreshes = 0;
  final api = s.client(
      plugins: [
        DiomanAuth(
            tokenManager: tokens,
            onRefresh: (store, _) async {
              refreshes++;
              s.log('Refreshing credentials', '正在刷新凭证');
              await s.wait(_shortDelay);
              store.setTokens(accessToken: 'renewed');
            },
            onAccessExpired: (store, _) => store.clear())
      ],
      respond: (request) {
        final renewed = request.headers['Authorization'] == 'Bearer renewed';
        s.log('Backend HTTP status', '后端 HTTP 状态', renewed ? 200 : 401);
        return demoJson({_value: 42}, status: renewed ? 200 : 401);
      });
  final result = await api.send<dynamic>(demoMethod, demoPath);
  s.log(
      'Refreshes / final success', '刷新次数 / 最终成功', '$refreshes / ${result.ok}');
}

/// 显示回调只记录边沿，活跃请求数通过管理 API 读取。
Future<void> _loading(DemoSession s) async {
  final api = s.client(
      plugins: [
        DiomanLoading(
            onChanged: (visible) =>
                s.log('Loading visibility', '加载指示器可见', visible))
      ],
      respond: (_) async {
        await s.wait(_transferDelay);
        return demoJson({_value: 42});
      });
  final pending = Future.wait(
      List.generate(3, (_) => api.send<dynamic>(demoMethod, demoPath)));
  await s.wait(_shortDelay);
  s.log('Active logical requests', '活跃逻辑请求数',
      api.plugin<DiomanLoadingApi>()!.activeCount);
  await pending;
  s.log('After settlement: active requests', '落定后活跃请求数',
      api.plugin<DiomanLoadingApi>()!.activeCount);
}

/// 在三次慢请求完成前执行 cancelAll 并读取取消事实。
Future<void> _cancel(DemoSession s) async {
  final api = s.client(respond: (_) async {
    await s.wait(_transferDelay);
    return demoJson({_value: 42});
  });
  final pending = Future.wait(
      List.generate(3, (_) => api.send<dynamic>(demoMethod, demoPath)));
  s.log('Three requests started', '三个请求已开始');
  await s.wait(_shortDelay);
  api.cancelAll('left page');
  final results = await pending;
  s.log(
      'Cancelled calls',
      '已取消调用数',
      results
          .where((r) => failureOf(r)?.kind == DiomanFailureKind.cancel)
          .length);
}

/// 离线等待一次连通事件，最后关闭宿主持有的广播流。
Future<void> _offline(DemoSession s) async {
  var online = false;
  final events = StreamController<bool>.broadcast();
  final api = s.client(plugins: [
    DiomanOffline(isOnline: () => online, onConnectivityChanged: events.stream)
  ]);
  try {
    final pending = api.send<dynamic>(demoMethod, demoPath,
        call: DiomanCall(options: {
          DiomanOffline.option:
              const DiomanOfflineOptions(maxWait: Duration(seconds: 2)),
        }));
    await s.wait(_shortDelay);
    s.log('Queued while offline', '离线排队请求数',
        api.plugin<DiomanOfflineApi>()!.pending);
    if (!s.closed) {
      online = true;
      s.log('Connectivity restored', '连通性已恢复');
      events.add(true);
    }
    final result = await pending;
    s.log('Resumed request succeeded', '恢复的请求已成功', result.ok);
  } finally {
    await events.close();
  }
}

/// 调用级预算超时，随后展示默认预算下相同传输正常成功。
Future<void> _deadline(DemoSession s) async {
  final api = s.client(
      deadline: const Duration(seconds: 2),
      respond: (_) async {
        await s.wait(_transferDelay);
        return demoJson({_value: 42});
      });
  final result = await api.send<dynamic>(demoMethod, demoPath,
      call: const DiomanCall(deadline: _shortDelay));
  s.log('Short budget: kind / reason', '短预算：失败类型 / 原因',
      '${failureOf(result)?.kind.name} / ${failureOf(result)?.reason}');
  if (s.closed) return;
  final success = await api.send<dynamic>(demoMethod, demoPath);
  s.log('Default budget: success', '默认预算：成功', success.ok);
}

/// 分别展示首条匹配与跳过首条规则的安装结果。
Future<void> _envs(DemoSession s) async {
  for (final development in [true, false]) {
    final api = s.client(plugins: [
      DiomanEnvs([
        EnvRule(
            rule: () => development,
            config: BaseOptions(baseUrl: _development)),
        EnvRule(rule: () => true, config: BaseOptions(baseUrl: _production)),
      ])
    ]);
    s.log('First matching environment', '首个匹配环境', api.dio.options.baseUrl);
  }
}

/// 观察网络等级配置写入的接收超时，不声称验证真实网络。
Future<void> _timeout(DemoSession s) async {
  final api = s.client(
      plugins: [DiomanTimeout(probe: () => NetworkQuality.good)],
      respond: (request) {
        s.log('Configured receive timeout', '配置的接收超时', request.receiveTimeout);
        return demoJson({_value: 42});
      });
  await api.get<dynamic>(demoPath,
      call: DiomanCall(options: {
        DiomanTimeout.option: const DiomanTimeoutOptions(timeouts: {
          NetworkQuality.good: DiomanTimeouts(receive: Duration(seconds: 3)),
        }),
      }));
}

/// HTTP 500 打开熔断器，第二次请求由 breaker 拒绝。
Future<void> _breaker(DemoSession s) async {
  var hits = 0;
  final api = s.client(
      plugins: [const DiomanBreaker(failureThreshold: 1)],
      respond: (_) {
        hits++;
        return demoJson({}, status: 500);
      });
  final first = await api.send<dynamic>(demoMethod, demoPath);
  final second = await api.send<dynamic>(demoMethod, demoPath);
  s.log('First HTTP / next failure kind / transports', '首次 HTTP / 后续失败类型 / 传输数',
      '${first.status} / ${failureOf(second)?.kind.name} / $hits');
}

/// 默认通知只发最终失败，第二个调用显式静默。
Future<void> _notify(DemoSession s) async {
  var notices = 0;
  final api = s.client(plugins: [
    DiomanNotify(notify: (_, result) {
      notices++;
      s.log('Final failure notice: HTTP', '最终失败通知：HTTP', result.status);
    })
  ], respond: (_) => demoJson({}, status: 500));
  await api.send<dynamic>(demoMethod, demoPath);
  await api.send<dynamic>(demoMethod, demoPath,
      call: const DiomanCall(silent: true));
  s.log('Failures / notices', '失败数 / 通知数', '2 / $notices');
}

/// 自定义 outer 插件配合内核 debug，日志协议字段保持原样。
Future<void> _trace(DemoSession s) async {
  final api = s.client(
      plugins: [DemoTrace(s)],
      debug: (message) => s.log('Kernel diagnostic', '内核诊断', message));
  await api.send<dynamic>(demoMethod, demoPath);
  s.log('Installed pipeline', '已安装管线', api.inspect());
}
