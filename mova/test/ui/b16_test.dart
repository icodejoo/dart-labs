import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mova/src/core/model/source.dart';
import 'package:mova/src/core/options/options.dart';
import 'package:mova/src/core/state/state.dart';
import 'package:mova/src/ui/components/common.dart';
import 'package:mova/src/ui/player.dart';
import 'package:mova/src/ui/skins/minimal_skin.dart';
import 'package:mova/src/ui/mini/mini_skin.dart';

import '../support/fake_api.dart';

/// 额外记录快捷键相对跳转量的播放替身。
class _KeyApi extends FakeMovaApi {
  /// 使用 [enabled] 设置快捷键开关。
  _KeyApi({bool enabled = true})
    : super(
        options: MovaOpts(controls: MovaCtrlsConfig(shortcuts: enabled)),
      );

  /// 已接收的相对跳转请求。
  final List<Duration> deltas = [];

  /// 记录 [delta] 后沿用替身的调用记录。
  @override
  Future<void> seekBy(Duration delta) async {
    deltas.add(delta);
    await super.seekBy(delta);
  }
}

/// 挂载无按钮皮肤，点击画面为播放器取得键盘焦点。
Future<void> _mount(WidgetTester t, FakeMovaApi api, {Widget? surface}) async {
  await t.pumpWidget(
    MaterialApp(
      home: MovaPlayer(
        api: api,
        skin: const MovaMinimalSkin(showBuffering: false),
        autoLoadQualities: false,
        surface: surface,
      ),
    ),
  );
  await t.tapAt(const Offset(400, 300));
  await t.pump();
  api.calls.clear();
}

