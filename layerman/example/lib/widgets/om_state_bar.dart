import 'package:flutter/material.dart';
import '../manager.dart';

/// Always-visible status bar driven by [om] — shows route, pause state,
/// active overlay ids, and queued ids. No local state needed: [om] is a
/// [ChangeNotifier] so [AnimatedBuilder] re-renders on every change.
class OmStateBar extends StatelessWidget {
  const OmStateBar({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: om,
      builder: (context, _) {
        final active = om.activeIds;
        final queued = om.queuedIds;
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: DefaultTextStyle(
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 11,
              color: Theme.of(context).colorScheme.onSurface,
            ),
            child: Wrap(
              spacing: 16,
              runSpacing: 4,
              children: [
                Text('route: ${om.currentRoute ?? "(none)"}'),
                if (om.isPaused)
                  const Text('⏸ PAUSED',
                      style: TextStyle(
                          color: Colors.orange, fontWeight: FontWeight.bold)),
                Text(
                    'active: [${active.isEmpty ? "" : active.join(", ")}]'),
                Text(
                    'queued: [${queued.isEmpty ? "" : queued.join(", ")}]'),
              ],
            ),
          ),
        );
      },
    );
  }
}
