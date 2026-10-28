import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mova/src/core/engine.dart';
import 'package:mova/src/core/events/events.dart';
import 'package:mova/src/core/model/quality.dart';
import 'package:mova/src/core/model/source.dart';

import '../support/fake_kernel.dart';

/// The VOD master playlist every case opens.
///
/// 各用例打开的点播 master 地址。
const _master = MovaSource('https://host/master.m3u8');

/// Where playback was when the variant is switched.
///
/// 切档时的播放位置。
const _resumeAt = Duration(seconds: 42);

/// Total duration the fake media reports.
///
/// 假媒体报告的总时长。
const _total = Duration(minutes: 5);

/// Resume-verify interval the cases shrink to keep the fake clock short.
///
/// 用例里缩短的续播校验间隔，让假时钟更短。
const _verify = Duration(milliseconds: 60);

/// Where a parked user seek aims.
///
/// 被寄存的用户 seek 的目标。
const _userSeek = Duration(seconds: 30);

const _high = MovaQuality(label: '1080p', uri: 'https://host/1080.m3u8', height: 1080);
const _low = MovaQuality(label: '480p', uri: 'https://host/480.m3u8', height: 480);

/// How many seeks the fake kernel has received so far.
///
/// 假内核目前收到的 seek 次数。
int _seeks(FakeKernel k) => k.calls.where((c) => c == 'seek').length;

/// An engine over a seek-echoing kernel, opened and watching [_resumeAt], with
/// the [_high]/[_low] ladder in place. Call inside `fakeAsync`.
///
/// 基于会自行回声 seek 的内核、已打开并播到 [_resumeAt]、档位表就位的引擎。
/// 在 `fakeAsync` 内调用。
MovaEngine _ready(FakeAsync async, FakeKernel k) {
  k.echoSeeks = true;
  final e = MovaEngine(kernel: k);
  e.open(_master);
  async.flushMicrotasks();
  k.emitDuration(_total);
  k.emitPosition(_resumeAt);
  async.flushMicrotasks();
  e.debugSetQualities(const [_high, _low], current: _high);
  e.debugResumeVerifyDelay = _verify;
  return e;
}

/// Switches to [_low] and lands the new variant through the buffering edge.
///
/// 切到 [_low] 并经 buffering 边沿让新档位落地。
void _switchAndLand(FakeAsync async, MovaEngine e, FakeKernel k) {
  e.switchQuality(_low);
  async.flushMicrotasks();
  k.emitDuration(_total);
  k.emitBuffering(true);
  k.emitBuffering(false);
  async.flushMicrotasks();
}

/// Disposes [e] inside a fakeAsync zone and lets the teardown settle.
///
/// 在 fakeAsync 内销毁 [e] 并让收尾落定。
void _teardown(FakeAsync async, MovaEngine e) {
  unawaited(e.dispose());
  async.flushMicrotasks();
}

