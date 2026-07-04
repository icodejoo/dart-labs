/// A Flutter-native overlay **queue** manager.
///
/// Manages when/which overlay is shown — serial one-at-a-time queueing with
/// named slots, priority, replace and overlap — and actually renders it by
/// inserting real [OverlayEntry]s into an attached [OverlayState]. Overlays
/// expose imperative `Future<T?>` results and a two-phase close for exit
/// animations.
library;

export 'src/overlay_manager.dart'
    show
        OverlayManager,
        OverlayHandle,
        OverlayPhase,
        OverlayContentBuilder,
        OverlayPredicate,
        OverlayCooldown,
        OverlayCooldownStorage,
        MemoryCooldownStorage,
        OverlayRecord,
        PresentContext,
        PresentedOverlay,
        Present;
export 'src/overlay_manager_scope.dart' show OverlayManagerScope;
