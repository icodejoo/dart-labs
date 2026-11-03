import 'dart:async';
import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';
import 'package:test/test.dart';
import '../support/fake_clock.dart';
import '../support/fake_network.dart';
import '../support/helpers.dart';
import '../support/auth_test_helpers.dart';

/// 假传输的地址。
const _base = 'https://deadline.test';

/// 截止测试的请求路径。
const _path = '/deadline';

/// 一次虚拟预算。
const _budget = Duration(seconds: 1);

/// 共用的请求动词。
const _method = 'GET';

/// 用户取消的原因。
const _userReason = 'user';

/// 假传输的路由。
const _route = '$_method:$_path';

/// 创建预算客户端，统一释放资源。
Dioman<Result> _client(FakeClock clock, FakeNetwork net,
    {Duration? deadline, List<DiomanPlugin<Result>> plugins = const []}) {
  final api = Dioman<Result>(
      dio: Dio(BaseOptions(baseUrl: _base))..httpClientAdapter = net,
      clock: clock,
      deadline: deadline,
      plugins: plugins);
  addTearDown(() async {
    await api.dispose();
    api.dio.close(force: true);
  });
  return api;
}

/// 检查所属预算的失败类别与原因。
void _expired(Result result) {
  expect(failureOf(result)?.kind, DiomanFailureKind.timeout);
  expect(failureOf(result)?.reason, 'deadline');
  expect(isDiomanCancel(result), isFalse);
}

/// 等待事件与微任务完成，保持虚拟时间不变。
Future<void> _settle() async {
  for (var i = 0; i < 5; i++) {
    await b3Turn();
  }
}

