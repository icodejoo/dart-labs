import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mova/mova.dart';
import '../support/fake_api.dart';
import '../support/pump.dart';

const content = MovaSource('https://host/content.mp4');
const ad = MovaAdBreak(
  kind: MovaAdBreakKind.pre,
  source: MovaSource('https://host/ad.mp4'),
  skippableAfter: Duration(seconds: 5),
);
const items = [
  MovaPlaylistItem(source: content, title: 'E1'),
  MovaPlaylistItem(source: MovaSource('https://host/next.mp4'), title: 'E2'),
];

({FakeMovaApi api, MovaAds ads, MovaPlaylist playlist}) fixture({
  List<MovaAdBreak> breaks = const [],
  bool shared = true,
}) {
  final api = FakeMovaApi(
    options: MovaOpts(
      ads: MovaAdOpts(enabled: true, breaks: breaks),
      playlist: const MovaPlaylistOpts(
        enabled: true,
        items: items,
        nextUpLeadTime: Duration(seconds: 10),
      ),
    ),
  );
  final ads = MovaAds(api);
  final playlist = MovaPlaylist(api, ads: shared ? ads : null);
  return (api: api, ads: ads, playlist: playlist);
}

Future<void> cleanup(
  WidgetTester tester,
  ({FakeMovaApi api, MovaAds ads, MovaPlaylist playlist}) f,
) async {
  await tester.pumpWidget(const SizedBox());
  await tester.runAsync(() async {
    await f.playlist.dispose();
    await f.ads.dispose();
    await f.api.dispose();
  });
}

Future<void> tick(
  WidgetTester t,
  FakeMovaApi api,
  Duration position,
  Duration duration,
) async {
  api.push(api.state.copyWith(duration: duration));
  api.pushProgress(MovaProg(position: position));
  await t.pump();
  await t.pump();
}

void main() {
  testWidgets('会话前贴片临近素材结束不显示 NextUp', (t) async {
    final f = fixture(breaks: [ad]);
    await f.ads.load(content);
    await pumpComponent(t, f.api, MovaNextUpComponent(f.playlist));
    await tick(
      t,
      f.api,
      const Duration(seconds: 9),
      const Duration(seconds: 10),
    );
    expect(f.ads.isShowingAd, isTrue);
    expect(find.text('即将播放'), findsNothing);
    await cleanup(t, f);
  });
  testWidgets('NextUp 进出广告立即隐藏旧卡片，回正片进入窗口重新显示', (t) async {
    final f = fixture();
    await f.playlist.jumpTo(0);
    await pumpComponent(t, f.api, MovaNextUpComponent(f.playlist));
    await tick(
      t,
      f.api,
      const Duration(seconds: 55),
      const Duration(seconds: 60),
    );
    expect(find.text('即将播放'), findsOneWidget);
    await f.ads.playAdNow(ad);
    await t.pump();
    expect(find.text('即将播放'), findsNothing);
    f.api.pushEvent(const MovaDone());
    await t.pump();
    await t.pump();
    expect(f.ads.session.cursor.phase, MovaSessionPhase.content);
    expect(find.text('即将播放'), findsNothing);
    await tick(
      t,
      f.api,
      const Duration(seconds: 55),
      const Duration(seconds: 60),
    );
    expect(find.text('即将播放'), findsOneWidget);
    await cleanup(t, f);
  });
  testWidgets('旧直连 NextUp 不读取独立广告会话，保留时长判据', (t) async {
    final f = fixture(breaks: [ad], shared: false);
    await f.ads.load(content);
    await pumpComponent(t, f.api, MovaNextUpComponent(f.playlist));
    await tick(
      t,
      f.api,
      const Duration(seconds: 9),
      const Duration(seconds: 10),
    );
    expect(find.text('即将播放'), findsOneWidget);
    await cleanup(t, f);
  });
  testWidgets('覆盖层 pod 第二条落地时旧 8 秒进度不提前显示跳过', (t) async {
    final f = fixture(breaks: [ad, ad]);
    await f.ads.load(content);
    await pumpComponent(t, f.api, MovaAdOverlayComponent(f.ads));
    await tick(
      t,
      f.api,
      const Duration(seconds: 8),
      const Duration(seconds: 10),
    );
    expect(f.ads.canSkip, isTrue);
    expect(find.text('跳过广告'), findsOneWidget);
    final gate = f.api.openGate = Completer<void>();
    addTearDown(() {
      if (!gate.isCompleted) gate.complete();
    });
    f.api.pushEvent(const MovaDone());
    await t.pump();
    f.api.pushProgress(const MovaProg(position: Duration(seconds: 8)));
    await t.pump();
    await t.pump();
    expect(f.ads.session.cursor.node?.ordinal, 1);
    expect(f.ads.adPosition, Duration.zero);
    expect(f.ads.canSkip, isFalse);
    expect(find.text('跳过广告'), findsNothing);
    expect(find.text('5'), findsOneWidget);
    gate.complete();
    await t.pump();
    await t.pump();
    await cleanup(t, f);
  });
  testWidgets('覆盖层倒计时读取 skipIn 并向上取整到微秒边界', (t) async {
    final f = fixture(breaks: [ad]);
    await f.ads.load(content);
    await pumpComponent(t, f.api, MovaAdOverlayComponent(f.ads));
    await tick(
      t,
      f.api,
      const Duration(milliseconds: 3001),
      const Duration(seconds: 10),
    );
    expect(f.ads.skipIn, const Duration(milliseconds: 1999));
    expect(find.text('2'), findsOneWidget);
    await tick(
      t,
      f.api,
      const Duration(microseconds: 4999999),
      const Duration(seconds: 10),
    );
    expect(f.ads.skipIn, const Duration(microseconds: 1));
    expect(f.ads.canSkip, isFalse);
    expect(find.text('1'), findsOneWidget);
    expect(find.text('0'), findsNothing);
    await cleanup(t, f);
  });
}
