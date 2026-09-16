import 'package:flutter_test/flutter_test.dart';
import 'package:mova/src/core/ad/ad_controller.dart';
import 'package:mova/src/core/events/events.dart';
import 'package:mova/src/core/model/ad.dart';
import 'package:mova/src/core/model/source.dart';
import 'package:mova/src/core/options/options.dart';
import 'package:mova/src/core/state/progress.dart';
import '../support/fake_api.dart';

const _content = MovaSource('https://host/content.m3u8');

/// Yields a few microtasks so chained `open`/`seek` awaits inside the
/// controller settle before assertions.
///
/// 让出几个微任务，使控制器内部链式的 `open`/`seek` await 在断言前结算完毕。
Future<void> settle() async {
  for (var i = 0; i < 3; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  group('dueMidRoll', () {
    const mid = MovaAdBreak(
      kind: MovaAdBreakKind.mid,
      source: MovaSource('https://host/mid.mp4'),
      offset: Duration(seconds: 30),
    );
    const pre = MovaAdBreak(
      kind: MovaAdBreakKind.pre,
      source: MovaSource('https://host/pre.mp4'),
    );

    test('returns a mid-roll once its offset is reached', () {
      expect(dueMidRoll([mid], const Duration(seconds: 31), {}), same(mid));
    });

    test('returns null before the offset', () {
      expect(dueMidRoll([mid], const Duration(seconds: 10), {}), isNull);
    });

    test('skips already-played and non-mid breaks', () {
      expect(dueMidRoll([mid], const Duration(seconds: 31), {mid}), isNull);
      expect(dueMidRoll([pre], const Duration(seconds: 31), {}), isNull);
    });
  });

  /// Builds a fake API + controller with [breaks] and an event sink.
  ///
  /// 用 [breaks] 与一个事件收集器构造假 API + 控制器。
  (FakeMovaApi, MovaAdCtrl, List<MovaAdEvent>) build(
    List<MovaAdBreak> breaks, {
    bool enabled = true,
  }) {
    final events = <MovaAdEvent>[];
    final api = FakeMovaApi(
      options: MovaOpts(
        ads: MovaAdConfig(enabled: enabled, breaks: breaks, onAdEvent: events.add),
      ),
    );
    return (api, MovaAdCtrl(api), events);
  }

  test('disabled: load opens the content directly, no ad', () async {
    const pre = MovaAdBreak(
      kind: MovaAdBreakKind.pre,
      source: MovaSource('https://host/pre.mp4'),
    );
    final (api, c, events) = build([pre], enabled: false);
    await c.load(_content);
    await settle();
    expect(c.isShowingAd, isFalse);
    expect(api.source?.uri, _content.uri);
    expect(events, isEmpty);
  });

  test('pre-roll plays before the content, then content on completion', () async {
    const pre = MovaAdBreak(
      kind: MovaAdBreakKind.pre,
      source: MovaSource('https://host/pre.mp4'),
    );
    final (api, c, events) = build([pre]);
    await c.load(_content);
    await settle();
    expect(c.isShowingAd, isTrue);
    expect(api.source?.uri, 'https://host/pre.mp4');

    api.pushEvent(const MovaDone());
    await settle();
    expect(c.isShowingAd, isFalse);
    expect(api.source?.uri, _content.uri);
    expect(events.map((e) => e.type),
        containsAllInOrder([MovaAdEventType.started, MovaAdEventType.completed]));
  });

  test('mid-roll triggers at its offset and resumes content at the saved position',
      () async {
    const mid = MovaAdBreak(
      kind: MovaAdBreakKind.mid,
      source: MovaSource('https://host/mid.mp4'),
      offset: Duration(seconds: 30),
    );
    final (api, c, _) = build([mid]);
    await c.load(_content);
    await settle();
    expect(api.source?.uri, _content.uri); // no pre-roll

    api.pushProgress(const MovaProg(position: Duration(seconds: 31)));
    await settle();
    expect(c.isShowingAd, isTrue);
    expect(api.source?.uri, 'https://host/mid.mp4');

    api.pushEvent(const MovaDone());
    await settle();
    expect(c.isShowingAd, isFalse);
    expect(api.source?.uri, _content.uri);
    expect(api.lastSeek, const Duration(seconds: 31));
  });

  test('mid-roll does not re-trigger after it has played', () async {
    const mid = MovaAdBreak(
      kind: MovaAdBreakKind.mid,
      source: MovaSource('https://host/mid.mp4'),
      offset: Duration(seconds: 30),
    );
    final (api, c, _) = build([mid]);
    await c.load(_content);
    await settle();
    api.pushProgress(const MovaProg(position: Duration(seconds: 31)));
    await settle();
    api.pushEvent(const MovaDone()); // ad ends → content resumes
    await settle();
    api.calls.clear();
    api.pushProgress(const MovaProg(position: Duration(seconds: 40)));
    await settle();
    expect(c.isShowingAd, isFalse);
    expect(api.calls, isNot(contains('open')));
  });

  test('post-roll plays when content completes, then goes idle', () async {
    const post = MovaAdBreak(
      kind: MovaAdBreakKind.post,
      source: MovaSource('https://host/post.mp4'),
    );
    final (api, c, _) = build([post]);
    await c.load(_content);
    await settle();
    expect(api.source?.uri, _content.uri);

    api.pushEvent(const MovaDone()); // content ends → post-roll
    await settle();
    expect(c.isShowingAd, isTrue);
    expect(api.source?.uri, 'https://host/post.mp4');

    api.pushEvent(const MovaDone()); // post-roll ends → idle
    await settle();
    expect(c.isShowingAd, isFalse);
  });

  test('skip is a no-op before the threshold and skips after it', () async {
    const pre = MovaAdBreak(
      kind: MovaAdBreakKind.pre,
      source: MovaSource('https://host/pre.mp4'),
      skippableAfter: Duration(seconds: 5),
    );
    final (api, c, events) = build([pre]);
    await c.load(_content);
    await settle();

    c.skip(); // ad position still 0 → not skippable
    await settle();
    expect(c.isShowingAd, isTrue);

    api.pushProgress(const MovaProg(position: Duration(seconds: 6)));
    await settle();
    expect(c.canSkip, isTrue);
    c.skip();
    await settle();
    expect(c.isShowingAd, isFalse);
    expect(api.source?.uri, _content.uri);
    expect(events.map((e) => e.type), contains(MovaAdEventType.skipped));
  });

  test('notifyClicked reports a click for the current ad only', () async {
    const pre = MovaAdBreak(
      kind: MovaAdBreakKind.pre,
      source: MovaSource('https://host/pre.mp4'),
      clickThroughUrl: 'https://advertiser.example',
    );
    final (_, c, events) = build([pre]);
    await c.load(_content);
    await settle();
    c.notifyClicked();
    final clicked = events.where((e) => e.type == MovaAdEventType.clicked);
    expect(clicked, hasLength(1));
    expect(clicked.first.adBreak.clickThroughUrl, 'https://advertiser.example');
  });

  test('suppresses STT during an ad and restores it after', () async {
    const mid = MovaAdBreak(
      kind: MovaAdBreakKind.mid,
      source: MovaSource('https://host/mid.mp4'),
      offset: Duration(seconds: 30),
    );
    final (api, c, _) = build([mid]);
    await c.load(_content);
    await settle();
    await api.stt.start(); // host turns STT on for the content
    expect(api.stt.isRunning, isTrue);

    api.pushProgress(const MovaProg(position: Duration(seconds: 31)));
    await settle();
    expect(c.isShowingAd, isTrue);
    expect(api.stt.isRunning, isFalse); // suppressed during the ad

    api.pushEvent(const MovaDone());
    await settle();
    expect(c.isShowingAd, isFalse);
    expect(api.stt.isRunning, isTrue); // restored on resume
  });

  test('does not start STT after an ad if it was not running before', () async {
    const mid = MovaAdBreak(
      kind: MovaAdBreakKind.mid,
      source: MovaSource('https://host/mid.mp4'),
      offset: Duration(seconds: 30),
    );
    final (api, c, _) = build([mid]);
    await c.load(_content);
    await settle();
    api.pushProgress(const MovaProg(position: Duration(seconds: 31)));
    await settle();
    api.pushEvent(const MovaDone());
    await settle();
    expect(api.stt.isRunning, isFalse);
    expect(api.stt.calls, isNot(contains('start')));
  });

  test('playAdNow inserts an ad at the current position and resumes there',
      () async {
    final (api, c, events) = build(const []); // no pre-configured breaks
    await c.load(_content);
    await settle();
    api.pushProgress(const MovaProg(position: Duration(seconds: 50)));
    await settle();

    await c.playAdNow(const MovaAdBreak(
      kind: MovaAdBreakKind.mid,
      source: MovaSource('https://host/flash.mp4'),
    ));
    await settle();
    expect(c.isShowingAd, isTrue);
    expect(api.source?.uri, 'https://host/flash.mp4');

    api.pushEvent(const MovaDone());
    await settle();
    expect(c.isShowingAd, isFalse);
    expect(api.source?.uri, _content.uri);
    expect(api.lastSeek, const Duration(seconds: 50));
    expect(events.map((e) => e.type),
        containsAllInOrder([MovaAdEventType.started, MovaAdEventType.completed]));
  });

  test('playAdNow is a no-op when no content is playing', () async {
    final (api, c, _) = build(const []);
    await c.playAdNow(const MovaAdBreak(
      kind: MovaAdBreakKind.mid,
      source: MovaSource('https://host/flash.mp4'),
    ));
    await settle();
    expect(c.isShowingAd, isFalse);
    expect(api.calls, isEmpty);
  });

  test('multiple mid-rolls at arbitrary offsets each play once, in order', () async {
    const mid1 = MovaAdBreak(
      kind: MovaAdBreakKind.mid,
      source: MovaSource('https://host/mid1.mp4'),
      offset: Duration(seconds: 30),
    );
    const mid2 = MovaAdBreak(
      kind: MovaAdBreakKind.mid,
      source: MovaSource('https://host/mid2.mp4'),
      offset: Duration(seconds: 60),
    );
    final (api, c, _) = build([mid1, mid2]);
    await c.load(_content);
    await settle();

    api.pushProgress(const MovaProg(position: Duration(seconds: 31)));
    await settle();
    expect(api.source?.uri, 'https://host/mid1.mp4');
    api.pushEvent(const MovaDone());
    await settle();
    expect(api.source?.uri, _content.uri); // resumed content

    api.pushProgress(const MovaProg(position: Duration(seconds: 61)));
    await settle();
    expect(api.source?.uri, 'https://host/mid2.mp4');
    api.pushEvent(const MovaDone());
    await settle();
    expect(api.source?.uri, _content.uri);
  });

  test('an ad pod plays every pre-roll in order before the content', () async {
    const pre1 = MovaAdBreak(
      kind: MovaAdBreakKind.pre,
      source: MovaSource('https://host/pre1.mp4'),
    );
    const pre2 = MovaAdBreak(
      kind: MovaAdBreakKind.pre,
      source: MovaSource('https://host/pre2.mp4'),
    );
    final (api, c, _) = build([pre1, pre2]);
    await c.load(_content);
    await settle();
    expect(api.source?.uri, 'https://host/pre1.mp4');

    api.pushEvent(const MovaDone());
    await settle();
    expect(api.source?.uri, 'https://host/pre2.mp4'); // pod continues

    api.pushEvent(const MovaDone());
    await settle();
    expect(api.source?.uri, _content.uri); // then the content
  });

  test('contentEnded fires after content completes with no post-roll', () async {
    final (api, c, _) = build(const []);
    final ended = <void>[];
    final sub = c.contentEnded.listen(ended.add);
    await c.load(_content);
    await settle();
    api.pushEvent(const MovaDone());
    await settle();
    expect(ended, hasLength(1));
    await sub.cancel();
  });

  test('contentEnded fires only after the post-roll pod finishes', () async {
    const post1 = MovaAdBreak(
      kind: MovaAdBreakKind.post,
      source: MovaSource('https://host/post1.mp4'),
    );
    const post2 = MovaAdBreak(
      kind: MovaAdBreakKind.post,
      source: MovaSource('https://host/post2.mp4'),
    );
    final (api, c, _) = build([post1, post2]);
    final ended = <void>[];
    final sub = c.contentEnded.listen(ended.add);
    await c.load(_content);
    await settle();

    api.pushEvent(const MovaDone()); // content → post1
    await settle();
    expect(api.source?.uri, 'https://host/post1.mp4');
    expect(ended, isEmpty);

    api.pushEvent(const MovaDone()); // post1 → post2
    await settle();
    expect(api.source?.uri, 'https://host/post2.mp4');
    expect(ended, isEmpty);

    api.pushEvent(const MovaDone()); // post2 → idle, content truly ended
    await settle();
    expect(c.isShowingAd, isFalse);
    expect(ended, hasLength(1));
    await sub.cancel();
  });

  test('dispose stops reacting to completion events', () async {
    const post = MovaAdBreak(
      kind: MovaAdBreakKind.post,
      source: MovaSource('https://host/post.mp4'),
    );
    final (api, c, _) = build([post]);
    await c.load(_content);
    await settle();
    await c.dispose();
    api.calls.clear();
    api.pushEvent(const MovaDone());
    await settle();
    expect(c.isShowingAd, isFalse);
    expect(api.calls, isEmpty);
  });

  group('MovaAdCtrl with a MovaSwapCtl (seamless ad→content swap)', () {
    const pre = MovaAdBreak(
      kind: MovaAdBreakKind.pre,
      source: MovaSource('https://host/pre.mp4'),
    );
    const mid = MovaAdBreak(
      kind: MovaAdBreakKind.mid,
      source: MovaSource('https://host/mid.mp4'),
      offset: Duration(seconds: 30),
    );

    test('not passing swap: behaviour is byte-for-byte unchanged (pre-roll uses open)', () async {
      final (api, c, _) = build([pre]);
      await c.load(_content);
      await settle();
      expect(api.source?.uri, 'https://host/pre.mp4');
      api.pushEvent(const MovaDone());
      await settle();
      expect(api.calls, contains('open'));
      expect(api.source?.uri, _content.uri);
    });

    test('not passing swap: mid-roll still uses open+seek to resume content', () async {
      final (api, c, _) = build([mid]);
      await c.load(_content);
      await settle();
      api.pushProgress(const MovaProg(position: Duration(seconds: 31)));
      await settle();
      api.pushEvent(const MovaDone());
      await settle();
      expect(c.isShowingAd, isFalse);
      expect(api.calls, contains('open'));
      expect(api.lastSeek, const Duration(seconds: 31));
    });

    test('swapEnabled false on the swap ctl: prepare is never called, _playContent still opens', () async {
      final events = <MovaAdEvent>[];
      final api = FakeMovaApi(
        options: MovaOpts(ads: MovaAdConfig(enabled: true, breaks: [pre], onAdEvent: events.add)),
      );
      final swap = FakeSwapCtl()..swapEnabled = false;
      final c = MovaAdCtrl(api, swap: swap);
      await c.load(_content);
      await settle();
      api.pushEvent(const MovaDone());
      await settle();
      expect(swap.calls, isNot(contains('prepare')));
      expect(api.calls, contains('open'));
    });

    test('every progress tick during the ad calls prepare with a shrinking remaining and fixed total', () async {
      final api = FakeMovaApi(options: MovaOpts(ads: MovaAdConfig(enabled: true, breaks: [pre])));
      final swap = FakeSwapCtl();
      final c = MovaAdCtrl(api, swap: swap);
      await c.load(_content);
      await settle();
      api.push(api.state.copyWith(duration: const Duration(seconds: 10)));

      api.pushProgress(const MovaProg(position: Duration(seconds: 3)));
      await settle();
      expect(swap.lastCue!.remaining, const Duration(seconds: 7));
      expect(swap.lastCue!.total, const Duration(seconds: 10));

      api.pushProgress(const MovaProg(position: Duration(seconds: 8)));
      await settle();
      expect(swap.lastCue!.remaining, const Duration(seconds: 2));
      expect(swap.lastCue!.total, const Duration(seconds: 10));
    });

    test('prepare is called with the saved content-resume position (zero for a pre-roll)', () async {
      final api = FakeMovaApi(options: MovaOpts(ads: MovaAdConfig(enabled: true, breaks: [pre])));
      final swap = FakeSwapCtl();
      final c = MovaAdCtrl(api, swap: swap);
      await c.load(_content);
      await settle();
      api.pushProgress(const MovaProg(position: Duration(seconds: 1)));
      await settle();
      expect(swap.lastPrepareAt, Duration.zero);
    });

    test('prepare uses the mid-roll saved resume position, not zero', () async {
      final api = FakeMovaApi(options: MovaOpts(ads: MovaAdConfig(enabled: true, breaks: [mid])));
      final swap = FakeSwapCtl();
      final c = MovaAdCtrl(api, swap: swap);
      await c.load(_content);
      await settle();
      api.pushProgress(const MovaProg(position: Duration(seconds: 31)));
      await settle();
      swap.calls.clear();
      api.pushProgress(const MovaProg(position: Duration(seconds: 1)));
      await settle();
      expect(swap.lastPrepareAt, const Duration(seconds: 31));
    });

    test('commit() returning true: no open/seek happens on the api', () async {
      final api = FakeMovaApi(options: MovaOpts(ads: MovaAdConfig(enabled: true, breaks: [pre])));
      final swap = FakeSwapCtl()..commitResult = true;
      final c = MovaAdCtrl(api, swap: swap);
      await c.load(_content);
      await settle();
      api.calls.clear();
      api.pushEvent(const MovaDone());
      await settle();
      expect(c.isShowingAd, isFalse);
      expect(api.calls, isNot(contains('open')));
      expect(api.calls, isNot(contains('seek')));
    });

    test('_playContent commits with waitForReady: true, not a bare commit()', () async {
      // Regression test for the bug where a bare commit() nearly always lost
      // the race against the readiness policy (the shadow is typically still
      // `warming`, not yet `ready`, at the exact instant the ad ends), so the
      // seamless path almost never actually engaged on real devices.
      //
      // 回归测试：裸 commit() 几乎总是输给就绪判据的时序竞争（广告结束的精确
      // 瞬间，影子引擎通常还是 `warming`、尚未 `ready`），导致无缝路径在真机上
      // 几乎从未真正生效。
      final api = FakeMovaApi(options: MovaOpts(ads: MovaAdConfig(enabled: true, breaks: [pre])));
      final swap = FakeSwapCtl()..commitResult = true;
      final c = MovaAdCtrl(api, swap: swap);
      await c.load(_content);
      await settle();
      api.pushEvent(const MovaDone());
      await settle();
      expect(swap.lastWaitForReady, isTrue);
    });

    test('commit() returning false: falls back to open (and seek for mid-roll)', () async {
      final api = FakeMovaApi(options: MovaOpts(ads: MovaAdConfig(enabled: true, breaks: [mid])));
      final swap = FakeSwapCtl()..commitResult = false;
      final c = MovaAdCtrl(api, swap: swap);
      await c.load(_content);
      await settle();
      api.pushProgress(const MovaProg(position: Duration(seconds: 31)));
      await settle();
      api.pushEvent(const MovaDone());
      await settle();
      expect(api.calls, contains('open'));
      expect(api.lastSeek, const Duration(seconds: 31));
    });

    test('STT restore still applies on the seamless path', () async {
      final api = FakeMovaApi(options: MovaOpts(ads: MovaAdConfig(enabled: true, breaks: [mid])));
      final swap = FakeSwapCtl()..commitResult = true;
      final c = MovaAdCtrl(api, swap: swap);
      await c.load(_content);
      await settle();
      await api.stt.start();
      api.pushProgress(const MovaProg(position: Duration(seconds: 31)));
      await settle();
      expect(api.stt.isRunning, isFalse);
      api.pushEvent(const MovaDone());
      await settle();
      expect(api.stt.isRunning, isTrue);
    });

    test('_playAd calls abandon (ad-pod scenario)', () async {
      const pre2 = MovaAdBreak(
        kind: MovaAdBreakKind.pre,
        source: MovaSource('https://host/pre2.mp4'),
      );
      final api = FakeMovaApi(options: MovaOpts(ads: MovaAdConfig(enabled: true, breaks: [pre, pre2])));
      final swap = FakeSwapCtl();
      final c = MovaAdCtrl(api, swap: swap);
      await c.load(_content);
      await settle();
      expect(swap.calls, contains('abandon'));
      swap.calls.clear();
      api.pushEvent(const MovaDone()); // pre -> pre2, another _playAd
      await settle();
      expect(swap.calls, contains('abandon'));
    });

    test('dispose calls abandon', () async {
      final api = FakeMovaApi(options: MovaOpts(ads: MovaAdConfig(enabled: true, breaks: [pre])));
      final swap = FakeSwapCtl();
      final c = MovaAdCtrl(api, swap: swap);
      await c.load(_content);
      await settle();
      await c.dispose();
      expect(swap.calls, contains('abandon'));
    });
  });
}
