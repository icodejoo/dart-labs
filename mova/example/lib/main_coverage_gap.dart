import 'dart:async';
import 'package:flutter/material.dart';
import 'package:mova/mova.dart';
import 'verify_auto/coverage_gap.dart';
import 'verify_auto/coverage_gap_skin.dart';

void main() {
  runZonedGuarded(
    () {
      WidgetsFlutterBinding.ensureInitialized();
      MovaEngine.ensureInitialized();
      registerGapSkinGroup();
      runApp(
        MaterialApp(
          builder: (context, child) =>
              MovaMiniHost(ctl: gapMini, child: child!),
          home: Scaffold(
            body: ValueListenableBuilder<GapSkinStage?>(
              valueListenable: gapSkinStage,
              builder: (context, stage, child) => stage != null
                  ? gapSkinStageView(stage)
                  : ValueListenableBuilder<MovaApi?>(
                      valueListenable: gapScreen,
                      builder: (context, a, child) => a == null
                          ? const Center(child: Text('Mova gap coverage ready'))
                          : ValueListenableBuilder<List<MovaApi>>(
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
