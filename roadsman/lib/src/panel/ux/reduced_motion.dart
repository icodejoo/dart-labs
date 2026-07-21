/// Listens for the system "reduce motion" preference and globally disables
/// animations when it is set.
///
/// Ported from `src/panel/ux/reduced-motion.ts`. The TS version listens to
/// the browser's `prefers-reduced-motion` media query; Flutter reads the
/// same system-level accessibility preference via
/// `MediaQuery.disableAnimations`. There is deliberately no override switch
/// to turn this off——accessibility is not optional.
library;

import 'package:flutter/widgets.dart';

/// Reads whether the system currently prefers reduced motion.
///
/// Usage: call this inside a widget's `build()` (it depends on
/// `MediaQuery`, so it will trigger a rebuild automatically when the
/// preference changes), then use the result to set
/// `RoadPanel.animDurationMs` to 0.
///
/// ```dart
/// final reduced = prefersReducedMotion(context);
/// RoadPanel(..., animDurationMs: reduced ? 0 : 280);
/// ```
bool prefersReducedMotion(BuildContext context) => MediaQuery.of(context).disableAnimations;
