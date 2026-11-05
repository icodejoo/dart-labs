/// 不负责渲染的弹层队列编排库。
/// 支持独立槽位、优先级、抢占、叠加、条件和冷却，通过 [Present] 委托展示。
/// 返回可空 Future 结果，并等待后端退场后推进队列。
library;

export 'src/overlay_manager.dart'
    show
        Layerman,
        OverlayPredicate,
        OverlayCooldown,
        OverlayCooldownStorage,
        MemoryCooldownStorage,
        OverlayRecord,
        OverlayTicket,
        OverlayHold,
        PresentContext,
        PresentedOverlay,
        Present;
export 'src/overlay_types.dart'
    show
        OverlayClock,
        OverlayMode,
        RouteMatcher,
        OverlayPhase,
        OverlayEndReason,
        OverlayOutcome,
        OverlayCooldownStatus,
        OverlayEvent,
        OverlayEventType,
        OverlaySlotOptions;
export 'src/overlay_navigator_observer.dart' show LayermanNavigatorObserver;
export 'src/route_managers.dart'
    show DialogManager, BottomSheetManager, presentRoute, OverlayVisibility;
export 'src/lifecycle_binding.dart' show LayermanLifecycle;
