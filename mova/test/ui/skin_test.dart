import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mova/src/core/api.dart';
import 'package:mova/src/ui/scope/scope.dart';
import 'package:mova/src/ui/skins/default_skin.dart';
import 'package:mova/src/ui/slots/component.dart';
import 'package:mova/src/ui/slots/patch.dart';
import 'package:mova/src/ui/slots/slot.dart';
import 'package:mova/src/ui/slots/tree.dart';

import '../support/fake_api.dart';

/// A ②-tier customisation: subclass [MovaDefSkin] and override just one
/// protected layer method, reusing the base's components/patches/other layers.
///
/// ②档定制：继承 [MovaDefSkin] 只覆写一个受保护的层方法，复用基类的
/// 组件/补丁/其余各层。
class _MarkedPlaybackSkin extends MovaDefSkin {
  const _MarkedPlaybackSkin();
  @override
  Widget buildPlaybackLayer(BuildContext context, MovaSlotBundle slots, Widget video) {
    return Positioned.fill(
      child: KeyedSubtree(key: const ValueKey('customPlayback'), child: video),
    );
  }
}

/// Minimal leaf carrying a [Key], used to locate where a slot renders.
///
/// 携带 [Key] 的最小叶子组件，用于定位某槽位渲染到何处。
class _Marker extends MovaComp {
  _Marker(this.name, this.slot);
  @override
  final String name;
  @override
  final MovaSlot slot;
  @override
  Widget build(BuildContext c, MovaApi api, List<Widget> children) =>
      SizedBox(key: ValueKey(name), width: 20, height: 20);
}

void main() {
  test('default skin emits one static tree', () {
    const skin = MovaDefSkin();
    final names = skin.components().map((c) => c.name).toList();
    expect(names, containsAll(['gestureLayer', 'hudLayer', 'topBar', 'centerPlay', 'bottomBar']));
  });

  test('the adaptive bottom bar exposes the union of VOD and live children', () {
    // One static node serves both; the union is fixed-order so patch paths
    // never shift by stream type.
    // 一个静态节点同时服务两者；并集顺序固定，patch 路径不随流类型错位。
    final bottom = const MovaDefSkin().components().firstWhere((c) => c.name == 'bottomBar');
    expect(bottom.children.map((c) => c.name), [
      'positionLabel',
      'liveBadge',
      'seekBar',
      'timeshift',
      'durationLabel',
      'backToLive',
    ]);
  });

  test('patches passed to the default skin are applied to its tree', () {
    final skin = MovaDefSkin(patches: [MovaPatch.remove('topBar/pipButton')]);
    final top = skin.components().firstWhere((c) => c.name == 'topBar');
    expect(top.children.map((c) => c.name), isNot(contains('pipButton')));
  });

  testWidgets('assemble stacks video at the bottom and overlays on top', (t) async {
    final api = FakeMovaApi();
    const skin = MovaDefSkin();
    await t.pumpWidget(MaterialApp(
      home: MovaScope(
        api: api,
        child: Builder(builder: (c) {
          final bundle = buildSlots(c, api, skin.components());
          return skin.assemble(c, bundle, const ColoredBox(color: Color(0xFF000000)));
        }),
      ),
    ));
    expect(find.byType(Stack), findsWidgets);
    await api.dispose();
  });

  // Regression: each of the three assembled layers must sit behind its own
  // RepaintBoundary, so the operable layer's frequent repaints (seek-bar
  // ticks, HUD fades) never force the playback/persistent layers to
  // re-raster alongside it, and vice versa.
  //
  // 回归测试：三层各自都要有独立的 RepaintBoundary，使操作层的频繁重绘（进度条
  // tick、HUD 淡出）不会连带播放层/常驻层一起重新光栅化，反之亦然。
  testWidgets('assemble isolates each of the three layers with a RepaintBoundary', (t) async {
    final api = FakeMovaApi();
    const skin = MovaDefSkin();
    await t.pumpWidget(MaterialApp(
      home: MovaScope(
        api: api,
        child: Builder(builder: (c) {
          final bundle = buildSlots(c, api, skin.components());
          return skin.assemble(c, bundle, const ColoredBox(color: Color(0xFF000000)));
        }),
      ),
    ));
    // Scoped to descendants of MovaScope: MaterialApp/the test binding add
    // their own framework-level RepaintBoundarys above it (root view,
    // Navigator overlay), which a global find.byType would also pick up.
    //
    // 限定在 MovaScope 的后代范围内：MaterialApp/测试绑定会在它外层再加自己的
    // 框架级 RepaintBoundary（根视图、Navigator overlay），全局 find.byType
    // 会把那些也算进去。
    expect(
      find.descendant(of: find.byType(MovaScope), matching: find.byType(RepaintBoundary)),
      findsNWidgets(3),
    );
    await api.dispose();
  });

  test('the default tree mounts the preview bubble in the bottomAbove slot', () {
    final tree = const MovaDefSkin().components();
    final preview = tree.firstWhere((c) => c.name == 'preview');
    expect(preview.slot, MovaSlot.bottomAbove);
  });

  testWidgets('assemble renders left/right slot content on the matching edge', (t) async {
    final api = FakeMovaApi();
    final skin = MovaDefSkin(patches: [
      MovaPatch.add(MovaSlot.left, _Marker('leftMark', MovaSlot.left)),
      MovaPatch.add(MovaSlot.right, _Marker('rightMark', MovaSlot.right)),
    ]);
    await t.pumpWidget(MaterialApp(
      home: MovaScope(
        api: api,
        child: Builder(builder: (c) {
          final bundle = buildSlots(c, api, skin.components());
          return skin.assemble(c, bundle, const ColoredBox(color: Color(0xFF000000)));
        }),
      ),
    ));
    final leftBox = t.getRect(find.byKey(const ValueKey('leftMark')));
    final rightBox = t.getRect(find.byKey(const ValueKey('rightMark')));
    final screen = t.getSize(find.byType(MaterialApp));
    // Left marker hugs the left edge; right marker hugs the right edge.
    // 左标记贴左缘，右标记贴右缘。
    expect(leftBox.left, 0);
    expect(rightBox.right, screen.width);
    await api.dispose();
  });

  testWidgets('a subclass can override one layer and reuse the rest', (t) async {
    final api = FakeMovaApi();
    const skin = _MarkedPlaybackSkin();
    await t.pumpWidget(MaterialApp(
      home: MovaScope(
        api: api,
        child: Builder(builder: (c) {
          final bundle = buildSlots(c, api, skin.components());
          return skin.assemble(c, bundle, const ColoredBox(color: Color(0xFF000000)));
        }),
      ),
    ));
    // The overridden playback layer is present...
    // 被覆写的播放层生效……
    expect(find.byKey(const ValueKey('customPlayback')), findsOneWidget);
    // ...while the base's persistent lock toggle still renders (other layers
    // reused). ……而基类常驻层的锁定切换按钮仍在（其余各层被复用）。
    expect(find.byIcon(Icons.lock_open_rounded), findsOneWidget);
    await api.dispose();
  });
}
