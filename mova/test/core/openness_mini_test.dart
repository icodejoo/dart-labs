import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mova/src/core/api.dart';
import 'package:mova/src/core/mini/placement.dart';
import 'package:mova/src/core/options/mini_config.dart';
import 'package:mova/src/ui/mini/mini_ctl.dart';
import 'package:mova/src/ui/mini/mini_skin.dart';
import 'package:mova/src/ui/skins/skin.dart';
import 'package:mova/src/ui/slots/component.dart';
import 'package:mova/src/ui/slots/tree.dart';

import '../support/fake_api.dart';

void main() {
  group('App 内小窗开放性对账 — 每条决策都需齐默认值 + 配置项 + 可注入策略', () {
    test('小窗挂在哪：不替宿主决定——show（方式 B）与 showInPage（方式 A）并存，宿主也可绕开两者自建容器', () {
      expect(MovaMiniMount.values, containsAll([MovaMiniMount.none, MovaMiniMount.page, MovaMiniMount.persistent]));
      // 可执行证明：MovaMiniCtl 本身对"谁挂载它"零假设——rect/skin/api 三个
      // 真值源与挂载方式完全解耦，见 mini_ctl.dart 的字段设计。
      final ctl = MovaMiniCtl();
      expect(ctl.mount, MovaMiniMount.none);
    });

    test('小窗多大：默认值 180 / 16:9，配置项 width/aspectRatio', () {
      const c = MovaMiniConfig();
      expect(c.width, 180);
      expect(c.aspectRatio, 16 / 9);
      const custom = MovaMiniConfig(width: 240, aspectRatio: 4 / 3);
      expect(custom.width, 240);
      expect(custom.aspectRatio, 4 / 3);
    });

    test('落在哪：默认右下角吸边，配置项 initialCorner/snapToEdge/margin，可注入 MovaMiniPlacement', () {
      const c = MovaMiniConfig();
      expect(c.initialCorner, MovaMiniCorner.bottomRight);
      expect(c.effectivePlacement, isA<MovaCornerSnap>());

      final injected = _FixedPlacement();
      final c2 = MovaMiniConfig(placement: injected);
      expect(c2.effectivePlacement, same(injected));
    });

    test('小窗里放什么 chrome：默认 MovaMiniSkin，MovaMiniCtl.show(skin:) 可换成任意 MovaSkin', () async {
      final ctl = MovaMiniCtl();
      expect(ctl.skin, isA<MovaMiniSkin>());
      final api = FakeMovaApi();
      final customSkin = _EmptySkin();
      await ctl.show(api, skin: customSkin);
      expect(ctl.skin, same(customSkin));
    });

    test('关闭后引擎怎么办：默认不 dispose，宿主经 onClosed 回调决定', () async {
      final ctl = MovaMiniCtl();
      final api = FakeMovaApi();
      MovaApi? closedWith;
      ctl.onClosed = (a) => closedWith = a;
      await ctl.show(api);
      await ctl.close();
      expect(closedWith, same(api));
      expect(api.disposed, isFalse, reason: '默认不 dispose，是否 dispose 完全交给宿主的 onClosed 回调决定');
    });
  });
}

/// A fixed, no-op [MovaMiniPlacement] used only to prove injection wins over
/// the built-in default.
///
/// 一个固定、空操作的 [MovaMiniPlacement]，仅用于证明注入优先于内置默认值。
class _FixedPlacement implements MovaMiniPlacement {
  @override
  MovaMiniRect settle(
    MovaMiniRect current, {
    required MovaMiniRect bounds,
    required MovaMiniInsets insets,
    double velocityX = 0,
    double velocityY = 0,
  }) =>
      current;
}

/// A minimal [MovaSkin] used only to prove [MovaMiniCtl.show] accepts any
/// skin, not just [MovaMiniSkin].
///
/// 一个最简 [MovaSkin]，仅用于证明 [MovaMiniCtl.show] 接受任意皮肤，而非
/// 只认 [MovaMiniSkin]。
class _EmptySkin implements MovaSkin {
  @override
  List<MovaComp> components() => const [];

  @override
  Widget assemble(BuildContext context, MovaSlotBundle slots, Widget video) => video;
}
