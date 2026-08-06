import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mova/src/core/model/source.dart';
import 'package:mova/src/core/options/options.dart';
import 'package:mova/src/core/state/state.dart';
import 'package:mova/src/ui/components/bottom_bar.dart';

import '../support/fake_api.dart';
import '../support/pump.dart';

/// A live state at the edge of a 300-second DVR window.
///
/// 处于 300 秒 DVR 窗口边缘的直播状态。
const _atEdge = MovaState(
  type: MovaStreamType.live,
  liveSeekable: true,
  seekableWindow: Duration(seconds: 300),
);

/// The same window, but replaying 65 seconds behind the edge.
///
/// 同一窗口，但正在回看落后边缘 65 秒的内容。
const _behind = MovaState(
  type: MovaStreamType.live,
  liveSeekable: true,
  seekableWindow: Duration(seconds: 300),
  timeshiftBehind: Duration(seconds: 65),
);

void main() {
  testWidgets('a non-seekable live bar shows the LIVE badge and no seek bar', (t) async {
    final api = FakeMovaApi();
    api.push(const MovaState(type: MovaStreamType.live));
    await pumpComponent(t, api, BottomBarComponent());
    expect(find.text('LIVE'), findsOneWidget);
    expect(find.byType(Slider), findsNothing);
    await api.dispose();
  });

  testWidgets('a seekable live bar shows the seek bar', (t) async {
    final api = FakeMovaApi();
    api.push(_atEdge);
    await pumpComponent(t, api, BottomBarComponent());
    expect(find.byType(Slider), findsOneWidget);
    await api.dispose();
  });

  testWidgets('the badge reads LIVE at the edge and 时移 while replaying', (t) async {
    final api = FakeMovaApi();
    api.push(_atEdge);
    await pumpComponent(t, api, BottomBarComponent());
    expect(find.text('LIVE'), findsOneWidget);
    api.push(_behind);
    await t.pump();
    await t.pump();
    expect(find.text('LIVE'), findsNothing);
    expect(find.text('时移'), findsOneWidget);
    await api.dispose();
  });

  testWidgets('the timeshift label shows the lag and hides at the edge', (t) async {
    final api = FakeMovaApi();
    api.push(_behind);
    await pumpComponent(t, api, BottomBarComponent());
    expect(find.text('-01:05'), findsOneWidget);
    api.push(_atEdge);
    await t.pump();
    await t.pump();
    expect(find.text('-01:05'), findsNothing);
    await api.dispose();
  });

  testWidgets('the back-to-live button calls backToLiveEdge, not reload', (t) async {
    final api = FakeMovaApi();
    api.push(_behind);
    await pumpComponent(t, api, BottomBarComponent());
    await t.tap(find.byIcon(Icons.sync_rounded));
    await t.pump();
    expect(api.calls, contains('backToLiveEdge'));
    expect(api.calls, isNot(contains('reload')));
    await api.dispose();
  });

  testWidgets('replacing MovaStrs relabels the badge without touching components', (t) async {
    final api = FakeMovaApi(
      options: const MovaOpts(strings: MovaStrs(live: 'ON AIR')),
    );
    api.push(_atEdge);
    await pumpComponent(t, api, BottomBarComponent());
    expect(find.text('ON AIR'), findsOneWidget);
    await api.dispose();
  });

  testWidgets('the live seek bar spans the DVR window, not the duration', (t) async {
    final api = FakeMovaApi();
    api.push(_atEdge);
    await pumpComponent(t, api, BottomBarComponent());
    final slider = t.widget<Slider>(find.byType(Slider));
    expect(slider.max, 300000.0);
    await api.dispose();
  });
}
