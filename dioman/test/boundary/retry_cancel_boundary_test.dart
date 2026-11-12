import '../support/response_contract.dart';
import 'package:dioman/src/diagnostics.dart';
import 'package:dioman/dioman.dart';
import 'package:test/test.dart';
import '../support/auth_test_helpers.dart';
import '../support/fake_clock.dart';
import '../support/helpers.dart';
import '../support/fake_network.dart';




/// 验证对应主题的行为与边界。
void main() {
  test('[DiomanNext] 重发之后 internal 原样抛出，取消禁止第三次尝试', () async {
    for (final internal in [false, true]) {
      final clock = FakeClock();
      var entered = 0;
      final bug = StateError('second');
      final api = testClient(clock: clock, plugins: [
        const DiomanRetry(max: 3),
        TestPlugin(b3ValueResult, stage: DiomanStage.source,
            handler: (ctx, next) async {
          entered++;
          if (entered == 2) {
            ctx.state.cancel();
            if (internal) throw bug;
          }
          return scriptedResult(ctx, diomanTestNetwork);
        })
      ]);
      final p = b3Finish(api.send<Object?>(b3ValueGet, b3Path), clock);
      if (internal) {
        await expectLater(p, throwsA(same(bug)));
      } else {
        expect(outcomeOf((await p)), diomanTestCancel);
      }
      expect(entered, 2);
      api.dispose();
    }
  });

  test('[DiomanRetry.option] 请求级关闭不恢复，旧请求失败不恢复别的逻辑调用', () async {
    final net = FakeNetwork()
      ..routes[b3Route] = [const FakeReply(status: 500), const FakeReply()];
    final clock = FakeClock();
    final api = testClient(
        statusOf: businessStatus,
        network: net,
        clock: clock,
        plugins: [const DiomanRetry(max: 1)]);
    final a = await api.send<Object?>(b3ValueGet, b3Path,
        call: DiomanCall(options: {DiomanRetry.option: false}));
    expect(a.status, 500);
    expect(net.sends.length, 1);
    expect((await b3Finish(api.send<Object?>(b3ValueGet, b3Path), clock)).ok,
        isTrue);
    expect(a.status, 500);
    api.dispose();
  });
}
