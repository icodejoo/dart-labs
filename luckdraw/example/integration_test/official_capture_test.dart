import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:luckdraw_example/official/official_gallery_page.dart';

/// 真实桌面引擎逐项截图，输出到环境变量 OFFICIAL_OUT 指定的目录，文件名为 `refAsset.png`。
///
/// 用于与 assets/official_ref/ 的官方截图并排对照；未设置 OFFICIAL_OUT 时跳过，
/// 例如 `$env:OFFICIAL_OUT='D:\out'; dart run tool/run_integration.dart --repeat=1 --file=official_capture_test.dart`。
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final out = Platform.environment['OFFICIAL_OUT'];
  testWidgets('截取全部官方对照示例', (tester) async {
    Directory(out!).createSync(recursive: true);
    final key = GlobalKey();
    for (final section in OfficialGalleryPage.sections) {
      for (final d in section.demos) {
        await tester.pumpWidget(MaterialApp(
            debugShowCheckedModeBanner: false,
            home: Scaffold(
                backgroundColor: Colors.white,
                body: Center(
                    child: SingleChildScrollView(
                        child: RepaintBoundary(
                            key: key,
                            child: Container(
                                color: Colors.white,
                                padding: const EdgeInsets.all(8),
                                child: Builder(builder: d.builder))))))));
        // 等图片解码并落到画布上。
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 300)));
        await tester.pump(const Duration(milliseconds: 50));
        await tester.runAsync(() async {
          final boundary =
              key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final image = await boundary.toImage(pixelRatio: 2);
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          File('$out/${d.refAsset}.png')
              .writeAsBytesSync(data!.buffer.asUint8List());
        });
        await tester.pumpWidget(const SizedBox());
      }
    }
  }, skip: out == null);
}