/// 验证截止时间的等待与归属边界。
void main() {
  test('[Dioman.deadline][DiomanCall.deadline] 默认、覆盖、成功清理与 extend', () async {
    final clock = FakeClock();
    final gate = Completer<void>();
    final net = FakeNetwork()..routes[_route] = [FakeReply(gate: gate.future)];
    final api = _client(clock, net, deadline: _budget);
    final child = api.extend(dio: Dio());
    expect(child.deadline, _budget);
    await child.dispose();
    final pending = api.send<Object?>(_method, _path,
        call: const DiomanCall(deadline: Duration(seconds: 2)));
    await _settle();
    clock.elapse(_budget);
    await _settle();
    expect(api.pending, 1);
    gate.complete();
    expect((await pending).ok, isTrue);
    expect(clock.pendingTimers, 0);
    final defaultGate = Completer<void>();
    net.routes[_route] = [FakeReply(gate: defaultGate.future)];
    final defaults = api.send<Object?>(_method, _path);
    await _settle();
    clock.elapse(_budget);
    _expired(await defaults);
    defaultGate.complete();
    expect(api.pending, 0);
    expect(clock.pendingTimers, 0);
  });

  test('[DiomanCall.deadline] 到期不吞掉同时发生的协议回调程序错误', () async {
    final clock = FakeClock();
    final bug = StateError('parse bug');
    final api = Dioman(
        dio: Dio(BaseOptions(baseUrl: _base))
          ..httpClientAdapter = FakeNetwork(),
        clock: clock,
        response: DiomanResponseFactory(parse: (_, __) {
          clock.elapse(_budget);
          throw bug;
        }));
    try {
      await expectLater(
          api.send<Object?>(_method, _path,
              call: const DiomanCall(deadline: _budget)),
          throwsA(same(bug)));
      expect(api.pending, 0);
      expect(clock.pendingTimers, 0);
    } finally {
      await api.dispose();
    }
  });

  for (final budget in [Duration.zero, const Duration(microseconds: -1)]) {
    test('[DiomanCall.deadline] 非正预算立即到期 $budget', () async {
      final clock = FakeClock();
      final net = FakeNetwork();
      final api = _client(clock, net);
      _expired(await api.send<Object?>(_method, _path,
          call: DiomanCall(deadline: budget)));
      expect(net.sends, isEmpty);
      expect(clock.pendingTimers, 0);
    });
  }

  test('[DiomanCall.deadline] 用户先取消保留类别并清理预算', () async {
    final clock = FakeClock();
    final gate = Completer<void>();
    final api = _client(
        clock, FakeNetwork()..routes[_route] = [FakeReply(gate: gate.future)]);
    final token = CancelToken();
    final pending = api.send<Object?>(_method, _path,
        call: DiomanCall(deadline: _budget, cancelToken: token));
    await _settle();
    token.cancel(_userReason);
    final result = await pending;
    expect(failureOf(result)?.kind, DiomanFailureKind.cancel);
    expect(failureOf(result)?.reason, _userReason);
    expect(clock.pendingTimers, 0);
    clock.elapse(_budget);
    expect(failureOf(result)?.kind, DiomanFailureKind.cancel);
    gate.complete();
  });

  test('[DiomanCall.deadline × DiomanRetry.delay] 重试等待计入同一预算', () async {
    final clock = FakeClock();
    final net = FakeNetwork()..routes[_route] = [const FakeReply(status: 500)];
    final api = _client(clock, net, plugins: [
      DiomanRetry(delay: (_, __, ___) => const Duration(seconds: 10))
    ]);
    final pending = api.send<Object?>(_method, _path,
        call: const DiomanCall(deadline: _budget));
    await _settle();
    expect(clock.pendingTimers, 2);
    clock.elapse(_budget);
    _expired(await pending);
    expect(net.sends, hasLength(1));
    expect(clock.pendingTimers, 0);
  });

  test('[DiomanCall.deadline × DiomanOfflineApi.pending] 离线排队到期立即摘队', () async {
    final clock = FakeClock();
    final changes = StreamController<bool>();
    final net = FakeNetwork();
    final api = _client(clock, net, plugins: [
      DiomanOffline(
          isOnline: () => false, onConnectivityChanged: changes.stream)
    ]);
    final pending = api.send<Object?>(_method, _path,
        call: const DiomanCall(deadline: _budget));
    await _settle();
    expect(api.plugin<DiomanOfflineApi>()!.pending, 1);
    clock.elapse(_budget);
    _expired(await pending);
    expect(api.plugin<DiomanOfflineApi>()!.pending, 0);
    expect(net.sends, isEmpty);
    expect(clock.pendingTimers, 0);
    await api.dispose();
    await changes.close();
  });

  test('[DiomanCall.deadline × DiomanAuth.onRefresh] 刷新排队者退出不取消刷新', () async {
    final clock = FakeClock();
    final tokens = TestTokens();
    final gate = Completer<void>();
    var refreshes = 0;
    final net = FakeNetwork()
      ..routes[_route] = [const FakeReply(status: 401), const FakeReply()];
    final api = _client(clock, net, plugins: [
      DiomanAuth(
          tokenManager: tokens,
          onRefresh: (_, __) async {
            refreshes++;
            await gate.future;
            tokens.setTokens(accessToken: b3Fresh);
          },
          onAccessExpired: (_, __) => fail('不应失效'))
    ]);
    final first = api.send<Object?>(_method, _path);
    await _settle();
    expect(refreshes, 1);
    final follower = api.send<Object?>(_method, _path,
        call: const DiomanCall(deadline: _budget));
    await _settle();
    clock.elapse(_budget);
    _expired(await follower);
    expect(api.pending, 1);
    gate.complete();
    expect((await first).ok, isTrue);
    expect(refreshes, 1);
    expect(clock.pendingTimers, 0);
  });

  for (final trip in [null, false, true]) {
    test('[DiomanCall.deadline × DiomanBreaker.shouldTrip] 截止失败进入熔断策略 $trip',
        () async {
      final clock = FakeClock();
      final gate = Completer<void>();
      final net = FakeNetwork()
        ..routes[_route] = [FakeReply(gate: gate.future)];
      final observed = <Result>[];
      final api = _client(clock, net, plugins: [
        DiomanBreaker(
            failureThreshold: 1,
            resetDuration: _budget,
            shouldTrip: trip == null
                ? null
                : (r) {
                    observed.add(r);
                    return trip;
                  })
      ]);
      final breaker = api.plugin<DiomanBreakerApi>()!;
      try {
        final first = api.send<Object?>(_method, _path,
            call: const DiomanCall(deadline: _budget));
        await _settle();
        clock.elapse(_budget);
        _expired(await first);
        expect(
            breaker.stateOf(_route),
            trip == false
                ? DiomanBreakerState.closed
                : DiomanBreakerState.open);
        if (trip != null) _expired(observed.single);
        if (trip != false) {
          clock.elapse(_budget);
          final probe = api.send<Object?>(_method, _path,
              call: const DiomanCall(deadline: _budget));
          await _settle();
          expect(breaker.stateOf(_route), DiomanBreakerState.halfOpen);
          clock.elapse(_budget);
          _expired(await probe);
          expect(breaker.stateOf(_route), DiomanBreakerState.open);
        }
        expect(clock.pendingTimers, 0);
      } finally {
        gate.complete();
      }
    });
  }

  for (final policy in DiomanSharePolicy.values) {
    for (final expiresFirst in [true, false]) {
      test(
          '[DiomanCall.deadline × DiomanShare.policy] 自身到期撤回 $policy 首发=$expiresFirst',
          () async {
        final clock = FakeClock();
        final gate = Completer<void>();
        final net = FakeNetwork()
          ..routes[_route] = [FakeReply(gate: gate.future)];
        final api = _client(clock, net, plugins: [DiomanShare(policy: policy)]);

        /// 为每个订阅者配置自身预算。
        DiomanCall call(bool expires) => DiomanCall(
            deadline: expires ? _budget : null,
            options: {DiomanShare.option: true});
        final first =
            api.send<Object?>(_method, _path, call: call(expiresFirst));
        await _settle();
        final second =
            api.send<Object?>(_method, _path, call: call(!expiresFirst));
        await _settle();
        final shared = policy == DiomanSharePolicy.start ||
            policy == DiomanSharePolicy.retry;
        expect(net.sends, hasLength(shared ? 1 : 2));
        clock.elapse(_budget);
        _expired(await (expiresFirst ? first : second));
        expect(api.pending, 1);
        if (shared) {
          expect(net.sends.single.options.cancelToken!.isCancelled, isFalse);
        }
        gate.complete();
        expect((await (expiresFirst ? second : first)).ok, isTrue);
        await _settle();
        expect(clock.pendingTimers, 0);
        expect(api.pending, 0);
      });
    }
  }

  test('[DiomanCall.deadline × DiomanShare.policy] 最后订阅者到期才中止共享传输', () async {
    final clock = FakeClock();
    final gate = Completer<void>();
    final net = FakeNetwork()..routes[_route] = [FakeReply(gate: gate.future)];
    final api = _client(clock, net, plugins: [const DiomanShare()]);
    final pending = api.send<Object?>(_method, _path,
        call:
            DiomanCall(deadline: _budget, options: {DiomanShare.option: true}));
    await _settle();
    clock.elapse(_budget);
    _expired(await pending);
    expect(net.sends.single.options.cancelToken!.isCancelled, isTrue);
    gate.complete();
    await _settle();
    expect(clock.pendingTimers, 0);
  });
}
