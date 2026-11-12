import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:layerman/layerman.dart';
import 'package:layerman_example/demo_kit/demo_kit.dart';
import 'package:layerman_example/scenarios.dart';
import 'package:layerman_example/widgets/scenario_demo.dart';

/// 将日期和计时器统一到 widget 测试的模拟时间。
class _WidgetClock extends OverlayClock {
  /// 保存测试驱动器。
  const _WidgetClock(this.tester);

  /// 提供模拟日期的驱动器。
  final WidgetTester tester;

  /// 返回随 pump 推进的日期。
  @override
  DateTime now() => tester.binding.clock.now();

  /// 使用当前测试区域的可控计时器。
  @override
  Timer createTimer(Duration duration, void Function() callback) =>
      Timer(duration, callback);
}

/// 挂载单个真实引擎场景，并推进首帧确认。
Future<void> _mount(WidgetTester tester, DemoScenario scenario) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: DemoCard(
          title: scenario.en,
          description: scenario.descriptionEn,
          child: ScenarioDemo(scenario: scenario, clock: _WidgetClock(tester)),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 250));
}

/// 推进后端淡出和引擎间隔，不跳过待测的长计时。
Future<void> _advance(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(demoFade);
  await tester.pump(const Duration(milliseconds: 130));
  await tester.pump();
}

/// 点击唯一的场景操作并推进真实队列。
Future<void> _tap(WidgetTester tester, String label) async {
  await tester.tap(find.text(label).first);
  await _advance(tester);
}

/// 卸载前结束挂载状态，使未完成计时不会泄漏到下一测试。
Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

