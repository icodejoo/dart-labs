import 'package:mova/mova.dart' show MovaCutover, MovaOpts, MovaCutoverOpts, MovaSource, MovaWarmPlan, MovaEagerWarm;
import 'package:mova/src/core/kernel/restart_observer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mova/src/core/keep_alive/keep_alive.dart';
import 'package:mova/src/core/state/state.dart';
import 'package:mova/src/ui/player.dart';
import 'package:mova/src/ui/poster.dart';
import 'package:mova/src/ui/ui_kits/ui_kit.dart';
import 'package:mova/src/ui/slots/component.dart';
import 'package:mova/src/ui/slots/tree.dart';

import '../support/fake_api.dart';

/// A UI kit that records the `video` widget it was handed and draws a marker on
/// top of it, to prove chrome sits above the poster.
///
/// 记录收到的 `video` 组件，并在其上画一个标记的 UI 套件，用来证明 chrome 在封面之上。
class _RecordingUiKit implements IMovaUiKit {
  Widget? video;

  @override
  List<MovaComponent> components() => const [];

  @override
  Widget assemble(BuildContext context, MovaSlotBundle slots, Widget video) {
    this.video = video;
    return Stack(children: [Positioned.fill(child: video), const SizedBox(key: ValueKey('chrome'))]);
  }
}

const _poster = SizedBox(key: ValueKey('poster'), width: 10, height: 10);
const _fade = Duration(milliseconds: 300);

/// Mounts a player with a poster over [api] using [uiKit].
///
/// 用 [uiKit] 在 [api] 上挂一个带封面的播放器。
Future<void> _mount(WidgetTester t, FakeMovaApi api, IMovaUiKit uiKit, {Widget? poster = _poster}) async {
  await t.pumpWidget(MaterialApp(
    home: MovaPlayer(api: api, uiKit: uiKit, poster: poster, posterFade: _fade),
  ));
  await t.pump();
}

/// Pushes [s] and pumps twice: once for the stream delivery, once for the rebuild.
///
/// 推送 [s] 并 pump 两次：一次等流投递，一次等重建。
Future<void> _push(WidgetTester t, FakeMovaApi api, MovaState s) async {
  api.push(s);
  await t.pump();
  await t.pump();
}

AnimatedOpacity _opacity(WidgetTester t) =>
    t.widget<AnimatedOpacity>(find.descendant(of: find.byType(MovaPosterLayer), matching: find.byType(AnimatedOpacity)));

/// 记录封面对可选精确首帧能力的请求。
class _RestartApi extends FakeMovaApi implements IMovaRestartObserver {
  /// [options] 控制代理预热；默认保持原配置。
  _RestartApi({super.options});

  /// 请求次数，便于检测动态挂载。
  int requests = 0;
  /// 记录一次精确首帧请求。
  @override
  void observeRestarts() => requests++;
}

