import 'response_contract.dart';
import 'package:dio/dio.dart';
import 'package:dioman/src/diagnostics.dart';
import 'dart:convert';
import 'package:dioman/dioman.dart';
import 'package:test/test.dart';
import 'fake_clock.dart';
import 'fake_network.dart';
import 'helpers.dart';

/// 观察显式清理后的资源，不依赖 Expando 的垃圾回收。
abstract final class SharedResourceProbe {
  /// 每个用例收尾必须没有会话持有者或显示窗口。
  static void assertEmpty() {
    expect(DiomanAuthDiagnostics.sessions, 0, reason: 'I10 auth 会话');
    expect(DiomanAuthDiagnostics.owners, 0, reason: 'I10 auth 持有者');
    expect(DiomanLoadingDiagnostics.entries, 0, reason: 'I10 loading 条目');
  }
}

/// 验证落定后的清空与封闭，并模拟迟到传输写入。
abstract final class NativeSlotProbe {
  /// 注入原生响应和异常后仍须保持空槽。
  static void assertClosed(DiomanContext ctx) {
    expect(ctx.state.nativeClosed, isTrue, reason: 'I11 封闭');
    expect(ctx.state.nativeSlot, isNull, reason: 'I11 清空');
    expect(ctx.native, isNull, reason: 'I11 公开视图');
    final result = ctx.factory.fail(ctx.request, DiomanFailureKind.network);
    ctx.writeNative(
        result,
        Response(requestOptions: ctx.request.toRequestOptions()),
        StateError('late'));
    ctx.observeNative(result);
    expect(ctx.state.nativeSlot, isNull, reason: 'I11 拒绝迟到写入');
    expect(ctx.state.nativeResult, isNull, reason: 'I11 拒绝迟到结果');
    expect(ctx.native, isNull, reason: 'I11 迟到公开视图');
  }
}

/// 启用 I1–I11，刷新按调用方声明的轮次统计。
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

  /// I8 在落定时记录调用方自身取消与实际结果类别。
  final ownership = <int, (bool, String)>{};

  /// 调用方计时器明确确认的自身超时；未声明的 timeout 属于污染。
  final ownTimeouts = <int>{};

  /// I9 由调用方登记的请求体与服务端回显。
  final expectedEcho = <int, Object?>{};
  final actualEcho = <int, Object?>{};

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
          r.ok || outcomeOf(r) == diomanTestCancel || ctx.request.silent
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
          ownership[ctx.id] = (ctx.cancelled() != null, outcomeOf(r));
          if (expectedEcho.containsKey(ctx.id) && r.status != 0) {
            actualEcho[ctx.id] = r.data;
          }
          exits.update(ctx.id, (n) => n + 1, ifAbsent: () => 1);
          return r;
        }),
        for (final stage in DiomanStage.values)
          for (final enforce in DiomanEnforce.values)
            TestPlugin('probe:${stage.name}:${enforce.name}',
                stage: stage, enforce: enforce, handler: (ctx, next) async {
              final r = await next();
              expect(outcomeOf(r), isNot(diomanTestInternal),
                  reason: 'I6 next 不抛且受控流程无 internal');
              return r;
            }),
      ];

  /// 登记一个逻辑调用及其最终一次落定。
  Future<T> track<T>(int id, Future<T> pending) => pending.whenComplete(() {
        settlements.update(id, (n) => n + 1, ifAbsent: () => 1);
      });

  /// 客户端全部释放后检查共享资源。
  void assertResourcesReleased() => SharedResourceProbe.assertEmpty();

  /// 统一断言不变量；测试夹具自身的坏证据也必须被拒绝。
  void assertAll(Dioman<Result> api) {
    expect(entries, isNotEmpty, reason: 'I1 不允许空跑');
    expect(entries.keys.toSet(), exits.keys.toSet());
    expect(entries.keys.toSet(), settlements.keys.toSet());
    for (final id in entries.keys) {
      expect([entries[id], exits[id], settlements[id]], [1, 1, 1]);
    }
    for (final entry in ownership.entries) {
      final outcome = entry.value;
      expect(outcome.$2 == diomanTestCancel, outcome.$1, reason: 'I8 取消归属');
      expect(outcome.$2 == diomanTestTimeout, ownTimeouts.contains(entry.key),
          reason: 'I8 超时归属');
    }
    for (final id in actualEcho.keys) {
      expect(actualEcho[id], expectedEcho[id], reason: 'I9 请求回显与调用方请求一致');
    }
    for (final ctx in contexts) {
      NativeSlotProbe.assertClosed(ctx);
    }
    expect(api.pending, 0, reason: 'I3');
    expect(api.cancellationSubscriptions, 0);
    expect(contexts.every((c) => c.cancellationSubscriptions == 0), isTrue);
    expect(clock.pendingTimers, 0);
    final bodies = <Object?, String>{};
    for (final send in network.sends) {
      if (expectedEcho.containsKey(send.invariant)) {
        expect(send.body, expectedEcho[send.invariant],
            reason: 'I9 实际发送等于调用方请求');
      }
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
