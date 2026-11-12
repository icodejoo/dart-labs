import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_stompsocket/flutter_stompsocket.dart';
import 'package:flutter_stompsocket_example/demo_kit/demo_kit.dart';
import 'package:flutter_stompsocket_example/demo_session.dart';
import 'package:flutter_stompsocket_example/demo_settings.dart';
import 'package:flutter_stompsocket_example/main.dart' as app;
import 'package:flutter_stompsocket_example/pages/send_page.dart';

import 'demo_fakes.dart';

/// 测试使用的稳定版本标记，入口另行核对真实 pubspec。
const _testVersion = 'test-version';

/// 挂载完整应用，可指定页面与语言。
Future<DemoLocale> _mount(
  WidgetTester tester,
  DemoSession session, {
  String page = 'connection',
  String language = 'en',
  double width = 1440,
}) async {
  tester.view.physicalSize = Size(width, width == 375 ? 667 : 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final locale = DemoLocale(uri: Uri.parse('https://test/?lang=$language'));
  await tester.pumpWidget(
    app.StompsocketDemoApp(
      version: _testVersion,
      session: session,
      locale: locale,
      initialFragment: '/pages/$page',
    ),
  );
  await tester.pumpAndSettle();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    locale.dispose();
    session.dispose();
  });
  return locale;
}

/// 点击指定卡片的重放，保证外部状态和局部表单同时重置。
Future<void> _replay(WidgetTester tester, int index) async {
  final target = find.descendant(
    of: find.byType(DemoCard).at(index),
    matching: find.byIcon(Icons.replay_rounded),
  );
  await tester.ensureVisible(target);
  await tester.tap(target);
  await tester.pumpAndSettle();
}

