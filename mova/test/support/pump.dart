import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mova/src/core/api.dart';
import 'package:mova/src/ui/scope/scope.dart';
import 'package:mova/src/ui/slots/component.dart';
import 'package:mova/src/ui/slots/tree.dart';

/// Pumps [component] (with its children built) inside a full-viewport [MovaScope].
///
/// 把 [component]（含其子组件）铺满视窗地挂在 [MovaScope] 里 pump 出来。
///
/// - [tester]: the widget tester / WidgetTester 实例
/// - [api]: capability surface injected into the scope / 注入 scope 的能力面
/// - [component]: component under test / 被测组件
Future<void> pumpComponent(
  WidgetTester tester,
  MovaApi api,
  MovaComp component,
) async {
  await tester.pumpWidget(MaterialApp(
    home: MovaScope(
      api: api,
      child: Builder(builder: (c) {
        final bundle = buildSlots(c, api, [component]);
        return SizedBox.expand(
          child: Stack(children: bundle[component.slot]),
        );
      }),
    ),
  ));
  await tester.pump();
}
