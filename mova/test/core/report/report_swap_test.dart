import 'package:flutter_test/flutter_test.dart';
import 'package:mova/src/core/report/report.dart';
import 'package:mova/src/core/swap/swap_engine.dart';

import '../../support/fake_api.dart';

void main() {
  test('MovaSwapEngine.report forwards verbatim to the active engine', () async {
    final active = FakeMovaApi();
    final swap = MovaSwapEngine(engineFactory: () => active);

    swap.report(MovaReportName.miniChange, params: {'x': 1});

    expect(active.lastReportName, MovaReportName.miniChange);
    expect(active.lastReportParams, {'x': 1});

    await swap.dispose();
  });
}
