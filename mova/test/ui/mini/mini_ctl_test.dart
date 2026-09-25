import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mova/src/core/api.dart';
import 'package:mova/src/core/mini/placement.dart';
import 'package:mova/src/core/options/options.dart';
import 'package:mova/src/ui/mini/mini_ctl.dart';
import 'package:mova/src/ui/mini/mini_window.dart';

import '../../support/fake_api.dart';

const _enabledOpts = MovaOpts(mini: MovaMiniConfig(enabled: true));

void main() {
  late MovaMiniController ctl;

  setUp(() {
    ctl = MovaMiniController();
  });

  test('show(api) sets mount to persistent, notifies once, calls setMini(true), inserts no entry', () async {
    final api = FakeMovaApi(options: _enabledOpts);
    var notified = 0;
    ctl.addListener(() => notified++);
    await ctl.show(api);
    expect(ctl.api, same(api));
    expect(ctl.mount, MovaMiniMount.persistent);
    expect(notified, 1);
    expect(api.lastMini, isTrue);
  });

  testWidgets('showInPage(context, api) sets mount to page and inserts exactly one entry', (tester) async {
    final api = FakeMovaApi(options: _enabledOpts);
    late BuildContext capturedContext;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) {
        capturedContext = context;
        return const SizedBox();
      }),
    ));
    await ctl.showInPage(capturedContext, api);
    await tester.pump();
    expect(ctl.mount, MovaMiniMount.page);
    expect(api.lastMini, isTrue);
    expect(find.byType(MovaMiniWindow), findsOneWidget);
  });

  testWidgets('showInPage then hide() detaches the entry; calling hide() again does not throw', (tester) async {
    final api = FakeMovaApi(options: _enabledOpts);
    late BuildContext capturedContext;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) {
        capturedContext = context;
        return const SizedBox();
      }),
    ));
    await ctl.showInPage(capturedContext, api);
    await tester.pump();
    await ctl.hide();
    await tester.pump();
    expect(ctl.mount, MovaMiniMount.none);
    expect(() => ctl.hide(), returnsNormally);
  });

  testWidgets('hide() after the hosting Overlay was destroyed (page popped) does not throw', (tester) async {
    final api = FakeMovaApi(options: _enabledOpts);
    final navKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navKey,
      home: Builder(builder: (context) {
        return ElevatedButton(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (inner) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                ctl.showInPage(inner, api);
              });
              return const SizedBox();
            },
          )),
          child: const Text('go'),
        );
      }),
    ));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(ctl.mount, MovaMiniMount.page);

    navKey.currentState!.pop();
    await tester.pumpAndSettle();

    expect(() => ctl.hide(), returnsNormally);
  });

  test('show() with the same api twice only notifies once and does not repeat setMini', () async {
    final api = FakeMovaApi(options: _enabledOpts);
    await ctl.show(api);
    api.calls.clear();
    var notified = 0;
    ctl.addListener(() => notified++);
    await ctl.show(api);
    expect(notified, 0);
    expect(api.calls, isEmpty);
  });

  test('show() with a different api flips setMini(false) on the old one, never disposes it', () async {
    final a = FakeMovaApi(options: _enabledOpts);
    final b = FakeMovaApi(options: _enabledOpts);
    await ctl.show(a);
    await ctl.show(b);
    expect(a.lastMini, isFalse);
    expect(b.lastMini, isTrue);
    expect(a.disposed, isFalse);
  });

  test('hide() clears api, flips setMini(false), does not call pause()', () async {
    final api = FakeMovaApi(options: _enabledOpts);
    await ctl.show(api);
    api.calls.clear();
    await ctl.hide();
    expect(ctl.api, isNull);
    expect(api.lastMini, isFalse);
    expect(api.calls, isNot(contains('pause')));
  });

  test('close() pauses, flips setMini(false), calls onClosed with the api, never disposes it', () async {
    final api = FakeMovaApi(options: _enabledOpts);
    MovaApi? closed;
    ctl.onClosed = (a) => closed = a;
    await ctl.show(api);
    await ctl.close();
    expect(api.calls, contains('pause'));
    expect(api.lastMini, isFalse);
    expect(closed, same(api));
    expect(api.disposed, isFalse);
  });

  test('isShowing uses identity, not equality', () async {
    final api = FakeMovaApi(options: _enabledOpts);
    final other = FakeMovaApi(options: _enabledOpts);
    await ctl.show(api);
    expect(ctl.isShowing(api), isTrue);
    expect(ctl.isShowing(other), isFalse);
  });

  test('hide()/close() are safe no-ops when nothing is showing', () async {
    await ctl.hide();
    await ctl.close();
    expect(ctl.api, isNull);
  });

  test('setRect notifies listeners', () {
    var notified = 0;
    ctl.addListener(() => notified++);
    ctl.setRect(const MovaMiniRect(left: 0, top: 0, width: 10, height: 10));
    expect(notified, 1);
    expect(ctl.rect, const MovaMiniRect(left: 0, top: 0, width: 10, height: 10));
  });
}
