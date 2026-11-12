import 'package:countman/countman.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 构建期写入的运行状态必须推迟到帧末通知，监听者放在组件前后都不能触发构建期 setState 断言。
void main() {
  tearDown(Countman.destroy);

  for (final listenerFirst in [true, false]) {
    testWidgets('监听者在${listenerFirst ? '前' : '后'}时挂载不断言且最终状态正确',
        (tester) async {
      final c = CountdownController();
      final seen = <CountmanRunState>[];
      final listener = ValueListenableBuilder<CountmanRunState>(
        valueListenable: c.runStateListenable,
        builder: (_, state, __) {
          seen.add(state);
          return Text('$state');
        },
      );
      await tester.pumpWidget(MaterialApp(
        home: Column(children: [
          if (listenerFirst) listener,
          TextCountdown(to: const Duration(seconds: 5), controller: c),
          if (!listenerFirst) listener,
        ]),
      ));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(c.runState, CountmanRunState.running);
      expect(seen.last, CountmanRunState.running);
      expect(find.text('${CountmanRunState.running}'), findsOneWidget);
    });
  }
}
