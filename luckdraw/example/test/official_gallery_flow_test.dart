import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luckdraw/grid.dart';
import 'package:luckdraw/wheel.dart';
import 'package:luckdraw_example/official/official_gallery_page.dart';

/// 官方 JS 里带 start/stop 流程、点击后会停下并结算的示例；其余示例在官方里是纯展示或只转不停。
const Set<String> _settlingIds = {
  'wheel-btn-radius',
  'wheel-btn-pointer',
  'wheel-btn-img',
  'wheel-btn-dom',
  'wheel-default-stopRange',
  'wheel-demo',
  'grid-btn',
  'grid-btn-img',
  'grid-btn-dom',
  'grid-layout-round',
  'grid-demo',
  'slot-demo',
  'more-wheel-zo',
  'more-wheel-pdmm',
  'more-wheel-jd',
  'more-wheel-xc',
  'more-wheel-bili',
  'more-grid-dy',
  'more-grid-wyyx',
  'more-grid-wyyyx',
  'more-grid-xdf',
  'more-grid-xq',
  'more-grid-hwl',
  'more-grid-round',
  'more-grid-yqs',
  'more-slot-didi',
};

/// 舞台在结算后显示的结果文字（转盘/九宫格为“中奖：”，老虎机为“结果：”）。
bool _hasResult() =>
    find.textContaining('中奖：').evaluate().isNotEmpty ||
    find.textContaining('结果：').evaluate().isNotEmpty;

/// 点击开始触发点：先点画布中心（画布内按钮），不出结果再点外部按钮/“开始”文字。
Future<void> _trigger(WidgetTester tester, {required bool external}) async {
  if (!external) {
    final canvas =
        find.byWidgetPredicate((w) => w is LuckyWheel || w is LuckyGrid);
    if (canvas.evaluate().isNotEmpty) {
      await tester.tap(canvas.first, warnIfMissed: false);
    }
    return;
  }
  final button = find.byType(FilledButton);
  final text = find.textContaining('开始');
  if (button.evaluate().isNotEmpty) {
    await tester.tap(button.first, warnIfMissed: false);
  } else if (text.evaluate().isNotEmpty) {
    await tester.tap(text.first, warnIfMissed: false);
  }
}

/// 按官方流程点击开始，期望带结算流程的示例在 10 秒内显示结果，且全程无异常。
void main() {
  testWidgets('官方示例的开始→停止→结算流程', (tester) async {
    tester.view.physicalSize = const Size(1000, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final missed = <String>[];
    var settled = 0;
    for (final section in OfficialGalleryPage.sections) {
      for (final d in section.demos) {
        await tester.pumpWidget(MaterialApp(
            home: Scaffold(
                body: Center(
                    child: SingleChildScrollView(
                        child: Builder(builder: d.builder))))));
        await tester.pump(const Duration(milliseconds: 300));
        await _trigger(tester, external: false);
        for (var i = 0; i < 100 && !_hasResult(); i++) {
          await tester.pump(const Duration(milliseconds: 100));
          if (i == 15) await _trigger(tester, external: true);
        }
        final got = _hasResult();
        expect(tester.takeException(), isNull, reason: d.id);
        if (got) settled++;
        if (got != _settlingIds.contains(d.id)) missed.add(d.id);
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 1));
      }
    }
    expect(missed, isEmpty, reason: '结算行为与官方 JS 不一致的示例');
    expect(settled, _settlingIds.length);
  });
}
