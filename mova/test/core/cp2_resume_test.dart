import 'package:flutter_test/flutter_test.dart';
import 'package:mova/mova.dart';

import '../support/fake_api.dart';
import 'ads_interleaving_test.dart' show AdOperationRig;
import 'cutover/cutover_operation_test.dart' show settleOperations;

/// 等待型中插预热期间正片仍在播放，续播目标应跟随它而非冻结在触发点。
void main() {
  for (final extension in ['mp4', 'm3u8']) {
    for (final warmReturn in [false, true]) {
      test('CP2 $extension 中插等待后${warmReturn ? '影子' : '直接'}续播最新正片点', () async {
        final content = MovaSource('https://host/content.$extension');
        const ad = MovaAdBreak(
          kind: MovaAdBreakKind.mid,
          source: MovaSource('https://host/ad.mp4'),
          offset: Duration(seconds: 4),
        );
        final rig = AdOperationRig(breaks: [ad]);
        addTearDown(rig.dispose);
        await rig.ads.load(content);
        final old = rig.engines.first;
        old.pushProgress(const MovaProg(position: Duration(seconds: 4)));
        await settleOperations();
        final adShadow = rig.engines.last;
        // 模拟真机预热耗时 1.12 秒，正片在换指前继续推进。
        const target = Duration(milliseconds: 5120);
        old.pushProgress(const MovaProg(position: target));
        await settleOperations();
        await rig.ready(adShadow);
        expect(rig.api.active, same(adShadow));
        if (warmReturn) {
          adShadow.pushProgress(
            const MovaProg(position: Duration(milliseconds: 100)),
          );
          await settleOperations();
          final shadow = rig.engines.last;
          expect(shadow, isNot(same(adShadow)));
          shadow.pushProgress(
            const MovaProg(position: target, buffer: Duration(seconds: 10)),
          );
          await settleOperations();
          shadow.pushProgress(
            const MovaProg(position: target, buffer: Duration(seconds: 10)),
          );
          await settleOperations();
        } else {
          // 就绪信号可能已启动正片预热；主动放弃，覆盖凭据不可用的直接打开兜底。
          await rig.api.abandon();
        }
        adShadow.emitDone();
        await settleOperations();
        final resumed = rig.api.active as FakeMovaApi;
        expect(resumed.source, content);
        expect(resumed.lastSeek, target);
        expect(rig.api.state.renderEpoch, warmReturn ? 2 : 1);
      });
    }
  }
}
