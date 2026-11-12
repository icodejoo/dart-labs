import 'package:flutter/widgets.dart';

import '../control/controller.dart';
import '../foundation/image.dart';
import '../motion/result.dart';
import '../render/renderer.dart';
import '../widgets/item_overlay.dart';
import 'frame.dart';
import 'layout.dart';

/// 命中对象类型。
enum LuckyHitKind {
  /// 可开始抽奖的按钮。
  button,

  /// 可点击条目。
  item,
}

/// 命中结果；例如 `const LuckyHit.button(0)`。
@immutable
final class LuckyHit {
  /// 命中第 [index] 个按钮。
  const LuckyHit.button(this.index) : kind = LuckyHitKind.button;

  /// 命中第 [index] 个条目。
  const LuckyHit.item(this.index) : kind = LuckyHitKind.item;

  /// 命中类型。
  final LuckyHitKind kind;

  /// 命中对象下标。
  final int index;
}

/// 拖动事件阶段。
enum LuckyPanPhase {
  /// 拖动开始。
  start,

  /// 拖动移动。
  update,

  /// 拖动结束。
  end,
}

/// 玩法收到的局部拖动事件。
@immutable
final class LuckyPanEvent {
  /// 指定事件阶段与局部位置。
  const LuckyPanEvent(this.phase, this.localPosition);

  /// 拖动阶段。
  final LuckyPanPhase phase;

  /// 相对玩法盒子的局部坐标。
  final Offset localPosition;
}

/// 无状态玩法 SPI；实现后可传给 LuckyGameView，无需修改 core。
abstract class LuckyGame<C extends Object, L extends LuckyLayout,
    F extends LuckyFrame, R extends LuckyResult<Object?>> {
  /// 常量构造。
  const LuckyGame();

  /// 由 [config] 和环境计算确定性布局。
  L computeLayout(C config, LuckyLayoutInput input);

  /// 返回全部命中；重叠按钮按列表顺序逐个触发，无命中返回空。
  List<LuckyHit> hitTestAll(C config, L layout, F frame, Offset position) =>
      const [];

  /// 返回本布局所需图片及解码尺寸提示。
  List<LuckyImageRequest> collectImages(C config, L layout);

  /// 按运行环境（例如系统减少动效）解析实际使用的配置；默认原样返回。
  ///
  /// 宿主每次构建都会调用，返回值与上次应用的配置不相等时重新计算布局并配置控制器；
  /// 实现必须在环境不变时返回相等的配置，否则每帧都会重配。
  C resolveConfig(BuildContext context, C config) => config;

  /// 创建宿主拥有的默认控制器。
  LuckyController<C, L, F, R> createController();

  /// 创建玩法自身的默认渲染器。
  LuckyRenderer<C, L, F, R> createDefaultRenderer();

  /// 判断是否改变条目数等结构，以便减速期间延后应用。
  bool isStructuralChange(C oldConfig, C newConfig);

  /// 返回默认无障碍标签。
  String semanticsLabel(C config);

  /// 可选条目几何；未提供时不支持条目叠加。
  LuckyItemGeometry<L, F>? get itemGeometry => null;

  /// 是否启用拖动手势。
  bool get wantsPanGestures => false;

  /// 接收拖动事件；默认无操作。
  void handlePan(
      LuckyController<C, L, F, R> controller, L layout, LuckyPanEvent event) {}
}
