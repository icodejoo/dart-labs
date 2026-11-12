import '../support/response_contract.dart';
import 'dart:async';
import 'package:dioman/dioman.dart';
import 'package:test/test.dart';
import '../support/auth_test_helpers.dart';
import '../support/helpers.dart';


/// 验证对应主题的行为与边界。
void main() {
  test('[DiomanAuth.setup] 同配置客户端共享窗口，卸载首发客户端后等待者继续', () async {
    final tm = TestTokens();
    final gates = List.generate(1, (_) => Completer<void>());
    final starts = List.generate(1, (_) => Completer<void>());
    var calls = 0;
    final auth = b3Auth(tm, refresh: (tokens, r) async {
      final index = calls++;
      starts[index].complete();
      await gates[index].future;
      tokens.setTokens(accessToken: b3Fresh);
    });
    final source = TestPlugin(b3ValueResult,
        stage: DiomanStage.source,
        handler: (ctx, next) async =>
            ctx.request.headers[b3Header] == 'Bearer $b3Old'
                ? scriptedResult(ctx, diomanTestHttp, status: 401)
                : next());
    final a = testClient(plugins: [auth, source]);
    final b = testClient(plugins: [auth, source]);
    final first = a.send<Object?>(b3ValueGet, b3Path);
    await starts[0].future;
    final second = b.send<Object?>(b3ValueGet, b3Path);
    await b3Turn();
    expect(calls, 1);
    a.dispose();
    expect(outcomeOf((await first)), diomanTestCancel);
    await expectLater(a.send<Object?>(b3ValueGet, b3Path), throwsStateError);
    gates[0].complete();
    expect((await second).ok, isTrue);
    b.dispose();
  });
}