/// 覆盖每个演示的挂载、重放、真实交互与清理契约。
void main() {
  for (final scenario in DemoScenario.values) {
    testWidgets('${scenario.name} replays without stale timers or state', (
      tester,
    ) async {
      await _mount(tester, scenario);
      expect(find.byTooltip('Replay'), findsOneWidget);
      await tester.tap(find.byTooltip('Replay'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expect(tester.takeException(), isNull);
      await _unmount(tester);
    });
  }

  for (final scenario in [
    DemoScenario.queue,
    DemoScenario.priority,
    DemoScenario.affix,
    DemoScenario.exit,
  ]) {
    testWidgets('${scenario.name} really advances A to B', (tester) async {
      await _mount(tester, scenario);
      expect(find.text('A'), findsOneWidget);
      await _tap(tester, 'Close');
      await tester.pump(const Duration(seconds: 1));
      await _advance(tester);
      expect(find.text('B'), findsOneWidget);
      expect(find.text('C'), findsNothing);
      await _unmount(tester);
    });
  }

  testWidgets('replace ends A permanently and replay restores A', (
    tester,
  ) async {
    await _mount(tester, DemoScenario.replace);
    await _tap(tester, 'Replace with B');
    expect(find.text('A'), findsNothing);
    expect(find.text('B'), findsOneWidget);
    expect(find.textContaining('replaced'), findsOneWidget);
    await _tap(tester, 'Close');
    expect(find.text('A'), findsNothing);
    await tester.tap(find.byTooltip('Replay'));
    await _advance(tester);
    expect(find.text('A'), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets('overlap and independent slots show two previews', (
    tester,
  ) async {
    for (final scenario in [DemoScenario.overlap, DemoScenario.slots]) {
      await _mount(tester, scenario);
      expect(find.text('Close'), findsNWidgets(2));
      await _unmount(tester);
    }
  });

  testWidgets('blockedBy holds overlap until modal has exited', (tester) async {
    await _mount(tester, DemoScenario.blocked);
    expect(find.text('A'), findsOneWidget);
    expect(find.text('B'), findsNothing);
    await _tap(tester, 'Close');
    expect(find.text('B'), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets('delay replay restarts the wait and duration really expires', (
    tester,
  ) async {
    await _mount(tester, DemoScenario.delay);
    expect(find.text('A'), findsNothing);
    await tester.pump(demoWait);
    await _advance(tester);
    expect(find.text('A'), findsOneWidget);
    await tester.tap(find.byTooltip('Replay'));
    await tester.pump();
    expect(find.text('A'), findsNothing);
    await _unmount(tester);
    await _mount(tester, DemoScenario.duration);
    await tester.pump(demoLifetime);
    await _advance(tester);
    expect(find.text('A'), findsNothing);
    expect(find.textContaining('expired'), findsOneWidget);
    await _unmount(tester);
  });

  for (final scenario in [DemoScenario.pauseAll, DemoScenario.pauseOne]) {
    testWidgets('${scenario.name} freezes and resumes remaining duration', (
      tester,
    ) async {
      await _mount(tester, scenario);
      await _tap(
        tester,
        scenario == DemoScenario.pauseAll ? 'Pause' : 'Pause A',
      );
      await tester.pump(const Duration(seconds: 6));
      expect(find.text('A'), findsOneWidget);
      await _tap(
        tester,
        scenario == DemoScenario.pauseAll ? 'Resume' : 'Resume A',
      );
      await tester.pump(const Duration(seconds: 6));
      await _advance(tester);
      expect(find.text('A'), findsNothing);
      await _unmount(tester);
    });
  }

  testWidgets('route, holds and lifecycle keep independent pauses', (
    tester,
  ) async {
    for (final scenario in [
      DemoScenario.routePause,
      DemoScenario.holds,
      DemoScenario.lifecycle,
    ]) {
      await _mount(tester, scenario);
      expect(find.text('A'), findsNothing);
      if (scenario == DemoScenario.holds) {
        await _tap(tester, 'Release one hold');
        expect(find.text('A'), findsNothing);
        await _tap(tester, 'Release one hold');
      } else {
        await _tap(
          tester,
          scenario == DemoScenario.routePause
              ? 'Leave /zone'
              : 'Return to foreground',
        );
      }
      expect(find.text('A'), findsOneWidget);
      await _unmount(tester);
    }
  });

  for (final scenario in [
    DemoScenario.route,
    DemoScenario.routeAny,
    DemoScenario.routeRegex,
    DemoScenario.stay,
  ]) {
    testWidgets('${scenario.name} uses context eligibility', (tester) async {
      await _mount(tester, scenario);
      expect(find.text('A'), findsNothing);
      await _tap(tester, 'Enter promo');
      expect(find.text('A'), findsOneWidget);
      await _tap(tester, 'Leave');
      expect(
        find.text('A'),
        scenario == DemoScenario.stay ? findsOneWidget : findsNothing,
      );
      await _unmount(tester);
    });
  }

  testWidgets('auth and when require context updates', (tester) async {
    await _mount(tester, DemoScenario.auth);
    await _tap(tester, 'Sign in as VIP');
    expect(find.text('A'), findsOneWidget);
    await _tap(tester, 'Sign out');
    expect(find.text('A'), findsNothing);
    await _unmount(tester);
    await _mount(tester, DemoScenario.when);
    await _tap(tester, 'Allow');
    expect(find.text('A'), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets('gate supports early pass, drop and automatic deadline', (
    tester,
  ) async {
    for (final action in ['Allow now', 'Drop', 'wait']) {
      await _mount(tester, DemoScenario.gate);
      if (action == 'wait') {
        await tester.pump(const Duration(seconds: 2));
        await _advance(tester);
      } else {
        await _tap(tester, action);
      }
      expect(find.text('A'), action == 'Drop' ? findsNothing : findsOneWidget);
      if (action == 'Drop') {
        expect(
          tester.widget<Text>(find.byKey(const ValueKey('events'))).data,
          contains('gated'),
        );
      }
      await _unmount(tester);
    }
  });

  testWidgets('session cap and permanent suppression reset on replay', (
    tester,
  ) async {
    for (final scenario in [DemoScenario.session, DemoScenario.suppress]) {
      await _mount(tester, scenario);
      await _tap(
        tester,
        scenario == DemoScenario.session ? 'Close' : 'Never again',
      );
      await _tap(tester, 'Try again');
      expect(find.text('A'), findsNothing);
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('events'))).data,
        contains(scenario == DemoScenario.session ? 'capped' : 'suppressed'),
      );
      await tester.tap(find.byTooltip('Replay'));
      await _advance(tester);
      expect(find.text('A'), findsOneWidget);
      await _unmount(tester);
    }
  });

  testWidgets('total and calendar caps govern repeated submissions', (
    tester,
  ) async {
    for (final scenario in [DemoScenario.total, DemoScenario.calendar]) {
      await _mount(tester, scenario);
      await _tap(tester, 'Close');
      await _tap(tester, 'Try again');
      if (scenario == DemoScenario.total) {
        expect(find.text('A'), findsOneWidget);
        await _tap(tester, 'Close');
        await _tap(tester, 'Try again');
      }
      expect(find.text('A'), findsNothing);
      await _unmount(tester);
    }
  });

  testWidgets('minGap, combined and temporary suppression wake automatically', (
    tester,
  ) async {
    for (final scenario in [
      DemoScenario.minGap,
      DemoScenario.combined,
      DemoScenario.suppress,
    ]) {
      await _mount(tester, scenario);
      await _tap(
        tester,
        scenario == DemoScenario.suppress ? 'Snooze 3s' : 'Close',
      );
      await _tap(tester, 'Try again');
      expect(find.text('A'), findsNothing);
      await tester.pump(demoLifetime);
      await _advance(tester);
      expect(find.text('A'), findsOneWidget);
      await _unmount(tester);
    }
  });

  testWidgets(
    'resolve, null resolve and live data really use engine payloads',
    (tester) async {
      await _mount(tester, DemoScenario.resolve);
      expect(find.textContaining('Resolving 1'), findsOneWidget);
      await tester.pump(demoWait);
      await _advance(tester);
      expect(find.text('A · 42'), findsOneWidget);
      await _unmount(tester);
      await _mount(tester, DemoScenario.resolveNull);
      await _advance(tester);
      expect(find.text('B'), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('events'))).data,
        contains('skipped'),
      );
      await _unmount(tester);
      await _mount(tester, DemoScenario.live);
      await _tap(tester, 'Update +1');
      expect(find.text('A · {n: 1}'), findsOneWidget);
      await tester.tap(find.byTooltip('Replay'));
      await _advance(tester);
      expect(find.text('A · {n: 0}'), findsOneWidget);
      await _unmount(tester);
    },
  );

  testWidgets('guard blocks close and ticket returns a typed value', (
    tester,
  ) async {
    await _mount(tester, DemoScenario.guard);
    await _tap(tester, 'Close');
    expect(find.text('A'), findsOneWidget);
    await _tap(tester, 'Unlock');
    await _tap(tester, 'Close');
    expect(find.text('A'), findsNothing);
    await _unmount(tester);
    await _mount(tester, DemoScenario.result);
    await _tap(tester, 'Close');
    expect(find.text('Returned: ok'), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets(
    'tag cleanup leaves untagged entry and queue expiry is observable',
    (tester) async {
      await _mount(tester, DemoScenario.tags);
      await _tap(tester, 'Clear promo');
      expect(find.text('C'), findsOneWidget);
      expect(find.text('A'), findsNothing);
      expect(find.text('B'), findsNothing);
      await _unmount(tester);
      await _mount(tester, DemoScenario.expiry);
      await tester.pump(demoWait);
      expect(find.textContaining('queueExpired'), findsOneWidget);
      await _unmount(tester);
    },
  );

  testWidgets('dismiss timeout releases engine but owner cleans the old view', (
    tester,
  ) async {
    await _mount(tester, DemoScenario.timeout);
    await _tap(tester, 'Close');
    await tester.pump(demoWait);
    expect(tester.takeException(), isA<TimeoutException>());
    await _advance(tester);
    expect(find.text('B'), findsOneWidget);
    expect(find.text('A'), findsOneWidget);
    await _tap(tester, 'Clean up view');
    expect(find.text('A'), findsNothing);
    await _unmount(tester);
  });
}