/// H18/H19: mpv can discard a seek even after the duration arrived or a RESTART
/// landed (real devices: RESTART=[23,23], the seek then echoes only ~23 ms).
/// `FakeKernel.echoSeeks` + `dropNextSeeks` reproduce that, so these cases check
/// the engine's re-send / verification chain converges under it.
///
/// H18/H19：即使时长已到、RESTART 已落地，mpv 仍可能丢弃 seek（真机上 RESTART=[23,23]，
/// seek 之后只回声约 23 ms）。`FakeKernel.echoSeeks` + `dropNextSeeks` 复现这一点，
/// 这些用例检查引擎的重发/校验链在此情形下能收敛。
void main() {
  group('H19: the seek sent right after a variant lands is discarded', () {
    test('the verify chain re-sends once and the second, accepted seek settles', () {
      fakeAsync((async) {
        final k = FakeKernel();
        final e = _ready(async, k);
        k.dropNextSeeks = 1;
        k.calls.clear();
        _switchAndLand(async, e, k);
        expect(_seeks(k), 1);
        expect(k.droppedSeeks, [_resumeAt]);

        async.elapse(_verify + const Duration(milliseconds: 10));
        async.flushMicrotasks();
        expect(_seeks(k), 2);
        expect(k.honoredSeeks, [_resumeAt]);

        // Settled: no further attempts however long we wait.
        // 已落定：再等多久也不会再发。
        async.elapse(const Duration(seconds: 5));
        expect(_seeks(k), 2);
        _teardown(async, e);
      });
    });

    test('the stale echo of the discarded seek never reaches the progress stream', () {
      fakeAsync((async) {
        final k = FakeKernel();
        final e = _ready(async, k);
        final seen = <Duration>[];
        e.progress.listen((p) => seen.add(p.position));
        k.dropNextSeeks = 1;
        _switchAndLand(async, e, k);
        async.elapse(const Duration(seconds: 1));
        async.flushMicrotasks();
        expect(seen, isNot(contains(k.staleEcho)));
        expect(seen.last, _resumeAt);
        _teardown(async, e);
      });
    });

    test('two discarded seeks in a row still converge on the third', () {
      fakeAsync((async) {
        final k = FakeKernel();
        final e = _ready(async, k);
        k.dropNextSeeks = 2;
        k.calls.clear();
        _switchAndLand(async, e, k);
        async.elapse(_verify * 3);
        async.flushMicrotasks();
        expect(k.droppedSeeks, hasLength(2));
        expect(k.honoredSeeks, [_resumeAt]);
        expect(_seeks(k), 3);
        async.elapse(const Duration(seconds: 5));
        expect(_seeks(k), 3);
        _teardown(async, e);
      });
    });

    test('a kernel that discards every seek is retried a bounded number of times, not forever', () {
      fakeAsync((async) {
        final k = FakeKernel();
        final e = _ready(async, k);
        k.dropNextSeeks = 1000;
        k.calls.clear();
        _switchAndLand(async, e, k);
        async.elapse(const Duration(seconds: 30));
        async.flushMicrotasks();
        expect(_seeks(k), 3, reason: 'one first attempt plus two re-sends');
        expect(k.honoredSeeks, isEmpty);
        _teardown(async, e);
      });
    });

    test('an accepted first seek is never re-sent', () {
      fakeAsync((async) {
        final k = FakeKernel();
        final e = _ready(async, k);
        k.calls.clear();
        _switchAndLand(async, e, k);
        async.elapse(const Duration(seconds: 5));
        expect(_seeks(k), 1);
        expect(k.honoredSeeks, [_resumeAt]);
        _teardown(async, e);
      });
    });
  });

  group('H18: the seek replayed when the duration arrives is discarded', () {
    test('a parked user seek is re-sent by the verify chain and then settles', () {
      fakeAsync((async) {
        final k = FakeKernel()..echoSeeks = true;
        final e = MovaEngine(kernel: k)..debugResumeVerifyDelay = _verify;
        final events = <MovaEvent>[];
        e.events.listen(events.add);
        e.open(_master);
        async.flushMicrotasks();
        e.seek(_userSeek);
        async.flushMicrotasks();
        expect(_seeks(k), 0, reason: 'parked until the duration is known');

        k.dropNextSeeks = 1;
        k.emitDuration(_total);
        async.flushMicrotasks();
        expect(k.droppedSeeks, [_userSeek]);

        async.elapse(_verify + const Duration(milliseconds: 10));
        async.flushMicrotasks();
        expect(k.honoredSeeks, [_userSeek]);
        // The caller was told once; the internal re-send is not a second user seek.
        // 调用方只被告知一次；内部重发不算第二次用户 seek。
        expect(events.whereType<MovaSeeked>(), hasLength(1));
        async.elapse(const Duration(seconds: 5));
        expect(_seeks(k), 2);
        _teardown(async, e);
      });
    });
  });

  group('a user seek the kernel discards', () {
    /// Opens, learns the duration, then lets the kernel discard [drops] seeks
    /// to minute three; returns the engine with a listener on its progress.
    /// [delay] shrinks the verify interval (null keeps the production value).
    ///
    /// 打开、拿到时长，再让内核丢掉 [drops] 次指向第三分钟的 seek；返回挂了进度监听的
    /// 引擎。[delay] 缩短校验间隔（null 保持生产值）。
    MovaEngine discarded(
      FakeAsync async,
      FakeKernel k,
      List<Duration> seen, {
      int drops = 1,
      Duration? delay,
      bool playing = true,
    }) {
      final e = MovaEngine(kernel: k);
      if (delay != null) e.debugResumeVerifyDelay = delay;
      e.open(_master);
      async.flushMicrotasks();
      k.emitDuration(_total);
      k.emitPlaying(playing);
      async.flushMicrotasks();
      e.progress.listen((p) => seen.add(p.position));
      k.dropNextSeeks = drops;
      e.seek(const Duration(minutes: 3));
      async.flushMicrotasks();
      return e;
    }

    // H17: a discarded user seek used to leave _pendingSeekTarget armed for good,
    // so every later real position was swallowed as a "stale echo".
    // H17：用户 seek 被丢弃曾让 _pendingSeekTarget 一直布防，此后所有真实位置都被当"陈旧回声"吞掉。
    test('does not freeze the progress stream for good', () {
      fakeAsync((async) {
        final k = FakeKernel()..echoSeeks = true;
        final seen = <Duration>[];
        // Every attempt is discarded, so the chain gives up after three seeks.
        // 每次尝试都被丢弃，校验链发了三次 seek 后放弃。
        final e = discarded(async, k, seen, drops: 1000, delay: _verify);
        async.elapse(_verify * 4);
        async.flushMicrotasks();
        expect(_seeks(k), 3);
        // The kernel plays on from where it really is.
        // 内核从它真实所在的位置继续播。
        for (var s = 1; s <= 5; s++) {
          k.emitPosition(Duration(seconds: s));
          async.elapse(const Duration(milliseconds: 300));
        }
        expect(seen.last, const Duration(seconds: 5));
        _teardown(async, e);
      });
    });

    test('one discarded seek is re-sent once and the second, accepted seek settles', () {
      fakeAsync((async) {
        final k = FakeKernel()..echoSeeks = true;
        final seen = <Duration>[];
        final e = discarded(async, k, seen, delay: _verify);
        expect(k.droppedSeeks, [const Duration(minutes: 3)]);
        async.elapse(_verify + const Duration(milliseconds: 10));
        async.flushMicrotasks();
        expect(k.honoredSeeks, [const Duration(minutes: 3)]);
        expect(seen, isNot(contains(k.staleEcho)));
        expect(seen.last, const Duration(minutes: 3));
        // Settled: no further attempts, and real positions flow again.
        // 已落定：不再重发，真实位置重新流动。
        async.elapse(const Duration(seconds: 5));
        expect(_seeks(k), 2);
        k.emitPosition(const Duration(minutes: 3, seconds: 1));
        async.flushMicrotasks();
        expect(seen.last, const Duration(minutes: 3, seconds: 1));
        _teardown(async, e);
      });
    });

    test('a seek the kernel keeps discarding is retried three times in total, then given up', () {
      fakeAsync((async) {
        final k = FakeKernel()..echoSeeks = true;
        final seen = <Duration>[];
        final e = discarded(async, k, seen, drops: 1000, delay: _verify);
        async.elapse(const Duration(seconds: 30));
        async.flushMicrotasks();
        expect(_seeks(k), 3, reason: 'one first attempt plus two re-sends');
        expect(k.honoredSeeks, isEmpty);
        _teardown(async, e);
      });
    });

    test('a newer seek mid-chain voids the old chain and wins', () {
      fakeAsync((async) {
        final k = FakeKernel()..echoSeeks = true;
        final seen = <Duration>[];
        final e = discarded(async, k, seen, drops: 2, delay: _verify);
        // The first re-send (also discarded) goes out, then the user seeks again.
        // 第一次重发（同样被丢弃）发出后，用户又 seek 了一次。
        async.elapse(_verify + const Duration(milliseconds: 10));
        async.flushMicrotasks();
        expect(_seeks(k), 2);
        e.seek(const Duration(minutes: 1));
        async.flushMicrotasks();
        expect(k.honoredSeeks, [const Duration(minutes: 1)]);
        async.elapse(const Duration(seconds: 5));
        async.flushMicrotasks();
        // The old 3-minute chain never fires again.
        // 旧的三分钟校验链不再触发。
        expect(_seeks(k), 3);
        expect(k.lastSeek, const Duration(minutes: 1));
        expect(seen.last, const Duration(minutes: 1));
        _teardown(async, e);
      });
    });

    test('a newer seek before the first verify re-sends only the new target', () {
      fakeAsync((async) {
        final k = FakeKernel()..echoSeeks = true;
        final seen = <Duration>[];
        final e = discarded(async, k, seen, drops: 1, delay: _verify);
        e.seek(const Duration(minutes: 1));
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 5));
        async.flushMicrotasks();
        expect(k.droppedSeeks, [const Duration(minutes: 3)]);
        expect(k.honoredSeeks, [const Duration(minutes: 1)]);
        expect(_seeks(k), 2);
        _teardown(async, e);
      });
    });

    test('also converges while paused', () {
      fakeAsync((async) {
        final k = FakeKernel()..echoSeeks = true;
        final seen = <Duration>[];
        final e = discarded(async, k, seen, playing: false, delay: _verify);
        expect(e.state.playing, isFalse);
        async.elapse(_verify + const Duration(milliseconds: 10));
        async.flushMicrotasks();
        expect(k.honoredSeeks, [const Duration(minutes: 3)]);
        expect(seen.last, const Duration(minutes: 3));
        _teardown(async, e);
      });
    });

    test('a paused seek that is always discarded gives up and follows the real position', () {
      fakeAsync((async) {
        final k = FakeKernel()..echoSeeks = true;
        final seen = <Duration>[];
        final e = discarded(async, k, seen, drops: 1000, playing: false, delay: _verify);
        async.elapse(_verify * 4);
        async.flushMicrotasks();
        expect(_seeks(k), 3);
        k.emitPosition(const Duration(seconds: 7));
        async.flushMicrotasks();
        expect(seen.last, const Duration(seconds: 7));
        _teardown(async, e);
      });
    });

    test('a live source never seeks, so no verify chain starts', () {
      fakeAsync((async) {
        final k = FakeKernel()..echoSeeks = true;
        final e = MovaEngine(kernel: k);
        e.open(const MovaSource('https://host/live.flv', type: MovaStreamType.live));
        async.flushMicrotasks();
        k.calls.clear();
        e.seek(const Duration(minutes: 3));
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 10));
        expect(_seeks(k), 0);
        _teardown(async, e);
      });
    });

    test('keeps the optimistic target on screen and hides the stale echo until the chain acts', () {
      fakeAsync((async) {
        final k = FakeKernel()..echoSeeks = true;
        final seen = <Duration>[];
        final e = discarded(async, k, seen);
        async.elapse(const Duration(seconds: 1));
        expect(seen.last, const Duration(minutes: 3));
        expect(seen, isNot(contains(k.staleEcho)));
        _teardown(async, e);
      });
    });
  });
}
