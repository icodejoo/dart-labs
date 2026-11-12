/// luckdraw Lots 玩法入口；仅依赖 core 与本玩法。
library;

export 'luckdraw.dart'
    show
        LuckyController,
        LuckyHooks,
        LuckyDrawHook,
        LuckyButtonTapCallback,
        LuckyEasing,
        QuadEasing,
        CubicEasing,
        QuartEasing,
        QuintEasing,
        SineEasing,
        ExpoEasing,
        CircEasing,
        CurveEasing,
        LuckyEasings,
        LuckyBorder,
        LuckyBoxBlock,
        LuckyCellStyle,
        LuckyEdgeInsets,
        LuckyFill,
        LuckyColorFill,
        LuckyGradientFill,
        LuckyLegacyLinearFill,
        LuckyLegacyGradientDirection,
        LuckyGradientKeyword,
        LuckyColorStop,
        LuckyImage,
        LuckyImageFormatter,
        LuckyImageError,
        LuckyLength,
        LuckyPx,
        LuckyPercent,
        LuckyPerformanceOptions,
        LuckyCacheMode,
        LuckyTextScaling,
        LuckyShadow,
        LuckyShadowBlurSpace,
        LuckyText,
        LuckyTextDefaults,
        LuckyTextOverride,
        LuckyGameRegistry,
        LuckyViewBuilder,
        LuckyMotionOptions,
        LuckyPhase,
        LuckyPhaseX,
        LuckyResult,
        LuckyStopSolver,
        MonotonicStopSolver,
        UpstreamStopSolver,
        LuckyTimebase,
        PrizePicker,
        PrizePickContext,
        WeightedPrizePicker,
        GuaranteedPrizePicker,
        LuckyLayer,
        LuckyCallbackLayer,
        LuckyLayerPosition,
        LuckyLayerContext,
        LuckyItemOverlay;
export 'src/lots/control/lots_controller.dart' show LotsController;
export 'src/lots/layout/lots_layout.dart' show LotsLayout;
export 'src/lots/lots_game.dart' show LotsGame;
export 'src/lots/model/lots_config.dart'
    show
        LotsConfig,
        LotsOptions,
        LotsStyle,
        LotsShakeWaveform,
        lotsSineWaveform,
        LotsLayoutAdjuster,
        LotsPartPainter,
        LotsStickBodyPainter;
export 'src/lots/model/lots_parts.dart' show LotsStick, LotsStickPainter;
export 'src/lots/motion/lots_motion.dart' show LotsFrame, LotsStage;
export 'src/lots/render/lots_canvas_renderer.dart' show LotsCanvasRenderer;
export 'src/lots/widgets/lucky_lots.dart' show LuckyLots;
