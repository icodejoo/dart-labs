import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mova/src/core/api.dart';
import 'package:mova/src/core/model/fit.dart';
import 'package:mova/src/core/model/source.dart';
import 'package:mova/src/core/options/options.dart';
import 'package:mova/src/ui/view.dart';

import '../support/fake_api.dart';

const _poster = SizedBox(key: ValueKey('poster'), width: 10, height: 10);

/// Builds a non-const [MovaSource] so two calls give distinct instances.
///
/// 构造一个非 const 的 [MovaSource]，使两次调用得到不同实例。
MovaSource _src(String uri, {String? title}) => MovaSource(uri, title: title);

/// Counts factory calls and keeps every engine it handed out.
///
/// 统计工厂调用次数，并保留发出去的每个引擎。
class _Engines {
  final List<FakeMovaApi> made = [];

  MovaApi make(MovaOpts options) {
    final api = FakeMovaApi(options: options);
    made.add(api);
    return api;
  }
}

Widget _view(
  _Engines engines,
  MovaSource? source, {
  bool autoPlay = true,
  MovaFit? fit,
  MovaOpts options = const MovaOpts(),
  bool autoLoadQualities = true,
  void Function(Object, StackTrace)? onOpenError,
}) {
  return MaterialApp(
    home: MovaView(
      source: source,
      autoPlay: autoPlay,
      fit: fit,
      poster: _poster,
      options: options,
      engineFactory: engines.make,
      autoLoadQualities: autoLoadQualities,
      onOpenError: onOpenError,
    ),
  );
}

