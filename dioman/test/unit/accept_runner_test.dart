// ignore_for_file: avoid_relative_lib_imports
import 'dart:async';
import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';
import 'package:test/test.dart';
import '../accept/lib/client.dart';
import '../accept/lib/common.dart';
import '../accept/lib/runner.dart';
import '../support/fake_network.dart';
import '../support/helpers.dart' show flush;

/// B7 共用字面量。
const _b7Steps = 'steps';

/// B7 共用字面量。
const _b7Request = 'request';

/// B7 共用字面量。
const _b7Query = 'query';

/// B7 共用字面量。
const _b7Fault = 'fault';

/// B7 共用字面量。
const _b7BadJson = 'bad_json';

/// B7 共用字面量。
const _b7Literal0 = 'id';

/// B7 共用字面量。
const _b7Literal1 = 'total-budget';

/// B7 共用字面量。
const _b7Literal2 = 'networks';

/// B7 共用字面量。
const _b7Literal3 = 'expect';

/// B7 共用字面量。
const _b7Literal4 = 'reasons';

/// B7 共用字面量。
const _b7Literal5 = 'business:503';

/// B7 共用字面量。
const _b7Literal6 = 'network';

/// B7 共用字面量。
const _b7Literal7 = 'parse';

/// B7 共用字面量。
const _b7Literal8 = 'offline';

/// B7 共用字面量。
const _b7Literal9 = 'auth';

/// B7 共用字面量。
const _b7Literal10 = 'key';

/// B7 共用字面量。
const _b7Literal11 = 'explicit';

/// B7 共用字面量。
const _b7Literal12 = 'results';

/// B7 共用字面量。
const _b7Literal13 = 'r';

/// B7 共用字面量。
const _b7Literal14 = 'error';

/// 场景配置中缓存插件的名称。
const _cache = 'cache';

/// 场景配置中共享插件的名称。
const _share = 'share';

/// 文件内共用的字面量。
const _literalGETGuard = "GET:/guard";

/// 文件内共用的字面量。
const _literalCode = "code";

/// 文件内共用的字面量。
const _literalData = "data";

/// 文件内共用的字面量。
const _literalClient = "client";

/// 文件内共用的字面量。
const _literalPlugins = "plugins";

/// 文件内共用的字面量。
const _literalRetry = "retry";

/// 文件内共用的字面量。
const _literalMax = "max";

/// 文件内共用的字面量。
const _literalGuard = "guard";

/// 文件内共用的字面量。
const _literalHttpsGuardTest = "https://guard.test";

/// 文件内共用的字面量。
const _literalBusiness = "business";

/// 文件内共用的字面量。
const _literalGET = "GET";

/// 文件内共用的字面量。
const _literalGuard1 = "/guard";

/// 文件内共用的字面量。
const _literalRecovered = "recovered";

/// 文件内共用的字面量。
const _literalTimeout = "timeout";

/// 文件内共用的字面量。
const _literalHttp = "http";

/// 文件内共用的字面量。
const _literalDenied = "denied";

/// 文件内共用的字面量。
const _literalMockInChain = "mock-in-chain";

/// 文件内共用的字面量。
const _literalRequires = "requires";

/// 文件内共用的字面量。
const _literalRawBusinessCode = "raw-business-code";

/// 文件内共用的字面量。
const _literalRunnerCheck = "runner-check";

/// 文件内共用的字面量。
const _literalNormal = "normal";

