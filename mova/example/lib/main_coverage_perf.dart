import 'dart:async';
import 'package:flutter/material.dart';
import 'package:mova/mova.dart';
import 'verify_auto/coverage_perf.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  Mova.ensureInitialized();
  runApp(
    MaterialApp(
      home: Scaffold(
        body: ValueListenableBuilder<List<IMovaApi>>(
          valueListenable: perfSurfaces,
          builder: (context, movas, child) => movas.isEmpty
              ? const Center(child: Text('Mova performance ready :18089'))
              : LayoutBuilder(
                  builder: (context, bounds) => SingleChildScrollView(
                    controller: perfScroll,
                    child: Column(
                      children: [
                        for (final mova in movas)
                          SizedBox(
                            height: bounds.maxHeight,
                            child: MovaPlayer(
                              key: ObjectKey(mova),
                              api: mova,
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