void main() {
  for (final entry in <String, MovaOpts>{
    'ads': const MovaOpts(ads: MovaAdConfig(enabled: true)),
    'playlist': const MovaOpts(playlist: MovaPlaylistConfig(enabled: true)),
    'mini': const MovaOpts(mini: MovaMiniConfig(enabled: true)),
  }.entries) {
    testWidgets('C03 ${entry.key} change keeps engine and playback', (t) async {
      final engines = _Engines();
      await t.pumpWidget(_view(engines, _src('https://a/1.mp4')));
      await t.pump();
      await t.pumpWidget(_view(engines, _src('https://a/1.mp4'), options: entry.value));
      await t.pump();
      expect(engines.made, hasLength(1));
      expect(engines.made.single.disposed, isFalse);
      expect(engines.made.single.openCalls, 1);
    });
  }
  testWidgets('C03 parent rebuild with inline irrelevant options keeps engine', (t) async {
    final engines = _Engines();
    for (var i = 0; i < 3; i++) {
      await t.pumpWidget(_view(engines, _src('https://a/1.mp4'),
        options: MovaOpts(mini: MovaMiniConfig(width: 180.0 + i))));
      await t.pump();
    }
    expect(engines.made, hasLength(1));
    expect(engines.made.single.openCalls, 1);
  });
  testWidgets('C03 unstable options warn once after ten consecutive frames', (t) async {
    final engines = _Engines();
    final messages = <String>[];
    final previous = debugPrint;
    debugPrint = (message, {wrapWidth}) { if (message != null) messages.add(message); };
    addTearDown(() => debugPrint = previous);
    try {
    for (var i = 0; i < 14; i++) {
      await t.pumpWidget(_view(engines, _src('https://a/1.mp4'),
        options: MovaOpts(preview: MovaPreviewConfig(frameWidth: 160 + i))),
        duration: const Duration(milliseconds: 16));
      if (i < 10) expect(messages.where((m) => m.contains('连续 10 帧')), isEmpty);
    }
    expect(messages.where((m) => m.contains('连续 10 帧')), hasLength(1));
    } finally { debugPrint = previous; }
  });

  group('MovaView', () {
    testWidgets('a null source builds no engine and shows only the poster', (t) async {
      final engines = _Engines();
      await t.pumpWidget(_view(engines, null));
      expect(engines.made, isEmpty);
      expect(find.byKey(const ValueKey('poster')), findsOneWidget);
    });

    testWidgets('the first source creates exactly one engine and opens it with autoPlay', (t) async {
      final engines = _Engines();
      await t.pumpWidget(_view(engines, _src('https://a/1.mp4'), autoPlay: false));
      await t.pump();
      expect(engines.made, hasLength(1));
      expect(engines.made.single.openedUris, ['https://a/1.mp4']);
      expect(engines.made.single.lastAutoPlay, isFalse);
    });

    testWidgets('a sameAs source on a new instance does not reopen', (t) async {
      final engines = _Engines();
      await t.pumpWidget(_view(engines, _src('https://a/1.mp4', title: 'a')));
      await t.pump();
      await t.pumpWidget(_view(engines, _src('https://a/1.mp4', title: 'b')));
      await t.pump();
      expect(engines.made.single.openCalls, 1);
    });

    testWidgets('a different uri reopens on the same engine', (t) async {
      final engines = _Engines();
      await t.pumpWidget(_view(engines, _src('https://a/1.mp4')));
      await t.pump();
      await t.pumpWidget(_view(engines, _src('https://a/2.mp4')));
      await t.pump();
      expect(engines.made, hasLength(1));
      expect(engines.made.single.openedUris, ['https://a/1.mp4', 'https://a/2.mp4']);
    });

    testWidgets('a source going null pauses the engine and shows the poster', (t) async {
      final engines = _Engines();
      await t.pumpWidget(_view(engines, _src('https://a/1.mp4')));
      await t.pump();
      await t.pumpWidget(_view(engines, null));
      await t.pump();
      expect(engines.made.single.calls, contains('pause'));
      expect(find.byKey(const ValueKey('poster')), findsOneWidget);
    });

    testWidgets('changed options dispose the old engine and reopen on a new one', (t) async {
      final engines = _Engines();
      await t.pumpWidget(_view(engines, _src('https://a/1.mp4')));
      await t.pump();
      await t.pumpWidget(_view(engines, _src('https://a/1.mp4'), options: const MovaOpts(theme: MovaTheme(accentColor: 0xFF00FF00))));
      await t.pump();
      expect(engines.made, hasLength(2));
      expect(engines.made.first.disposed, isTrue);
      expect(engines.made.last.openedUris, ['https://a/1.mp4']);
    });

    testWidgets('unmounting disposes the engine', (t) async {
      final engines = _Engines();
      await t.pumpWidget(_view(engines, _src('https://a/1.mp4')));
      await t.pump();
      await t.pumpWidget(const MaterialApp(home: SizedBox()));
      await t.pump();
      expect(engines.made.single.disposed, isTrue);
    });

    testWidgets('a declarative fit is forwarded to the engine', (t) async {
      final engines = _Engines();
      await t.pumpWidget(_view(engines, _src('https://a/1.mp4'), fit: MovaFit.cover));
      await t.pump();
      expect(engines.made.single.lastFit, MovaFit.cover);
    });

    testWidgets('an open() failure reaches onOpenError without an unhandled exception', (t) async {
      final engines = _Engines();
      Object? caught;
      final api = FakeMovaApi()..openThrows = StateError('boom');
      await t.pumpWidget(MaterialApp(
        home: MovaView(
          source: _src('https://a/1.mp4'),
          engineFactory: (_) => api,
          onOpenError: (e, s) => caught = e,
        ),
      ));
      await t.pump();
      expect(caught, isA<StateError>());
      expect(t.takeException(), isNull);
      expect(engines.made, isEmpty);
    });

    testWidgets('autoLoadQualities runs loadQualities after open', (t) async {
      final engines = _Engines();
      await t.pumpWidget(_view(engines, _src('https://a/1.mp4')));
      await t.pump();
      final calls = engines.made.single.calls;
      expect(calls.indexOf('loadQualities'), greaterThan(calls.indexOf('open')));
      expect(calls.where((c) => c == 'loadQualities'), hasLength(1));
    });
  });
}
