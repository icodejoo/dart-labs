import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mova/src/core/model/ad.dart';
import 'package:mova/src/core/model/source.dart';
import 'package:mova/src/core/state/progress.dart';

import 'ads_interleaving_test.dart' show AdOperationRig;
import 'cutover/cutover_operation_test.dart' show settleOperations;

/// 验证回正片等待期间只处理转场，不解释旧广告事件。
void main() {
  const content = MovaSource('https://host/A.mp4');
  const mid = MovaAdBreak(
    kind: MovaAdBreakKind.mid,
    source: MovaSource('https://host/mid.mp4'),
    offset: Duration(seconds: 5),
  );
  const post = MovaAdBreak(kind: MovaAdBreakKind.post, source: MovaSource('https://host/post.mp4'));

  test('回正片 commit 等待期间广告 tick 越过中插，不触发 pending', () async {
    final rig = AdOperationRig(breaks: [mid]);
    addTearDown(rig.dispose);
    await rig.ads.load(content);
    final shadow = await rig.warmContent();
    final old = rig.engines.first;
    old.pauseGate = Completer<void>();
    old.emitDone();
    await settleOperations();
    expect(rig.ads.isShowingAd, isFalse);
    old.pushProgress(const MovaProg(position: Duration(seconds: 30)));
    await settleOperations();
    expect(rig.ads.isAdPending, isFalse);
    expect(rig.ads.currentBreak, isNull);
    expect(rig.engines, hasLength(2));
    old.pauseGate!.complete();
    await settleOperations();
    expect(rig.api.active, same(shadow));
    shadow.pushProgress(const MovaProg(position: Duration(seconds: 6)));
    await settleOperations();
    expect(rig.ads.isAdPending, isTrue, reason: '正片真正接管后的进度仍能触发中插');
  });

  test('回正片期间旧广告 Done 不触发后贴片或 contentEnded', () async {
    final rig = AdOperationRig(breaks: [post]);
    addTearDown(rig.dispose);
    var ended = 0;
    final sub = rig.ads.contentEnded.listen((_) => ended++);
    addTearDown(sub.cancel);
    await rig.ads.load(content);
    await rig.warmContent();
    final old = rig.engines.first;
    old.pauseGate = Completer<void>();
    old.emitDone();
    await settleOperations();
    old.emitDone();
    await settleOperations();
    expect(rig.ads.isShowingAd, isFalse);
    expect(rig.ads.currentBreak, isNull);
    expect(old.openedUris, isNot(contains(post.source.uri)));
    expect(ended, 0);
    old.pauseGate!.complete();
    await settleOperations();
  });

  test('回正片期间 playAdNow 不用旧广告位置插播', () async {
    final rig = AdOperationRig();
    addTearDown(rig.dispose);
    await rig.ads.load(content);
    final shadow = await rig.warmContent();
    final old = rig.engines.first;
    old.pauseGate = Completer<void>();
    old.emitDone();
    await settleOperations();
    old.pushProgress(const MovaProg(position: Duration(seconds: 30)));
    await settleOperations();
    await rig.ads.playAdNow(mid);
    expect(rig.ads.currentBreak, isNull);
    expect(rig.ads.isAdPending, isFalse);
    expect(rig.engines, hasLength(2));
    old.pauseGate!.complete();
    await settleOperations();
    expect(rig.api.active, same(shadow));
  });
}
