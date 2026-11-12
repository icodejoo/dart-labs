/// 扭蛋机公共入口；只依赖核心与本玩法。
library;

export 'luckdraw.dart';
export 'src/capsule/capsule_game.dart' show CapsuleGame;
export 'src/capsule/control/capsule_controller.dart' show CapsuleController;
export 'src/capsule/layout/capsule_layout.dart' show CapsuleLayout;
export 'src/capsule/model/capsule_config.dart' show CapsuleConfig;
export 'src/capsule/model/capsule_parts.dart'
    show CapsulePrize, CapsulePrizePainter, CapsuleOptions, CapsuleStyle;
export 'src/capsule/motion/capsule_motion.dart' show CapsuleFrame, CapsuleStage;
export 'src/capsule/render/capsule_canvas_renderer.dart'
    show CapsuleCanvasRenderer;
export 'src/capsule/widgets/lucky_capsule_machine.dart'
    show LuckyCapsuleMachine;
