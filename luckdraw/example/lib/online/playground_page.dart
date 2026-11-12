import 'package:flutter/material.dart';

import '../demo_kit/demo_kit.dart';
import '../pages/capsule_page.dart';
import '../pages/compat_page.dart';
import '../pages/grid_page.dart';
import '../pages/lever_page.dart';
import '../pages/lots_page.dart';
import '../pages/lotto_page.dart';
import '../pages/number_wheel_page.dart';
import '../pages/overlay_page.dart';
import '../pages/slot_page.dart';
import '../pages/wheel_page.dart';

/// 线上导航对应的三个演示分组。
enum PlaygroundGroup {
  /// 八种抽奖玩法。
  games,

  /// 显式开启的实验性物理碰撞。
  physics,

  /// JSON 迁移与动画 Widget 叠加。
  integration,
}

/// 双语演示卡片的静态描述。
class _Example {
  /// 创建文案和可独立重挂载的页面主体。
  const _Example(this.en, this.zh, this.detailEn, this.detailZh, this.child);

  /// 英文标题。
  final String en;

  /// 中文标题。
  final String zh;

  /// 英文操作说明。
  final String detailEn;

  /// 中文操作说明。
  final String detailZh;

  /// 持有自身控制器生命周期的原有演示。
  final Widget child;
}

/// 八种玩法复用当前公开 API 与原有画布配置。
const _games = [
  _Example('Wheel', '抽奖转盘', 'Spin, then land on the server-selected prize.',
      '开始旋转，再由模拟服务端指定奖品。', WheelPage()),
  _Example('Nine-grid', '九宫格', 'Follow the highlight around eight prizes.',
      '观察高亮沿八个奖品循环并停下。', GridPage()),
  _Example('Slot machine', '老虎机', 'Three reels stop at independent indices.',
      '三个滚轮按各自目标下标停下。', SlotPage()),
  _Example('Lever slots', '拉霸机', 'Pull the lever or use Start to spin.',
      '拖动拉杆或点击开始，再返回模拟结果。', LeverPage()),
  _Example(
      'Capsule machine',
      '扭蛋机',
      'Turn the knob, mix, drop and open a capsule.',
      '转动旋钮，观察搅拌、掉落和开蛋。',
      CapsulePage()),
  _Example('Number wheel', '数字转盘', 'The ball lands on the selected number: 8.',
      '小球与圆盘反向旋转，停在指定号码 8。', NumberWheelPage()),
  _Example('Drawing lots', '抽签', 'Shake, raise a stick and reveal its fortune.',
      '摇签、升签，再展示选中的签文。', LotsPage()),
  _Example(
      'Lotto draw',
      '大乐透',
      'Reveal five front and two back numbers in order.',
      '按服务端顺序逐球揭晓前五后二区号码。',
      LottoPage()),
];

/// 两种实验性碰撞模式，分别拥有完整重放生命周期。
const _physics = [
  _Example(
      'Capsule collisions',
      '扭蛋物理碰撞',
      'Falling capsules collide with the globe and arms.',
      '胶囊从顶部落下，与球壁及拨杆发生碰撞。',
      CapsulePage(initialPhysics: true)),
  _Example(
      'Lotto collisions',
      '大乐透物理碰撞',
      'Colliding balls keep the same server-selected results.',
      '号码球碰撞，开奖结果仍由模拟服务端指定。',
      LottoPage(initialPhysics: true)),
];

/// 把迁移与扩展整合到同一页面，避免重复玩法导航。
const _integration = [
  _Example(
      'JSON migration',
      'JSON 配置迁移',
      'Convert lucky-canvas JSON with the strict preset.',
      '使用严格预设转换 lucky-canvas JSON。',
      CompatPage()),
  _Example(
      'Animated overlays',
      '动画 Widget 叠加',
      'Replay also restarts every rotating gift Widget.',
      '重放会同时重启转盘和自转礼物 Widget。',
      OverlayPage()),
];

/// 当前控制器调用示例，代码中的标识符不参与翻译。
const _gameCode = '''final controller = WheelController();
final config = WheelConfig(prizes: [
  WheelPrize(texts: [LuckyText('A')]),
  WheelPrize(texts: [LuckyText('B')]),
]);
LuckyWheel(config: config, controller: controller);
controller.play();
controller.stop(1);
// SlotController.stopEach([0, 1, 2]);
// NumberWheelController.stopNumber(8);
// LottoController.stopWith(LottoDraw([[7, 1, 18, 25, 35], [12, 3]]));
controller.dispose();''';

/// 两种碰撞模式的显式开关。
const _physicsCode = '''const capsule = CapsuleConfig(
  options: CapsuleOptions(physics: LuckyPhysics()),
);
final lotto = LottoConfig.superLotto(
  options: const LottoOptions(
    sortResults: false,
    physics: LuckyPhysics(),
  ),
);''';

/// 当前兼容层与叠加扩展的公开契约。
const _integrationCode = '''final converted = wheelFromLuckyCanvasConfig(
  {'prizes': [{'fonts': [{'text': 'A'}]}]},
  options: LuckyCanvasCompatOptions.strictUpstream(),
);
LuckyWheel(config: converted.config, controller: controller);
// In a custom LuckyRenderer.buildSurface:
LuckyItemOverlay(
  geometry: const WheelGame().itemGeometry,
  layout: data.layout,
  frame: data.frame,
  frameListenable: data.frameListenable,
  children: prizeWidgets,
);''';

/// 不展示开发期预算或历史性能数据的响应式玩法页。
class PlaygroundPage extends StatelessWidget {
  /// 创建指定分组的页面。
  const PlaygroundPage({super.key, required this.group});

  /// 当前导航分组。
  final PlaygroundGroup group;

  /// 按主题排列卡片并提供整行折叠代码。
  @override
  Widget build(BuildContext context) {
    final (en, zh, examples, code) = switch (group) {
      PlaygroundGroup.games => ('Eight games', '八种玩法', _games, _gameCode),
      PlaygroundGroup.physics => (
          'Physics collisions',
          '物理碰撞',
          _physics,
          _physicsCode
        ),
      PlaygroundGroup.integration => (
          'Migration & overlays',
          '迁移与叠加',
          _integration,
          _integrationCode
        ),
    };
    return DemoPage(
      title: tr(context, en, zh),
      description: tr(context, 'Start → Server result. Replay resets the demo.',
          '开始 → 服务端返回；重放会重置演示。'),
      sections: [
        DemoSection(
          title: tr(context, 'Try it', '动手试试'),
          code: code,
          child: DemoGrid(children: [
            for (final example in examples)
              DemoGridItem(
                  child: DemoCard(
                key: ValueKey(example.en),
                title: tr(context, example.en, example.zh),
                description: tr(context, example.detailEn, example.detailZh),
                child: example.child,
              )),
          ]),
        ),
        InfoNote(
          kind: group == PlaygroundGroup.physics
              ? InfoNoteKind.warning
              : InfoNoteKind.tip,
          text: group == PlaygroundGroup.physics
              ? tr(
                  context,
                  'Physics is experimental and opt-in. Results and callbacks match the default mode; reduced motion follows the system.',
                  '物理碰撞为实验性可选模式；结果与回调和默认模式一致，减少动态效果默认跟随系统。')
              : tr(
                  context,
                  'Use canPlay / canStop for controller actions. All controllers are released when you replay or leave the page.',
                  '使用 canPlay / canStop 判断可用操作；重放和离开页面都会释放控制器。'),
        ),
      ],
    );
  }
}
