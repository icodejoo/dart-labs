import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mova/mova.dart';
import '../../support/fake_api.dart';

Future<void> mount(
  WidgetTester t, {
  MovaPlayerStyle? style,
  ThemeData? theme,
}) async {
  final api = FakeMovaApi();
  addTearDown(api.dispose);
  await t.pumpWidget(
    MaterialApp(
      theme: theme,
      home: MovaPlayer(api: api, style: style),
    ),
  );
  await t.pump();
}

void main() {
  testWidgets(
    'default chrome icons remain and icons section has value semantics',
    (t) async {
      const a = MovaIcons();
      const b = MovaIcons(pip: Icons.open_in_new);
      expect(a, const MovaIcons());
      expect(a.hashCode, const MovaIcons().hashCode);
      expect(a, isNot(b));
      const style = MovaPlayerStyle(icons: b);
      expect(const MovaPlayerStyle().copyWith(icons: b), style);
      expect(style.hashCode, style.copyWith().hashCode);
      expect(style.copyWith().icons, b);
      expect(style, isNot(const MovaPlayerStyle(icons: a)));
      expect(
        [
          a.pip,
          a.quality,
          a.aspectRatio,
          a.rotate,
          a.enterFullscreen,
          a.exitFullscreen,
          a.lock,
          a.unlock,
          a.subtitles,
          a.subtitlesOff,
          a.speed,
          a.backToLive,
          a.play,
          a.pause,
          a.volumeOff,
          a.volumeUp,
          a.brightness,
          a.retry,
          a.check,
          a.closeMini,
        ],
        [
          Icons.picture_in_picture_alt_rounded,
          Icons.high_quality_rounded,
          Icons.aspect_ratio_rounded,
          Icons.screen_rotation_rounded,
          Icons.fullscreen_rounded,
          Icons.fullscreen_exit_rounded,
          Icons.lock_open_rounded,
          Icons.lock_rounded,
          Icons.subtitles_rounded,
          Icons.subtitles_off_rounded,
          Icons.speed_rounded,
          Icons.sync_rounded,
          Icons.play_circle_filled_rounded,
          Icons.pause_circle_filled_rounded,
          Icons.volume_off_rounded,
          Icons.volume_up_rounded,
          Icons.brightness_6_rounded,
          Icons.refresh_rounded,
          Icons.check_rounded,
          Icons.close,
        ],
      );
      await mount(t);
      expect(find.byIcon(Icons.picture_in_picture_alt_rounded), findsOneWidget);
      expect(find.byIcon(Icons.aspect_ratio_rounded), findsOneWidget);
      expect(find.byIcon(Icons.fullscreen_rounded), findsOneWidget);
      final api =
          MovaScope.of(t.element(find.byType(MovaIconButton).first))
              as FakeMovaApi;
      api.push(api.state.copyWith(type: MovaStreamType.live));
      await t.pump();
      await t.pump();
      expect(
        find.byWidgetPredicate(
          (w) => w is MovaIconButton && w.label == '回到直播：回到直播',
        ),
        findsOneWidget,
      );
    },
  );
  testWidgets(
    'custom pip icon keeps explicit label and overrides theme section',
    (t) async {
      await mount(
        t,
        theme: ThemeData(
          extensions: const [
            MovaPlayerStyle(icons: MovaIcons(pip: Icons.cast)),
          ],
        ),
        style: const MovaPlayerStyle(icons: MovaIcons(pip: Icons.open_in_new)),
      );
      expect(find.byIcon(Icons.open_in_new), findsOneWidget);
      expect(find.byIcon(Icons.cast), findsNothing);
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is MovaIconButton &&
              w.icon == Icons.open_in_new &&
              w.label == '画中画',
        ),
        findsOneWidget,
      );
      await mount(
        t,
        theme: ThemeData(
          extensions: const [
            MovaPlayerStyle(icons: MovaIcons(pip: Icons.cast)),
          ],
        ),
      );
      expect(find.byIcon(Icons.cast), findsOneWidget);
    },
  );
  testWidgets(
    'progress color overrides track and thumb while null preserves host',
    (t) async {
      const host = SliderThemeData(
        activeTrackColor: Colors.blue,
        thumbColor: Colors.purple,
      );
      for (final color in [0xff00ff00, null]) {
        await mount(
          t,
          theme: ThemeData(sliderTheme: host),
          style: MovaPlayerStyle(theme: MovaTheme(progressColor: color)),
        );
        final data = SliderTheme.of(t.element(find.byType(Slider)));
        expect(
          data.activeTrackColor,
          color == null ? host.activeTrackColor : Color(color),
        );
        expect(data.thumbColor, color == null ? host.thumbColor : Color(color));
      }
      expect(
        const MovaTheme(progressColor: 1),
        isNot(const MovaTheme(progressColor: 2)),
      );
    },
  );
}
