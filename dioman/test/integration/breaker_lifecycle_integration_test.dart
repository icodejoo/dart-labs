import '../support/response_contract.dart';
import 'package:dioman/dioman.dart';
import 'package:test/test.dart';
import '../support/auth_test_helpers.dart';
import '../support/fake_clock.dart';
import '../support/helpers.dart';


/// 验证对应主题的行为与边界。
void main() {
  test('[Dioman.use × DiomanBreakerApi.stateOf] 插入移除替换熔断器使用新实例，dispose 拒绝复活',
      () async {
    final clock = FakeClock();
    var sends = 0;
    final api = testClient(clock: clock, plugins: [
      const DiomanRetry(max: 2),
      TestPlugin(b3ValueResult, stage: DiomanStage.source,
          handler: (ctx, next) async {
        sends++;
        return scriptedResult(ctx, diomanTestNetwork);
      })
    ]);
    api.use(const DiomanBreaker(failureThreshold: 1));
    final old = api.plugin<DiomanBreakerApi>()!;
    expect(
        outcomeOf(
            (await b3Finish(api.send<Object?>(b3ValueGet, b3Path), clock))),
        diomanTestBreaker);
    expect(sends, 1);
    expect(api.eject(DiomanBreaker.pluginName), isTrue);
    expect(old.bucketCount, 0);
    expect(
        outcomeOf(
            (await b3Finish(api.send<Object?>(b3ValueGet, b3Path), clock))),
        diomanTestNetwork);
    expect(sends, 4);
    api.use(const DiomanBreaker(failureThreshold: 2));
    expect(identical(api.plugin<DiomanBreakerApi>(), old), isFalse);
    expect(
        outcomeOf(
            (await b3Finish(api.send<Object?>(b3ValueGet, b3Path), clock))),
        diomanTestBreaker);
    expect(sends, 6);
    api.dispose();
    await expectLater(api.send<Object?>(b3ValueGet, b3Path), throwsStateError);
  });
}
