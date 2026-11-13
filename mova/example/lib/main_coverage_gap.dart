import 'dart:async';
import 'package:flutter/material.dart';
import 'package:mova/mova.dart';
import 'verify_auto/coverage_gap.dart';
import 'verify_auto/coverage_gap_ui_kit.dart';

void main() {
  runZonedGuarded(
    () {
      WidgetsFlutterBinding.ensureInitialized();
      Mova.ensureInitialized();
      registerGapUiKitGroup();
      runApp(
        MaterialApp(
          builder: (context, child) =>
              MovaMiniHost(mini: gapMini, child: child!),
          home: Scaffold(
            body: ValueListenableBuilder<GapUiKitStage?>(
              valueListenable: gapUiKitStage,
              builder: (context, stage, child) => stage != null
                  ? gapUiKitStageView(stage)
                  : ValueListenableBuilder<IMovaApi?>(
                      valueListenable: gapScreen,
                      builder: (context, a, child) => a == null
                          ? const Center(child: Text('Mova gap coverage ready'))
                          : ValueListenableBuilder<List<IMovaApi>>(
                              valueListenable: gapSurfaces,
                              builder: (context, surfaces, child) => Column(
                                children: [
                                  for (final surface in surfaces)
                                    Expanded(child: MovaPlayer(api: surface)),
                                ],
                              ),
                            ),
                    ),
            ),
          ),
        ),
      );
      unawaited(serveGap());
    },
    (e, s) =>
        gap.log('ERROR', {'kind': 'HARNESS', 'error': '$e', 'stack': '$s'}),
  );
}