void main() {
  testWidgets('A14 cutover forwards poster restarts to current and later shadow players', (t) async {
    final movas = <_RestartApi>[];
    final proxy = MovaCutover(movaFactory: () {
      final e = _RestartApi(options: const MovaOpts(cutover: MovaCutoverOpts(enabled: true)));
      movas.add(e);
      return e;
    });
    await t.pumpWidget(MaterialApp(home: MovaPlayer(api: proxy, poster: _poster)));
    expect(movas.single.requests, 1);
    await t.runAsync(() => proxy.prepare(const MovaSource('https://h/shadow.mp4'), plan: const MovaWarmPlan(trigger: MovaEagerWarm())));
    expect(movas, hasLength(2));
    expect(movas.last.requests, 1);
    proxy.observeRestarts();
    expect(movas.last.requests, 2);
    await t.pumpWidget(const SizedBox());
    await t.runAsync(proxy.dispose);
  });

  testWidgets('A14 poster requests native restarts', (t) async {
    final api = _RestartApi();
    await _mount(t, api, _RecordingUiKit());
    expect(api.requests, 1);
    await api.dispose();
  });

  testWidgets('A14 adding a poster later requests restarts while no poster leaves fallback', (t) async {
    final api = _RestartApi();
    final uiKit = _RecordingUiKit();
    await _mount(t, api, uiKit, poster: null);
    expect(api.requests, 0);
    await _mount(t, api, uiKit);
    expect(api.requests, 1);
    await api.dispose();
  });

  testWidgets('poster: null adds no layer and hands the raw surface to the UI kit', (t) async {
    final api = FakeMovaApi();
    final uiKit = _RecordingUiKit();
    await _mount(t, api, uiKit, poster: null);
    expect(find.byType(MovaPosterLayer), findsNothing);
    expect(uiKit.video, isNot(isA<Stack>()));
    await api.dispose();
  });

  testWidgets('the poster starts fully opaque', (t) async {
    final api = FakeMovaApi();
    await _mount(t, api, _RecordingUiKit());
    expect(_opacity(t).opacity, 1);
    await api.dispose();
  });

  testWidgets('rendered with a picture size fades the poster out over posterFade', (t) async {
    final api = FakeMovaApi();
    await _mount(t, api, _RecordingUiKit());
    await _push(t, api, const MovaState(rendered: true, width: 1280, height: 720));
    final o = _opacity(t);
    expect(o.opacity, 0);
    expect(o.duration, _fade);
    await t.pump(_fade);
    expect(_opacity(t).opacity, 0);
    await api.dispose();
  });

  testWidgets('rendered without a picture size keeps the poster visible', (t) async {
    final api = FakeMovaApi();
    await _mount(t, api, _RecordingUiKit());
    await _push(t, api, const MovaState(rendered: true));
    expect(_opacity(t).opacity, 1);
    await api.dispose();
  });

  testWidgets('rendered flipping back to false re-covers instantly', (t) async {
    final api = FakeMovaApi();
    await _mount(t, api, _RecordingUiKit());
    await _push(t, api, const MovaState(rendered: true, width: 1280, height: 720));
    await t.pump(_fade);
    await _push(t, api, const MovaState(width: 1280, height: 720));
    final o = _opacity(t);
    expect(o.opacity, 1);
    expect(o.duration, Duration.zero);
    await api.dispose();
  });

  testWidgets('the poster is wrapped in IgnorePointer', (t) async {
    final api = FakeMovaApi();
    await _mount(t, api, _RecordingUiKit());
    expect(
      find.descendant(of: find.byType(MovaPosterLayer), matching: find.byType(IgnorePointer)),
      findsWidgets,
    );
    final ip = t.widget<IgnorePointer>(
        find.descendant(of: find.byType(MovaPosterLayer), matching: find.byType(IgnorePointer)).first);
    expect(ip.ignoring, isTrue);
    await api.dispose();
  });

  testWidgets('the poster is a descendant of the video handed to the UI kit (chrome sits above it)', (t) async {
    final api = FakeMovaApi();
    final uiKit = _RecordingUiKit();
    await _mount(t, api, uiKit);
    expect(uiKit.video, isA<Stack>());
    expect(find.descendant(of: find.byWidget(uiKit.video!), matching: find.byKey(const ValueKey('poster'))),
        findsOneWidget);
    expect(find.byKey(const ValueKey('chrome')), findsOneWidget);
    await api.dispose();
  });

  testWidgets('keepAlive: the poster covers at once while holding and while resuming, and fades only once off', (t) async {
    final api = FakeMovaApi();
    await _mount(t, api, _RecordingUiKit());
    const shown = MovaState(rendered: true, width: 1280, height: 720);
    await _push(t, api, shown);
    expect(_opacity(t).opacity, 0);
    await _push(t, api, shown.copyWith(keepAlivePhase: MovaKeepAlivePhase.holding));
    expect(_opacity(t).opacity, 1);
    expect(_opacity(t).duration, Duration.zero);
    await _push(t, api, shown.copyWith(keepAlivePhase: MovaKeepAlivePhase.resuming));
    expect(_opacity(t).opacity, 1);
    await _push(t, api, shown.copyWith(keepAlivePhase: MovaKeepAlivePhase.off));
    expect(_opacity(t).opacity, 0);
    expect(_opacity(t).duration, _fade);
  });

  testWidgets('keepAlive: a fallback pause leaves the poster off, like a plain pause', (t) async {
    final api = FakeMovaApi();
    await _mount(t, api, _RecordingUiKit());
    await _push(t, api, const MovaState(rendered: true, width: 1280, height: 720, keepAlivePhase: MovaKeepAlivePhase.fallback));
    expect(_opacity(t).opacity, 0);
  });

  testWidgets('keepAlive: before a first frame the poster shows whatever the phase is', (t) async {
    final api = FakeMovaApi();
    await _mount(t, api, _RecordingUiKit());
    await _push(t, api, const MovaState(keepAlivePhase: MovaKeepAlivePhase.off));
    expect(_opacity(t).opacity, 1);
  });
}
