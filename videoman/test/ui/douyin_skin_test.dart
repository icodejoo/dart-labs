import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:videoman/src/core/feed/feed_controller.dart';
import 'package:videoman/src/core/model/feed_item.dart';
import 'package:videoman/src/core/model/source.dart';
import 'package:videoman/src/ui/scope/scope.dart';
import 'package:videoman/src/ui/skins/douyin_skin.dart';
import 'package:videoman/src/ui/slots/tree.dart';

import '../support/fake_api.dart';

Future<VmFeedController> _controllerWith(FakeVmApi api, VmFeedItem item) async {
  final controller = VmFeedController(api: api, loader: (i) async => item);
  await controller.ensure(0);
  return controller;
}

void main() {
  testWidgets('renders author, music, and social counts', (t) async {
    final api = FakeVmApi();
    final item = VmFeedItem(
      source: const VmSource('https://h/0.mp4'),
      authorName: 'alice',
      musicName: 'Original Sound',
      commentCount: 12,
      shareCount: 3,
      initialLikeCount: 100,
    );
    final controller = await _controllerWith(api, item);
    final notifier = ValueNotifier(controller.likeStateOf(0));

    await t.pumpWidget(MaterialApp(
      home: VmScope(
        api: api,
        child: Builder(builder: (c) {
          final skin = VmDouyinSkin(item: item, controller: controller, index: 0, likeNotifier: notifier);
          final bundle = buildSlots(c, api, skin.components());
          return skin.assemble(c, bundle, const SizedBox.expand());
        }),
      ),
    ));
    await t.pump();

    expect(find.text('@alice'), findsOneWidget);
    expect(find.text('Original Sound'), findsOneWidget);
    expect(find.text('100'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);

    await api.dispose();
  });

  testWidgets('single tap toggles play/pause, double tap toggles like', (t) async {
    final api = FakeVmApi();
    var likeCalls = 0;
    final item = VmFeedItem(
      source: const VmSource('https://h/0.mp4'),
      onLikeChanged: (liked, count) => likeCalls++,
    );
    final controller = await _controllerWith(api, item);
    final notifier = ValueNotifier(controller.likeStateOf(0));

    await t.pumpWidget(MaterialApp(
      home: VmScope(
        api: api,
        child: Builder(builder: (c) {
          final skin = VmDouyinSkin(item: item, controller: controller, index: 0, likeNotifier: notifier);
          final bundle = buildSlots(c, api, skin.components());
          return skin.assemble(c, bundle, const SizedBox.expand());
        }),
      ),
    ));
    await t.pump();

    // The social rail's avatar/like/comment/share buttons are also plain
    // `GestureDetector`s, so `.first` is unreliable — the gesture layer is
    // the only one that registers `onDoubleTap`.
    //
    // 社交竖排的头像/点赞/评论/分享按钮同样是普通 `GestureDetector`，
    // `.first` 并不可靠——只有手势层会注册 `onDoubleTap`。
    final gestureFinder = find.byWidgetPredicate((w) => w is GestureDetector && w.onDoubleTap != null);

    // Since this GestureDetector also has `onDoubleTap`, Flutter deliberately
    // delays recognizing a single tap by `kDoubleTapTimeout` in case a second
    // tap follows — a zero-duration pump would observe nothing yet.
    //
    // 由于该 GestureDetector 同时注册了 `onDoubleTap`，Flutter 会故意延迟
    // `kDoubleTapTimeout` 才判定为单击（等第二次点击是否出现）——零时长的
    // pump 还看不到结果。
    await t.tap(gestureFinder);
    await t.pump(kDoubleTapTimeout + const Duration(milliseconds: 50));
    expect(api.calls, contains('playOrPause'));

    // Let any pending tap-recognition window fully lapse before the
    // deliberate double-tap below, so it can't be misread as a stray third
    // tap of a prior gesture.
    await t.pump(const Duration(seconds: 1));

    // A double tap is two taps within Flutter's double-tap window
    // (`kDoubleTapTimeout`, 300ms) — two `tester.tap` calls with a short
    // pump in between reproduces that timing.
    await t.tap(gestureFinder);
    await t.pump(const Duration(milliseconds: 100));
    await t.tap(gestureFinder);
    await t.pumpAndSettle();

    expect(likeCalls, greaterThan(0));
    expect(find.byIcon(Icons.favorite_rounded), findsWidgets);

    await api.dispose();
  });

  test('components expose no top bar and no drag-based gesture component', () {
    final api = FakeVmApi();
    final item = VmFeedItem(source: const VmSource('https://h/0.mp4'));
    final controller = VmFeedController(api: api, loader: (i) async => item);
    final skin = VmDouyinSkin(
      item: item,
      controller: controller,
      index: 0,
      likeNotifier: ValueNotifier(controller.likeStateOf(0)),
    );
    final names = skin.components().map((c) => c.name).toList();
    expect(names, isNot(contains('topBar')));
    expect(names, isNot(contains('gestureLayer')));
    expect(names, contains('douyinGestureLayer'));
  });
}
