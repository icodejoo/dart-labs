import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mova/src/core/ad/ads.dart';
import 'package:mova/src/core/ad/fail.dart';
import 'package:mova/src/core/events/events.dart';
import 'package:mova/src/core/model/ad.dart';
import 'package:mova/src/core/model/source.dart';
import 'package:mova/src/core/options/options.dart';
import 'package:mova/src/core/render/first_frame.dart';
import 'package:mova/src/core/state/progress.dart';

import '../support/fake_api.dart';

const _content = MovaSource('https://host/content.m3u8');
const _pre = MovaAdBreak(
  kind: MovaAdBreakKind.pre,
  source: MovaSource('https://host/pre.mp4'),
  duration: Duration(seconds: 5),
);
const _mid = MovaAdBreak(
  kind: MovaAdBreakKind.mid,
  source: MovaSource('https://host/mid.mp4'),
  offset: Duration(seconds: 30),
);

/// Lets the controller's async chains settle inside a [fakeAsync] zone.
///
/// 在 [fakeAsync] 区域内让控制器的异步链结算完毕。
void _flush(FakeAsync async) => async.elapse(const Duration(milliseconds: 1));

/// Builds api + controller around one pre-roll with a 8s load deadline.
///
/// 围绕一条前贴片、8 秒加载期限构造 api + 控制器。
(FakeMovaApi, MovaAds, _RecordingFail) _build({bool fromFirstFrame = true}) {
  final policy = _RecordingFail();
  final api = FakeMovaApi(
    options: MovaOpts(
      ads: MovaAdConfig(
        enabled: true,
        breaks: const [_pre],
        failPolicy: policy,
        durationFromFirstFrame: fromFirstFrame,
        waitForAdReady: const MovaAdWaitByKind(),
      ),
    ),
  );
  return (api, MovaAds(api), policy);
}

