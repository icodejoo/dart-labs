import 'package:dioman/dioman.dart';
import 'package:test/test.dart';
import '../support/helpers.dart';
import '../support/fake_clock.dart';

/// 本文件共用的测试值。
const _diomanLiteral0 = 'GET';

/// 本文件共用的测试值。
const _diomanLiteral1 = 'failure';

/// 默认退避的逐毫秒验证。
void main() {
  test(
      '[DiomanRetry.max][DiomanRetry.delayMax][DiomanRetry.defaultDelay] 默认重试两次，300/600ms 且仅幂等方法',
      () async {
    const config = DiomanRetry();
    expect(config.max, 2);
    expect(config.delayMax, const Duration(seconds: 10));
    for (final method in [_diomanLiteral0, 'POST']) {
      var sends = 0;
      final clock = FakeClock();
      final api = testClient(clock: clock, plugins: [
        config,
        TestPlugin(_diomanLiteral1, stage: DiomanStage.source,
            handler: (ctx, next) async {
          sends++;
          return DiomanResponse<dynamic>(
              ok: false, status: 500, request: ctx.request);
        })
      ]);
      final pending = api.send<Object?>(method, '/retry');
      await flush();
      expect(sends, 1);
      if (method == _diomanLiteral0) {
        for (final milliseconds in [300, 600]) {
          final before = sends;
          clock.elapse(Duration(milliseconds: milliseconds - 1));
          await flush();
          expect(sends, before);
          clock.elapse(const Duration(milliseconds: 1));
          await flush();
          expect(sends, before + 1);
        }
      }
      await pending;
      expect(sends, method == _diomanLiteral0 ? 3 : 1);
      expect(clock.pendingTimers, 0);
    }
  });
  test('[DiomanRetry.delayMax] 百次重试仍由默认十秒上限裁剪', () async {
    final clock = FakeClock();
    var sends = 0;
    final api = testClient(clock: clock, plugins: [
      const DiomanRetry(max: 100),
      TestPlugin(_diomanLiteral1, stage: DiomanStage.source,
          handler: (ctx, next) async {
        sends++;
        return DiomanResponse<dynamic>(
            ok: false, status: 500, request: ctx.request);
      })
    ]);
    final pending = api.send<Object?>(_diomanLiteral0, '/cap');
    await flush();
    for (final milliseconds in [
      300,
      600,
      1200,
      2400,
      4800,
      9600,
      ...List.filled(94, 10000)
    ]) {
      final before = sends;
      clock.elapse(Duration(milliseconds: milliseconds - 1));
      await flush();
      expect(sends, before);
      clock.elapse(const Duration(milliseconds: 1));
      await flush();
      expect(sends, before + 1);
    }
    await pending;
    expect(sends, 101);
  });
}
