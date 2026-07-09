import 'package:flutter/widgets.dart';

/// Whether the OS "reduce motion" / disable-animations accessibility flag is
/// active. Read from the platform dispatcher so it works in `initState`
/// (no [BuildContext] needed) — the same source [MediaQuery.disableAnimations]
/// derives from.
///
/// countman widgets collapse animation [Duration]s to [Duration.zero] when
/// this is true, snapping straight to the final value. Functional timers
/// (countdown / elapsed) are NOT affected — only decorative animation.
bool get reduceMotion =>
    WidgetsBinding.instance.platformDispatcher.accessibilityFeatures.disableAnimations;

/// [duration] collapsed to [Duration.zero] when [reduceMotion] is active.
Duration motionDuration(Duration duration) =>
    reduceMotion ? Duration.zero : duration;
