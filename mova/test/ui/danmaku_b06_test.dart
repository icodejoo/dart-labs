import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mova/mova.dart';

import '../support/fake_api.dart';
import '../support/pump.dart';

/// 创建已播放的弹幕替身，可注入密集列表。
FakeMovaApi _api({List<MovaDanmakuItem>? items}) {
  final api = FakeMovaApi(options: MovaOpts(danmaku: MovaDanmakuConfig(
    enabled: true, crossDuration: const Duration(seconds: 4),
    items: items ?? const [MovaDanmakuItem(text: 'bullet', time: Duration(seconds: 1))],
  )));
  api.push(api.state.copyWith(playing: true));
  return api;
}

/// 跨过弹幕时间并使动画开始计时。
Future<void> _spawn(WidgetTester t, FakeMovaApi api) async {
  await pumpComponent(t, api, MovaDanmakuTrackComponent());
  api.pushProgress(const MovaProg(position: Duration(seconds: 1)));
  await t.pump();
  await t.pump();
}

/// B06 的游标、同屏上限和播放时钟回归。
void main() {
  testWidgets('从 30 分钟续播只移动游标，不生成跨越区间弹幕', (t) async {
    final api = _api(items: List.generate(18000, (i) =>
      MovaDanmakuItem(text: 'b$i', time: Duration(milliseconds: i * 100))));
    await pumpComponent(t, api, MovaDanmakuTrackComponent());
    api.pushProgress(const MovaProg(position: Duration(minutes: 30)));
    await t.pump();
    expect(find.byType(Text), findsNothing);
    await api.dispose();
  });

  testWidgets('密集弹幕同屏不超过轨道数两倍，丢弃项不在后续补发', (t) async {
    final api = _api(items: List.generate(100, (i) =>
      MovaDanmakuItem(text: 'b$i', time: const Duration(seconds: 1))));
    await _spawn(t, api);
    expect(find.byType(Text), findsNWidgets(8));
    await t.pump(const Duration(seconds: 5));
    api.pushProgress(const MovaProg(position: Duration(seconds: 2)));
    await t.pump();
    expect(find.byType(Text), findsNothing);
    await api.dispose();
  });

  testWidgets('暂停后墙钟推进也不改变弹幕位置', (t) async {
    final api = _api();
    await _spawn(t, api);
    await t.pump(const Duration(seconds: 1));
    api.push(api.state.copyWith(playing: false));
    await t.pump();
    final before = t.getTopLeft(find.text('bullet'));
    await t.pump(const Duration(seconds: 3));
    expect(t.getTopLeft(find.text('bullet')), before);
    await api.dispose();
  });

  testWidgets('恢复播放从暂停位置继续直到正常退场', (t) async {
    final api = _api();
    await _spawn(t, api);
    await t.pump(const Duration(seconds: 1));
    api.push(api.state.copyWith(playing: false));
    await t.pump();
    await t.pump(const Duration(seconds: 5));
    api.push(api.state.copyWith(playing: true));
    await t.pump();
    await t.pump();
    await t.pump(const Duration(seconds: 2));
    expect(find.text('bullet'), findsOneWidget);
    await t.pump(const Duration(seconds: 2));
    expect(find.text('bullet'), findsNothing);
    await api.dispose();
  });

  testWidgets('运行中切换两倍速保留当前位置并加快剩余动画', (t) async {
    final api = _api();
    await _spawn(t, api);
    await t.pump(const Duration(seconds: 1));
    final before = t.getTopLeft(find.text('bullet'));
    api.push(api.state.copyWith(rate: 2));
    await t.pump();
    expect(t.getTopLeft(find.text('bullet')), before);
    await t.pump();
    await t.pump(const Duration(milliseconds: 1600));
    expect(find.text('bullet'), findsNothing);
    await api.dispose();
  });

  testWidgets('显式 seek 清屏，后跳后可再次跨过并生成目标后的弹幕', (t) async {
    final api = _api();
    await _spawn(t, api);
    api.pushEvent(const MovaSeek(Duration.zero));
    await t.pump();
    expect(find.text('bullet'), findsNothing);
    api.pushProgress(const MovaProg(position: Duration(seconds: 1)));
    await t.pump();
    expect(find.text('bullet'), findsOneWidget);
    await api.dispose();
  });
}
