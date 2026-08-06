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
  (FakeMovaApi, MovaAdCtrl, List<MovaAdEvent>) build(
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
    return (api, MovaAdCtrl(api), events);
  }

  testWidgets('renders nothing when ads are disabled', (t) async {
    const pre = MovaAdBreak(
      kind: MovaAdBreakKind.pre,
      source: MovaSource('https://host/pre.mp4'),
    );
    final (api, c, _) = build(pre, enabled: false);
    await c.load(_content);
    await pumpComponent(t, api, AdOverlayComponent(c));
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
    await pumpComponent(t, api, AdOverlayComponent(c));
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
    await pumpComponent(t, api, AdOverlayComponent(c));
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
    await pumpComponent(t, api, AdOverlayComponent(c));
    await t.tapAt(const Offset(400, 300));
    await t.pump();
    final clicked = events.where((e) => e.type == MovaAdEventType.clicked);
    expect(clicked, hasLength(1));
    expect(clicked.first.adBreak.clickThroughUrl, 'https://advertiser.example');
    await api.dispose();
  });
}
