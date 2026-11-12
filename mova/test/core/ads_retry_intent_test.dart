import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mova/mova.dart';

import '../support/fake_kernel.dart';

/// 首次在写入意图之前抛错，第二次允许打开。
class _TransientHook extends MovaHook {
  /// 已进入钩子的次数。
  int calls = 0;

  /// 第一次抛临时异常，其余打开直接放行。
  @override
  Future<bool> beforeOpen(MovaSource source) async {
    if (++calls == 1) throw StateError('transient beforeOpen');
    return true;
  }
}

/// 用真实引擎验证首次钩子异常后的重试意图。
void main() {
  for (final pauseOnFailure in [false, true]) {
    test('F-O 首次 beforeOpen 抛错后重试保留 load 意图，失败窗口暂停=$pauseOnFailure', () async {
      final kernel = FakeKernel();
      final hook = _TransientHook();
      late MovaApi api;
      api = createMovaEngine(
        kernel: kernel,
        pip: MovaNoopPipPort(),
        orientation: MovaNoopOrientationPort(),
        brightness: MovaFallbackBrightnessPort(),
        interceptors: [hook],
        options: MovaOpts(ads: MovaAdConfig(
          enabled: true,
          breaks: const [MovaAdBreak(
            kind: MovaAdBreakKind.pre,
            source: MovaSource('https://host/pre.mp4'),
            waitForReady: false,
          )],
          failPolicy: const MovaAdRetrySkip(maxRetries: 1),
          onAdEvent: (event) {
            if (pauseOnFailure && event.type == MovaAdEventType.failed) {
              unawaited(api.pause());
            }
          },
        )),
      );
      final ads = MovaAds(api);
      addTearDown(() async { await ads.dispose(); await api.dispose(); });
      expect(api.state.playbackIntent, isFalse);
      await ads.load(const MovaSource('https://host/content.mp4'));
      expect(hook.calls, 2);
      expect(kernel.lastUri, 'https://host/pre.mp4');
      expect(kernel.lastPlay, !pauseOnFailure);
      expect(api.state.playbackIntent, !pauseOnFailure);
      expect(ads.isShowingAd, isTrue);
    });
  }
}
