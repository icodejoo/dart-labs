import 'package:flutter_test/flutter_test.dart';
import 'package:mova/src/core/model/danmaku.dart';
import 'package:mova/src/core/options/options.dart';
import 'package:mova/src/core/state/progress.dart';
import 'package:mova/src/ui/components/danmaku.dart';

import '../support/fake_api.dart';
import '../support/pump.dart';

void main() {
  testWidgets('renders nothing when disabled', (t) async {
    final api = FakeMovaApi();
    await pumpComponent(t, api, DanmakuTrackComponent());
    expect(find.byType(DanmakuTrackComponent), findsNothing);
    await api.dispose();
  });

  testWidgets('spawns a comment once playback crosses its time, then retires it', (t) async {
    final api = FakeMovaApi(
      options: MovaOpts(
        danmaku: const MovaDanmakuConfig(
          enabled: true,
          items: [MovaDanmakuItem(text: 'hello', time: Duration(seconds: 5))],
          crossDuration: Duration(milliseconds: 500),
        ),
      ),
    );
    await pumpComponent(t, api, DanmakuTrackComponent());
    expect(find.text('hello'), findsNothing);

    api.pushProgress(const MovaProg(position: Duration(seconds: 6)));
    await t.pump();
    await t.pump();
    expect(find.text('hello'), findsOneWidget);

    await t.pump(const Duration(milliseconds: 600));
    expect(find.text('hello'), findsNothing);

    await api.dispose();
  });

  testWidgets('does not respawn a comment already passed on a later tick', (t) async {
    final api = FakeMovaApi(
      options: MovaOpts(
        danmaku: const MovaDanmakuConfig(
          enabled: true,
          items: [MovaDanmakuItem(text: 'once', time: Duration(seconds: 2))],
          crossDuration: Duration(seconds: 10),
        ),
      ),
    );
    await pumpComponent(t, api, DanmakuTrackComponent());

    api.pushProgress(const MovaProg(position: Duration(seconds: 3)));
    await t.pump();
    await t.pump();
    api.pushProgress(const MovaProg(position: Duration(seconds: 4)));
    await t.pump();
    await t.pump();

    expect(find.text('once'), findsOneWidget);
    await api.dispose();
  });
}
