import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mova/src/core/state/progress.dart';
import 'package:mova/src/core/stt/cue.dart';
import 'package:mova/src/ui/components/subtitle.dart';

import '../support/fake_api.dart';
import '../support/pump.dart';

void main() {
  group('SubtitleButtonComponent', () {
    testWidgets('renders nothing when no engine is configured', (t) async {
      final api = FakeMovaApi();
      await pumpComponent(t, api, SubtitleButtonComponent());

      expect(find.byIcon(Icons.subtitles_off_rounded), findsNothing);
      expect(find.byIcon(Icons.subtitles_rounded), findsNothing);

      await api.dispose();
    });

    testWidgets('tapping the "on" row starts stt and flips the icon', (t) async {
      final api = FakeMovaApi();
      api.stt.languages = ['zh', 'en'];
      await pumpComponent(t, api, SubtitleButtonComponent());

      expect(find.byIcon(Icons.subtitles_off_rounded), findsOneWidget);

      await t.tap(find.byIcon(Icons.subtitles_off_rounded));
      await t.pumpAndSettle();
      expect(find.text('zh/en'), findsOneWidget);

      await t.tap(find.text('zh/en'));
      await t.pumpAndSettle();
      expect(api.stt.calls, contains('start'));
      expect(find.byIcon(Icons.subtitles_rounded), findsOneWidget);

      await api.dispose();
    });

    testWidgets('tapping the off row stops stt and flips the icon back', (t) async {
      final api = FakeMovaApi();
      api.stt.languages = ['zh', 'en'];
      await pumpComponent(t, api, SubtitleButtonComponent());

      await t.tap(find.byIcon(Icons.subtitles_off_rounded));
      await t.pumpAndSettle();
      await t.tap(find.text('zh/en'));
      await t.pumpAndSettle();
      expect(find.byIcon(Icons.subtitles_rounded), findsOneWidget);

      await t.tap(find.byIcon(Icons.subtitles_rounded));
      await t.pumpAndSettle();
      expect(find.text(api.options.strings.subtitleOff), findsOneWidget);
      await t.tap(find.text(api.options.strings.subtitleOff));
      await t.pumpAndSettle();

      expect(api.stt.calls, contains('stop'));
      expect(find.byIcon(Icons.subtitles_off_rounded), findsOneWidget);

      await api.dispose();
    });
  });

  group('SubtitleOverlayComponent', () {
    testWidgets('renders nothing when no engine is configured', (t) async {
      final api = FakeMovaApi();
      await pumpComponent(t, api, SubtitleOverlayComponent());
      expect(find.byType(Text), findsNothing);
      await api.dispose();
    });

    testWidgets('renders nothing until a cue covers the current position', (t) async {
      final api = FakeMovaApi();
      api.stt.languages = ['zh', 'en'];
      await pumpComponent(t, api, SubtitleOverlayComponent());
      expect(find.byType(Text), findsNothing);
      await api.dispose();
    });

    testWidgets('shows the cue text once one is pushed', (t) async {
      final api = FakeMovaApi();
      api.stt.languages = ['zh', 'en'];
      await pumpComponent(t, api, SubtitleOverlayComponent());

      api.stt.push(const MovaSttCue(text: '大家好', start: Duration.zero, end: Duration(seconds: 5)));
      await t.pump();
      await t.pump();

      expect(find.text('大家好'), findsOneWidget);

      await api.dispose();
    });

    testWidgets('hides again once a progress tick moves past the cue end', (t) async {
      final api = FakeMovaApi();
      api.stt.languages = ['zh', 'en'];
      await pumpComponent(t, api, SubtitleOverlayComponent());

      api.stt.push(const MovaSttCue(text: '大家好', start: Duration.zero, end: Duration(seconds: 2)));
      await t.pump();
      await t.pump();
      expect(find.text('大家好'), findsOneWidget);

      // A cue can stop covering the position without a new one arriving —
      // the overlay must re-check `current` on every progress tick, not just
      // on `cues`. This fake doesn't implement that expiry itself (see
      // `FakeSttApi.clear`'s doc comment), so the test drives it directly and
      // asserts the overlay reacts to the progress tick that follows.
      //
      // 字幕可能在没有新字幕产出的情况下就不再覆盖当前位置——叠加层必须在每次
      // progress tick 都重新检查 `current`，而不只是在 `cues` 上。这个假对象
      // 本身不实现这层过期逻辑（见 `FakeSttApi.clear` 的文档注释），因此测试
      // 直接驱动它，断言叠加层对随后的 progress tick 有反应。
      api.stt.clear();
      api.pushProgress(const MovaProg(position: Duration(seconds: 5), buffer: Duration.zero));
      await t.pump();
      await t.pump();

      expect(find.text('大家好'), findsNothing);

      await api.dispose();
    });
  });
}
