import 'dart:async';
import 'package:flutter/material.dart';
import 'package:mova/mova.dart';
import 'verify_auto/coverage_perf.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MovaEngine.ensureInitialized();
  runApp(
    MaterialApp(
      home: Scaffold(
        body: ValueListenableBuilder<List<MovaApi>>(
          valueListenable: perfSurfaces,
          builder: (context, engines, child) => engines.isEmpty
              ? const Center(child: Text('Mova performance ready :18089'))
              : LayoutBuilder(
                  builder: (context, bounds) => SingleChildScrollView(
                    controller: perfScroll,
                    child: Column(
                      children: [
                        for (final engine in engines)
                          SizedBox(
                            height: bounds.maxHeight,
                            child: MovaPlayer(
                              key: ObjectKey(engine),
                              api: engine,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
        ),
      ),
    ),
  );
  unawaited(servePerf());
}
