import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mova/mova.dart';
import '../../test/support/fake_api.dart';
import 'package:mova_example/verify_auto/cp3_pages_auto.dart';
import 'package:mova_example/verify_auto/cp3_harness.dart';
import 'package:mova_example/verify_auto/s00d_receipt.dart';

void main() {
  test('回执只比较事件相关字段，保留真正载荷差异', () async {
    final api = FakeMovaApi();
    final checks = <Map<String, Object?>>[];
    final audit = ReceiptAudit(api, (_, data) => checks.add(data));
    api.push(api.state.copyWith(duration: const Duration(seconds: 100)));
    // 状态订阅尚未交付，但无关时长变化不能让倍速事件失败。
    audit.receive(const MovaRateChange(1));
    expect(checks.last['pass'], isTrue);
    audit.receive(const MovaRateChange(2));
    expect(checks.last['pass'], isFalse);
    expect(checks.last['differences'], ['rate']);
    // progress 订阅尚未交付不是 state 载荷错误，也不能据此声明原生已落地。
    audit.receive(const MovaSeeked(Duration(seconds: 5)));
    expect(checks.last['pass'], isTrue);
    expect((checks.last['seekReceipt'] as Map)['lastProgressMs'], 0);
    expect((checks.last['seekReceipt'] as Map)['landingVerified'], isFalse);
    audit.receive(const MovaSizeChange(640, 360));
    expect(checks.last['pass'], isFalse);
    expect(checks.last['differences'], ['width', 'height']);
    await audit.dispose();
    await api.dispose();
  });
  test('all CP3 scripts compile as independent entry contracts', () {
    final scripts = <Cp3Script>[
      runFullscreen,
      runTheme,
      runHeaders,
      runFeedplayer,
      runC04chrome,
      runCp1gap,
    ];
    expect(scripts.length, 6);
  });
  testWidgets('style rebuild preserves pending hide and dragging gates timer', (
    t,
  ) async {
    final api = FakeMovaApi();
    final chrome = MovaChrome();
    Widget page(int color) => MaterialApp(
      home: Scaffold(
        body: MovaPlayer(
          api: api,
          chrome: chrome,
          surface: const SizedBox(),
          style: MovaPlayerStyle(
            theme: MovaTheme(accentColor: color),
            controls: const MovaCtrlsConfig(
              autoHideDelay: Duration(milliseconds: 600),
            ),
          ),
        ),
      ),
    );
    await t.pumpWidget(page(0xff00ff00));
    chrome.show();
    await t.pump(const Duration(milliseconds: 300));
    await t.pumpWidget(page(0xffff0000));
    await t.pump(const Duration(milliseconds: 350));
    expect(chrome.value.controlsVisible, isFalse);
    chrome.setDragging(true);
    await t.pump(const Duration(seconds: 2));
    expect(chrome.value.controlsVisible, isTrue);
    chrome.setDragging(false);
    await t.pump(const Duration(milliseconds: 650));
    expect(chrome.value.controlsVisible, isFalse);
    await t.pumpWidget(const SizedBox());
    chrome.dispose();
    await api.dispose();
  });
}
