import 'package:flutter/foundation.dart';

import '../game/frame.dart';
import '../game/layout.dart';
import '../motion/motion.dart';
import '../motion/result.dart';
import 'controller.dart';

/// 持有具体玩法状态机类型的控制器基类，子类无需对 `motion` 向下转型。
///
/// 泛型参数依次为配置、布局、帧、结果、状态机；例如 GridController 继承它并指定 GridMotion，
/// 在子类内用 [typedMotion] 访问。
abstract class LuckyMotionController<
    C extends Object,
    L extends LuckyLayout,
    F extends LuckyFrame,
    R extends LuckyResult<Object?>,
    M extends LuckyMotion<C, L, F, R>> extends LuckyController<C, L, F, R> {
  /// 创建控制器；[motion] 同时交给基类调度。
  LuckyMotionController({required M motion, super.picker, super.random})
      : typedMotion = motion,
        super(motion: motion);

  /// 具体类型的玩法状态机，与基类 `motion` 是同一对象。
  @protected
  final M typedMotion;
}
