import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:videoman/src/core/model/fit.dart';
import 'package:videoman/src/core/model/source.dart';
import 'package:videoman/src/core/options/options.dart';
import 'package:videoman/src/core/state/state.dart';
import 'package:videoman/src/ui/components/top_bar.dart';

import '../support/fake_api.dart';
import '../support/pump.dart';

void main() {
  testWidgets('fit button cycles the fill mode and shows the configured label', (t) async {
    final api = FakeVmApi();
    await pumpComponent(t, api, TopBarComponent());
    expect(find.text('适应'), findsOneWidget);
    await t.tap(find.byIcon(Icons.aspect_ratio_rounded));
    await t.pump();
    expect(api.calls, contains('setFit'));
    expect(api.lastFit, VmFit.cover);
    await api.dispose();
  });

  testWidgets('pip button is hidden when the platform reports no pip support', (t) async {
    final api = FakeVmApi()..pipSupported = false;
    await pumpComponent(t, api, TopBarComponent());
    expect(find.byIcon(Icons.picture_in_picture_alt_rounded), findsNothing);
    await api.dispose();
  });

  testWidgets('pip button shows and enters pip when supported', (t) async {
    final api = FakeVmApi()..pipSupported = true;
    await pumpComponent(t, api, TopBarComponent());
    await t.tap(find.byIcon(Icons.picture_in_picture_alt_rounded));
    await t.pump();
    expect(api.calls, contains('enterPip'));
    await api.dispose();
  });

  testWidgets('quality button is hidden when there are no variants', (t) async {
    final api = FakeVmApi();
    api.push(const VmState());
    await pumpComponent(t, api, TopBarComponent());
    expect(find.byIcon(Icons.high_quality_rounded), findsNothing);
    await api.dispose();
  });

  testWidgets('replacing VmStrings changes the fit label without touching components', (t) async {
    final api = FakeVmApi(options: const VmOptions(strings: VmStrings(fitContain: 'Fit')));
    await pumpComponent(t, api, TopBarComponent());
    expect(find.text('Fit'), findsOneWidget);
    await api.dispose();
  });

  testWidgets('title shows the current source title, empty when none', (t) async {
    final api = FakeVmApi();
    await pumpComponent(t, api, TopBarComponent());
    expect(find.text(''), findsOneWidget);

    await api.open(const VmSource('https://host/video.mp4', title: 'My Video'));
    await t.pumpAndSettle();
    expect(find.text('My Video'), findsOneWidget);
    await api.dispose();
  });

  // Regression: re-opening a *different* source of the SAME VmStreamType
  // (VOD -> VOD here) must still update the shown title. Round-1 of this
  // fix piggybacked reactivity on VmState.type, which does not change in
  // this case, so the title stayed stuck on the first source — this test
  // exercises exactly that same-type re-open path.
  //
  // 回归测试：重新打开同一 VmStreamType（此处为点播 -> 点播）的另一个源时，
  // 展示的标题也必须更新。本修复第一轮曾把响应式重建挂在 VmState.type 上，
  // 而这种情况下 type 不会变化，导致标题停留在第一个源上——本测试专门覆盖
  // 这种同类型重开的路径。
  testWidgets('title updates when re-opening a different source of the same stream type', (t) async {
    final api = FakeVmApi();
    await api.open(const VmSource('https://host/a.mp4', title: 'A'));
    await pumpComponent(t, api, TopBarComponent());
    expect(find.text('A'), findsOneWidget);
    expect(api.state.type, VmStreamType.vod);

    await api.open(const VmSource('https://host/b.mp4', title: 'B'));
    expect(api.state.type, VmStreamType.vod);
    await t.pumpAndSettle();
    expect(find.text('B'), findsOneWidget);
    expect(find.text('A'), findsNothing);
    await api.dispose();
  });
}
