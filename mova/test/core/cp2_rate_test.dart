import 'package:flutter_test/flutter_test.dart';
import 'package:mova/mova.dart';

import '../support/fake_kernel.dart';
import 'cutover/cutover_operation_test.dart' show settleOperations;

/// 用真实引擎和替身内核保留状态总线的异步时序。
void main() {
  for (final warmReturn in [false, true]) {
    test('CP2 即时插播后${warmReturn ? '影子提交' : '直接打开'}恢复刚设定的倍速', () async {
      final kernels = <FakeKernel>[];
      final api = MovaCutoverEngine(
        engineFactory: () {
          final kernel = FakeKernel();
          kernels.add(kernel);
          return MovaEngine(
            kernel: kernel,
            options: const MovaOpts(
              cutover: MovaCutoverConfig(
                enabled: true,
                trigger: MovaEagerWarm(),
              ),
              ads: MovaAdConfig(enabled: true),
            ),
          );
        },
      );
      final ads = MovaAds(api, cutover: api);
      addTearDown(() async {
        await ads.dispose();
        await api.dispose();
      });
      await ads.load(const MovaSource('https://host/content.mp4'));
      await settleOperations();
      await api.setRate(1.5);
      // 紧接 await 插播，不能插入排空微任务掩盖用户快照读取旧代理状态的问题。
      await ads.playAdNow(
        const MovaAdBreak(
          kind: MovaAdBreakKind.mid,
          source: MovaSource('https://host/ad.mp4'),
          waitForReady: false,
          skippableAfter: Duration.zero,
        ),
      );
      await settleOperations();
      expect(kernels.first.lastRate, 1.0);
      if (warmReturn) {
        kernels.first.emitPosition(const Duration(milliseconds: 100));
        await settleOperations();
        expect(kernels, hasLength(2));
        final shadow = kernels.last;
        shadow.emitDuration(const Duration(minutes: 2));
        shadow.emitBuffering(false);
        shadow.emitBuffer(const Duration(seconds: 10));
        for (var i = 0; i < 3; i++) {
          shadow.emitPosition(Duration(milliseconds: 100 + i * 100));
          await Future<void>.delayed(const Duration(milliseconds: 250));
          await settleOperations();
        }
      }
      ads.skip();
      await settleOperations();
      expect(ads.isShowingAd, isFalse);
      expect(api.state.rate, 1.5);
      expect(kernels.last.lastRate, 1.5);
      expect(api.state.renderEpoch, warmReturn ? 1 : 0);
    });
  }
}
