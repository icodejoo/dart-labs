import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luckdraw_example/official/official_gallery_page.dart';

/// 画廊冒烟：每个分区的每个示例都能独立构建、渲染并随后卸载，且无异常。
void main() {
  for (final section in OfficialGalleryPage.sections) {
    testWidgets('${section.title} 全部示例可渲染', (tester) async {
      tester.view.physicalSize = const Size(1000, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      expect(section.demos, isNotEmpty);
      for (final d in section.demos) {
        await tester.pumpWidget(MaterialApp(
            home: Scaffold(body: Center(child: Builder(builder: d.builder)))));
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.takeException(), isNull, reason: d.id);
        await tester.pumpWidget(const SizedBox());
      }
    });
  }

  testWidgets('画廊页四个分区标签与条目数', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: OfficialGalleryPage()));
    await tester.pump();
    final counts = OfficialGalleryPage.sections.map((s) => s.demos.length);
    expect(counts, [19, 25, 17, 15]);
  });
}
