import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mova/mova.dart';
import '../support/fake_api.dart';

/// 页面状态须随浏览窗口回收，而非跟随整个 Feed 生命周期增长。
void main() {
  testWidgets('连续翻页后请求标记和点赞 notifier 有界，回收与卸载不访问已销毁状态', (t) async {
    var loads = 0;
    await t.pumpWidget(
      MaterialApp(
        home: MovaFeedPlayer(
          engineFactory: FakeMovaApi.new,
          prefetchDepth: 0,
          loader: (i) async {
            loads++;
            return MovaFeedItem(
              source: MovaSource('$i'),
              authorName: 'author$i',
            );
          },
        ),
      ),
    );
    await t.pumpAndSettle();
    final dynamic state = t.state(find.byType(MovaFeedPlayer));
    for (var i = 1; i <= 60; i++) {
      t.widget<PageView>(find.byType(PageView)).controller!.jumpToPage(i);
      await t.pumpAndSettle();
      expect(state.debugPageStateCount as int, lessThanOrEqualTo(14));
      expect(t.takeException(), isNull);
    }
    expect(loads, greaterThan(50));
    t.widget<PageView>(find.byType(PageView)).controller!.jumpToPage(0);
    await t.pumpAndSettle();
    expect(find.text('@author0'), findsOneWidget);
    await t.pumpWidget(const SizedBox.shrink());
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  });
}
