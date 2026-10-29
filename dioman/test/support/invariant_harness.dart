import 'package:dioman/src/diagnostics.dart';
import 'dart:convert';
import 'package:dioman/dioman.dart';
import 'package:test/test.dart';
import 'fake_clock.dart';
import 'fake_network.dart';
import 'helpers.dart';

/// 启用 I1–I7，刷新按调用方声明的轮次统计。
class InvariantHarness {
  /// 绑定网络和时钟。
  InvariantHarness(this.network, this.clock);

  /// 网络发送证据。
  final FakeNetwork network;

  /// 时间资源证据。
  final FakeClock clock;

  /// 外层进入次数。
  final entries = <int, int>{};

  /// 外层离开次数。
  final exits = <int, int>{};

  /// 调用方落定次数。
  final settlements = <int, int>{};

  /// I2 回调配对序列。
  final loading = <Object, List<bool>>{};

  /// I4 每请求通知次数。
  final notifications = <int, int>{};

  /// I5 每轮刷新次数。
  final refreshRounds = <int, int>{};

  /// 声明即将开始的刷新轮，零调用也会被 I5 拒绝。
  void beginRefreshRound(int round) => refreshRounds[round] = 0;

  /// 包装真实 onRefresh；同一轮多次刷新会被 I5 拒绝。
  DiomanAuthRefresh refreshInRound(int round, DiomanAuthRefresh refresh) =>
      (tokens, result) {
        refreshRounds.update(round, (n) => n + 1);
        return refresh(tokens, result);
      };

  /// 各层保存的上下文，用于请求结束后追踪取消订阅。
  final contexts = <DiomanContext<Result>>[];

  /// 创建按回调身份记录 I2 的真实 loading 插件。
  DiomanLoading<Result> loadingPlugin(
      {Duration delay = Duration.zero, Duration delayClose = Duration.zero}) {
    final identity = Object();
    return DiomanLoading<Result>(
        onChanged: (visible) {
          loading.putIfAbsent(identity, () => []).add(visible);
        },
        delay: delay,
        delayClose: delayClose);
  }

  /// stringify 以 ctx.id 标记，notify 按逻辑请求而非响应身份记录 I4。
  DiomanNotify<Result> notifyPlugin() => DiomanNotify<Result>(
      stringify: (r, ctx) =>
          r.ok || r.kind == DiomanKind.cancel || ctx.request.silent
              ? ''
              : '${ctx.id}',
      notify: (message, r) {
        notifications.update(int.parse(message), (n) => n + 1,
            ifAbsent: () => 1);
      });

  /// 生成最外层及每阶段 pre/post 的直通探针。
  List<DiomanPlugin<Result>> probes() => [
        TestPlugin('invariant',
            stage: DiomanStage.outer,
            enforce: DiomanEnforce.pre, handler: (ctx, next) async {
          entries.update(ctx.id, (n) => n + 1, ifAbsent: () => 1);
          contexts.add(ctx);
          final r = await next();
          exits.update(ctx.id, (n) => n + 1, ifAbsent: () => 1);
          return r;
        }),
        for (final stage in DiomanStage.values)
          for (final enforce in DiomanEnforce.values)
            TestPlugin('probe:${stage.name}:${enforce.name}',
                stage: stage, enforce: enforce, handler: (ctx, next) async {
              final r = await next();
              expect(r.kind, isNot(DiomanKind.internal),
                  reason: 'I6 next 不抛且受控流程无 internal');
              return r;
            }),
      ];

  /// 登记一个逻辑调用及其最终一次落定。
  Future<T> track<T>(int id, Future<T> pending) => pending.whenComplete(() {
        settlements.update(id, (n) => n + 1, ifAbsent: () => 1);
      });

  /// 统一断言不变量；测试夹具自身的坏证据也必须被拒绝。
  void assertAll(Dioman<Result> api) {
    expect(entries, isNotEmpty, reason: 'I1 不允许空跑');
    expect(entries.keys.toSet(), exits.keys.toSet());
    expect(entries.keys.toSet(), settlements.keys.toSet());
    for (final id in entries.keys) {
      expect([entries[id], exits[id], settlements[id]], [1, 1, 1]);
    }
    expect(api.pending, 0, reason: 'I3');
    expect(api.cancellationSubscriptions, 0);
    expect(contexts.every((c) => c.cancellationSubscriptions == 0), isTrue);
    expect(clock.pendingTimers, 0);
    final bodies = <Object?, String>{};
    for (final send in network.sends) {
      if (send.invariant == null) continue;
      final body = jsonEncode(send.body);
      expect(body, bodies.putIfAbsent(send.invariant, () => body),
          reason: 'I7');
    }
    for (final sequence in loading.values) {
      expect(sequence.length.isEven, isTrue);
      for (var i = 0; i < sequence.length; i++) {
        expect(sequence[i], i.isEven);
      }
    }
    expect(notifications.values.every((n) => n <= 1), isTrue);
    expect(refreshRounds.values.every((n) => n == 1), isTrue);
  }
}
