/// Haptic feedback wrapper, disabled by default.
///
/// Ported from `src/panel/ux/haptics.ts`. The TS version wraps
/// `navigator.vibrate`; Flutter uses `HapticFeedback` (which has no vibration
/// duration parameter, so `vibrate()` only ever maps to a single light
/// impact——this is a difference in the mobile platform APIs themselves, not
/// something missed in this port).
library;

import 'package:flutter/services.dart';

/// Haptic feedback options.
class HapticsOptions {
  /// Whether enabled by default; defaults to false (in most scenarios,
  /// haptic feedback should be something the user opts into).
  final bool enabled;

  const HapticsOptions({this.enabled = false});
}

/// Haptic feedback effect controller.
class HapticsEffect {
  bool enabled;

  HapticsEffect({this.enabled = false});

  /// Toggle the effect on/off.
  void toggle(bool on) => enabled = on;

  /// Fire a light haptic impact ([ms] is kept only for API parity; the
  /// Flutter side does not distinguish duration).
  void vibrate([int ms = 50]) {
    if (!enabled) return;
    HapticFeedback.lightImpact();
  }
}

/// Create a haptic feedback effect controller.
HapticsEffect createHapticsEffect({HapticsOptions options = const HapticsOptions()}) =>
    HapticsEffect(enabled: options.enabled);
