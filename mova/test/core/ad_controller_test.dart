import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mova/src/core/ad/ad_controller.dart';
import 'package:mova/src/core/ad/fail.dart';
import 'package:mova/src/core/events/events.dart';
import 'package:mova/src/core/model/ad.dart';
import 'package:mova/src/core/model/source.dart';
import 'package:mova/src/core/options/options.dart';
import 'package:mova/src/core/state/progress.dart';
import 'package:mova/src/core/swap/ctl.dart';
import 'package:mova/src/core/swap/trigger.dart';
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
            // These tests deliberately let an ad sit without a first frame to
            // prove the slot clock has not started; the no-first-frame
            // deadline is a separate concern, exercised in its own group.
            //
            // 本组用例刻意让广告长时间没有首帧，以证明广告位时钟尚未起算；
            // "始终没有首帧"的判定期限是另一回事，由它自己那组用例覆盖。
            loadTimeout: const Duration(minutes: 10),
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

  group('_Phase.pending — the delay countdown, with the content playing on', () {
    /// Builds api + controller for [breaks], optionally with a swap ctl and a
    /// custom wait policy.
    ///
    /// 为 [breaks] 构造 api + 控制器，可选地带切换能力面与自定义等待策略。
    (FakeMovaApi, MovaAdCtrl, List<MovaAdEvent>) pendBuild(
      List<MovaAdBreak> breaks, {
      MovaSwapCtl? swap,
      MovaAdWaitPolicy? wait,
    }) {
      final events = <MovaAdEvent>[];
      final api = FakeMovaApi(
        options: MovaOpts(
          ads: MovaAdConfig(
            enabled: true,
            breaks: breaks,
            onAdEvent: events.add,
            waitForAdReady: wait ?? const MovaAdWaitByKind(),
          ),
        ),
      );
      return (api, MovaAdCtrl(api, swap: swap), events);
    }

    /// Lets the controller's async chains settle inside a [fakeAsync] zone.
    ///
    /// 在 [fakeAsync] 区域内让控制器的异步链结算完毕。
    void flush(FakeAsync async) => async.elapse(const Duration(milliseconds: 1));

    const midNoDelay = MovaAdBreak(
      kind: MovaAdBreakKind.mid,
      source: MovaSource('https://host/mid.mp4'),
      offset: Duration(seconds: 30),
    );
    const mid5 = MovaAdBreak(
      kind: MovaAdBreakKind.mid,
      source: MovaSource('https://host/mid.mp4'),
      offset: Duration(seconds: 30),
      delay: Duration(seconds: 5),
    );

    test('a zero delay with no swap engine keeps the mid-roll path byte-for-byte unchanged', () {
      fakeAsync((async) {
        final (api, c, events) = pendBuild([midNoDelay]);
        c.load(_content);
        flush(async);
        api.pushProgress(const MovaProg(position: Duration(seconds: 31)));
        flush(async);
        expect(c.isAdPending, isFalse);
        expect(c.isShowingAd, isTrue);
        expect(api.source?.uri, 'https://host/mid.mp4');
        expect(events.map((e) => e.type), isNot(contains(MovaAdEventType.pending)));
      });
    });

    test('a 5s delay enters pending: the content is not interrupted', () {
      fakeAsync((async) {
        final (api, c, _) = pendBuild([mid5]);
        c.load(_content);
        flush(async);
        api.pushProgress(const MovaProg(position: Duration(seconds: 31)));
        flush(async);
        expect(c.isAdPending, isTrue);
        expect(c.isShowingAd, isFalse);
        expect(c.pendingBreak, same(mid5));
        expect(api.source?.uri, _content.uri);
      });
    });

    test('entering pending fires a pending event but not started yet', () {
      fakeAsync((async) {
        final (api, c, events) = pendBuild([mid5]);
        c.load(_content);
        flush(async);
        api.pushProgress(const MovaProg(position: Duration(seconds: 31)));
        flush(async);
        expect(events.map((e) => e.type), contains(MovaAdEventType.pending));
        expect(events.map((e) => e.type), isNot(contains(MovaAdEventType.started)));
      });
    });

    test('entering pending emits once on changes', () {
      fakeAsync((async) {
        final (api, c, _) = pendBuild([mid5]);
        var changes = 0;
        final sub = c.changes.listen((_) => changes++);
        c.load(_content);
        flush(async);
        changes = 0;
        api.pushProgress(const MovaProg(position: Duration(seconds: 31)));
        flush(async);
        expect(changes, 1);
        sub.cancel();
      });
    });

    test('delayRemaining counts down with the content ticks and stays positive until expiry', () {
      fakeAsync((async) {
        final (api, c, _) = pendBuild([mid5]);
        c.load(_content);
        flush(async);
        api.pushProgress(const MovaProg(position: Duration(seconds: 31)));
        flush(async);
        expect(c.delayRemaining, const Duration(seconds: 5));
        api.pushProgress(const MovaProg(position: Duration(seconds: 33)));
        flush(async);
        expect(c.delayRemaining, const Duration(seconds: 3));
        expect(c.delayRemaining, greaterThan(Duration.zero));
      });
    });

    test('after the countdown the ad takes over and reports started', () {
      fakeAsync((async) {
        final (api, c, events) = pendBuild([mid5]);
        c.load(_content);
        flush(async);
        api.pushProgress(const MovaProg(position: Duration(seconds: 31)));
        flush(async);
        async.elapse(const Duration(seconds: 5));
        flush(async);
        expect(c.isShowingAd, isTrue);
        expect(c.isAdPending, isFalse);
        expect(api.source?.uri, 'https://host/mid.mp4');
        expect(events.map((e) => e.type), contains(MovaAdEventType.started));
      });
    });

    test('the content is never touched during the countdown', () {
      fakeAsync((async) {
        final (api, c, _) = pendBuild([mid5]);
        c.load(_content);
        flush(async);
        api.pushProgress(const MovaProg(position: Duration(seconds: 31)));
        flush(async);
        api.calls.clear();
        for (var s = 32; s <= 34; s++) {
          api.pushProgress(MovaProg(position: Duration(seconds: s)));
          flush(async);
        }
        expect(api.calls, isNot(contains('pause')));
        expect(api.calls, isNot(contains('open')));
        expect(api.calls, isNot(contains('seek')));
      });
    });

    test('the resume point is where the ad actually took over, not where the countdown began', () {
      fakeAsync((async) {
        final (api, c, _) = pendBuild([mid5]);
        c.load(_content);
        flush(async);
        api.pushProgress(const MovaProg(position: Duration(seconds: 30)));
        flush(async);
        api.pushProgress(const MovaProg(position: Duration(seconds: 35)));
        flush(async);
        async.elapse(const Duration(seconds: 5));
        flush(async);
        expect(c.isShowingAd, isTrue);
        api.pushEvent(const MovaDone());
        flush(async);
        expect(api.lastSeek, const Duration(seconds: 35));
      });
    });

    test('inside a mid-roll pod the countdown pops exactly once and the content never flashes back', () {
      fakeAsync((async) {
        const a = MovaAdBreak(
          kind: MovaAdBreakKind.mid,
          source: MovaSource('https://host/mid1.mp4'),
          offset: Duration(seconds: 30),
          delay: Duration(seconds: 3),
        );
        const b = MovaAdBreak(
          kind: MovaAdBreakKind.mid,
          source: MovaSource('https://host/mid2.mp4'),
          offset: Duration(seconds: 30),
          delay: Duration(seconds: 3),
        );
        final (api, c, events) = pendBuild([a, b]);
        c.load(_content);
        flush(async);
        api.pushProgress(const MovaProg(position: Duration(seconds: 31)));
        flush(async);
        async.elapse(const Duration(seconds: 3));
        flush(async);
        expect(api.source?.uri, 'https://host/mid1.mp4');
        api.pushEvent(const MovaDone());
        flush(async);
        expect(api.source?.uri, 'https://host/mid2.mp4',
            reason: 'the pod chains directly, with no content in between');
        expect(events.where((e) => e.type == MovaAdEventType.pending), hasLength(1));
        expect(c.isAdPending, isFalse);
      });
    });

    test('no second mid-roll may be triggered while one is pending', () {
      fakeAsync((async) {
        const later = MovaAdBreak(
          kind: MovaAdBreakKind.mid,
          source: MovaSource('https://host/later.mp4'),
          offset: Duration(seconds: 60),
        );
        final (api, c, _) = pendBuild([mid5, later]);
        c.load(_content);
        flush(async);
        api.pushProgress(const MovaProg(position: Duration(seconds: 31)));
        flush(async);
        api.pushProgress(const MovaProg(position: Duration(seconds: 61)));
        flush(async);
        expect(c.pendingBreak, same(mid5));
        expect(api.source?.uri, _content.uri);
      });
    });

    test('playAdNow with a delay goes through pending and resumes at the takeover point', () {
      fakeAsync((async) {
        final (api, c, _) = pendBuild([]);
        c.load(_content);
        flush(async);
        api.pushProgress(const MovaProg(position: Duration(seconds: 10)));
        flush(async);
        const runtime = MovaAdBreak(
          kind: MovaAdBreakKind.mid,
          source: MovaSource('https://host/flash.mp4'),
          delay: Duration(seconds: 4),
        );
        c.playAdNow(runtime);
        flush(async);
        expect(c.isAdPending, isTrue);
        api.pushProgress(const MovaProg(position: Duration(seconds: 12)));
        flush(async);
        async.elapse(const Duration(seconds: 4));
        flush(async);
        expect(c.isShowingAd, isTrue);
        api.pushEvent(const MovaDone());
        flush(async);
        expect(api.lastSeek, const Duration(seconds: 12));
      });
    });

    test('playAdNow is a no-op while an ad is already pending', () {
      fakeAsync((async) {
        final (api, c, _) = pendBuild([mid5]);
        c.load(_content);
        flush(async);
        api.pushProgress(const MovaProg(position: Duration(seconds: 31)));
        flush(async);
        expect(c.isAdPending, isTrue);
        c.playAdNow(const MovaAdBreak(
          kind: MovaAdBreakKind.mid,
          source: MovaSource('https://host/other.mp4'),
        ));
        flush(async);
        expect(c.pendingBreak, same(mid5));
        expect(api.source?.uri, _content.uri);
      });
    });

    test('the content ending during pending drops the queued break and runs the post-roll path', () {
      fakeAsync((async) {
        const post = MovaAdBreak(
          kind: MovaAdBreakKind.post,
          source: MovaSource('https://host/post.mp4'),
        );
        final (api, c, _) = pendBuild([mid5, post]);
        c.load(_content);
        flush(async);
        api.pushProgress(const MovaProg(position: Duration(seconds: 31)));
        flush(async);
        expect(c.isAdPending, isTrue);
        api.pushEvent(const MovaDone());
        flush(async);
        expect(c.isAdPending, isFalse);
        expect(api.source?.uri, 'https://host/post.mp4');
        async.elapse(const Duration(seconds: 10));
        flush(async);
        expect(api.source?.uri, 'https://host/post.mp4',
            reason: 'the cancelled delay timer must not fire the dropped mid-roll');
      });
    });

    test('skip() is a no-op during pending', () {
      fakeAsync((async) {
        final (api, c, _) = pendBuild([mid5]);
        c.load(_content);
        flush(async);
        api.pushProgress(const MovaProg(position: Duration(seconds: 31)));
        flush(async);
        api.calls.clear();
        c.skip();
        flush(async);
        expect(c.isAdPending, isTrue);
        expect(api.calls, isEmpty);
      });
    });

    test('a zero delay still goes through pending when the break waits for readiness', () {
      fakeAsync((async) {
        final swap = FakeSwapCtl();
        final (api, c, events) = pendBuild([midNoDelay], swap: swap);
        c.load(_content);
        flush(async);
        api.pushProgress(const MovaProg(position: Duration(seconds: 31)));
        flush(async);
        // The pending phase is entered (mid-rolls wait by default) but, with no
        // countdown to run, it is left again in the same turn — the readiness
        // wait itself lives inside _beginAd.
        //
        // 待播阶段被进入（中插默认等待），但没有倒计时可走，因此同一轮内即离开——
        // 就绪等待本身发生在 _beginAd 内部。
        expect(events.map((e) => e.type), contains(MovaAdEventType.pending));
        expect(events.map((e) => e.type), contains(MovaAdEventType.started));
        expect(c.delayRemaining, isNull, reason: 'a silent wait renders no countdown');
      });
    });

    test('a zero delay with waiting turned off never enters pending', () {
      fakeAsync((async) {
        final swap = FakeSwapCtl();
        final (api, c, _) = pendBuild(
          [midNoDelay],
          swap: swap,
          wait: const MovaAdWaitByKind(mid: false),
        );
        c.load(_content);
        flush(async);
        api.pushProgress(const MovaProg(position: Duration(seconds: 31)));
        flush(async);
        expect(c.isAdPending, isFalse);
        expect(c.isShowingAd, isTrue);
        expect(api.source?.uri, 'https://host/mid.mp4');
      });
    });
  });

  group('waiting for ad readiness — per-kind defaults and atomic cut-in', () {
    /// Builds api + controller with an optional swap ctl, wait policy and
    /// not-ready action.
    ///
    /// 构造 api + 控制器，可选地带切换能力面、等待策略与等不到时的动作。
    (FakeMovaApi, MovaAdCtrl, List<MovaAdEvent>) waitBuild(
      List<MovaAdBreak> breaks, {
      MovaSwapCtl? swap,
      MovaAdWaitPolicy? wait,
      MovaAdNotReady notReady = MovaAdNotReady.hardCut,
    }) {
      final events = <MovaAdEvent>[];
      final api = FakeMovaApi(
        options: MovaOpts(
          ads: MovaAdConfig(
            enabled: true,
            breaks: breaks,
            onAdEvent: events.add,
            waitForAdReady: wait ?? const MovaAdWaitByKind(),
            notReadyAction: notReady,
          ),
        ),
      );
      return (api, MovaAdCtrl(api, swap: swap), events);
    }

    /// Lets the controller's async chains settle inside a [fakeAsync] zone.
    ///
    /// 在 [fakeAsync] 区域内让控制器的异步链结算完毕。
    void flush(FakeAsync async) => async.elapse(const Duration(milliseconds: 1));

    const pre = MovaAdBreak(
      kind: MovaAdBreakKind.pre,
      source: MovaSource('https://host/pre.mp4'),
    );
    const post = MovaAdBreak(
      kind: MovaAdBreakKind.post,
      source: MovaSource('https://host/post.mp4'),
    );
    const mid = MovaAdBreak(
      kind: MovaAdBreakKind.mid,
      source: MovaSource('https://host/mid.mp4'),
      offset: Duration(seconds: 30),
    );

    test('with no swap ctl nothing is ever prepared or swapped; everything opens', () {
      fakeAsync((async) {
        final (api, c, _) = waitBuild([mid]);
        c.load(_content);
        flush(async);
        api.pushProgress(const MovaProg(position: Duration(seconds: 31)));
        flush(async);
        expect(c.isShowingAd, isTrue);
        expect(api.calls.where((e) => e == 'open'), hasLength(2));
      });
    });

    test('a disabled swap ctl behaves the same, even though waitsFor says yes', () {
      fakeAsync((async) {
        final swap = FakeSwapCtl()..swapEnabled = false;
        final (api, c, _) = waitBuild([mid], swap: swap);
        c.load(_content);
        flush(async);
        api.pushProgress(const MovaProg(position: Duration(seconds: 31)));
        flush(async);
        expect(swap.calls, isNot(contains('prepare')));
        expect(swap.calls, isNot(contains('swapTo')));
        expect(c.isShowingAd, isTrue);
      });
    });

    test('a mid-roll waits by default: it prepares, and the content is not interrupted', () {
      fakeAsync((async) {
        final swap = FakeSwapCtl();
        const delayed = MovaAdBreak(
          kind: MovaAdBreakKind.mid,
          source: MovaSource('https://host/mid.mp4'),
          offset: Duration(seconds: 30),
          delay: Duration(seconds: 3),
        );
        final (api, c, _) = waitBuild([delayed], swap: swap);
        c.load(_content);
        flush(async);
        api.pushProgress(const MovaProg(position: Duration(seconds: 31)));
        flush(async);
        expect(c.isAdPending, isTrue);
        api.pushProgress(const MovaProg(position: Duration(seconds: 32)));
        flush(async);
        expect(swap.calls, contains('prepare'));
        expect(api.source?.uri, _content.uri);
      });
    });

    test('a pre-roll does NOT wait by default: no prepare, no swapTo', () {
      fakeAsync((async) {
        final swap = FakeSwapCtl();
        final (api, c, _) = waitBuild([pre], swap: swap);
        c.load(_content);
        flush(async);
        expect(swap.calls, isNot(contains('prepare')));
        expect(swap.calls, isNot(contains('swapTo')));
        expect(api.source?.uri, 'https://host/pre.mp4');
      });
    });

    test('a post-roll does NOT wait by default either', () {
      fakeAsync((async) {
        final swap = FakeSwapCtl();
        final (api, c, _) = waitBuild([post], swap: swap);
        c.load(_content);
        flush(async);
        swap.calls.clear();
        api.pushEvent(const MovaDone());
        flush(async);
        expect(swap.calls, isNot(contains('swapTo')));
        expect(api.source?.uri, 'https://host/post.mp4');
      });
    });

    test('MovaAdWaitByKind(mid: false) puts mid-rolls back on the hard-cut path', () {
      fakeAsync((async) {
        final swap = FakeSwapCtl();
        final (api, c, _) = waitBuild([mid], swap: swap, wait: const MovaAdWaitByKind(mid: false));
        c.load(_content);
        flush(async);
        api.pushProgress(const MovaProg(position: Duration(seconds: 31)));
        flush(async);
        expect(swap.calls, isNot(contains('prepare')));
        expect(c.isShowingAd, isTrue);
      });
    });

    test('MovaAdWaitByKind(pre: true) routes the pre-roll through swapTo, not open', () {
      fakeAsync((async) {
        final swap = FakeSwapCtl()..commitResult = true;
        final (api, c, _) = waitBuild([pre], swap: swap, wait: const MovaAdWaitByKind(pre: true));
        c.load(_content);
        flush(async);
        expect(swap.calls, contains('swapTo'));
        expect(api.calls, isNot(contains('open')));
        expect(c.isShowingAd, isTrue);
      });
    });

    test('MovaAdBreak.waitForReady false overrides the mid default of true', () {
      fakeAsync((async) {
        final swap = FakeSwapCtl();
        const forced = MovaAdBreak(
          kind: MovaAdBreakKind.mid,
          source: MovaSource('https://host/mid.mp4'),
          offset: Duration(seconds: 30),
          waitForReady: false,
        );
        final (api, c, _) = waitBuild([forced], swap: swap);
        c.load(_content);
        flush(async);
        api.pushProgress(const MovaProg(position: Duration(seconds: 31)));
        flush(async);
        expect(swap.calls, isNot(contains('prepare')));
        expect(c.isShowingAd, isTrue);
      });
    });

    test('MovaAdBreak.waitForReady true overrides the pre default of false', () {
      fakeAsync((async) {
        final swap = FakeSwapCtl()..commitResult = true;
        const forced = MovaAdBreak(
          kind: MovaAdBreakKind.pre,
          source: MovaSource('https://host/pre.mp4'),
          waitForReady: true,
        );
        final (api, c, _) = waitBuild([forced], swap: swap);
        c.load(_content);
        flush(async);
        expect(swap.calls, contains('swapTo'));
      });
    });

    test('an injected MovaAdWaitPolicy is actually consulted and obeyed', () {
      fakeAsync((async) {
        final policy = RecordingAdWaitPolicy(answer: false);
        final swap = FakeSwapCtl();
        final (api, c, _) = waitBuild([mid], swap: swap, wait: policy);
        c.load(_content);
        flush(async);
        api.pushProgress(const MovaProg(position: Duration(seconds: 31)));
        flush(async);
        expect(policy.calls, greaterThan(0));
        expect(swap.calls, isNot(contains('prepare')), reason: 'the policy said do not wait');
        expect(c.isShowingAd, isTrue);
      });
    });

    test('the warm-up uses the content→ad plan, always at position zero', () {
      fakeAsync((async) {
        final swap = FakeSwapCtl();
        const delayed = MovaAdBreak(
          kind: MovaAdBreakKind.mid,
          source: MovaSource('https://host/mid.mp4'),
          offset: Duration(seconds: 30),
          delay: Duration(seconds: 3),
        );
        final (api, c, _) = waitBuild([delayed], swap: swap);
        c.load(_content);
        flush(async);
        api.pushProgress(const MovaProg(position: Duration(seconds: 31)));
        flush(async);
        api.pushProgress(const MovaProg(position: Duration(seconds: 32)));
        flush(async);
        expect(swap.lastPlan!.pauseWhenReady, isTrue);
        expect(swap.lastPlan!.trigger, isA<MovaEagerWarm>());
        expect(swap.lastPrepareAt, Duration.zero);
      });
    });

    test('the cue carries the countdown when there is one, and nothing when there is not', () {
      fakeAsync((async) {
        final swap = FakeSwapCtl();
        const delayed = MovaAdBreak(
          kind: MovaAdBreakKind.mid,
          source: MovaSource('https://host/mid.mp4'),
          offset: Duration(seconds: 30),
          delay: Duration(seconds: 5),
        );
        final (api, c, _) = waitBuild([delayed], swap: swap);
        c.load(_content);
        flush(async);
        api.pushProgress(const MovaProg(position: Duration(seconds: 30)));
        flush(async);
        api.pushProgress(const MovaProg(position: Duration(seconds: 32)));
        flush(async);
        expect(swap.lastCue!.total, const Duration(seconds: 5));
        expect(swap.lastCue!.remaining, const Duration(seconds: 3));

        // A zero-delay mid-roll: the warm-up still starts, with an empty cue.
        final swap2 = FakeSwapCtl();
        final (api2, c2, _) = waitBuild([mid], swap: swap2);
        c2.load(_content);
        flush(async);
        api2.pushProgress(const MovaProg(position: Duration(seconds: 31)));
        flush(async);
        expect(swap2.calls, contains('prepare'));
        expect(swap2.lastCue!.remaining, isNull);
        expect(swap2.lastCue!.total, isNull);
      });
    });

    test('a successful commit cuts in with no open(), and keeps every bit of bookkeeping', () {
      fakeAsync((async) {
        final swap = FakeSwapCtl()..commitResult = true;
        final (api, c, events) = waitBuild([mid], swap: swap);
        c.load(_content);
        flush(async);
        api.calls.clear();
        swap.calls.clear();
        var changes = 0;
        final sub = c.changes.listen((_) => changes++);
        api.pushProgress(const MovaProg(position: Duration(seconds: 31)));
        flush(async);
        expect(api.calls, isNot(contains('open')));
        expect(c.isShowingAd, isTrue);
        expect(c.currentBreak, same(mid));
        expect(events.map((e) => e.type), contains(MovaAdEventType.started));
        expect(changes, greaterThan(0));
        expect(swap.calls, isNot(contains('abandon')),
            reason: 'the shadow has just been promoted; it must not be torn down');
        sub.cancel();
      });
    });

    test('a failed commit with hardCut falls back to open(), the way it always did', () {
      fakeAsync((async) {
        final swap = FakeSwapCtl()..commitResult = false;
        final (api, c, _) = waitBuild([mid], swap: swap);
        c.load(_content);
        flush(async);
        api.calls.clear();
        api.pushProgress(const MovaProg(position: Duration(seconds: 31)));
        flush(async);
        expect(api.calls, contains('open'));
        expect(c.isShowingAd, isTrue);
        expect(api.source?.uri, 'https://host/mid.mp4');
      });
    });

    test('a failed commit with dropBreak never interrupts the content', () {
      fakeAsync((async) {
        final swap = FakeSwapCtl()..commitResult = false;
        final (api, c, events) = waitBuild(
          [mid],
          swap: swap,
          notReady: MovaAdNotReady.dropBreak,
        );
        c.load(_content);
        flush(async);
        api.calls.clear();
        swap.calls.clear();
        api.pushProgress(const MovaProg(position: Duration(seconds: 31)));
        flush(async);
        expect(api.calls, isNot(contains('open')));
        expect(c.isShowingAd, isFalse);
        expect(c.isAdPending, isFalse);
        expect(events.map((e) => e.type), contains(MovaAdEventType.failed));
        expect(swap.calls.where((e) => e == 'abandon'), hasLength(1));
        // The break is marked played, so it does not re-trigger on later ticks.
        api.pushProgress(const MovaProg(position: Duration(seconds: 40)));
        flush(async);
        expect(c.isShowingAd, isFalse);
      });
    });

    test('the ad→content direction still warms with the default plan, unmixed', () {
      fakeAsync((async) {
        final swap = FakeSwapCtl();
        final (api, c, _) = waitBuild([pre], swap: swap);
        c.load(_content);
        flush(async);
        swap.calls.clear();
        api.pushProgress(const MovaProg(position: Duration(seconds: 1)));
        flush(async);
        expect(swap.calls, contains('prepare'));
        expect(swap.lastPlan!.pauseWhenReady, isFalse,
            reason: 'ad→content keeps rolling; only content→ad holds at frame zero');
        expect(swap.lastPlan!.trigger, isNull, reason: 'the configured trigger applies');
      });
    });
  });

  group('ad failure fallback', () {
    /// Builds api + controller with an optional failure policy.
    ///
    /// 构造 api + 控制器，可选地带失败兜底策略。
    (FakeMovaApi, MovaAdCtrl, List<MovaAdEvent>) failBuild(
      List<MovaAdBreak> breaks, {
      MovaAdFailPolicy? policy,
      Duration loadTimeout = const Duration(seconds: 8),
    }) {
      final events = <MovaAdEvent>[];
      final api = FakeMovaApi(
        options: MovaOpts(
          ads: MovaAdConfig(
            enabled: true,
            breaks: breaks,
            onAdEvent: events.add,
            failPolicy: policy,
            loadTimeout: loadTimeout,
            // Keep these tests on the plain open() path.
            waitForAdReady: const MovaAdWaitByKind(mid: false),
          ),
        ),
      );
      return (api, MovaAdCtrl(api), events);
    }

    /// Counts how many times [uri] was opened, throwing attempts included.
    ///
    /// 统计 [uri] 被 open 了多少次，含抛出的那些尝试。
    int opensOf(FakeMovaApi api, String uri) =>
        api.openedUris.where((u) => u == uri).length;

    /// Lets the controller's async chains settle inside a [fakeAsync] zone.
    ///
    /// 在 [fakeAsync] 区域内让控制器的异步链结算完毕。
    void flush(FakeAsync async) => async.elapse(const Duration(milliseconds: 1));

    const pre = MovaAdBreak(
      kind: MovaAdBreakKind.pre,
      source: MovaSource('https://host/pre.mp4'),
    );
    const mid = MovaAdBreak(
      kind: MovaAdBreakKind.mid,
      source: MovaSource('https://host/mid.mp4'),
      offset: Duration(seconds: 30),
    );

    test('with no failure the policy is never consulted', () {
      fakeAsync((async) {
        final policy = RecordingFailPolicy();
        final (api, c, _) = failBuild([pre], policy: policy);
        c.load(_content);
        flush(async);
        api.pushProgress(const MovaProg(position: Duration(seconds: 1)));
        flush(async);
        api.pushEvent(const MovaDone());
        flush(async);
        expect(policy.seen, isEmpty);
        expect(api.source?.uri, _content.uri);
      });
    });

    test('a throwing open() reports failed with kind openThrew and the thrown object', () {
      fakeAsync((async) {
        final policy = RecordingFailPolicy();
        final (api, c, events) = failBuild([pre], policy: policy);
        final boom = StateError('404');
        api.openThrows = boom;
        api.openThrowsFor = 'https://host/pre.mp4';
        c.load(_content);
        flush(async);
        expect(policy.seen, hasLength(1));
        expect(policy.seen.first.kind, MovaAdFailKind.openThrew);
        expect(policy.seen.first.error, same(boom));
        expect(events.map((e) => e.type), contains(MovaAdEventType.failed));
        expect(events.firstWhere((e) => e.type == MovaAdEventType.failed).error, same(boom));
      });
    });

    test('the default policy skips the break after one failed attempt', () {
      fakeAsync((async) {
        final (api, c, _) = failBuild([pre]);
        api.openThrows = StateError('404');
        api.openThrowsFor = 'https://host/pre.mp4';
        c.load(_content);
        flush(async);
        expect(opensOf(api, 'https://host/pre.mp4'), 1, reason: 'no retry by default');
        expect(c.isShowingAd, isFalse);
        expect(api.source?.uri, _content.uri, reason: 'the skip path resumes the content');
      });
    });

    test('MovaAdRetrySkip(maxRetries: 2) tries three times, then gives up', () {
      fakeAsync((async) {
        final (api, c, _) = failBuild([pre], policy: const MovaAdRetrySkip(maxRetries: 2));
        api.openThrows = StateError('404');
        api.openThrowsFor = 'https://host/pre.mp4';
        c.load(_content);
        flush(async);
        expect(opensOf(api, 'https://host/pre.mp4'), 3,
            reason: 'the first attempt plus two retries');
        expect(c.isShowingAd, isFalse);
      });
    });

    test('a retry that succeeds plays the ad, reporting started, failed, started', () {
      fakeAsync((async) {
        final (api, c, events) = failBuild([pre], policy: const MovaAdRetrySkip(maxRetries: 1));
        // Throw on the first open only, so the retry succeeds.
        api.openThrows = StateError('transient');
        api.openThrowsOnce = true;
        api.openThrowsFor = 'https://host/pre.mp4';
        c.load(_content);
        flush(async);
        expect(opensOf(api, 'https://host/pre.mp4'), 2,
            reason: 'the failed attempt plus the successful retry');
        expect(c.isShowingAd, isTrue);
        expect(api.source?.uri, 'https://host/pre.mp4');
        expect(
          events.map((e) => e.type).toList(),
          containsAllInOrder([
            MovaAdEventType.started,
            MovaAdEventType.failed,
            MovaAdEventType.started,
          ]),
        );
      });
    });

    test('MovaAdAbandonPod drops every remaining pre-roll of the pod', () {
      fakeAsync((async) {
        const p2 = MovaAdBreak(
          kind: MovaAdBreakKind.pre,
          source: MovaSource('https://host/pre2.mp4'),
        );
        const p3 = MovaAdBreak(
          kind: MovaAdBreakKind.pre,
          source: MovaSource('https://host/pre3.mp4'),
        );
        final (api, c, _) = failBuild([pre, p2, p3], policy: const MovaAdAbandonPod());
        api.openThrows = StateError('404');
        api.openThrowsFor = 'https://host/pre.mp4';
        c.load(_content);
        flush(async);
        expect(opensOf(api, 'https://host/pre2.mp4'), 0);
        expect(opensOf(api, 'https://host/pre3.mp4'), 0);
        expect(c.isShowingAd, isFalse);
        expect(api.source?.uri, _content.uri, reason: 'pre2 and pre3 must not play');
      });
    });

    test('abandonPod on a mid-roll spares later mid-rolls at other offsets', () {
      fakeAsync((async) {
        const later = MovaAdBreak(
          kind: MovaAdBreakKind.mid,
          source: MovaSource('https://host/later.mp4'),
          offset: Duration(minutes: 20),
        );
        final (api, c, _) = failBuild([mid, later], policy: const MovaAdAbandonPod());
        c.load(_content);
        flush(async);
        api.openThrows = StateError('404');
        api.openThrowsFor = 'https://host/mid.mp4';
        api.pushProgress(const MovaProg(position: Duration(seconds: 31)));
        flush(async);
        expect(c.isShowingAd, isFalse);
        api.pushProgress(const MovaProg(position: Duration(minutes: 21)));
        flush(async);
        expect(c.isShowingAd, isTrue, reason: 'a pod is one insertion point, not the whole schedule');
        expect(api.source?.uri, 'https://host/later.mp4');
      });
    });

    test('a player error during an ad goes through the failure policy', () {
      fakeAsync((async) {
        final policy = RecordingFailPolicy();
        final (api, c, _) = failBuild([pre], policy: policy);
        c.load(_content);
        flush(async);
        api.pushEvent(MovaErrorEvent('decode failed'));
        flush(async);
        expect(policy.seen, hasLength(1));
        expect(policy.seen.first.kind, MovaAdFailKind.playerError);
      });
    });

    test('a player error during the content does not reach the failure policy', () {
      fakeAsync((async) {
        final policy = RecordingFailPolicy();
        final (api, c, _) = failBuild([], policy: policy);
        c.load(_content);
        flush(async);
        api.pushEvent(MovaErrorEvent('network blip'));
        flush(async);
        expect(policy.seen, isEmpty);
      });
    });

    test('an ad that never produces a first frame fails on loadTimeout', () {
      fakeAsync((async) {
        final policy = RecordingFailPolicy();
        final (api, c, _) = failBuild([pre], policy: policy);
        c.load(_content);
        flush(async);
        async.elapse(const Duration(seconds: 8));
        flush(async);
        expect(policy.seen, hasLength(1));
        expect(policy.seen.first.kind, MovaAdFailKind.loadTimeout);
      });
    });

    test('once the first frame lands the load deadline no longer applies', () {
      fakeAsync((async) {
        final policy = RecordingFailPolicy();
        final (api, c, _) = failBuild([pre], policy: policy);
        c.load(_content);
        flush(async);
        api.pushProgress(const MovaProg(position: Duration(milliseconds: 200)));
        flush(async);
        async.elapse(const Duration(seconds: 30));
        flush(async);
        expect(policy.seen, isEmpty);
        expect(c.isShowingAd, isTrue);
      });
    });

    test('skipBreak takes the same resume path as skip(): back to the saved position', () {
      fakeAsync((async) {
        final (api, c, _) = failBuild([mid]);
        c.load(_content);
        flush(async);
        api.openThrows = StateError('404');
        api.openThrowsFor = 'https://host/mid.mp4';
        api.pushProgress(const MovaProg(position: Duration(seconds: 31)));
        flush(async);
        expect(api.lastSeek, const Duration(seconds: 31));
      });
    });

    test('one failed break in a pod does not take its siblings down', () {
      fakeAsync((async) {
        const p2 = MovaAdBreak(
          kind: MovaAdBreakKind.pre,
          source: MovaSource('https://host/pre2.mp4'),
        );
        final (api, c, _) = failBuild([pre, p2]);
        api.openThrows = StateError('404');
        api.openThrowsFor = 'https://host/pre.mp4';
        c.load(_content);
        flush(async);
        expect(api.source?.uri, 'https://host/pre2.mp4', reason: 'the sibling still plays');
      });
    });

    test('a retried break gets a fresh duration, counted from its new first frame', () {
      fakeAsync((async) {
        const timed = MovaAdBreak(
          kind: MovaAdBreakKind.pre,
          source: MovaSource('https://host/pre.mp4'),
          duration: Duration(seconds: 10),
        );
        final (api, c, _) = failBuild(
          [timed],
          policy: const MovaAdRetrySkip(maxRetries: 1),
          loadTimeout: const Duration(minutes: 10),
        );
        api.openThrows = StateError('transient');
        api.openThrowsOnce = true;
        api.openThrowsFor = 'https://host/pre.mp4';
        c.load(_content);
        flush(async);
        expect(c.isShowingAd, isTrue, reason: 'the retry re-opened successfully');
        // The retried break starts its 10s slot from its own first frame, so a
        // long wait with no frame yet must not end it.
        async.elapse(const Duration(seconds: 20));
        flush(async);
        expect(c.isShowingAd, isTrue, reason: 'no first frame yet, so the slot has not started');
        api.pushProgress(const MovaProg(position: Duration(milliseconds: 100)));
        flush(async);
        async.elapse(const Duration(seconds: 9));
        expect(c.isShowingAd, isTrue, reason: 'the retried ad gets its full 10s');
        async.elapse(const Duration(seconds: 1));
        flush(async);
        expect(c.isShowingAd, isFalse);
      });
    });
  });
}

