import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mova/mova.dart';

import '../support/fake_api.dart';
import 'ads_interleaving_test.dart' show AdOperationRig;
import 'cutover/cutover_operation_test.dart' show settleOperations;

/// CP2 同配置的等待型前贴片 pod；隔离原生资源污染与正常换指路径。
const _pod = [
  MovaAdBreak(
    kind: MovaAdBreakKind.pre,
    source: MovaSource('https://host/ad.mp4'),
    waitForReady: true,
  ),
  MovaAdBreak(
    kind: MovaAdBreakKind.pre,
    source: MovaSource('https://host/ad2.mp4'),
    waitForReady: true,
  ),
];
const _content = MovaSource('https://host/content.mp4');

/// 完成第一条广告的准备与提交。
Future<void> _first(AdOperationRig rig) async {
  final loading = rig.ads.load(_content);
  await settleOperations();
  await rig.ready(rig.engines.last);
  expect(await loading, isTrue);
  expect(rig.api.state.renderEpoch, 1);
}

void main() {
  test('CP2 干净资源下连续二十轮 pod 第二条均独立提交并释放', () async {
    for (var run = 0; run < 20; run++) {
      final rig = AdOperationRig(breaks: _pod);
      try {
        await _first(rig);
        final first = rig.api.active as FakeMovaApi;
        first.emitDone();
        await settleOperations();
        final second = rig.engines.last;
        expect(second, isNot(same(first)));
        await rig.ready(second);
        expect(rig.api.active, same(second));
        expect(second.source, _pod[1].source);
        expect(rig.api.state.renderEpoch, 2, reason: '第 $run 轮');
        expect(first.openedUris, isNot(contains(_pod[1].source.uri)));
      } finally {
        await rig.dispose();
      }
      expect(rig.engines.every((e) => e.disposeCount == 1), isTrue);
    }
  });

  test('CP2 第二条影子初始化失败按契约硬切主引擎且不增长纪元', () async {
    final rig = AdOperationRig(breaks: _pod);
    addTearDown(rig.dispose);
    await _first(rig);
    final first = rig.api.active as FakeMovaApi;
    final gate = rig.gateShadow = Completer<void>();
    first.emitDone();
    await settleOperations();
    final failed = rig.engines.last;
    expect(failed, isNot(same(first)));
    // 仅注入原生资源不可用的结果，验证既有 fallback，并非制造新的产品错误。
    failed.openThrows = StateError('decoder resource exhausted');
    gate.complete();
    await settleOperations();
    expect(failed.disposeCount, 1);
    expect(rig.api.active, same(first));
    expect(first.source, _pod[1].source);
    expect(rig.api.state.renderEpoch, 1);
    expect(rig.ads.currentBreak, same(_pod[1]));
  });
}
