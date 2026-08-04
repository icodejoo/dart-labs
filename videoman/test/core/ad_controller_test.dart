import 'package:flutter_test/flutter_test.dart';
import 'package:videoman/src/core/ad/ad_controller.dart';
import 'package:videoman/src/core/events/events.dart';
import 'package:videoman/src/core/model/ad.dart';
import 'package:videoman/src/core/model/source.dart';
import 'package:videoman/src/core/options/options.dart';
import 'package:videoman/src/core/state/progress.dart';

import '../support/fake_api.dart';

const _content = VmSource('https://host/content.m3u8');

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
    const mid = VmAdBreak(
      kind: VmAdBreakKind.mid,
      source: VmSource('https://host/mid.mp4'),
      offset: Duration(seconds: 30),
    );
    const pre = VmAdBreak(
      kind: VmAdBreakKind.pre,
      source: VmSource('https://host/pre.mp4'),
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
  (FakeVmApi, VmAdController, List<VmAdEvent>) build(
    List<VmAdBreak> breaks, {
    bool enabled = true,
  }) {
    final events = <VmAdEvent>[];
    final api = FakeVmApi(
      options: VmOptions(
        ads: VmAdConfig(enabled: enabled, breaks: breaks, onAdEvent: events.add),
      ),
    );
    return (api, VmAdController(api), events);
  }

  test('disabled: load opens the content directly, no ad', () async {
    const pre = VmAdBreak(
      kind: VmAdBreakKind.pre,
      source: VmSource('https://host/pre.mp4'),
    );
    final (api, c, events) = build([pre], enabled: false);
    await c.load(_content);
    await settle();
    expect(c.isShowingAd, isFalse);
    expect(api.source?.uri, _content.uri);
    expect(events, isEmpty);
  });

  test('pre-roll plays before the content, then content on completion', () async {
    const pre = VmAdBreak(
      kind: VmAdBreakKind.pre,
      source: VmSource('https://host/pre.mp4'),
    );
    final (api, c, events) = build([pre]);
    await c.load(_content);
    await settle();
    expect(c.isShowingAd, isTrue);
    expect(api.source?.uri, 'https://host/pre.mp4');

    api.pushEvent(const VmCompleted());
    await settle();
    expect(c.isShowingAd, isFalse);
    expect(api.source?.uri, _content.uri);
    expect(events.map((e) => e.type),
        containsAllInOrder([VmAdEventType.started, VmAdEventType.completed]));
  });

  test('mid-roll triggers at its offset and resumes content at the saved position',
      () async {
    const mid = VmAdBreak(
      kind: VmAdBreakKind.mid,
      source: VmSource('https://host/mid.mp4'),
      offset: Duration(seconds: 30),
    );
    final (api, c, _) = build([mid]);
    await c.load(_content);
    await settle();
    expect(api.source?.uri, _content.uri); // no pre-roll

    api.pushProgress(const VmProgress(position: Duration(seconds: 31)));
    await settle();
    expect(c.isShowingAd, isTrue);
    expect(api.source?.uri, 'https://host/mid.mp4');

    api.pushEvent(const VmCompleted());
    await settle();
    expect(c.isShowingAd, isFalse);
    expect(api.source?.uri, _content.uri);
    expect(api.lastSeek, const Duration(seconds: 31));
  });

  test('mid-roll does not re-trigger after it has played', () async {
    const mid = VmAdBreak(
      kind: VmAdBreakKind.mid,
      source: VmSource('https://host/mid.mp4'),
      offset: Duration(seconds: 30),
    );
    final (api, c, _) = build([mid]);
    await c.load(_content);
    await settle();
    api.pushProgress(const VmProgress(position: Duration(seconds: 31)));
    await settle();
    api.pushEvent(const VmCompleted()); // ad ends → content resumes
    await settle();
    api.calls.clear();
    api.pushProgress(const VmProgress(position: Duration(seconds: 40)));
    await settle();
    expect(c.isShowingAd, isFalse);
    expect(api.calls, isNot(contains('open')));
  });

  test('post-roll plays when content completes, then goes idle', () async {
    const post = VmAdBreak(
      kind: VmAdBreakKind.post,
      source: VmSource('https://host/post.mp4'),
    );
    final (api, c, _) = build([post]);
    await c.load(_content);
    await settle();
    expect(api.source?.uri, _content.uri);

    api.pushEvent(const VmCompleted()); // content ends → post-roll
    await settle();
    expect(c.isShowingAd, isTrue);
    expect(api.source?.uri, 'https://host/post.mp4');

    api.pushEvent(const VmCompleted()); // post-roll ends → idle
    await settle();
    expect(c.isShowingAd, isFalse);
  });

  test('skip is a no-op before the threshold and skips after it', () async {
    const pre = VmAdBreak(
      kind: VmAdBreakKind.pre,
      source: VmSource('https://host/pre.mp4'),
      skippableAfter: Duration(seconds: 5),
    );
    final (api, c, events) = build([pre]);
    await c.load(_content);
    await settle();

    c.skip(); // ad position still 0 → not skippable
    await settle();
    expect(c.isShowingAd, isTrue);

    api.pushProgress(const VmProgress(position: Duration(seconds: 6)));
    await settle();
    expect(c.canSkip, isTrue);
    c.skip();
    await settle();
    expect(c.isShowingAd, isFalse);
    expect(api.source?.uri, _content.uri);
    expect(events.map((e) => e.type), contains(VmAdEventType.skipped));
  });

  test('notifyClicked reports a click for the current ad only', () async {
    const pre = VmAdBreak(
      kind: VmAdBreakKind.pre,
      source: VmSource('https://host/pre.mp4'),
      clickThroughUrl: 'https://advertiser.example',
    );
    final (_, c, events) = build([pre]);
    await c.load(_content);
    await settle();
    c.notifyClicked();
    final clicked = events.where((e) => e.type == VmAdEventType.clicked);
    expect(clicked, hasLength(1));
    expect(clicked.first.adBreak.clickThroughUrl, 'https://advertiser.example');
  });

  test('suppresses STT during an ad and restores it after', () async {
    const mid = VmAdBreak(
      kind: VmAdBreakKind.mid,
      source: VmSource('https://host/mid.mp4'),
      offset: Duration(seconds: 30),
    );
    final (api, c, _) = build([mid]);
    await c.load(_content);
    await settle();
    await api.stt.start(); // host turns STT on for the content
    expect(api.stt.isRunning, isTrue);

    api.pushProgress(const VmProgress(position: Duration(seconds: 31)));
    await settle();
    expect(c.isShowingAd, isTrue);
    expect(api.stt.isRunning, isFalse); // suppressed during the ad

    api.pushEvent(const VmCompleted());
    await settle();
    expect(c.isShowingAd, isFalse);
    expect(api.stt.isRunning, isTrue); // restored on resume
  });

  test('does not start STT after an ad if it was not running before', () async {
    const mid = VmAdBreak(
      kind: VmAdBreakKind.mid,
      source: VmSource('https://host/mid.mp4'),
      offset: Duration(seconds: 30),
    );
    final (api, c, _) = build([mid]);
    await c.load(_content);
    await settle();
    api.pushProgress(const VmProgress(position: Duration(seconds: 31)));
    await settle();
    api.pushEvent(const VmCompleted());
    await settle();
    expect(api.stt.isRunning, isFalse);
    expect(api.stt.calls, isNot(contains('start')));
  });

  test('playAdNow inserts an ad at the current position and resumes there',
      () async {
    final (api, c, events) = build(const []); // no pre-configured breaks
    await c.load(_content);
    await settle();
    api.pushProgress(const VmProgress(position: Duration(seconds: 50)));
    await settle();

    await c.playAdNow(const VmAdBreak(
      kind: VmAdBreakKind.mid,
      source: VmSource('https://host/flash.mp4'),
    ));
    await settle();
    expect(c.isShowingAd, isTrue);
    expect(api.source?.uri, 'https://host/flash.mp4');

    api.pushEvent(const VmCompleted());
    await settle();
    expect(c.isShowingAd, isFalse);
    expect(api.source?.uri, _content.uri);
    expect(api.lastSeek, const Duration(seconds: 50));
    expect(events.map((e) => e.type),
        containsAllInOrder([VmAdEventType.started, VmAdEventType.completed]));
  });

  test('playAdNow is a no-op when no content is playing', () async {
    final (api, c, _) = build(const []);
    await c.playAdNow(const VmAdBreak(
      kind: VmAdBreakKind.mid,
      source: VmSource('https://host/flash.mp4'),
    ));
    await settle();
    expect(c.isShowingAd, isFalse);
    expect(api.calls, isEmpty);
  });

  test('multiple mid-rolls at arbitrary offsets each play once, in order', () async {
    const mid1 = VmAdBreak(
      kind: VmAdBreakKind.mid,
      source: VmSource('https://host/mid1.mp4'),
      offset: Duration(seconds: 30),
    );
    const mid2 = VmAdBreak(
      kind: VmAdBreakKind.mid,
      source: VmSource('https://host/mid2.mp4'),
      offset: Duration(seconds: 60),
    );
    final (api, c, _) = build([mid1, mid2]);
    await c.load(_content);
    await settle();

    api.pushProgress(const VmProgress(position: Duration(seconds: 31)));
    await settle();
    expect(api.source?.uri, 'https://host/mid1.mp4');
    api.pushEvent(const VmCompleted());
    await settle();
    expect(api.source?.uri, _content.uri); // resumed content

    api.pushProgress(const VmProgress(position: Duration(seconds: 61)));
    await settle();
    expect(api.source?.uri, 'https://host/mid2.mp4');
    api.pushEvent(const VmCompleted());
    await settle();
    expect(api.source?.uri, _content.uri);
  });

  test('an ad pod plays every pre-roll in order before the content', () async {
    const pre1 = VmAdBreak(
      kind: VmAdBreakKind.pre,
      source: VmSource('https://host/pre1.mp4'),
    );
    const pre2 = VmAdBreak(
      kind: VmAdBreakKind.pre,
      source: VmSource('https://host/pre2.mp4'),
    );
    final (api, c, _) = build([pre1, pre2]);
    await c.load(_content);
    await settle();
    expect(api.source?.uri, 'https://host/pre1.mp4');

    api.pushEvent(const VmCompleted());
    await settle();
    expect(api.source?.uri, 'https://host/pre2.mp4'); // pod continues

    api.pushEvent(const VmCompleted());
    await settle();
    expect(api.source?.uri, _content.uri); // then the content
  });

  test('contentEnded fires after content completes with no post-roll', () async {
    final (api, c, _) = build(const []);
    final ended = <void>[];
    final sub = c.contentEnded.listen(ended.add);
    await c.load(_content);
    await settle();
    api.pushEvent(const VmCompleted());
    await settle();
    expect(ended, hasLength(1));
    await sub.cancel();
  });

  test('contentEnded fires only after the post-roll pod finishes', () async {
    const post1 = VmAdBreak(
      kind: VmAdBreakKind.post,
      source: VmSource('https://host/post1.mp4'),
    );
    const post2 = VmAdBreak(
      kind: VmAdBreakKind.post,
      source: VmSource('https://host/post2.mp4'),
    );
    final (api, c, _) = build([post1, post2]);
    final ended = <void>[];
    final sub = c.contentEnded.listen(ended.add);
    await c.load(_content);
    await settle();

    api.pushEvent(const VmCompleted()); // content → post1
    await settle();
    expect(api.source?.uri, 'https://host/post1.mp4');
    expect(ended, isEmpty);

    api.pushEvent(const VmCompleted()); // post1 → post2
    await settle();
    expect(api.source?.uri, 'https://host/post2.mp4');
    expect(ended, isEmpty);

    api.pushEvent(const VmCompleted()); // post2 → idle, content truly ended
    await settle();
    expect(c.isShowingAd, isFalse);
    expect(ended, hasLength(1));
    await sub.cancel();
  });

  test('dispose stops reacting to completion events', () async {
    const post = VmAdBreak(
      kind: VmAdBreakKind.post,
      source: VmSource('https://host/post.mp4'),
    );
    final (api, c, _) = build([post]);
    await c.load(_content);
    await settle();
    await c.dispose();
    api.calls.clear();
    api.pushEvent(const VmCompleted());
    await settle();
    expect(c.isShowingAd, isFalse);
    expect(api.calls, isEmpty);
  });
}