/// A [MovaAdFailPolicy] that records every failure it is shown.
///
/// 一个记录所有被告知失败的 [MovaAdFailPolicy]。
class RecordingFailPolicy implements MovaAdFailPolicy {
  /// Every failure passed to [onFailure], in order.
  ///
  /// 依次传给 [onFailure] 的所有失败记录。
  final List<MovaAdFail> seen = <MovaAdFail>[];

  /// What [onFailure] answers.
  ///
  /// [onFailure] 的回答。
  final MovaAdFailAction action;

  /// Creates a recording failure policy answering [action].
  ///
  /// 创建一个回答 [action] 的记录型失败策略。
  RecordingFailPolicy({this.action = MovaAdFailAction.skipBreak});

  @override
  MovaAdFailAction onFailure(MovaAdFail failure) {
    seen.add(failure);
    return action;
  }
}

/// A [MovaAdWaitPolicy] that records how often the controller consulted it.
///
/// 一个记录控制器咨询次数的 [MovaAdWaitPolicy]。
class RecordingAdWaitPolicy implements MovaAdWaitPolicy {
  /// What [waitFor] answers.
  ///
  /// [waitFor] 的回答。
  final bool answer;

  /// How many times [waitFor] was called.
  ///
  /// [waitFor] 被调用的次数。
  int calls = 0;

  /// Creates a recording wait policy answering [answer].
  ///
  /// 创建一个回答 [answer] 的记录型等待策略。
  RecordingAdWaitPolicy({this.answer = true});

  @override
  bool waitFor(MovaAdBreak adBreak) {
    calls++;
    return answer;
  }
}
