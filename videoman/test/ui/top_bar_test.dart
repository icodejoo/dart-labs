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

  // NOTE: VmApi exposes no synchronous "is PiP supported" getter (VmPipPort
  // .isSupported() is async and not surfaced on VmApi at all), so this
  // component cannot decide visibility from `FakeVmApi.pipSupported` (which
  // only controls what `enterPip()` resolves to). Per the task brief's
  // documented fallback, the button always shows; unsupported platforms rely
  // on `enterPip()` resolving to `false`/no-op at runtime. See the task
  // report for details.
  //
  // 说明：VmApi 未暴露同步的"是否支持画中画"getter（VmPipPort.isSupported()
  // 是异步的，且未在 VmApi 上暴露），因此本组件无法根据
  // `FakeVmApi.pipSupported`（其真实含义只是 `enterPip()` 的返回值）来决定
  // 可见性。按任务简报中记录的兜底方案，该按钮始终显示；不支持的平台依赖
  // `enterPip()` 在运行时返回 `false`/静默无效果。详见任务报告。
  testWidgets('pip button always shows (no sync capability check on VmApi)', (t) async {
    final api = FakeVmApi()..pipSupported = false;
    await pumpComponent(t, api, TopBarComponent());
    expect(find.byIcon(Icons.picture_in_picture_alt_rounded), findsOneWidget);
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

    api.source = const VmSource('https://host/video.mp4', title: 'My Video');
    api.push(api.state.copyWith(type: VmStreamType.live));
    await t.pumpAndSettle();
    expect(find.text('My Video'), findsOneWidget);
    await api.dispose();
  });
}
