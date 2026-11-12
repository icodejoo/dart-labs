import 'package:dioman/src/diagnostics.dart';
import 'dart:async';
import 'package:dioman/dioman.dart';
import 'package:test/test.dart';
import '../support/source_test_helpers.dart';
import '../support/fake_network.dart';
import '../support/helpers.dart';


/// 验证对应主题的行为与边界。
void main() {
  test(
      '[INV-context-lifecycle]'
      '[DiomanShare.policy × Dioman.cancelAll] 胜出后落败传输随订阅退出取消，之后取消或销毁幂等',
      () async {
    for (final policy in [DiomanSharePolicy.end, DiomanSharePolicy.race]) {
      for (final dispose in [false, true]) {
        final gate = Completer<void>();
        final net = FakeNetwork()
          ..routes[b4Route] = [FakeReply(gate: gate.future), const FakeReply()];
        final api =
            testClient(network: net, plugins: [const DiomanShare<Result>()]);
        final loser =
            api.send<Object?>(b4Get, b4Path, call: b4Call(share: policy));
        await b4Turn();
        final winner =
            api.send<Object?>(b4Get, b4Path, call: b4Call(share: policy));
        expect((await loser).ok, isTrue);
        expect((await winner).ok, isTrue);
        expect(api.pending, 0);
        expect(api.plugin<DiomanShareApi>()!.activeEntries, 0);
        final token = net.sends.first.options.cancelToken!;
        expect(token.isCancelled, isTrue);
        await b4Turn();
        if (dispose) {
          api.dispose();
        } else {
          expect(api.cancelAll(), 0);
        }
        expect(token.isCancelled, isTrue);
        gate.complete();
        await b4Turn();
        expect(api.cancelAll(), 0);
        expect(api.cancellationSubscriptions, 0);
        api.dispose();
      }
    }
  });
}
