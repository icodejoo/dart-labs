import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mova/src/core/ad/ad_controller.dart';
import 'package:mova/src/core/events/events.dart';
import 'package:mova/src/core/model/ad.dart';
import 'package:mova/src/core/model/source.dart';
import 'package:mova/src/core/options/options.dart';
import 'package:mova/src/core/state/progress.dart';
import 'package:mova/src/core/swap/ctl.dart';
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

  group('MovaAdCtrl.loadDeferred — lazy content source resolution', () {
    const pre = MovaAdBreak(
      kind: MovaAdBreakKind.pre,
      source: MovaSource('https://host/pre.mp4'),
    );
    const mid = MovaAdBreak(
      kind: MovaAdBreakKind.mid,
      source: MovaSource('https://host/mid.mp4'),
      offset: Duration(seconds: 30),
    );
    const resolved = MovaSource('https://host/signed-content.m3u8');

    /// Builds an api + controller over [breaks], plus a counting resolver.
    ///
    /// 基于 [breaks] 构造 api + 控制器，外加一个计数型解析器。
    (FakeMovaApi, MovaAdCtrl, List<int>) deferredBuild(
      List<MovaAdBreak> breaks, {
      MovaSwapCtl? swap,
    }) {
      final api = FakeMovaApi(
        options: MovaOpts(ads: MovaAdConfig(enabled: true, breaks: breaks)),
      );
      return (api, MovaAdCtrl(api, swap: swap), <int>[]);
    }

    test('the resolver is NOT called while a pre-roll is playing', () async {
      final (api, c, calls) = deferredBuild([pre]);
      await c.loadDeferred(() async {
        calls.add(1);
        return resolved;
      });
      await settle();
      expect(c.isShowingAd, isTrue);
      expect(api.source?.uri, 'https://host/pre.mp4');
      expect(calls, isEmpty, reason: 'the content URL must stay unresolved until it is needed');
    });

    test('the resolver runs exactly once when the pre-roll finishes, and its source is opened', () async {
      final (api, c, calls) = deferredBuild([pre]);
      await c.loadDeferred(() async {
        calls.add(1);
        return resolved;
      });
      await settle();
      api.pushEvent(const MovaDone());
      await settle();
      expect(calls, hasLength(1));
      expect(api.source?.uri, resolved.uri);
    });

    test('with no pre-roll the resolver runs immediately and the content starts', () async {
      final (api, c, calls) = deferredBuild([]);
      await c.loadDeferred(() async {
        calls.add(1);
        return resolved;
      });
      await settle();
      expect(calls, hasLength(1));
      expect(api.source?.uri, resolved.uri);
      expect(c.isShowingAd, isFalse);
    });

    test('the resolved source is memoised across a mid-roll round trip', () async {
      final (api, c, calls) = deferredBuild([mid]);
      await c.loadDeferred(() async {
        calls.add(1);
        return resolved;
      });
      await settle();
      expect(calls, hasLength(1));
      api.pushProgress(const MovaProg(position: Duration(seconds: 31)));
      await settle();
      expect(c.isShowingAd, isTrue);
      api.pushEvent(const MovaDone());
      await settle();
      expect(calls, hasLength(1), reason: 'resolution is memoised, not repeated per ad');
      expect(api.source?.uri, resolved.uri);
    });

    test('the warm-up path prepares the resolved source, still resolving only once', () async {
      final swap = FakeSwapCtl();
      final (api, c, calls) = deferredBuild([pre], swap: swap);
      await c.loadDeferred(() async {
        calls.add(1);
        return resolved;
      });
      await settle();
      for (var i = 1; i <= 3; i++) {
        api.pushProgress(MovaProg(position: Duration(seconds: i)));
        await settle();
      }
      expect(swap.calls, contains('prepare'));
      expect(calls, hasLength(1), reason: 'every tick shares one in-flight resolution');
    });

    test('a throwing resolver reports on contentError and opens nothing', () async {
      final (api, c, _) = deferredBuild([]);
      final errors = <Object>[];
      final sub = c.contentError.listen(errors.add);
      final boom = StateError('no entitlement');
      await c.loadDeferred(() async => throw boom);
      await settle();
      expect(errors, [same(boom)]);
      expect(c.isShowingAd, isFalse);
      expect(api.calls, isNot(contains('open')));
      await sub.cancel();
    });

    test('after a failed resolution a second loadDeferred can retry', () async {
      final (api, c, _) = deferredBuild([]);
      await c.loadDeferred(() async => throw StateError('first'));
      await settle();
      expect(api.calls, isNot(contains('open')));
      await c.loadDeferred(() async => resolved);
      await settle();
      expect(api.source?.uri, resolved.uri);
    });

    test('the plain load(MovaSource) path is byte-for-byte unchanged', () async {
      final api = FakeMovaApi(
        options: MovaOpts(ads: MovaAdConfig(enabled: true, breaks: [pre])),
      );
      final c = MovaAdCtrl(api);
      await c.load(_content);
      await settle();
      expect(api.source?.uri, 'https://host/pre.mp4');
      api.pushEvent(const MovaDone());
      await settle();
      expect(api.calls.where((e) => e == 'open'), hasLength(2));
      expect(api.source?.uri, _content.uri);
    });
  });

  group('MovaAdBreak.duration — fixed-length slots driven by a plain Timer', () {
    /// Builds api + controller for [breaks] with an event sink, optionally
    /// counting the slot from `open()` instead of the first frame.
    ///
    /// 为 [breaks] 构造 api + 控制器与事件收集器，可选择从 `open()` 而非首帧起算。
    (FakeMovaApi, MovaAdCtrl, List<MovaAdEvent>) slotBuild(
      List<MovaAdBreak> breaks, {
      bool fromFirstFrame = true,
    }) {
      final events = <MovaAdEvent>[];
      final api = FakeMovaApi(
        options: MovaOpts(
          ads: MovaAdConfig(
            enabled: true,
            breaks: breaks,
            onAdEvent: events.add,
            durationFromFirstFrame: fromFirstFrame,
          ),
        ),
      );
      return (api, MovaAdCtrl(api), events);
    }

    /// Lets the controller's async chains settle inside a [fakeAsync] zone.
    ///
    /// 在 [fakeAsync] 区域内让控制器的异步链结算完毕。
    void flush(FakeAsync async) => async.elapse(const Duration(milliseconds: 1));

    const midPlain = MovaAdBreak(
      kind: MovaAdBreakKind.mid,
      source: MovaSource('https://host/mid.mp4'),
      offset: Duration(seconds: 30),
    );
    const mid15 = MovaAdBreak(
      kind: MovaAdBreakKind.mid,
      source: MovaSource('https://host/mid.mp4'),
      offset: Duration(seconds: 30),
      duration: Duration(seconds: 15),
    );

    test('a null duration leaves behaviour byte-for-byte unchanged (no timer)', () {
      fakeAsync((async) {
        final (api, c, _) = slotBuild([midPlain]);
        c.load(_content);
        flush(async);
        api.pushProgress(const MovaProg(position: Duration(seconds: 31)));
        flush(async);
        expect(c.isShowingAd, isTrue);
        api.pushProgress(const MovaProg(position: Duration(seconds: 1)));
        async.elapse(const Duration(minutes: 5));
        expect(c.isShowingAd, isTrue, reason: 'with no duration the ad still ends on MovaDone only');
        api.pushEvent(const MovaDone());
        flush(async);
        expect(c.isShowingAd, isFalse);
      });
    });

    test('a 15s slot resumes the content on expiry, without any MovaDone', () {
      fakeAsync((async) {
        final (api, c, _) = slotBuild([mid15]);
        c.load(_content);
        flush(async);
        api.pushProgress(const MovaProg(position: Duration(seconds: 31)));
        flush(async);
        api.pushProgress(const MovaProg(position: Duration(seconds: 1)));
        flush(async);
        expect(c.isShowingAd, isTrue);
        async.elapse(const Duration(seconds: 15));
        flush(async);
        expect(c.isShowingAd, isFalse);
        expect(api.source?.uri, _content.uri);
      });
    });

    test('slot expiry reports completed, not skipped', () {
      fakeAsync((async) {
        final (api, c, events) = slotBuild([mid15]);
        c.load(_content);
        flush(async);
        api.pushProgress(const MovaProg(position: Duration(seconds: 31)));
        flush(async);
        api.pushProgress(const MovaProg(position: Duration(seconds: 1)));
        async.elapse(const Duration(seconds: 16));
        flush(async);
        expect(events.map((e) => e.type), contains(MovaAdEventType.completed));
        expect(events.map((e) => e.type), isNot(contains(MovaAdEventType.skipped)));
      });
    });

    test('slot expiry takes exactly the same resume path as skip(): back to the saved position', () {
      fakeAsync((async) {
        final (api, c, _) = slotBuild([mid15]);
        c.load(_content);
        flush(async);
        api.pushProgress(const MovaProg(position: Duration(seconds: 31)));
        flush(async);
        api.pushProgress(const MovaProg(position: Duration(seconds: 1)));
        async.elapse(const Duration(seconds: 16));
        flush(async);
        expect(api.lastSeek, const Duration(seconds: 31));
      });
    });

    test('an early MovaDone resumes at once, and the later timer does not resume a second time', () {
      fakeAsync((async) {
        final (api, c, _) = slotBuild([mid15]);
        c.load(_content);
        flush(async);
        api.pushProgress(const MovaProg(position: Duration(seconds: 31)));
        flush(async);
        api.pushProgress(const MovaProg(position: Duration(seconds: 1)));
        flush(async);
        api.calls.clear();
        api.pushEvent(const MovaDone());
        flush(async);
        expect(api.calls.where((e) => e == 'open'), hasLength(1));
        async.elapse(const Duration(seconds: 30));
        flush(async);
        expect(api.calls.where((e) => e == 'open'), hasLength(1),
            reason: 'the cancelled slot timer must not resume a second time');
      });
    });

    test('an early skip() resumes at once, and the later timer does not resume a second time', () {
      fakeAsync((async) {
        const skippable = MovaAdBreak(
          kind: MovaAdBreakKind.mid,
          source: MovaSource('https://host/mid.mp4'),
          offset: Duration(seconds: 30),
          duration: Duration(seconds: 15),
          skippableAfter: Duration(seconds: 5),
        );
        final (api, c, _) = slotBuild([skippable]);
        c.load(_content);
        flush(async);
        api.pushProgress(const MovaProg(position: Duration(seconds: 31)));
        flush(async);
        api.pushProgress(const MovaProg(position: Duration(seconds: 6)));
        flush(async);
        api.calls.clear();
        c.skip();
        flush(async);
        expect(api.calls.where((e) => e == 'open'), hasLength(1));
        async.elapse(const Duration(seconds: 30));
        flush(async);
        expect(api.calls.where((e) => e == 'open'), hasLength(1));
      });
    });

    test('durationFromFirstFrame true: the clock starts at the first tick, not at open()', () {
      fakeAsync((async) {
        final (api, c, _) = slotBuild([mid15]);
        c.load(_content);
        flush(async);
        api.pushProgress(const MovaProg(position: Duration(seconds: 31)));
        flush(async);
        // No ad-side progress yet: a slow load must not eat into the slot.
        async.elapse(const Duration(seconds: 20));
        flush(async);
        expect(c.isShowingAd, isTrue, reason: 'the slot has not started counting yet');
        api.pushProgress(const MovaProg(position: Duration(seconds: 1)));
        flush(async);
        async.elapse(const Duration(seconds: 15));
        flush(async);
        expect(c.isShowingAd, isFalse);
      });
    });

    test('durationFromFirstFrame false: the clock starts at open(), with no tick at all', () {
      fakeAsync((async) {
        final (api, c, _) = slotBuild([mid15], fromFirstFrame: false);
        c.load(_content);
        flush(async);
        api.pushProgress(const MovaProg(position: Duration(seconds: 31)));
        flush(async);
        expect(c.isShowingAd, isTrue);
        async.elapse(const Duration(seconds: 15));
        flush(async);
        expect(c.isShowingAd, isFalse);
        expect(api.source?.uri, _content.uri);
      });
    });

    test('inside a pod each break counts its own duration independently', () {
      fakeAsync((async) {
        const pre1 = MovaAdBreak(
          kind: MovaAdBreakKind.pre,
          source: MovaSource('https://host/pre1.mp4'),
          duration: Duration(seconds: 5),
        );
        const pre2 = MovaAdBreak(
          kind: MovaAdBreakKind.pre,
          source: MovaSource('https://host/pre2.mp4'),
          duration: Duration(seconds: 5),
        );
        final (api, c, _) = slotBuild([pre1, pre2]);
        c.load(_content);
        flush(async);
        expect(api.source?.uri, 'https://host/pre1.mp4');

        api.pushProgress(const MovaProg(position: Duration(seconds: 1)));
        flush(async);
        async.elapse(const Duration(seconds: 4));
        expect(api.source?.uri, 'https://host/pre1.mp4', reason: 'only 4s of pre1 elapsed');
        async.elapse(const Duration(seconds: 1));
        flush(async);
        expect(api.source?.uri, 'https://host/pre2.mp4');

        api.pushProgress(const MovaProg(position: Duration(seconds: 1)));
        flush(async);
        async.elapse(const Duration(seconds: 4));
        expect(api.source?.uri, 'https://host/pre2.mp4', reason: 'pre2 gets its own full 5s');
        async.elapse(const Duration(seconds: 1));
        flush(async);
        expect(api.source?.uri, _content.uri);
      });
    });
  });
}
