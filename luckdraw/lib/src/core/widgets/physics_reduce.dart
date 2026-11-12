import 'package:flutter/widgets.dart';

import '../kinematics/physics_options.dart';

/// 是否应按 [physics.reduceMotion] 把物理模式回退到参数化轨迹。
///
/// `always` 恒为真，`never` 恒为假，`system` 跟随 MediaQuery.disableAnimations，
/// 没有 MediaQuery 时视为假；会让调用处依赖 MediaQuery，系统设置变化时随之重建。
bool luckyPhysicsReduced(BuildContext context, LuckyPhysics physics) =>
    physics.reduceMotion == LuckyPhysicsReduceMotion.always ||
    physics.reduceMotion == LuckyPhysicsReduceMotion.system &&
        (MediaQuery.maybeDisableAnimationsOf(context) ?? false);
