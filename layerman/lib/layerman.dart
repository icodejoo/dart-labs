/// A **headless** overlay **queue** orchestrator.
///
/// Manages when/which overlay is shown — serial one-at-a-time queueing with
/// named slots, priority, replace, overlap, conditions and cooldown — while
/// staying UI-agnostic: rendering is delegated to a [Present] backend
/// (showDialog / GetX / bot_toast / a self-managed `OverlayEntry` / ...) that
/// the manager invokes when the queue grants a slot. Overlays expose imperative
/// `Future<T?>` results and a two-phase close so a backend can play its exit
/// animation before the queue advances.
library;

export 'src/overlay_manager.dart'
    show
        Layerman,
        OverlayPredicate,
        OverlayCooldown,
        OverlayCooldownStorage,
        MemoryCooldownStorage,
        OverlayRecord,
        PresentContext,
        PresentedOverlay,
        Present;
export 'src/overlay_navigator_observer.dart' show LayermanNavigatorObserver;
