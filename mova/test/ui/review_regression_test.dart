import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mova/src/core/engine.dart';
import 'package:mova/src/core/guard/auto_pause.dart';
import 'package:mova/src/core/interceptor/interceptor.dart';
import 'package:mova/src/core/model/source.dart';
import 'package:mova/src/core/options/options.dart';
import 'package:mova/src/core/state/state.dart';
import 'package:mova/src/ui/guard/auto_pause.dart';
import 'package:mova/src/ui/skins/minimal_skin.dart';
import 'package:mova/src/ui/view.dart';

import '../support/fake_api.dart';
import '../support/fake_kernel.dart';

/// Delays acceptance before the engine has opened anything.
///
/// 在引擎打开任何内容前延迟接受请求。
class _OpenHook extends MovaHook {
  final gate = Completer<bool>();
  @override
  Future<bool> beforeOpen(MovaSource source) => gate.future;
}

/// Counts quality probes while using the real engine load path.
///
/// 使用真实引擎加载路径并统计档位探测。
class _Engine extends MovaEngine {
  _Engine(FakeKernel k, _OpenHook hook)
    : super(
        kernel: k,
        interceptors: [hook],
        options: const MovaOpts(controls: MovaCtrlsConfig(autoHide: false)),
      );
  int probes = 0;
  @override
  Future<void> loadQualities() async {
    probes++;
  }
}

/// Simulates a live reload that can finish after another visibility change.
///
/// 模拟可能晚于另一次可见性变化完成的直播重载。
class _SlowEdge extends FakeMovaApi {
  final gate = Completer<void>();
  @override
  Future<void> backToLiveEdge() async {
    calls.add('backToLiveEdge');
    await gate.future;
    push(state.copyWith(playing: true));
  }
}

/// Builds the same guarded child with variable visibility and configuration.
///
/// 构建可变可见性与配置的同一守卫子组件。
Widget _guard(
  FakeMovaApi api,
  bool visible, {
  MovaAutoPauseConfig config = const MovaAutoPauseConfig(),
}) => MaterialApp(
  home: TickerMode(
    enabled: visible,
    child: MovaAutoPause(
      api: api,
      config: config,
      child: const SizedBox(height: 100),
    ),
  ),
);

void main() {
  testWidgets(
    '#2 hidden MovaView pauses asynchronous open and resumes on show',
    (t) async {
      final k = FakeKernel();
      final hook = _OpenHook();
      final e = _Engine(k, hook);
      Widget app(bool visible) => MaterialApp(
        home: TickerMode(
          enabled: visible,
          child: MovaView(
            source: const MovaSource('https://h/a.mp4'),
            engineFactory: (_) => e,
            skin: const MovaMinimalSkin(),
            autoPause: const MovaAutoPauseConfig(),
          ),
        ),
      );
      await t.pumpWidget(app(false));
      hook.gate.complete(true);
      await t.pump();
      await t.pump();
      expect(e.state.playbackIntent, isFalse);
      expect(k.calls, contains('pause'));
      await t.pumpWidget(app(true));
      await t.pump();
      expect(e.state.playbackIntent, isTrue);
      expect(k.calls.last, 'play');
      await t.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    '#2 hidden guard rebinds engines and pauses after mini exemption ends',
    (t) async {
      final old = FakeMovaApi();
      final next = FakeMovaApi()
        ..push(const MovaState(playbackIntent: true, mini: true));
      await t.pumpWidget(_guard(old, false));
      await t.pumpWidget(_guard(next, false));
      expect(next.calls, isNot(contains('pause')));
      old.push(const MovaState(playing: true));
      next.push(const MovaState(playbackIntent: true));
      await t.pump();
      expect(next.calls, contains('pause'));
      expect(old.calls, isEmpty);
      await t.pumpWidget(_guard(next, true));
      await t.pump();
      expect(next.calls, contains('play'));
    },
  );

  testWidgets(
    '#3 source null invalidates delayed beforeOpen and skips quality probe',
    (t) async {
      final k = FakeKernel();
      final hook = _OpenHook();
      final e = _Engine(k, hook);
      Widget app(MovaSource? source) => MaterialApp(
        home: MovaView(
          source: source,
          engineFactory: (_) => e,
          skin: const MovaMinimalSkin(),
        ),
      );
      await t.pumpWidget(app(const MovaSource('https://h/a.m3u8')));
      await t.pumpWidget(app(null));
      final pauses = k.calls.where((v) => v == 'pause').length;
      hook.gate.complete(true);
      await t.pump();
      await t.pump();
      expect(e.state.playbackIntent, isFalse);
      expect(k.calls.where((v) => v == 'pause').length, greaterThan(pauses));
      expect(e.probes, 0);
      await t.pumpWidget(const SizedBox());
    },
  );

  for (final swap in [false, true]) {
    testWidgets(
      '#5 delayed live resume checks ${swap ? "api replacement" : "hidden generation"}',
      (t) async {
        const config = MovaAutoPauseConfig(liveResumeGrace: Duration.zero);
        final api = _SlowEdge()
          ..push(const MovaState(playing: true, type: MovaStreamType.live));
        await t.pumpWidget(_guard(api, true, config: config));
        await t.pumpWidget(_guard(api, false, config: config));
        api.push(api.state.copyWith(playing: false));
        await t.pump(const Duration(seconds: 4));
        await t.pumpWidget(_guard(api, true, config: config));
        expect(api.calls, contains('backToLiveEdge'));
        if (swap) {
          await t.pumpWidget(_guard(FakeMovaApi(), true));
        } else {
          await t.pumpWidget(_guard(api, false, config: config));
        }
        final pauses = api.calls.where((v) => v == 'pause').length;
        api.gate.complete();
        await t.pump();
        await t.pump();
        expect(api.calls, isNot(contains('play')));
        expect(
          api.calls.where((v) => v == 'pause').length,
          greaterThan(pauses),
        );
      },
    );
  }

  test('#10 gate config update preserves original hidden timestamp', () {
    final g = MovaAutoPauseGate(const MovaAutoPauseConfig());
    final start = DateTime(2026, 10, 23);
    g.update(
      MovaHideReason.tickerOff,
      true,
      playing: true,
      live: true,
      exempt: false,
      now: start,
    );
    g.reconfigure(
      const MovaAutoPauseConfig(minVisibleFraction: .5),
      playing: false,
      live: true,
      exempt: false,
      now: start.add(const Duration(seconds: 4)),
    );
    expect(
      g.update(
        MovaHideReason.tickerOff,
        false,
        playing: false,
        live: true,
        exempt: false,
        now: start.add(const Duration(seconds: 4)),
      ),
      MovaGuardAction.reloadEdge,
    );
  });

  testWidgets(
    '#10 config update preserves hidden intent and original grace start',
    (t) async {
      final api = FakeMovaApi()
        ..push(const MovaState(playing: true, type: MovaStreamType.live));
      await t.pumpWidget(_guard(api, true));
      await t.pumpWidget(_guard(api, false));
      api.push(api.state.copyWith(playing: false));
      await t.pump(const Duration(seconds: 4));
      const next = MovaAutoPauseConfig(
        minVisibleFraction: .5,
        liveResumeGrace: Duration.zero,
      );
      await t.pumpWidget(_guard(api, false, config: next));
      await t.pumpWidget(_guard(api, true, config: next));
      await t.pump();
      expect(api.calls, contains('backToLiveEdge'));
      expect(api.calls, contains('play'));
    },
  );
}
