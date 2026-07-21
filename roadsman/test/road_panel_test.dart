import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roadsman/roadsman.dart';

void main() {
  testWidgets('RoadPanel mounts and renders a big road layout without throwing', (tester) async {
    final engine = createEngine(['bigRoad']);
    final results = [
      const RawResult(no: 1, winner: 'B', bankerPair: false, playerPair: false),
      const RawResult(no: 2, winner: 'B', bankerPair: false, playerPair: false),
      const RawResult(no: 3, winner: 'P', bankerPair: false, playerPair: false),
    ];
    final cfg = LayoutConfig(cellSize: 18, rows: 6, theme: resolveTheme());
    final output = engine.compute(results, cfg);
    final layout = output.layouts['bigRoad']!;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RoadPanel(
            cells: layout.cells,
            decorations: layout.decorations ?? const [],
            contentWidth: layout.contentWidth,
            contentHeight: layout.contentHeight,
            theme: resolveTheme(),
            panelWidth: 200,
            panelHeight: 108,
          ),
        ),
      ),
    );

    expect(find.byType(CustomPaint), findsWidgets);
    await tester.pump(const Duration(milliseconds: 50));
  });
}
