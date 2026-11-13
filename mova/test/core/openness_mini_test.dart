import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mova/src/core/api.dart';
import 'package:mova/src/core/mini/placement.dart';
import 'package:mova/src/core/options/options.dart';
import 'package:mova/src/ui/mini/mini.dart';
import 'package:mova/src/ui/mini/mini_ui_kit.dart';
import 'package:mova/src/ui/ui_kits/ui_kit.dart';
import 'package:mova/src/ui/slots/component.dart';
import 'package:mova/src/ui/slots/tree.dart';

import '../support/fake_api.dart';

void main() {
  group('App 内小窗开放性对账 — 每条决策都需齐默认值 + 配置项 + 可注入策略', () {
    test('小窗挂在哪：不替宿主决定——show（方式 B）与 showInPage（方式 A）并存，宿主也可绕开两者自建容器', () {
      expect(MovaMiniMount.values, containsAll([MovaMiniMount.none, MovaMiniMount.page, MovaMiniMount.persistent]));
      // 可执行证明：MovaMini 本身对"谁挂载它"零假设——rect/uiKit/api 三个
      // 真值源与挂载方式完全解耦，见 mini.dart 的字段设计。
      final mini = MovaMini();
      expect(mini.mount, MovaMiniMount.none);
    });

    test('小窗多大：默认值 180 / 16:9，配置项 width/aspectRatio', () {
      const c = MovaMiniOpts();
      expect(c.width, 180);
      expect(c.aspectRatio, 16 / 9);
      const custom = MovaMiniOpts(width: 240, aspectRatio: 4 / 3);
      expect(custom.width, 240);
      expect(custom.aspectRatio, 4 / 3);
    });

    test('落在哪：默认右下角吸边，配置项 initialCorner/snapToEdge/margin，可注入 IMovaMiniPlacement', () {
      const c = MovaMiniOpts();
      expect(c.initialCorner, MovaMiniCorner.bottomRight);
      expect(c.effectivePlacement, isA<MovaCornerSnap>());

      final injected = _FixedPlacement();
      final c2 = MovaMiniOpts(placement: injected);
      expect(c2.effectivePlacement, same(injected));
    });

    test('小窗里放什么 chrome：默认 MovaMiniUiKit，MovaMini.show(uiKit:) 可换成任意 IMovaUiKit', () async {
      final mini = MovaMini();
      expect(mini.uiKit, isA<MovaMiniUiKit>());
      final api = FakeMovaApi(options: const MovaOpts(mini: MovaMiniOpts(enabled: true)));
      final customUiKit = _EmptyUiKit();
      await mini.show(api, uiKit: customUiKit);
      expect(mini.uiKit, same(customUiKit));
    });

    test('关闭后播放器怎么办：默认不 dispose，宿主经 onClosed 回调决定', () async {
      final mini = MovaMini();
      final api = FakeMovaApi(options: const MovaOpts(mini: MovaMiniOpts(enabled: true)));
      IMovaApi? closedWith;
      mini.onClosed = (a) => closedWith = a;
      await mini.show(api);
      await mini.close();
      expect(closedWith, same(api));
      expect(api.disposed, isFalse, reason: '默认不 dispose，是否 dispose 完全交给宿主的 onClosed 回调决定');
    });
  });
}

/// A fixed, no-op [IMovaMiniPlacement] used only to prove injection wins over
/// the built-in default.
///
/// 一个固定、空操作的 [IMovaMiniPlacement]，仅用于证明注入优先于内置默认值。
class _FixedPlacement implements IMovaMiniPlacement {
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

/// A minimal [IMovaUiKit] used only to prove [MovaMini.show] accepts any
/// UI kit, not just [MovaMiniUiKit].
///
/// 一个最简 [IMovaUiKit]，仅用于证明 [MovaMini.show] 接受任意 UI 套件，而非
/// 只认 [MovaMiniUiKit]。
class _EmptyUiKit implements IMovaUiKit {
  @override
  List<MovaComponent> components() => const [];

  @override
  Widget assemble(BuildContext context, MovaSlotBundle slots, Widget video) => video;
}
