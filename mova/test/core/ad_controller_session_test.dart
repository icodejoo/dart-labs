import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mova/src/core/ad/ad_controller.dart';
import 'package:mova/src/core/model/ad.dart';
import 'package:mova/src/core/model/source.dart';
import 'package:mova/src/core/options/options.dart';
import 'package:mova/src/core/state/progress.dart';

import '../support/fake_api.dart';

const _srcA = MovaSource('https://host/a.m3u8');
const _srcB = MovaSource('https://host/b.m3u8');
const _pre = MovaAdBreak(
  kind: MovaAdBreakKind.pre,
  source: MovaSource('https://host/pre.mp4'),
);

/// Yields a few microtasks so chained awaits inside the controller settle.
///
/// 让出几个微任务，使控制器内部链式 await 结算完毕。
Future<void> settle() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  group('MovaAdController 会话隔离（旧解析结果不得污染新会话）', () {
    test('loadDeferred(R1) 未返回时再 loadDeferred(R2)：R2 用自己的结果，R1 迟到结果不重开旧正片', () async {
      final api = FakeMovaApi(options: const MovaOpts(ads: MovaAdConfig(enabled: true, breaks: [])));
      final c = MovaAdController(api);
      final r1 = Completer<MovaSource>();
      final f1 = c.loadDeferred(() => r1.future);
      await settle();
      final f2 = c.loadDeferred(() async => _srcB);
      await settle();
      expect(api.openedUris.last, _srcB.uri);

      r1.complete(_srcA);
      await Future.wait([f1, f2]);
      await settle();
      expect(api.openedUris, isNot(contains(_srcA.uri)), reason: '旧会话的解析结果不能被打开');
      expect(api.source?.uri, _srcB.uri);
    });

    test('loadDeferred(R1) 未返回时 load(B)：R1 迟到结果不覆盖 B', () async {
      final api = FakeMovaApi(options: const MovaOpts(ads: MovaAdConfig(enabled: true, breaks: [])));
      final c = MovaAdController(api);
      final r1 = Completer<MovaSource>();
      final f1 = c.loadDeferred(() => r1.future);
      await settle();
      await c.load(_srcB);
      await settle();

      r1.complete(_srcA);
      await f1;
      await settle();
      expect(api.openedUris, isNot(contains(_srcA.uri)));
      expect(api.source?.uri, _srcB.uri);
    });

    test('解析途中 dispose：迟到结果不再 open 正片', () async {
      final api = FakeMovaApi(options: const MovaOpts(ads: MovaAdConfig(enabled: true, breaks: [])));
      final c = MovaAdController(api);
      final r1 = Completer<MovaSource>();
      final f1 = c.loadDeferred(() => r1.future);
      await settle();
      await c.dispose();

      r1.complete(_srcA);
      await f1;
      await settle();
      expect(api.openedUris, isEmpty);
    });

    test('预热等待解析期间换了会话：旧结果不触发 prepare', () async {
      final swap = FakeSwapCtl();
      final api = FakeMovaApi(
        options: const MovaOpts(ads: MovaAdConfig(enabled: true, breaks: [_pre])),
      );
      final c = MovaAdController(api, swap: swap);
      final r1 = Completer<MovaSource>();
      await c.loadDeferred(() => r1.future);
      await settle();
      // 广告首帧进度 tick，触发预热并卡在解析上。
      api.pushProgress(const MovaProg(position: Duration(seconds: 1)));
      await settle();
      // 新会话仍然在播前贴片，_phase 依旧是 ad，旧校验区分不出来。
      await c.load(_srcB);
      await settle();
      swap.calls.clear();

      r1.complete(_srcA);
      await settle();
      expect(swap.calls, isNot(contains('prepare')), reason: '旧会话的解析结果不得预热');
    });
  });
}
