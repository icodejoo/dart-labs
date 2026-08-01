import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:videoman/src/core/model/feed_item.dart';
import 'package:videoman/src/core/model/source.dart';
import 'package:videoman/src/ui/feed_player.dart';

import '../support/fake_api.dart';

void main() {
  testWidgets('activates the first page on mount', (t) async {
    final api = FakeVmApi();
    await t.pumpWidget(MaterialApp(
      home: VmFeedPlayer(
        api: api,
        loader: (i) async => VmFeedItem(source: VmSource('https://h/$i.mp4'), authorName: 'author$i'),
      ),
    ));
    await t.pump();
    await t.pump();

    expect(api.calls, contains('open'));
    expect(api.source?.uri, 'https://h/0.mp4');
    expect(find.text('@author0'), findsOneWidget);

    await api.dispose();
  });

  testWidgets('swiping up activates the next page', (t) async {
    final api = FakeVmApi();
    await t.pumpWidget(MaterialApp(
      home: VmFeedPlayer(
        api: api,
        loader: (i) async => VmFeedItem(source: VmSource('https://h/$i.mp4'), authorName: 'author$i'),
      ),
    ));
    await t.pump();
    await t.pump();
    expect(api.source?.uri, 'https://h/0.mp4');

    await t.fling(find.byType(PageView), const Offset(0, -400), 1000);
    await t.pumpAndSettle();
    // Let the async `activate()` triggered by onPageChanged resolve.
    await t.pump();
    await t.pump();

    expect(api.source?.uri, 'https://h/1.mp4');
    expect(find.text('@author1'), findsOneWidget);

    await api.dispose();
  });

  testWidgets('an ended feed (loader returns null) shows a black placeholder without crashing', (t) async {
    final api = FakeVmApi();
    await t.pumpWidget(MaterialApp(
      home: VmFeedPlayer(api: api, loader: (i) async => null),
    ));
    await t.pump();
    await t.pump();

    expect(t.takeException(), isNull);
    expect(api.calls, isNot(contains('open')));

    await api.dispose();
  });
}
