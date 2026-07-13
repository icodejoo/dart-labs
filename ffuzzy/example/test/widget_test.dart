// Smoke test for the ffuzzy demo app: the search field renders and typing
// a query narrows the result list.
//
// ffuzzy demo app 冒烟测试：搜索框能渲染，输入查询能收窄结果列表。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ffuzzy_example/main.dart';

void main() {
  testWidgets('search field narrows results', (WidgetTester tester) async {
    await tester.pumpWidget(const FuzzyDemoApp());
    // TabBarView only builds the active page, so at startup the sole
    // TextField in the tree is the initially-active "搜索模式" tab's shared
    // query box. Several of its cards share the same corpus/query, so a hit
    // can legitimately render in more than one card at once — and each
    // ResultList line renders as "• <item>  (score N)", not the bare item
    // text, hence textContaining() below rather than an exact find.text().
    //
    // TabBarView 只构建当前激活页，所以启动时树里唯一的 TextField 就是默认
    // 激活的"搜索模式" Tab 的共享查询框。它下面好几张卡共用同一个 corpus/
    // 查询，所以同一条命中结果完全可能同时出现在多张卡里；而且 ResultList
    // 每行渲染成 "• <item>  (score N)"，不是纯 item 文本，所以下面用
    // textContaining() 而不是精确匹配的 find.text()。
    final searchField = find.byType(TextField).first;
    expect(searchField, findsOneWidget);

    // Each search runs on a background Isolate (real wall-clock async, not a
    // fake Timer), so runAsync() is needed for the real event loop to make
    // progress. Poll instead of a fixed sleep: resolves in ~1 tick on the fast
    // path, still tolerates a slow CI box up to the outer bound. Each
    // iteration alternates a real-time wait (lets the isolate progress) with
    // a pump (applies the resulting setState to the widget tree).
    //
    // 每次搜索都跑在后台 Isolate 上（真实挂钟时间异步，不是假 Timer），所以需要
    // runAsync() 让真实事件循环继续推进。这里用轮询代替固定 sleep：快路径下约
    // 1 个轮询周期就返回，慢速 CI 机器也能在外层上限内兜住。每轮迭代交替做一次
    // 真实等待（让 isolate 有时间推进）和一次 pump（把结果的 setState 应用到
    // widget 树上）。
    await tester.enterText(searchField, 'readme');
    for (var i = 0; i < 100; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
      if (find.textContaining('README.md').evaluate().isNotEmpty) break;
    }
    await tester.pumpAndSettle();

    expect(find.textContaining('README.md'), findsWidgets);
    expect(find.textContaining('CHANGELOG.md'), findsNothing);
  });
}
