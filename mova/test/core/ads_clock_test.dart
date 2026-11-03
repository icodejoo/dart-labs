import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mova/mova.dart';
import '../support/fake_api.dart';

/// 广告时钟测试固定正片。
const content = MovaSource('https://host/content.mp4');
/// 十秒广告位，允许立即跳过。
const slot = MovaAdBreak(kind: MovaAdBreakKind.pre, source: MovaSource('https://host/ad.mp4'), duration: Duration(seconds: 10), skippableAfter: Duration.zero);
/// 带五秒倒计时的中插。
const delayed = MovaAdBreak(kind: MovaAdBreakKind.mid, source: MovaSource('https://host/mid.mp4'), offset: Duration(seconds: 30), delay: Duration(seconds: 5), duration: Duration(seconds: 10));

/// 用注入时钟构造广告环境，不依赖墙钟流逝。
(FakeMovaApi, MovaAds, List<MovaAdEvent>) rig(FakeAsync a, {bool pending = false, bool framed = false, bool startPending = true}) {
  final events = <MovaAdEvent>[];
  final api = FakeMovaApi(options: MovaOpts(ads: MovaAdConfig(enabled: true, breaks: [pending ? delayed : slot], durationFromFirstFrame: framed, loadTimeout: const Duration(seconds: 8), onAdEvent: events.add)));
  final ads = MovaAds(api)..debugClock = () => DateTime.utc(2026).add(a.elapsed);
  ads.load(content);
  a.flushMicrotasks();
  api.push(api.state.copyWith(playing: true));
  a.flushMicrotasks();
  if (pending && startPending) {
    api.pushProgress(const MovaProg(position: Duration(seconds: 31)));
    a.flushMicrotasks();
  }
  if (!pending && !framed) {
    api.pushEvent(const MovaFirstFrame(sinceOpen: Duration.zero, signal: MovaFirstFrameSignal.restart));
    a.flushMicrotasks();
  }
  return (api, ads, events);
}

/// 推送独立的内核播放观测。
void playing(FakeAsync a, FakeMovaApi api, bool value) {
  api.push(api.state.copyWith(playing: value));
  a.flushMicrotasks();
}

void main() {
  test('广告位计时中 playing 真→假→真：剩余时长保留', () => fakeAsync((a) {
    final (api, ads, events) = rig(a);
    a.elapse(const Duration(seconds: 4));
    playing(a, api, false);
    a.elapse(const Duration(seconds: 30));
    expect(events.where((e) => e.type == MovaAdEventType.completed), isEmpty);
    playing(a, api, true);
    a.elapse(const Duration(seconds: 5));
    expect(ads.isShowingAd, isTrue);
    a.elapse(const Duration(seconds: 1));
    expect(events.where((e) => e.type == MovaAdEventType.completed), hasLength(1));
    ads.dispose(); a.flushMicrotasks();
  }));
  test('倒计时中暂停正片：delayRemaining 停住，恢复后再走', () => fakeAsync((a) {
    final (api, ads, _) = rig(a, pending: true);
    a.elapse(const Duration(seconds: 2));
    playing(a, api, false);
    a.elapse(const Duration(seconds: 10));
    expect(ads.delayRemaining, const Duration(seconds: 3));
    expect(ads.isAdPending, isTrue);
    playing(a, api, true);
    a.elapse(const Duration(seconds: 3));
    expect(ads.isShowingAd, isTrue);
    ads.dispose(); a.flushMicrotasks();
  }));
  test('暂停中 skip 只续播一次', () => fakeAsync((a) {
    final (api, ads, events) = rig(a);
    a.elapse(const Duration(seconds: 3));
    playing(a, api, false);
    ads.skip(); a.flushMicrotasks();
    a.elapse(const Duration(seconds: 20));
    expect(events.where((e) => e.type == MovaAdEventType.skipped), hasLength(1));
    expect(events.where((e) => e.type == MovaAdEventType.completed), isEmpty);
    expect(api.openedUris.where((u) => u == content.uri), hasLength(1));
    expect(a.pendingTimers, isEmpty);
    ads.dispose(); a.flushMicrotasks();
  }));
  test('暂停中 Done 只结算一次', () => fakeAsync((a) {
    final (api, ads, events) = rig(a);
    playing(a, api, false);
    api.emitDone(); api.emitDone(); a.flushMicrotasks();
    expect(events.where((e) => e.type == MovaAdEventType.completed), hasLength(1));
    expect(api.openedUris.where((u) => u == content.uri), hasLength(1));
    expect(a.pendingTimers, isEmpty);
    ads.dispose(); a.flushMicrotasks();
  }));
  test('暂停中 load(B)：旧时钟作废', () => fakeAsync((a) {
    final (api, ads, events) = rig(a, pending: true, startPending: false);
    ads.playAdNow(slot); a.flushMicrotasks();
    api.pushEvent(const MovaFirstFrame(sinceOpen: Duration.zero, signal: MovaFirstFrameSignal.restart));
    a.flushMicrotasks();
    playing(a, api, false);
    ads.load(const MovaSource('https://host/B.mp4')); a.flushMicrotasks();
    final opened = api.openCalls;
    playing(a, api, true);
    a.elapse(const Duration(seconds: 30));
    expect(events.where((e) => e.type == MovaAdEventType.completed), isEmpty);
    expect(api.openCalls, opened);
    expect(api.source!.uri.toString(), 'https://host/B.mp4');
    expect(a.pendingTimers, isEmpty);
    ads.dispose(); a.flushMicrotasks();
  }));
  test('起表时意图为假则以暂停态起表', () => fakeAsync((a) {
    final (api, ads, events) = rig(a, pending: true, framed: true, startPending: false);
    api.pause(); a.flushMicrotasks();
    ads.playAdNow(slot); a.flushMicrotasks();
    api.pause(); a.flushMicrotasks();
    api.pushEvent(const MovaFirstFrame(sinceOpen: Duration.zero, signal: MovaFirstFrameSignal.restart));
    a.flushMicrotasks();
    a.elapse(const Duration(seconds: 20));
    expect(events.where((e) => e.type == MovaAdEventType.completed), isEmpty);
    playing(a, api, false);
    playing(a, api, true);
    a.elapse(const Duration(seconds: 10));
    expect(events.where((e) => e.type == MovaAdEventType.completed), hasLength(1));
    ads.dispose(); a.flushMicrotasks();
  }));
  test('正片相的 playing 边沿不碰时钟、加载期限不随暂停', () => fakeAsync((a) {
    final (api, ads, events) = rig(a, framed: true);
    playing(a, api, false);
    a.elapse(const Duration(seconds: 8));
    expect(events.where((e) => e.type == MovaAdEventType.failed), hasLength(1));
    expect(ads.isShowingAd, isFalse);
    playing(a, api, true); playing(a, api, false);
    expect(a.pendingTimers, isEmpty);
    ads.dispose(); a.flushMicrotasks();
  }));
  test('dispose 同步取消时钟', () => fakeAsync((a) {
    for (final pending in [false, true]) {
      final (_, ads, _) = rig(a, pending: pending);
      expect(a.pendingTimers, isNotEmpty);
      ads.dispose();
      expect(a.pendingTimers, isEmpty);
      a.flushMicrotasks();
    }
  }));
}
