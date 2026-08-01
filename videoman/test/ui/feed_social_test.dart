import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:videoman/src/core/feed/feed_controller.dart';
import 'package:videoman/src/core/model/feed_item.dart';
import 'package:videoman/src/core/model/source.dart';
import 'package:videoman/src/ui/components/feed_social.dart';

import '../support/fake_api.dart';
import '../support/pump.dart';

void main() {
  testWidgets('like button toggles icon/count and notifies the item callback', (t) async {
    final api = FakeVmApi();
    bool? likedSeen;
    final item = VmFeedItem(
      source: const VmSource('https://h/0.mp4'),
      initialLikeCount: 5,
      onLikeChanged: (liked, count) => likedSeen = liked,
    );
    final controller = VmFeedController(api: api, loader: (i) async => item);
    await controller.ensure(0);
    final notifier = ValueNotifier(controller.likeStateOf(0));

    await pumpComponent(t, api, LikeButtonComponent(controller: controller, index: 0, likeNotifier: notifier));
    expect(find.text('5'), findsOneWidget);
    expect(find.byIcon(Icons.favorite_border_rounded), findsOneWidget);

    await t.tap(find.byIcon(Icons.favorite_border_rounded));
    await t.pump();

    expect(find.text('6'), findsOneWidget);
    expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);
    expect(likedSeen, isTrue);
    expect(notifier.value.liked, isTrue);

    await api.dispose();
  });

  testWidgets('comment button fires onComment and shows the display-only count', (t) async {
    final api = FakeVmApi();
    var tapped = 0;
    final item = VmFeedItem(
      source: const VmSource('https://h/0.mp4'),
      commentCount: 42,
      onComment: () => tapped++,
    );
    await pumpComponent(t, api, CommentButtonComponent(item: item));

    expect(find.text('42'), findsOneWidget);
    await t.tap(find.byIcon(Icons.chat_bubble_rounded));
    expect(tapped, 1);

    await api.dispose();
  });

  testWidgets('share button fires onShare and shows the display-only count', (t) async {
    final api = FakeVmApi();
    var tapped = 0;
    final item = VmFeedItem(
      source: const VmSource('https://h/0.mp4'),
      shareCount: 7,
      onShare: () => tapped++,
    );
    await pumpComponent(t, api, ShareButtonComponent(item: item));

    expect(find.text('7'), findsOneWidget);
    await t.tap(find.byIcon(Icons.reply_rounded));
    expect(tapped, 1);

    await api.dispose();
  });

  testWidgets('avatar tap and follow tap fire their own callbacks independently', (t) async {
    final api = FakeVmApi();
    var avatarTaps = 0;
    var followTaps = 0;
    final item = VmFeedItem(
      source: const VmSource('https://h/0.mp4'),
      onAvatarTap: () => avatarTaps++,
      onFollowTap: () => followTaps++,
    );
    await pumpComponent(t, api, AvatarComponent(item: item));

    await t.tap(find.byIcon(Icons.person_rounded));
    expect(avatarTaps, 1);
    expect(followTaps, 0);

    await t.tap(find.byIcon(Icons.add_circle_rounded));
    expect(followTaps, 1);

    await api.dispose();
  });

  testWidgets('feed info shows author and music, omitting either when absent', (t) async {
    final api = FakeVmApi();
    await pumpComponent(
      t,
      api,
      FeedInfoComponent(item: VmFeedItem(source: const VmSource('https://h/0.mp4'), authorName: 'bob')),
    );
    expect(find.text('@bob'), findsOneWidget);
    expect(find.byIcon(Icons.music_note_rounded), findsNothing);

    await api.dispose();
  });
}
