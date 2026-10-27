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
const _pre1 = MovaAdBreak(kind: MovaAdBreakKind.pre, source: MovaSource('https://host/pre1.mp4'));
const _pre2 = MovaAdBreak(
  kind: MovaAdBreakKind.pre,
  source: MovaSource('https://host/pre2.mp4'),
  duration: Duration(seconds: 5),
);
const _preOpen = MovaAdBreak(kind: MovaAdBreakKind.pre, source: MovaSource('https://host/pre3.mp4'));
const _loadTimeout = Duration(seconds: 8);

/// Lets the controller's async chains settle inside a [fakeAsync] zone.
///
/// 在 [fakeAsync] 区域内让控制器的异步链结算完毕。
void _flush(FakeAsync async) => async.elapse(const Duration(milliseconds: 1));

/// Fake whose `open()` suspends until [gate] completes.
///
/// `open()` 会挂起到 [gate] 完成的假 API。
class _GatedOpenApi extends FakeMovaApi {
  /// Creates the fake with [options].
  ///
  /// 以 [options] 创建。
  _GatedOpenApi({super.options});

  /// Completer that releases the suspended `open()`.
  ///
  /// 放行被挂起的 `open()` 的 completer。
  final Completer<void> gate = Completer<void>();

  /// What `state.rendered` becomes right after `open()` settles.
  ///
  /// `open()` 落定后 `state.rendered` 的取值。
  bool renderedAfterOpen = false;

  @override
  Future<bool> open(MovaSource source, {bool autoPlay = true}) async {
    final ok = await super.open(source, autoPlay: autoPlay);
    await gate.future;
    push(state.copyWith(rendered: renderedAfterOpen));
    return ok;
  }
}

/// Cutover double whose `cutoverTo` suspends until [gate] completes.
///
/// `cutoverTo` 会挂起到 [gate] 完成的切换替身。
class _GatedCutoverCtl extends FakeCutoverCtl {
  /// Completer that releases the suspended `cutoverTo`.
  ///
  /// 放行被挂起的 `cutoverTo` 的 completer。
  final Completer<void> gate = Completer<void>();

  /// Runs right after the gate opens, to model the ad engine taking over.
  ///
  /// 闸门放行后立即执行，用来模拟广告引擎接班。
  void Function()? onSettled;

  @override
  Future<bool> cutoverTo(MovaSource source, {Duration at = Duration.zero, double? rate}) async {
    calls.add('cutoverTo');
    await gate.future;
    onSettled?.call();
    return commitResult;
  }
}

/// Fail policy that records every failure and skips the break.
///
/// 记录所有失败并跳过广告位的失败策略。
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

/// Builds options with [breaks], first-frame slot clock and a fixed load deadline.
///
/// 构造带 [breaks]、首帧起表与固定加载期限的选项。
MovaOpts _opts(List<MovaAdBreak> breaks, _RecordingFail policy, {bool waitPre = false}) => MovaOpts(
      ads: MovaAdConfig(
        enabled: true,
        breaks: breaks,
        failPolicy: policy,
        loadTimeout: _loadTimeout,
        durationFromFirstFrame: true,
        waitForAdReady: MovaAdWaitByKind(pre: waitPre),
      ),
    );

void main() {
  group('stale first-frame signals while open()/cutoverTo() is in flight', () {
    test('cutover path: a stale rendered tick before cutoverTo settles does not leave the load timer orphaned', () {
      fakeAsync((async) {
        final policy = _RecordingFail();
        final api = FakeMovaApi(options: _opts([_pre1, _preOpen], policy, waitPre: true));
        final cutover = _GatedCutoverCtl()..commitResult = true;
        final c = MovaAds(api, cutover: cutover);
        c.load(_content);
        _flush(async);
        // pre1 went through prepare/commit; end it so pre2 chains via cutoverTo.
        api.push(api.state.copyWith(rendered: true));
        api.pushEvent(const MovaDone());
        _flush(async);
        expect(cutover.calls, contains('cutoverTo'));
        // Old engine still on screen: its rendered tick must be discarded.
        api.pushProgress(const MovaProg(position: Duration(seconds: 3)));
        _flush(async);
        cutover.onSettled = () => api.push(api.state.copyWith(rendered: false));
        cutover.gate.complete();
        _flush(async);
        // The ad's own first frame lands shortly after.
        async.elapse(const Duration(seconds: 1));
        api.pushEvent(const MovaFirstFrame(sinceOpen: Duration(milliseconds: 90), signal: MovaFirstFrameSignal.restart));
        _flush(async);
        async.elapse(_loadTimeout);
        _flush(async);
        expect(policy.seen, isEmpty, reason: 'a playing ad must not be failed by an orphaned load timer');
        expect(c.isShowingAd, isTrue, reason: 'the ad is still playing');
      });
    });

    test('open path: a stale rendered tick before open() settles does not orphan the load timer', () {
      fakeAsync((async) {
        final policy = _RecordingFail();
        final api = _GatedOpenApi(options: _opts([_preOpen], policy));
        final c = MovaAds(api);
        c.load(_content);
        _flush(async);
        // 内容引擎的残留：open 尚未落定，rendered 为 true 的 tick 先到。
        api.push(api.state.copyWith(rendered: true));
        api.pushProgress(const MovaProg(position: Duration(seconds: 3)));
        _flush(async);
        api.gate.complete();
        _flush(async);
        async.elapse(const Duration(seconds: 1));
        api.pushEvent(const MovaFirstFrame(sinceOpen: Duration(milliseconds: 90), signal: MovaFirstFrameSignal.restart));
        _flush(async);
        async.elapse(_loadTimeout);
        _flush(async);
        expect(policy.seen, isEmpty);
        expect(c.isShowingAd, isTrue);
      });
    });

    test('rendered already true when open() settles: first frame is taken directly, no load timer', () {
      fakeAsync((async) {
        final policy = _RecordingFail();
        final api = _GatedOpenApi(options: _opts([_pre2], policy))..renderedAfterOpen = true;
        final c = MovaAds(api);
        c.load(_content);
        _flush(async);
        api.gate.complete();
        _flush(async);
        // No progress tick, no FirstFrame event ever arrives.
        async.elapse(const Duration(seconds: 4));
        expect(c.isShowingAd, isTrue, reason: 'slot clock started from the direct first frame');
        async.elapse(const Duration(seconds: 2));
        _flush(async);
        expect(policy.seen, isEmpty);
        expect(c.isShowingAd, isFalse, reason: '5s slot delivered');
      });
    });
  });
}
