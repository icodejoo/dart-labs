import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mova/src/core/ad/ad_controller.dart';
import 'package:mova/src/core/model/ad.dart';
import 'package:mova/src/core/model/source.dart';
import 'package:mova/src/core/options/options.dart';
import 'package:mova/src/core/state/progress.dart';
import 'package:mova/src/ui/components/ad_overlay.dart';

import '../support/fake_api.dart';
import '../support/pump.dart';

const _content = MovaSource('https://host/content.m3u8');

void main() {
  /// Builds a fake API + ad controller with a single [break_], collecting ad
  /// events into the returned list.
  ///
  /// 用单个 [break_] 构造假 API + 广告控制器，把广告事件收集进返回的列表。
  (FakeMovaApi, MovaAdController, List<MovaAdEvent>) build(
    MovaAdBreak break_, {
    bool enabled = true,
  }) {
    final events = <MovaAdEvent>[];
    final api = FakeMovaApi(
      options: MovaOpts(
        ads: MovaAdConfig(
          enabled: enabled,
          breaks: [break_],
          onAdEvent: events.add,
        ),
      ),
    );
    return (api, MovaAdController(api), events);
  }

  testWidgets('renders nothing when ads are disabled', (t) async {
    const pre = MovaAdBreak(
      kind: MovaAdBreakKind.pre,
      source: MovaSource('https://host/pre.mp4'),
    );
    final (api, c, _) = build(pre, enabled: false);
    await c.load(_content);
    await pumpComponent(t, api, MovaAdOverlayComponent(c));
    expect(find.text('广告'), findsNothing);
    await api.dispose();
  });

  testWidgets('shows the ad badge and a countdown, then the skip button', (t) async {
    const pre = MovaAdBreak(
      kind: MovaAdBreakKind.pre,
      source: MovaSource('https://host/pre.mp4'),
      skippableAfter: Duration(seconds: 5),
    );
    final (api, c, _) = build(pre);
    await c.load(_content);
    await pumpComponent(t, api, MovaAdOverlayComponent(c));
    expect(find.text('广告'), findsOneWidget);
    expect(find.text('跳过广告'), findsNothing);

    api.pushProgress(const MovaProg(position: Duration(seconds: 6)));
    await t.pump();
    await t.pump();
    expect(find.text('跳过广告'), findsOneWidget);
    await api.dispose();
  });

  testWidgets('tapping skip resumes content and hides the overlay', (t) async {
    const pre = MovaAdBreak(
      kind: MovaAdBreakKind.pre,
      source: MovaSource('https://host/pre.mp4'),
      skippableAfter: Duration(seconds: 5),
    );
    final (api, c, _) = build(pre);
    await c.load(_content);
    await pumpComponent(t, api, MovaAdOverlayComponent(c));
    api.pushProgress(const MovaProg(position: Duration(seconds: 6)));
    await t.pump();
    await t.pump();

    await t.tap(find.text('跳过广告'));
    await t.pump();
    await t.pump();
    expect(find.text('广告'), findsNothing);
    expect(api.source?.uri, _content.uri);
    await api.dispose();
  });

  testWidgets('tapping the surface reports a click-through', (t) async {
    const pre = MovaAdBreak(
      kind: MovaAdBreakKind.pre,
      source: MovaSource('https://host/pre.mp4'),
      clickThroughUrl: 'https://advertiser.example',
    );
    final (api, c, events) = build(pre);
    await c.load(_content);
    await pumpComponent(t, api, MovaAdOverlayComponent(c));
    // The ad has rendered its first frame, which is also what clears the
    // no-first-frame deadline.
    //
    // 广告已产出首帧——这同时也是解除"始终没有首帧"判定期限的那一下。
    api.pushProgress(const MovaProg(position: Duration(seconds: 1)));
    await t.pump();
    await t.tapAt(const Offset(400, 300));
    await t.pump();
    final clicked = events.where((e) => e.type == MovaAdEventType.clicked);
    expect(clicked, hasLength(1));
    expect(clicked.first.adBreak.clickThroughUrl, 'https://advertiser.example');
    await api.dispose();
  });

  /// Builds a fake API + controller whose single mid-roll carries [delay],
  /// with the swap ctl needed for the readiness-wait paths.
  ///
  /// 构造假 API + 控制器，其唯一的中插带有 [delay]，并带上就绪等待路径所需的
  /// 切换能力面。
  (FakeMovaApi, MovaAdController, List<MovaAdEvent>) pendingBuild({
    required Duration delay,
    MovaAdWaitPolicy? wait,
    FakeSwapCtl? swap,
  }) {
    final mid = MovaAdBreak(
      kind: MovaAdBreakKind.mid,
      source: const MovaSource('https://host/mid.mp4'),
      offset: const Duration(seconds: 30),
      delay: delay,
    );
    final events = <MovaAdEvent>[];
    final api = FakeMovaApi(
      options: MovaOpts(
        ads: MovaAdConfig(
          enabled: true,
          breaks: [mid],
          onAdEvent: events.add,
          waitForAdReady: wait ?? const MovaAdWaitByKind(),
        ),
      ),
    );
    return (api, MovaAdController(api, swap: swap), events);
  }


  /// Ends a pending phase cleanly: lets the delay timer fire, feeds the ad its
  /// first frame (which clears the no-first-frame deadline), then disposes —
  /// so no timer outlives the test.
  ///
  /// 干净地结束待播阶段：让倒计时定时器触发、给广告喂一个首帧（这会解除"始终
  /// 没有首帧"的判定期限），然后销毁——使没有定时器活过本用例。
  Future<void> finishPending(WidgetTester t, FakeMovaApi api) async {
    await t.pump(const Duration(seconds: 6));
    api.pushProgress(const MovaProg(position: Duration(seconds: 1)));
    await t.pump();
    await api.dispose();
  }

  testWidgets('renders nothing when neither an ad nor a pending one exists', (t) async {
    final (api, c, pendEvents) = pendingBuild(delay: const Duration(seconds: 5));
    await c.load(_content);
    await pumpComponent(t, api, MovaAdOverlayComponent(c));
    expect(find.byType(Text), findsNothing);
    await api.dispose();
  });

  testWidgets('a delay countdown renders the adStartingIn copy', (t) async {
    final (api, c, pendEvents) = pendingBuild(delay: const Duration(seconds: 5));
    await c.load(_content);
    await pumpComponent(t, api, MovaAdOverlayComponent(c));
    api.pushProgress(const MovaProg(position: Duration(seconds: 31)));
    await t.pump();
    await t.pump();
    expect(c.isAdPending, isTrue);
    expect(find.text(movaDefaultAdStartingIn(5)), findsOneWidget);
    await finishPending(t, api);
  });

  testWidgets('the pending phase renders no ad badge', (t) async {
    final (api, c, pendEvents) = pendingBuild(delay: const Duration(seconds: 5));
    await c.load(_content);
    await pumpComponent(t, api, MovaAdOverlayComponent(c));
    api.pushProgress(const MovaProg(position: Duration(seconds: 31)));
    await t.pump();
    await t.pump();
    expect(find.text('广告'), findsNothing);
    await finishPending(t, api);
  });

  testWidgets('the pending phase does not swallow taps on the content', (t) async {
    final (api, c, pendEvents) = pendingBuild(delay: const Duration(seconds: 5));
    await c.load(_content);
    await pumpComponent(t, api, MovaAdOverlayComponent(c));
    api.pushProgress(const MovaProg(position: Duration(seconds: 31)));
    await t.pump();
    await t.pump();
    await t.tapAt(const Offset(400, 300));
    await t.pump();
    expect(
      pendEvents.where((e) => e.type == MovaAdEventType.clicked),
      isEmpty,
      reason: 'no full-surface tap layer during pending, so the content keeps its gestures',
    );
    await finishPending(t, api);
  });

  testWidgets('the countdown number decrements as content ticks arrive', (t) async {
    final (api, c, pendEvents) = pendingBuild(delay: const Duration(seconds: 5));
    await c.load(_content);
    await pumpComponent(t, api, MovaAdOverlayComponent(c));
    api.pushProgress(const MovaProg(position: Duration(seconds: 30)));
    await t.pump();
    await t.pump();
    expect(find.text(movaDefaultAdStartingIn(5)), findsOneWidget);
    api.pushProgress(const MovaProg(position: Duration(seconds: 32)));
    await t.pump();
    await t.pump();
    expect(find.text(movaDefaultAdStartingIn(3)), findsOneWidget);
    expect(find.text(movaDefaultAdStartingIn(5)), findsNothing);
    await finishPending(t, api);
  });

  testWidgets('the countdown gives way to the ad badge when the ad takes over', (t) async {
    final (api, c, pendEvents) = pendingBuild(delay: const Duration(seconds: 5));
    await c.load(_content);
    await pumpComponent(t, api, MovaAdOverlayComponent(c));
    api.pushProgress(const MovaProg(position: Duration(seconds: 31)));
    await t.pump();
    await t.pump();
    expect(find.text(movaDefaultAdStartingIn(5)), findsOneWidget);

    await t.pump(const Duration(seconds: 5));
    await t.pump();
    expect(c.isShowingAd, isTrue);
    expect(find.text(movaDefaultAdStartingIn(5)), findsNothing);
    expect(find.text('广告'), findsOneWidget);
    api.pushProgress(const MovaProg(position: Duration(seconds: 1)));
    await t.pump();
    await api.dispose();
  });

  testWidgets('a zero-delay pending phase renders nothing at all', (t) async {
    // Waiting silently for readiness must stay imperceptible.
    //
    // 静默等待就绪必须保持用户无感。
    final swap = FakeSwapCtl();
    final (api, c, pendEvents) = pendingBuild(delay: Duration.zero, swap: swap);
    await c.load(_content);
    await pumpComponent(t, api, MovaAdOverlayComponent(c));
    expect(c.delayRemaining, isNull);
    expect(find.byType(Text), findsNothing);
    await api.dispose();
  });
}
