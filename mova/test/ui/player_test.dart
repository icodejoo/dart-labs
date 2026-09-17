import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mova/src/core/state/progress.dart';
import 'package:mova/src/core/state/state.dart';
import 'package:mova/src/ui/player.dart';
import 'package:mova/src/ui/scope/scope.dart';
import 'package:mova/src/ui/skins/default_skin.dart';

import '../support/fake_api.dart';

/// Finds the render surface's inner placeholder/video widget's key, used to
/// tell whether the surface actually rebuilt and re-read [MovaApi.renderHandle].
///
/// 找到渲染面内部占位/视频组件的 key，用于判断渲染面是否真的重建并重新读取了
/// [MovaApi.renderHandle]。
Key? _surfaceKey(WidgetTester t) {
  final matches = t.widgetList<ColoredBox>(find.byWidgetPredicate(
      (w) => w is ColoredBox && w.key.runtimeType.toString() == '_RenderHandleKey'));
  return matches.first.key;
}

void main() {
  testWidgets('MovaPlayer provides its api down the tree and renders the skin', (t) async {
    final api = FakeMovaApi();
    await t.pumpWidget(MaterialApp(home: MovaPlayer(api: api, skin: const MovaDefSkin())));
    await t.pump();
    expect(find.byType(MovaScope), findsOneWidget);
    await api.dispose();
  });

  testWidgets('MovaPlayer applies zoom from state via Transform.scale', (t) async {
    final api = FakeMovaApi();
    api.push(const MovaState(zoom: 2.0));
    await t.pumpWidget(MaterialApp(home: MovaPlayer(api: api)));
    await t.pump();
    final ts = t.widget<Transform>(find.byType(Transform).first);
    expect(ts.transform.getMaxScaleOnAxis(), closeTo(2.0, 0.001));
    await api.dispose();
  });

  testWidgets(
    'swapping to a different api remounts the component subtree, so the seek '
    'bar reflects the new engine instead of freezing on the old one '
    '(regression: switching engines under a live MovaPlayer left the seek bar '
    'stuck, since the old stateful subtree never unmounted its subscription '
    'to the disposed engine)',
    (t) async {
      final api1 = FakeMovaApi();
      api1.push(const MovaState(duration: Duration(seconds: 100)));
      await t.pumpWidget(MaterialApp(home: MovaPlayer(api: api1)));
      await t.pump();
      api1.pushProgress(const MovaProg(position: Duration(seconds: 40)));
      await t.pump();
      await t.pump();
      expect(t.widget<Slider>(find.byType(Slider)).value, 40000);

      // Same widget position, same type, no key — exactly what the demo app
      // does when switching sources by rebuilding with a fresh MovaEngine.
      final api2 = FakeMovaApi();
      api2.push(const MovaState(duration: Duration(seconds: 100)));
      await t.pumpWidget(MaterialApp(home: MovaPlayer(api: api2)));
      await t.pump();
      api2.pushProgress(const MovaProg(position: Duration(seconds: 5)));
      await t.pump();
      await t.pump();

      expect(t.widget<Slider>(find.byType(Slider)).value, 5000);

      await api1.dispose();
      await api2.dispose();
    },
  );

  testWidgets(
    'changing renderHandle alone, without pushing a state change, does not rebuild the render surface',
    (t) async {
      final api = FakeMovaApi();
      await t.pumpWidget(MaterialApp(home: MovaPlayer(api: api)));
      await t.pump();
      final before = _surfaceKey(t);

      api.renderHandle = 'new-handle';
      await t.pump();
      final after = _surfaceKey(t);

      expect(after, equals(before));
      await api.dispose();
    },
  );

  testWidgets(
    'changing renderHandle and bumping renderEpoch rebuilds the surface with the new handle',
    (t) async {
      final api = FakeMovaApi();
      await t.pumpWidget(MaterialApp(home: MovaPlayer(api: api)));
      await t.pump();

      api.renderHandle = 'new-handle';
      api.bumpRenderEpoch();
      await t.pump();
      await t.pump();

      expect((_surfaceKey(t) as ValueKey<Object?>).value, 'new-handle');
      await api.dispose();
    },
  );

  testWidgets('renderEpoch stays 0 across a plain FakeMovaApi state push', (t) async {
    final api = FakeMovaApi();
    await t.pumpWidget(MaterialApp(home: MovaPlayer(api: api)));
    await t.pump();
    expect(api.state.renderEpoch, 0);
    await api.dispose();
  });

  testWidgets('a null renderHandle mounts the placeholder branch without throwing', (t) async {
    // The audio-only shape: no VideoController was ever created, so the
    // handle is null and the surface falls into the placeholder branch.
    //
    // 仅音频形态：从未创建过 VideoController，句柄为 null，渲染面落入占位分支。
    final api = FakeMovaApi();
    expect(api.renderHandle, isNull);
    await t.pumpWidget(MaterialApp(home: MovaPlayer(api: api)));
    await t.pump();

    expect(t.takeException(), isNull);
    expect((_surfaceKey(t) as ValueKey<Object?>).value, isNull);
    await api.dispose();
  });

  testWidgets('a custom surface replaces the render surface entirely under audio-only', (t) async {
    // Proves the audio-only cover/waveform/lyrics panel needs no MovaAudioSkin:
    // MovaPlayer.surface is already the hook for it.
    //
    // 证明仅音频场景的封面/波形/歌词面无需 MovaAudioSkin：MovaPlayer.surface
    // 本来就是那个口子。
    final api = FakeMovaApi();
    await t.pumpWidget(MaterialApp(
      home: MovaPlayer(
        api: api,
        surface: const ColoredBox(key: ValueKey('cover'), color: Color(0xFF123456)),
      ),
    ));
    await t.pump();

    expect(find.byKey(const ValueKey('cover')), findsOneWidget);
    expect(
      find.byWidgetPredicate((w) => w.key.runtimeType.toString() == '_RenderHandleKey'),
      findsNothing,
      reason: '_RenderSurface is never constructed when a surface is supplied / '
          '传入 surface 时 _RenderSurface 根本不会被构造',
    );
    await api.dispose();
  });

  testWidgets('switching from an audio-only handle to a video one rebuilds the surface', (t) async {
    // The reverse path MovaSwapEngine makes possible: one tree, audio engine
    // swapped out for a video engine.
    //
    // MovaSwapEngine 打开的反向路径：同一棵树上，音频引擎换成视频引擎。
    final api = FakeMovaApi();
    await t.pumpWidget(MaterialApp(home: MovaPlayer(api: api)));
    await t.pump();
    expect((_surfaceKey(t) as ValueKey<Object?>).value, isNull);

    api.renderHandle = 'video-handle';
    api.bumpRenderEpoch();
    await t.pump();
    await t.pump();

    expect((_surfaceKey(t) as ValueKey<Object?>).value, 'video-handle');
    await api.dispose();
  });
}
