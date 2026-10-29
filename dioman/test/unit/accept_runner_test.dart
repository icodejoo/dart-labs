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
  test('[ScenarioClient] total_ms 没有库实现，显式拒绝配置，不能静默失效', () {
    expect(
        () => ScenarioClient({
              _literalClient: {
                _literalPlugins: {
                  _literalTimeout: {'total_ms': 10}
                }
              }
            }, 'budget', _literalHttpsGuardTest, _literalHttp),
        throwsStateError);
  });
  test('[client.classify] 归类只读取 kind reason status，原始数据不参与判断', () {
    final request = DiomanRequest(RequestOptions(path: '/classification'));
    for (final entry in {
      DiomanKind.biz: 'business:503',
      DiomanKind.http: 'http:503',
      DiomanKind.cancel: 'canceled',
      DiomanKind.timeout: _literalTimeout,
      DiomanKind.network: 'network',
      DiomanKind.parse: 'parse',
      DiomanKind.breaker: 'breaker_open',
      DiomanKind.offline: 'offline',
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
        'id': _literalRunnerCheck,
        _literalRequires: missing ? [_literalRawBusinessCode] : [],
        'networks': [_literalNormal],
        'styles': [_literalHttp],
        'expect': <String, Object?>{}
      };
      final run = ScenarioRun(scenario, missing ? _literalNormal : 'weak',
          _literalHttp, _literalRunnerCheck);
      final result = await run.execute();
      final reasons = result['reasons'] as List;
      expect(
          reasons.single, startsWith(missing ? 'skipped: missing ' : '不适用：'));
    }
  });
}
