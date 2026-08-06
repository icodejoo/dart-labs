import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mova/src/core/state/state.dart';
import 'package:mova/src/ui/scope/scope.dart';
import 'package:mova/src/ui/scope/selector.dart';

import '../support/fake_api.dart';

void main() {
  testWidgets('MovaSelect rebuilds only when the picked field changes', (t) async {
    final api = FakeMovaApi();
    var builds = 0;
    await t.pumpWidget(MaterialApp(
      home: MovaScope(
        api: api,
        child: MovaSelect<bool>(
          selector: (s) => s.playing,
          builder: (c, playing) {
            builds++;
            return Text('$playing');
          },
        ),
      ),
    ));
    await t.pump();
    final base = builds;

    // FakeMovaApi's states stream is backed by a plain (non-`sync`)
    // broadcast StreamController, so a pushed value is only delivered to
    // listeners on a later microtask. AutomatedTestWidgetsFlutterBinding's
    // `pump()` checks `hasScheduledFrame` *before* flushing that
    // microtask, so the rebuild triggered by a push always lands one pump
    // after the push that caused it — hence two pumps per push below.
    //
    // FakeMovaApi 的 states 流由一个普通（非 `sync`）广播 StreamController
    // 支撑，推送的值只会在之后的某个微任务里送达监听者。
    // AutomatedTestWidgetsFlutterBinding 的 `pump()` 在刷新该微任务*之前*
    // 就检查了 `hasScheduledFrame`，所以由某次推送触发的重建总会落在触发它
    // 的那次 pump 之后一拍——因此下面每次推送要跟两次 pump。
    api.push(const MovaState(volume: 50)); // 无关字段
    await t.pump();
    await t.pump();
    expect(builds, base);

    api.push(const MovaState(volume: 50, playing: true));
    await t.pump();
    await t.pump();
    expect(builds, base + 1);
    expect(find.text('true'), findsOneWidget);
    await api.dispose();
  });

  testWidgets('MovaScope.of throws a readable error outside a scope', (t) async {
    await t.pumpWidget(Builder(builder: (c) {
      expect(() => MovaScope.of(c), throwsA(isA<FlutterError>()));
      return const SizedBox();
    }));
  });
}
