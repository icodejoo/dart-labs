import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mova/mova.dart';

import '../support/fake_api.dart';
import '../support/fake_kernel.dart';

/// 记录真实引擎向 HTTP 端口发出的请求。
class _Fetch implements MovaHttpFetch {
  /// master 请求次数。
  int requests = 0;

  /// 只记录请求并返回空结果。
  @override
  Future<Uint8List?> get(Uri url) async {
    requests++;
    return null;
  }

  /// 测试端口没有底层资源。
  @override
  Future<void> close() async {}
}

void main() {
  for (final view in [false, true]) {
    final name = view ? 'MovaView' : 'MovaPlayer';
    testWidgets('F-H $name probeVariants false blocks automatic HTTP but permits explicit probe', (t) async {
      final fetcher = _Fetch();
      const options = MovaOpts(
        abr: MovaAbrConfig(probeVariants: false),
        controls: MovaCtrlsConfig(autoHide: false),
      );
      final engine = MovaEngine(
        kernel: FakeKernel(),
        fetcher: fetcher,
        options: options,
        brightness: MovaFallbackBrightnessPort(),
        pip: MovaNoopPipPort(),
        orientation: MovaNoopOrientationPort(),
      );
      const source = MovaSource('https://h/master.m3u8');
      if (!view) {
        engine.open(source);
        await t.pump();
      }
      await t.pumpWidget(MaterialApp(home: view
          ? MovaView(source: source, options: options, engineFactory: (_) => engine)
          : MovaPlayer(api: engine)));
      await t.pump();
      expect(fetcher.requests, 0);
      await engine.loadQualities();
      expect(fetcher.requests, 1);
      await t.pumpWidget(const SizedBox());
      await t.pump();
      engine.dispose();
      await t.pump();
    });

    for (final autoLoad in [false, true]) {
      testWidgets('F-H $name default probeVariants preserves autoLoadQualities $autoLoad', (t) async {
        final api = FakeMovaApi();
        await t.pumpWidget(MaterialApp(home: view
            ? MovaView(
                source: const MovaSource('https://h/master.m3u8'),
                engineFactory: (_) => api,
                autoLoadQualities: autoLoad,
              )
            : MovaPlayer(api: api, autoLoadQualities: autoLoad)));
        await t.pump();
        expect(api.calls.where((c) => c == 'loadQualities'), hasLength(autoLoad ? 1 : 0));
        await t.pumpWidget(const SizedBox());
        await t.pump();
        await api.dispose();
      });
    }
  }
}
