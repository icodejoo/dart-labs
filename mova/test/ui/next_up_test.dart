import 'package:flutter_test/flutter_test.dart';
import 'package:mova/src/core/model/playlist.dart';
import 'package:mova/src/core/model/source.dart';
import 'package:mova/src/core/options/options.dart';
import 'package:mova/src/core/playlist/playlist_controller.dart';
import 'package:mova/src/core/state/progress.dart';
import 'package:mova/src/ui/components/next_up.dart';

import '../support/fake_api.dart';
import '../support/pump.dart';

/// A two-item playlist for the next-up card tests.
///
/// 下一集卡片测试用的两集播放列表。
const _items = [
  MovaPlistItem(source: MovaSource('https://host/e1.mp4'), title: 'E1'),
  MovaPlistItem(source: MovaSource('https://host/e2.mp4'), title: 'E2'),
];

void main() {
  /// Builds a fake API with the playlist enabled (or not) plus a controller.
  ///
  /// 构造一个启用（或不启用）播放列表的假 API 及其控制器。
  (FakeMovaApi, MovaPlistCtrl) build({bool enabled = true}) {
    final api = FakeMovaApi(
      options: MovaOpts(
        playlist: MovaPlistConfig(enabled: enabled, items: _items),
      ),
    );
    return (api, MovaPlistCtrl(api));
  }

  /// Sets the fake's duration, pushes a progress tick at [position], and pumps
  /// twice so the stream event is delivered and the resulting rebuild settles.
  ///
  /// 设置假对象的时长、在 [position] 推送一次进度 tick，并 pump 两次，使流事件
  /// 送达并让由此触发的重建收敛。
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

  testWidgets('renders nothing when the playlist is disabled', (t) async {
    final (api, c) = build(enabled: false);
    await pumpComponent(t, api, NextUpComponent(c));
    await tick(t, api, const Duration(seconds: 55), const Duration(seconds: 60));
    expect(find.text('即将播放'), findsNothing);
    await api.dispose();
  });

  testWidgets('stays hidden while far from the end', (t) async {
    final (api, c) = build();
    await pumpComponent(t, api, NextUpComponent(c));
    await tick(t, api, const Duration(seconds: 10), const Duration(seconds: 60));
    expect(find.text('即将播放'), findsNothing);
    await api.dispose();
  });

  testWidgets('shows the next item once within the lead window', (t) async {
    final (api, c) = build();
    await pumpComponent(t, api, NextUpComponent(c));
    await tick(t, api, const Duration(seconds: 55), const Duration(seconds: 60));
    expect(find.text('即将播放'), findsOneWidget);
    expect(find.text('E2'), findsOneWidget);
    await api.dispose();
  });

  testWidgets('play-now opens the next source', (t) async {
    final (api, c) = build();
    await pumpComponent(t, api, NextUpComponent(c));
    await tick(t, api, const Duration(seconds: 55), const Duration(seconds: 60));
    await t.tap(find.text('立即播放'));
    await t.pump();
    expect(c.currentIndex, 1);
    expect(api.source?.uri, 'https://host/e2.mp4');
    await api.dispose();
  });

  testWidgets('cancel dismisses the card for the current item', (t) async {
    final (api, c) = build();
    await pumpComponent(t, api, NextUpComponent(c));
    await tick(t, api, const Duration(seconds: 55), const Duration(seconds: 60));
    await t.tap(find.text('取消'));
    await t.pump();
    expect(find.text('即将播放'), findsNothing);
    // A further tick in-window must not resurrect it.
    await tick(t, api, const Duration(seconds: 56), const Duration(seconds: 60));
    expect(find.text('即将播放'), findsNothing);
    await api.dispose();
  });
}