void main() {
  group('ad first-frame detection (#23)', () {
    test('a zero-position tick is not a first frame: load deadline still fires', () {
      fakeAsync((async) {
        final (api, c, policy) = _build();
        c.load(_content);
        _flush(async);
        api.pushProgress(const MovaProg(position: Duration.zero, buffer: Duration(seconds: 2)));
        _flush(async);
        async.elapse(const Duration(seconds: 8));
        _flush(async);
        expect(policy.seen, hasLength(1));
        expect(policy.seen.first.kind, MovaAdFailKind.loadTimeout);
      });
    });

    test('one lone non-zero tick (stale residue) is not a first frame', () {
      fakeAsync((async) {
        final (api, c, policy) = _build();
        c.load(_content);
        _flush(async);
        api.pushProgress(const MovaProg(position: Duration(seconds: 40)));
        _flush(async);
        async.elapse(const Duration(seconds: 8));
        _flush(async);
        expect(policy.seen, hasLength(1));
      });
    });

    test('two consecutive rising ticks (no precise signal) count as the first frame', () {
      fakeAsync((async) {
        final (api, c, policy) = _build();
        c.load(_content);
        _flush(async);
        api.pushProgress(const MovaProg(position: Duration(milliseconds: 100)));
        api.pushProgress(const MovaProg(position: Duration(milliseconds: 200)));
        _flush(async);
        async.elapse(const Duration(seconds: 30));
        _flush(async);
        expect(policy.seen, isEmpty);
      });
    });

    test('state.rendered == true makes any tick count as the first frame', () {
      fakeAsync((async) {
        final (api, c, policy) = _build();
        c.load(_content);
        _flush(async);
        api.push(api.state.copyWith(rendered: true));
        api.pushProgress(const MovaProg(position: Duration.zero));
        _flush(async);
        async.elapse(const Duration(seconds: 30));
        _flush(async);
        expect(policy.seen, isEmpty);
      });
    });

    test('a MovaFirstFrame event lands the first frame without any progress tick', () {
      fakeAsync((async) {
        final (api, c, policy) = _build();
        c.load(_content);
        _flush(async);
        api.pushEvent(const MovaFirstFrame(sinceOpen: Duration(milliseconds: 90), signal: MovaFirstFrameSignal.restart));
        _flush(async);
        async.elapse(const Duration(seconds: 30));
        _flush(async);
        expect(policy.seen, isEmpty);
      });
    });

    test('durationFromFirstFrame: a zero tick does not start the slot clock', () {
      fakeAsync((async) {
        final (api, c, _) = _build();
        c.load(_content);
        _flush(async);
        api.pushProgress(const MovaProg(position: Duration.zero));
        _flush(async);
        async.elapse(const Duration(seconds: 6));
        // 广告位时长 5s：若零位置 tick 误起表，这里早已播完。
        expect(c.isShowingAd, isTrue);
      });
    });
  });

  group('ad rate handling on the cutover path', () {
    test('ad starts at 1x and content resumes at the user rate (cutover-aware)', () {
      fakeAsync((async) {
        final api = FakeMovaApi(
          options: const MovaOpts(
            ads: MovaAdConfig(enabled: true, breaks: [_mid], waitForAdReady: MovaAdWaitByKind(mid: false)),
          ),
        );
        final cutover = FakeCutoverCtl()..commitResult = true;
        final c = MovaAds(api, cutover: cutover);
        c.load(_content);
        _flush(async);
        api.push(api.state.copyWith(rate: 2.0));
        api.pushProgress(const MovaProg(position: Duration(seconds: 31)));
        _flush(async);
        expect(c.isShowingAd, isTrue);
        expect(api.lastRate, 1.0, reason: 'the ad must not play sped up');
        api.push(api.state.copyWith(rate: 1.0));
        api.pushEvent(const MovaDone());
        _flush(async);
        expect(c.isShowingAd, isFalse);
        expect(api.lastRate, 2.0, reason: 'content gets the user rate back');
      });
    });

    test('ad-engine progress during the return hand-off does not overwrite the saved content rate', () {
      fakeAsync((async) {
        final api = FakeMovaApi(
          options: const MovaOpts(
            ads: MovaAdConfig(enabled: true, breaks: [_mid], waitForAdReady: MovaAdWaitByKind(mid: false)),
          ),
        );
        final cutover = _GatedCommitCutover();
        final c = MovaAds(api, cutover: cutover);
        c.load(_content);
        _flush(async);
        api.push(api.state.copyWith(rate: 2.0));
        api.pushProgress(const MovaProg(position: Duration(seconds: 31)));
        _flush(async);
        expect(c.isShowingAd, isTrue);
        // 广告引擎 1x；广告结束，commit 卡住（影子未就绪）。
        api.push(api.state.copyWith(rate: 1.0));
        api.pushEvent(const MovaDone());
        _flush(async);
        expect(cutover.pending, isTrue);
        // 过渡期内活动引擎仍是广告，其 progress 不得覆盖已保存的 2x。
        api.pushProgress(const MovaProg(position: Duration(seconds: 4)));
        _flush(async);
        cutover.release(true);
        _flush(async);
        expect(c.isShowingAd, isFalse);
        expect(api.lastRate, 2.0, reason: 'content resumes at the user rate');
      });
    });

    test('rate changed after the last tick is snapshotted by playAdNow and restored after the ad', () {
      fakeAsync((async) {
        final api = FakeMovaApi(
          options: const MovaOpts(
            ads: MovaAdConfig(enabled: true, breaks: [_mid], waitForAdReady: MovaAdWaitByKind(mid: false)),
          ),
        );
        final cutover = FakeCutoverCtl()..commitResult = true;
        final c = MovaAds(api, cutover: cutover);
        c.load(_content);
        _flush(async);
        // 正片 2x，推一个 tick 让 _contentRate = 2.0。
        api.push(api.state.copyWith(rate: 2.0));
        api.pushProgress(const MovaProg(position: Duration(seconds: 10)));
        _flush(async);
        // 不再推 tick，直接改为 1.5x 后立刻插播。
        api.push(api.state.copyWith(rate: 1.5));
        c.playAdNow(
          const MovaAdBreak(kind: MovaAdBreakKind.mid, source: MovaSource('https://host/now.mp4')),
        );
        _flush(async);
        expect(c.isShowingAd, isTrue);
        expect(api.lastRate, 1.0, reason: 'the ad must not play sped up');
        api.push(api.state.copyWith(rate: 1.0));
        api.pushEvent(const MovaDone());
        _flush(async);
        expect(c.isShowingAd, isFalse);
        expect(api.lastRate, 1.5, reason: 'the rate set right before playAdNow survives');
      });
    });
  });
}

/// Cutover fake whose `commit` blocks until [release] is called.
///
/// `commit` 阻塞到调用 [release] 的 cutover 替身。
class _GatedCommitCutover extends FakeCutoverCtl {
  /// Completer of the in-flight commit, or null when none is pending.
  ///
  /// 在途 commit 的 completer；没有挂起的则为 null。
  Completer<bool>? _gate;

  /// Whether a commit is currently blocked.
  ///
  /// 当前是否有 commit 被阻塞。
  bool get pending => _gate != null;

  /// Completes the blocked commit with [result].
  ///
  /// 以 [result] 放行被阻塞的 commit。
  void release(bool result) {
    final g = _gate;
    _gate = null;
    g?.complete(result);
  }

  @override
  Future<bool> commit({bool waitForReady = false}) {
    calls.add('commit');
    lastWaitForReady = waitForReady;
    return (_gate = Completer<bool>()).future;
  }
}

/// A fail policy that records every failure it is shown and skips the break.
///
/// 记录所有被告知的失败并跳过广告位的失败策略。
class _RecordingFail implements MovaAdFailPolicy {
  /// Every failure passed to [onFailure], in order.
  ///
  /// 依次传给 [onFailure] 的所有失败记录。
  final List<MovaAdFail> seen = <MovaAdFail>[];

  @override
  MovaAdFailAction onFailure(MovaAdFail failure) {
    seen.add(failure);
    return MovaAdFailAction.skipBreak;
  }
}