/// 验证真实入口、双语布局、每种交互及重放的资源清理。
void main() {
  testWidgets(
    'entrypoint reads the package manifest and displays its version',
    (tester) async {
      final manifest = File(DemoSettings.packageManifest).readAsStringSync();
      final expected = RegExp(
        r'^version:\s*(\S+)',
        multiLine: true,
      ).firstMatch(manifest)!.group(1)!;
      expect(await app.loadPackageVersion(), expected);
      await app.main();
      await tester.pumpAndSettle();
      expect(find.text(expected), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final width in [375.0, 1440.0]) {
    for (final language in ['en', 'zh']) {
      for (final page in ['connection', 'subscribe', 'send', 'config']) {
        testWidgets('$page layout at $width in $language', (tester) async {
          final session = DemoSession();
          await _mount(
            tester,
            session,
            page: page,
            language: language,
            width: width,
          );
          expect(find.byType(DemoPage), findsOneWidget);
          expect(find.byType(DemoGrid), findsWidgets);
          expect(find.text(_testVersion), findsOneWidget);
          final cards = tester.widgetList<DemoCard>(find.byType(DemoCard));
          for (final card in cards) {
            expect(card.replayable, card.onReplay != null);
          }
          for (final element in find.byType(DemoCard).evaluate()) {
            final rect = tester.getRect(find.byWidget(element.widget));
            expect(rect.left, greaterThanOrEqualTo(0));
            expect(rect.right, lessThanOrEqualTo(width));
          }
          expect(tester.takeException(), isNull);
        });
      }
    }
  }

  testWidgets('full shell adapts continuously from 360 to 1600', (
    tester,
  ) async {
    final session = DemoSession();
    await _mount(tester, session);
    for (final width in <double>[
      360,
      599,
      600,
      899,
      900,
      999,
      1000,
      1200,
      1500,
      1600,
    ]) {
      tester.view.physicalSize = Size(width, 900);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'width $width');
      expect(
        find.byKey(const ValueKey('demo-sidebar')),
        width >= DemoTokens.sidebarBreakpoint ? findsOneWidget : findsNothing,
      );
    }
  });

  testWidgets(
    'preview connect, reconnect, stop and replay cancel pending timers',
    (tester) async {
      final session = DemoSession();
      await _mount(tester, session);
      await tester.tap(find.text('Connect'));
      await tester.pump();
      expect(session.connection, StompConnectionState.connecting);
      await tester.pump(DemoSettings.previewDelay);
      expect(session.connection, StompConnectionState.connected);
      await tester.tap(find.text('Reconnect'));
      await tester.pump();
      expect(session.connection, StompConnectionState.reconnecting);
      await _replay(tester, 0);
      await tester.pump(DemoSettings.previewReconnectDelay);
      expect(session.connection, StompConnectionState.idle);
      expect(session.socket, isNull);
      session.connect(DemoSettings.brokerUrl);
      session.stop();
      await tester.pump(DemoSettings.previewDelay);
      expect(session.connection, StompConnectionState.disconnected);
      session.connect(DemoSettings.brokerUrl);
      session.changeMode(true);
      await tester.pump(DemoSettings.previewDelay);
      expect(session.connection, StompConnectionState.idle);
    },
  );

  testWidgets(
    'preview manual delivery keeps registered ACK mode and replay clears all',
    (tester) async {
      final session = DemoSession();
      await _mount(tester, session, page: 'subscribe');
      await tester.tap(find.byType(DropdownButtonFormField<AckMode>));
      await tester.pumpAndSettle();
      await tester.tap(find.text(AckMode.manual.name).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Subscribe'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Deliver preview'));
      await tester.pumpAndSettle();
      expect(session.subscriptions.single.status, DeliveryStatus.pending);
      await tester.tap(find.text('ACK'));
      await tester.pumpAndSettle();
      expect(session.subscriptions.single.status, DeliveryStatus.acked);
      await tester.tap(find.text('Deliver preview'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('NACK'));
      await tester.pumpAndSettle();
      expect(session.subscriptions.single.status, DeliveryStatus.nacked);
      await tester.tap(find.text('Unsubscribe'));
      await tester.pumpAndSettle();
      expect(session.subscriptions, isEmpty);
      await tester.tap(find.text('Subscribe'));
      await tester.pumpAndSettle();
      await _replay(tester, 0);
      expect(session.subscriptions, isEmpty);
      expect(find.text(AckMode.auto.name), findsOneWidget);
    },
  );

  testWidgets(
    'real disconnected sends call send; handles survive stop and are cleaned by replay',
    (tester) async {
      final sockets = <RecordingSocket>[];
      final session = DemoSession(
        socketFactory: (_, _) {
          final socket = RecordingSocket();
          sockets.add(socket);
          return socket;
        },
      );
      await _mount(tester, session);
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('broker-url')),
        'invalid',
      );
      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();
      expect(sockets, isEmpty);
      await tester.enterText(
        find.byKey(const ValueKey('broker-url')),
        DemoSettings.brokerUrl,
      );
      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();
      final socket = sockets.single;
      session.subscribe(DemoSettings.topic, AckMode.manual);
      final first = RecordingAck();
      final second = RecordingAck();
      socket.callbacks.single('first', first);
      socket.callbacks.single(['second'], second);
      session.acknowledge(session.subscriptions.single, accept: true);
      session.acknowledge(session.subscriptions.single, accept: false);
      expect(first.accepted, 1);
      expect(second.rejected, 1);
      session.stop();
      session.send(DemoSettings.destination, {'offline': true});
      expect(socket.bodies, [
        {'offline': true},
      ]);
      expect(session.subscriptions.length, 1);
      session.connect(DemoSettings.brokerUrl);
      expect(socket.activations, 2);
      session.reconnect();
      expect(socket.reconnects, 1);
      session.clearSubscriptions();
      expect(socket.clears, greaterThan(0));
      expect(session.subscriptions, isEmpty);
      socket.callbacks.single('late', first);
      expect(session.subscriptions, isEmpty);
      await tester.pumpAndSettle();
      await _replay(tester, 1);
      expect(session.socket, isNull);
      socket.states.value = StompConnectionState.connecting;
      expect(session.connection, StompConnectionState.idle);
      expect(find.byKey(const ValueKey('broker-url')), findsOneWidget);
    },
  );

  testWidgets(
    'JSON validation accepts arrays and scalars; all body types reach send',
    (tester) async {
      final socket = RecordingSocket();
      final session = DemoSession(socketFactory: (_, _) => socket)
        ..changeMode(true)
        ..connect(DemoSettings.brokerUrl);
      await _mount(tester, session, page: 'send');
      final body = find.byKey(const ValueKey('send-body'));
      await tester.enterText(body, '{broken');
      await tester.tap(find.text('Send'));
      await tester.pumpAndSettle();
      expect(find.text('Enter valid JSON.'), findsOneWidget);
      expect(socket.bodies, isEmpty);
      for (final json in [
        '[1,2]',
        '7',
        'true',
        'null',
        '"hello"',
        DemoSettings.jsonBody,
      ]) {
        await tester.enterText(body, json);
        await tester.tap(find.text('Send'));
        await tester.pumpAndSettle();
      }
      expect(socket.bodies, [
        [1, 2],
        7,
        true,
        null,
        'hello',
        {'message': 'hello'},
      ]);
      for (final label in ['Text', 'Binary (UTF-8)', 'No body']) {
        await tester.tap(find.byType(DropdownButtonFormField<SendBodyKind>));
        await tester.pumpAndSettle();
        await tester.tap(find.text(label).last);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Send'));
        await tester.pumpAndSettle();
      }
      expect(socket.bodies[6], DemoSettings.jsonBody);
      expect(socket.bodies[7], isA<Uint8List>());
      expect(socket.bodies[8], isNull);
      await _replay(tester, 0);
      expect(session.sendAttempts, 0);
      expect(session.socket, isNull);
      expect(find.text('JSON'), findsOneWidget);
    },
  );

  testWidgets('preview buffer is bounded, flushes and replay discards it', (
    tester,
  ) async {
    final session = DemoSession();
    await _mount(tester, session, page: 'send');
    for (var i = 0; i <= DemoSettings.queueLimit; i++) {
      session.send(DemoSettings.destination, i);
    }
    expect(session.previewQueued, DemoSettings.queueLimit);
    expect(session.events.length, DemoSettings.logLimit);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Connect & flush preview'));
    await tester.pump(DemoSettings.previewDelay);
    expect(session.previewQueued, 0);
    session.stop();
    session.send(DemoSettings.destination, null);
    await tester.pumpAndSettle();
    await _replay(tester, 1);
    expect(session.previewQueued, 0);
    expect(session.sendAttempts, 0);
  });

  testWidgets(
    'navigation preserves session; translated history, log replay and links work',
    (tester) async {
      final session = DemoSession();
      final locale = await _mount(tester, session);
      session.subscribe(DemoSettings.topic, AckMode.auto);
      session.deliverPreview();
      await tester.tap(find.text('Subscriptions'));
      await tester.pumpAndSettle();
      expect(session.subscriptions.single.received, 1);
      locale.select('zh');
      await tester.pumpAndSettle();
      expect(find.textContaining('预览消息已分发'), findsOneWidget);
      await _replay(tester, 3);
      expect(session.events, isEmpty);
      final copied = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied.add(call.arguments['text'] as String);
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      for (final tooltip in ['pub.dev', 'GitHub', '阅读文档']) {
        await tester.tap(find.byTooltip(tooltip));
        await tester.pump();
      }
      expect(copied, [
        DemoSettings.pubUrl,
        DemoSettings.githubUrl,
        DemoSettings.readmeUrl,
      ]);
    },
  );

  testWidgets(
    'subscription limits, empty targets and disconnected real mode are explicit',
    (tester) async {
      final session = DemoSession();
      await _mount(tester, session, page: 'subscribe');
      session.subscribe('', AckMode.auto);
      expect(session.subscriptions, isEmpty);
      for (var i = 0; i <= DemoSettings.subscriptionLimit; i++) {
        session.subscribe(DemoSettings.topic, AckMode.smart);
      }
      expect(session.subscriptions.length, DemoSettings.subscriptionLimit);
      session.changeMode(true);
      session.subscribe(DemoSettings.topic, AckMode.auto);
      session.send(DemoSettings.destination, null);
      session.send('', null);
      session.deliverPreview();
      expect(session.subscriptions, isEmpty);
      expect(session.sendAttempts, 0);
      expect(session.events.first.en, 'Destination is required.');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
