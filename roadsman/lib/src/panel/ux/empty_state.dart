/// Empty-state text overlay: shows a hint message centered in the panel
/// when results are empty.
///
/// Ported from `src/panel/ux/empty-state.ts`; the Flutter version is a plain
/// widget that can simply be layered on `RoadPanel` via a `Stack`, without
/// needing to manually add/remove DOM nodes like the TS version does.
library;

import 'package:flutter/material.dart';

/// Empty-state overlay: renders nothing when `message` is an empty string.
class EmptyStateOverlay extends StatelessWidget {
  /// Hint message, defaults to "waiting for the round to start".
  final String message;

  /// Text color.
  final Color color;

  const EmptyStateOverlay({super.key, this.message = 'Waiting for a new shoe', this.color = Colors.white70});

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Center(child: Text(message, style: TextStyle(color: color, fontSize: 14))),
  );
}