void main() {
  testWidgets('B16 图标按钮默认带动作语义和 tooltip，禁用时不可操作', (t) async {
    final semantics = t.ensureSemantics();

    await t.pumpWidget(
      MaterialApp(
        home: Center(
          child: MovaIconButton(
            icon: Icons.fullscreen_rounded,
            onPressed: () {},
            theme: const MovaTheme(),
          ),
        ),
      ),
    );
    expect(
      t.getSemantics(find.bySemanticsLabel('进入全屏')),
      isSemantics(
        label: '进入全屏',
        isButton: true,
        isEnabled: true,
        hasTapAction: true,
      ),
    );
    expect(find.byTooltip('进入全屏'), findsOneWidget);
    await t.pumpWidget(
      const MaterialApp(
        home: Center(
          child: MovaIconButton(
            icon: Icons.cast,
            label: '投屏',
            onPressed: null,
            theme: MovaTheme(),
          ),
        ),
      ),
    );
    expect(
      t.getSemantics(find.bySemanticsLabel('投屏')),
      isSemantics(
        label: '投屏',
        isButton: true,
        isEnabled: false,
        hasTapAction: false,
      ),
    );
    await t.sendKeyEvent(LogicalKeyboardKey.tab);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(t.takeException(), isNull);
    final api = _KeyApi(enabled: false);
    addTearDown(api.dispose);
    await t.pumpWidget(MaterialApp(home: MovaPlayer(api: api)));
    expect(
      t.getSemantics(find.bySemanticsLabel('播放')),
      isSemantics(isButton: true, hasTapAction: true),
    );
    api.push(const MovaState(playing: true));
    await t.pumpAndSettle();
    expect(find.byTooltip('暂停'), findsOneWidget);
    await t.pumpWidget(
      MaterialApp(
        home: MovaPlayer(
          api: api,
          skin: MovaMiniSkin(onClose: () {}),
        ),
      ),
    );
    expect(find.byTooltip('关闭小窗'), findsOneWidget);
    for (final entry in {
      Icons.picture_in_picture_alt_rounded: '画中画',
      Icons.high_quality_rounded: '清晰度',
      Icons.aspect_ratio_rounded: '画面比例',
      Icons.screen_rotation_rounded: '旋转屏幕',
      Icons.fullscreen_exit_rounded: '退出全屏',
      Icons.lock_open_rounded: '锁定控制',
      Icons.lock_rounded: '解锁控制',
      Icons.subtitles_rounded: '字幕选择',
      Icons.subtitles_off_rounded: '字幕选择',
      Icons.speed_rounded: '播放速度',
      Icons.sync_rounded: '回到直播',
    }.entries) {
      await t.pumpWidget(
        MaterialApp(
          home: Center(
            child: MovaIconButton(
              icon: entry.key,
              caption: '当前值',
              onPressed: () {},
              theme: const MovaTheme(),
            ),
          ),
        ),
      );
      expect(find.byTooltip('${entry.value}：当前值'), findsOneWidget);
    }
    semantics.dispose();
  });

  testWidgets('B16 Tab 聚焦并显示边框，Enter 激活无 Material/Overlay 祖先的按钮', (t) async {
    var presses = 0;
    await t.pumpWidget(
      WidgetsApp(
        color: Colors.black,
        builder: (context, _) => FocusScope(
          autofocus: true,
          child: Center(
          child: MovaIconButton(
            icon: Icons.fullscreen_rounded,
            onPressed: () => presses++,
            theme: const MovaTheme(),
          ),
          ),
        ),
      ),
    );
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.tab);
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pump();
    expect(presses, 1);
    final box = t.widget<DecoratedBox>(
      find
          .descendant(
            of: find.byType(MovaIconButton),
            matching: find.byType(DecoratedBox),
          )
          .first,
    );
    expect(
      (box.decoration as BoxDecoration).border!.top.color,
      isNot(Colors.transparent),
    );
  });

  testWidgets('B16 空格激活聚焦按钮一次，不触发播放器空格动作', (t) async {
    var presses = 0;
    final api = _KeyApi();
    addTearDown(api.dispose);
    await _mount(
      t,
      api,
      surface: Center(
        child: MovaIconButton(
          icon: Icons.fullscreen_rounded,
          onPressed: () => presses++,
          theme: const MovaTheme(),
        ),
      ),
    );
    presses = 0;
    await t.sendKeyEvent(LogicalKeyboardKey.tab);
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.space);
    await t.pump();
    expect(presses, 1);
    expect(api.calls, contains('showControls'));
    expect(api.calls, isNot(contains('playOrPause')));
  });

  testWidgets('B16 悬停唤出控制条，锁定和 PiP/mini 不唤出', (t) async {
    final api = _KeyApi(enabled: false);
    addTearDown(api.dispose);
    await _mount(t, api);
    final mouse = await t.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(1, 1));
    await mouse.moveTo(const Offset(200, 200));
    await t.pump();
    expect(api.calls, contains('showControls'));
    for (final state in [
      const MovaState(locked: true),
      const MovaState(pip: true),
      const MovaState(mini: true),
    ]) {
      api.push(state);
      api.calls.clear();
      await mouse.moveTo(Offset(210 + state.hashCode % 20, 210));
      await t.pump();
      expect(api.calls, isNot(contains('showControls')));
    }
    await mouse.removePointer();
  });

  testWidgets('B16 快捷键默认关闭，配置值比较包含 shortcuts', (t) async {
    expect(const MovaCtrlsConfig().shortcuts, isFalse);
    expect(
      const MovaCtrlsConfig(shortcuts: true),
      isNot(const MovaCtrlsConfig()),
    );
    expect(
      const MovaCtrlsConfig(shortcuts: true).hashCode,
      isNot(const MovaCtrlsConfig().hashCode),
    );
    final api = _KeyApi(enabled: false);
    addTearDown(api.dispose);
    await _mount(t, api);
    for (final key in [
      LogicalKeyboardKey.space,
      LogicalKeyboardKey.arrowRight,
      LogicalKeyboardKey.keyF,
    ]) {
      await t.sendKeyEvent(key);
    }
    expect(api.calls, isEmpty);
  });

  testWidgets('B16 启用后空格播放暂停，按住不重复切换', (t) async {
    final api = _KeyApi();
    addTearDown(api.dispose);
    await _mount(t, api);
    await t.sendKeyDownEvent(LogicalKeyboardKey.space);
    await t.sendKeyRepeatEvent(LogicalKeyboardKey.space);
    await t.sendKeyUpEvent(LogicalKeyboardKey.space);
    await t.pump();
    expect(api.calls.where((call) => call == 'playOrPause'), hasLength(1));
    expect(api.calls, contains('showControls'));
  });

  testWidgets('B16 方向键跳转十秒、音量钳制，不可拖动直播不跳转', (t) async {
    final api = _KeyApi();
    addTearDown(api.dispose);
    await _mount(t, api);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await t.pump();
    expect(api.deltas, [
      const Duration(seconds: -10),
      const Duration(seconds: 10),
    ]);
    api.push(const MovaState(volume: 98));
    await t.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await t.pump();
    expect(api.lastVolume, 100);
    api.push(const MovaState(volume: 2));
    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await t.pump();
    expect(api.lastVolume, 0);
    api.push(const MovaState(type: MovaStreamType.live));
    await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    expect(api.deltas, hasLength(2));
    api.push(const MovaState(type: MovaStreamType.live, liveSeekable: true));
    await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    expect(api.deltas, hasLength(3));
  });

  testWidgets('B16 F 切换全屏，Esc 仅在全屏时退出', (t) async {
    final api = _KeyApi();
    addTearDown(api.dispose);
    await _mount(t, api);
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    expect(api.lastFullscreen, isNull);
    await t.sendKeyEvent(LogicalKeyboardKey.keyF);
    await t.pump();
    expect(api.lastFullscreen, isTrue);
    api.push(const MovaState(fullscreen: true));
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pump();
    expect(api.lastFullscreen, isFalse);
  });

  testWidgets('B16 锁定、PiP、mini 和编辑文本时不劫持按键', (t) async {
    final api = _KeyApi();
    addTearDown(api.dispose);
    await _mount(t, api);
    for (final state in [
      const MovaState(locked: true),
      const MovaState(pip: true),
      const MovaState(mini: true),
    ]) {
      api.push(state);
      await t.sendKeyEvent(LogicalKeyboardKey.space);
      await t.sendKeyEvent(LogicalKeyboardKey.keyF);
      expect(api.calls, isEmpty);
    }
    api.push(const MovaState());
    final controller = TextEditingController(text: 'abc');
    addTearDown(controller.dispose);
    await _mount(
      t,
      api,
      surface: Scaffold(body: TextField(controller: controller)),
    );
    await t.tap(find.byType(TextField));
    await t.pump();
    api.calls.clear();
    await t.sendKeyEvent(LogicalKeyboardKey.space);
    await t.sendKeyEvent(LogicalKeyboardKey.keyF);
    expect(api.calls, isEmpty);
    await t.enterText(find.byType(TextField), '正常输入');
    expect(controller.text, '正常输入');
  });

  testWidgets('B16 多播放器只响应获得焦点的视图，换 api 后使用新实例', (t) async {
    final a = _KeyApi();
    final b = _KeyApi();
    addTearDown(a.dispose);
    addTearDown(b.dispose);
    await t.pumpWidget(
      MaterialApp(
        home: Row(
          children: [
            Expanded(
              child: MovaPlayer(
                api: a,
                skin: const MovaMinimalSkin(showBuffering: false),
              ),
            ),
            Expanded(
              child: MovaPlayer(
                api: b,
                skin: const MovaMinimalSkin(showBuffering: false),
              ),
            ),
          ],
        ),
      ),
    );
    await t.tapAt(const Offset(200, 300));
    await t.pump();
    a.calls.clear();
    b.calls.clear();
    await t.sendKeyEvent(LogicalKeyboardKey.space);
    await t.pump();
    expect(a.calls, contains('playOrPause'));
    expect(b.calls, isEmpty);
    await t.tapAt(const Offset(600, 300));
    await t.pump();
    a.calls.clear();
    await t.sendKeyEvent(LogicalKeyboardKey.space);
    await t.pump();
    expect(a.calls, isEmpty);
    expect(b.calls, contains('playOrPause'));
    await _mount(t, a);
    await _mount(t, b);
    await t.sendKeyEvent(LogicalKeyboardKey.space);
    expect(b.calls, contains('playOrPause'));
  });
}
