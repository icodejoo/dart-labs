/// luckdraw 扩展 SPI 入口。
library;

export 'src/core/control/controller.dart'
    show LuckyController, LuckyControllerHost;
export 'src/core/control/hooks.dart'
    show LuckyHooks, LuckyDrawHook, LuckyButtonTapCallback;
export 'src/core/easing/easing.dart'
    show
        LuckyEasing,
        QuadEasing,
        CubicEasing,
        QuartEasing,
        QuintEasing,
        SineEasing,
        ExpoEasing,
        CircEasing,
        CurveEasing,
        LuckyEasings;
export 'src/core/foundation/angles.dart' show luckyDegToRad;
export 'src/core/foundation/border.dart' show LuckyBorder;
export 'src/core/foundation/box_block.dart' show LuckyBoxBlock;
export 'src/core/foundation/cell_style.dart' show LuckyCellStyle;
export 'src/core/foundation/color_utils.dart' show colorAlpha8;
export 'src/core/foundation/constants.dart' show kLuckyReferenceFrameMs;
export 'src/core/foundation/edge_insets.dart' show LuckyEdgeInsets;
export 'src/core/foundation/fill.dart'
    show
        LuckyFill,
        LuckyColorFill,
        LuckyGradientFill,
        LuckyLegacyLinearFill,
        LuckyLegacyGradientDirection,
        LuckyGradientKeyword,
        LuckyColorStop;
export 'src/core/foundation/image.dart'
    show
        LuckyImage,
        LuckyImageFormatter,
        LuckyImageError,
        LuckyImageSlot,
        LuckyImageRequest;
export 'src/core/foundation/length.dart'
    show LuckyLength, LuckyPx, LuckyPercent;
export 'src/core/foundation/options.dart'
    show LuckyPerformanceOptions, LuckyCacheMode, LuckyTextScaling;
export 'src/core/foundation/shadow.dart' show LuckyShadow, LuckyShadowBlurSpace;
export 'src/core/foundation/text.dart'
    show LuckyText, LuckyTextDefaults, LuckyTextOverride;
export 'src/core/game/frame.dart' show LuckyFrame;
export 'src/core/game/game.dart'
    show LuckyGame, LuckyHit, LuckyHitKind, LuckyPanEvent, LuckyPanPhase;
export 'src/core/game/layout.dart' show LuckyLayout, LuckyLayoutInput;
export 'src/core/game/registry.dart' show LuckyGameRegistry, LuckyViewBuilder;
export 'src/core/geometry/canvas_arc.dart' show canvasArcSweep;
export 'src/core/geometry/fan_path.dart' show buildFanPath;
export 'src/core/geometry/image_box.dart'
    show computeImageBox, LuckyImagePlacement;
export 'src/core/geometry/round_rect.dart' show buildRoundRectPath;
export 'src/core/image/image_resolver.dart' show LuckyImageResolver;
export 'src/core/image/image_set.dart' show LuckyImageSet, LuckyResolvedImage;
export 'src/core/kinematics/swirl_mixer.dart'
    show LuckySwirlMixer, packCirclesInCircle;
export 'src/core/motion/clock.dart' show LuckyClock, TickerLuckyClock;
export 'src/core/motion/motion.dart'
    show LuckyMotion, LuckyMotionEvents, LuckyFrameNotifier;
export 'src/core/motion/motion_options.dart' show LuckyMotionOptions;
export 'src/core/motion/phase.dart' show LuckyPhase, LuckyPhaseX;
export 'src/core/motion/result.dart' show LuckyResult;
export 'src/core/motion/stop_solver.dart'
    show
        LuckyStopSolver,
        MonotonicStopSolver,
        UpstreamStopSolver,
        LuckyStopCandidate,
        LuckyStopSelection,
        LuckyStopProblem;
export 'src/core/motion/timebase.dart' show LuckyTimebase;
export 'src/core/motion/timeline.dart' show LuckyTimeline;
export 'src/core/picker/prize_picker.dart'
    show
        PrizePicker,
        PrizePickContext,
        WeightedPrizePicker,
        GuaranteedPrizePicker;
export 'src/core/render/layer.dart'
    show LuckyLayer, LuckyCallbackLayer, LuckyLayerPosition, LuckyLayerContext;
export 'src/core/render/picture_cache.dart' show LuckyPictureCache;
export 'src/core/render/renderer.dart' show LuckyRenderer, LuckySurfaceData;
export 'src/core/text/split_text.dart' show splitLuckyText, removeLineBreaks;
export 'src/core/text/text_line.dart' show LuckyTextLine, layoutLuckyTextLines;
export 'src/core/text/text_measurer.dart'
    show LuckyTextMeasurer, TextPainterMeasurer;
export 'src/core/widgets/game_view.dart' show LuckyGameView;
export 'src/core/widgets/item_overlay.dart'
    show LuckyItemOverlay, LuckyItemGeometry, LuckyItemClipGeometry;