/// 执行器只观察公开结果，缺能力在发请求前被识别。
void main() {
  test('[ScenarioClient] 安装 cache 后省略请求覆盖仍缓存，false 明确关闭', () async {
    final network = FakeNetwork();
    final client = ScenarioClient({
      _literalClient: {
        _literalPlugins: {_cache: <String, dynamic>{}}
      }
    }, _literalGuard, _literalHttpsGuardTest, _literalHttp, transport: network);
    try {
      for (var i = 0; i < 2; i++) {
        final result = await client.api
            .send<dynamic>(_literalGET, _literalGuard1, call: client.call({}));
        expect(result.ok, isTrue);
      }
      expect(network.sends, hasLength(1));
      await client.api.send<dynamic>(_literalGET, _literalGuard1,
          call: client.call({_cache: false}));
      expect(network.sends, hasLength(2));
    } finally {
      await client.dispose();
    }
  });
  test('[ScenarioClient] 安装 share 后省略请求覆盖仍合并，false 明确关闭', () async {
    for (final disabled in [false, true]) {
      final gate = Completer<void>();
      final sent = Completer<void>();
      final bothSent = Completer<void>();
      var sends = 0;
      final network = FakeNetwork(onSend: (_) {
        sends++;
        if (!sent.isCompleted) sent.complete();
        if (sends == 2) bothSent.complete();
      })
        ..routes[_literalGETGuard] = [FakeReply(gate: gate.future)];
      final client = ScenarioClient({
        _literalClient: {
          _literalPlugins: {_share: <String, dynamic>{}}
        }
      }, _literalGuard, _literalHttpsGuardTest, _literalHttp,
          transport: network);
      try {
        final options = disabled ? {_share: false} : <String, dynamic>{};
        final first = client.api.send<dynamic>(_literalGET, _literalGuard1,
            call: client.call(options));
        await sent.future;
        final second = client.api.send<dynamic>(_literalGET, _literalGuard1,
            call: client.call(options));
        if (disabled) {
          await bothSent.future;
        } else {
          await flush();
        }
        expect(network.sends, hasLength(disabled ? 2 : 1));
        gate.complete();
        expect((await Future.wait([first, second])).every((r) => r.ok), isTrue);
        expect(network.sends, hasLength(disabled ? 2 : 1));
      } finally {
        if (!gate.isCompleted) gate.complete();
        await client.dispose();
      }
    }
  });
  test('[ScenarioClient] 服务停止只读归一化逻辑状态，在重试前阻止非注入 429/503', () async {
    for (final status in [429, 503]) {
      final network = FakeNetwork()
        ..routes[_literalGETGuard] = [
          FakeReply(body: {_literalCode: status, _literalData: null}),
        ];
      final client = ScenarioClient({
        _literalClient: {
          _literalPlugins: {
            _literalRetry: {_literalMax: 2}
          }
        }
      }, _literalGuard, _literalHttpsGuardTest, _literalBusiness,
          transport: network);
      try {
        await expectLater(client.api.send<dynamic>(_literalGET, _literalGuard1),
            throwsStateError);
        expect(serviceBlocked, isTrue);
        expect(network.sends, hasLength(1));
      } finally {
        await client.dispose();
        serviceBlocked = false;
      }
    }
  });
  test('[ScenarioClient] 注入 HTTP/business 503 正常交给库重试', () async {
    for (final business in [true, false]) {
      final network = FakeNetwork()
        ..routes[_literalGETGuard] = [
          FakeReply(status: business ? 200 : 503, body: {
            _literalCode: 503,
            _literalData: {'reason': 'injected'}
          }),
          const FakeReply(
              body: {_literalCode: 0, _literalData: _literalRecovered}),
        ];
      final client = ScenarioClient({
        _literalClient: {
          _literalPlugins: {
            _literalRetry: {_literalMax: 1}
          }
        }
      }, _literalGuard, _literalHttpsGuardTest, _literalBusiness,
          transport: network);
      try {
        final result =
            await client.api.send<dynamic>(_literalGET, _literalGuard1);
        expect(result.data, _literalRecovered);
        expect(result.ok, isTrue);
        expect(serviceBlocked, isFalse);
        expect(network.sends, hasLength(2));
      } finally {
        await client.dispose();
      }
    }
  });
  test('[ScenarioRun.execute] total_ms 缺能力时跳过，不访问服务也不补计时器', () async {
    for (final declared in [true, false]) {
      final result = await ScenarioRun({
        _b7Literal0: _b7Literal1,
        _literalRequires: [if (declared) timeoutTotalCapability],
        _b7Literal2: [_literalNormal],
        _b7Literal3: <String, Object?>{},
        _literalClient: {
          _literalPlugins: {
            _literalTimeout: {'total_ms': 10}
          }
        }
      }, _literalNormal, _literalHttp, _b7Literal1)
          .execute();
      expect(result['status'], '跳过');
      expect(result[_b7Literal4], ['skipped: missing $timeoutTotalCapability']);
    }
  });
  test('[client.classify] 归类只读取 kind reason status，原始数据不参与判断', () {
    final request = DiomanRequest(RequestOptions(path: '/classification'));
    for (final entry in {
      DiomanKind.biz: _b7Literal5,
      DiomanKind.http: 'http:503',
      DiomanKind.cancel: 'canceled',
      DiomanKind.timeout: _literalTimeout,
      DiomanKind.network: _b7Literal6,
      DiomanKind.parse: _b7Literal7,
      DiomanKind.breaker: 'breaker_open',
      DiomanKind.offline: _b7Literal8,
      DiomanKind.auth: _literalDenied,
    }.entries) {
      final response = DiomanResponse<Object?>(
          ok: false,
          kind: entry.key,
          status: 503,
          httpStatus: 200,
          request: request,
          reason: _literalDenied,
          data: {_literalCode: 0});
      expect(classify(response), entry.value);
    }
  });
  test('[common.missingCapabilities] mock 在链内，raw-business-code 未声明', () {
    expect(supportedCapabilities, contains(_literalMockInChain));
    expect(
        missingCapabilities({
          _literalRequires: [_literalMockInChain, _literalRawBusinessCode]
        }),
        [_literalRawBusinessCode]);
  });
  test('[ScenarioRun.execute] 缺能力和未声明维度分别跳过，且不访问服务', () async {
    for (final missing in [true, false]) {
      final scenario = {
        _b7Literal0: _literalRunnerCheck,
        _literalRequires: missing ? [_literalRawBusinessCode] : [],
        _b7Literal2: [_literalNormal],
        'styles': [_literalHttp],
        _b7Literal3: <String, Object?>{}
      };
      final run = ScenarioRun(scenario, missing ? _literalNormal : 'weak',
          _literalHttp, _literalRunnerCheck);
      final result = await run.execute();
      final reasons = result[_b7Literal4] as List;
      expect(
          reasons.single, startsWith(missing ? 'skipped: missing ' : '不适用：'));
    }
  });
  test('[ScenarioClient] 无刷新凭证不调用端点，原生刷新失败仍通知过期', () async {
    final network = FakeNetwork()
      ..routes[_literalGETGuard] = [
        const FakeReply(
            status: 401, body: {_literalCode: 401, _literalData: null})
      ];
    final client = ScenarioClient({
      _literalClient: {
        _literalPlugins: {_b7Literal9: {}}
      }
    }, _literalGuard, _literalHttpsGuardTest, _literalHttp, transport: network);
    client.tokens.replace('Bearer old', null);
    try {
      final result = await client.api.send<dynamic>(_literalGET, _literalGuard1,
          call: client.call({_b7Literal9: true}));
      expect(result.reason, 'expired',
          reason:
              '$result sends=${network.sends.map((s) => s.options.path).toList()}');
      expect(client.refreshCount, 0);
      expect(client.expiredCount, 1);
      expect(network.sends, hasLength(1));
    } finally {
      await client.dispose();
    }
  });
  test('[ScenarioClient] 中立 key 显式启用与 share none 映射成原生配置', () async {
    final client = ScenarioClient({
      _literalClient: {
        _literalPlugins: {_b7Literal10: {}, _share: {}}
      }
    }, _literalGuard, _literalHttpsGuardTest, _literalHttp,
        transport: FakeNetwork());
    try {
      expect(client.call({}).key, isFalse);
      expect(client.call({_b7Literal10: true}).key, isNull);
      expect(client.call({_b7Literal10: _b7Literal11}).key, _b7Literal11);
      expect(
          client.call({_share: 'none'}).options[DiomanShare.option], isFalse);
    } finally {
      await client.dispose();
    }
  });
  test('[ScenarioClient] probe 失败使用原生零等待队列返回 offline', () async {
    final network = FakeNetwork();
    final client = ScenarioClient({
      _literalClient: {
        _literalPlugins: {_b7Literal8: {}}
      }
    }, _literalGuard, _literalHttpsGuardTest, _literalHttp, transport: network);
    client.online = false;
    try {
      final result =
          await client.api.send<dynamic>(_literalGET, _literalGuard1);
      expect(result.kind, DiomanKind.offline);
      expect(client.api.pending, 0);
      expect(network.sends, isEmpty);
    } finally {
      await client.dispose();
    }
  });
  test('[common.designInapplicability] 通用字段识别，允许替代错误时仍执行', () {
    final scenario = {
      _b7Steps: [
        {
          _b7Request: {
            _b7Query: {_b7Fault: _b7BadJson}
          }
        }
      ]
    };
    expect(
        designInapplicability(scenario, {
          _b7Literal12: {
            _b7Literal13: {_b7Literal14: _b7Literal7}
          }
        }),
        isNotNull);
    expect(
        designInapplicability(scenario, {
          _b7Literal12: {
            _b7Literal13: {
              _b7Literal14: [_b7Literal7, _b7Literal6]
            }
          }
        }),
        isNull);
    expect(
        designInapplicability({}, {
          _b7Literal12: {
            _b7Literal13: {_b7Literal14: 'business:5001'}
          }
        }),
        isNotNull);
    expect(
        designInapplicability({}, {
          _b7Literal12: {
            _b7Literal13: {_b7Literal14: _b7Literal5}
          }
        }),
        isNull);
  });
  test('[common.scenarioSteps] 只识别真实控制字段，负载中同名键保持数据语义', () {
    final payload = [
      {
        _b7Request: {
          'body': {
            _b7Request: {
              _b7Query: {_b7Fault: _b7BadJson}
            },
            'cancel_all': {}
          }
        }
      }
    ];
    expect(usesScenarioCancellation(payload), isFalse);
    expect(
        designInapplicability({
          _b7Steps: payload
        }, {
          _b7Literal12: {
            _b7Literal13: {_b7Literal14: _b7Literal7}
          }
        }),
        isNull);
    expect(
        usesScenarioCancellation([
          {
            'sequence': [
              {
                'fire': {
                  'repeat': {
                    'step': {
                      _b7Request: {'cancel_after_ms': 10}
                    }
                  }
                }
              }
            ]
          }
        ]),
        isTrue);
  });
}
