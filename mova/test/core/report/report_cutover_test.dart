import 'package:flutter_test/flutter_test.dart';
import 'package:mova/src/core/report/report.dart';
import 'package:mova/src/core/cutover/cutover_engine.dart';

import '../../support/fake_api.dart';

void main() {
  test('MovaCutoverEngine.report forwards verbatim to the active engine', () async {
    final active = FakeMovaApi();
    final cutover = MovaCutoverEngine(engineFactory: () => active);

    cutover.report(MovaReportName.miniChange, params: {'x': 1});

    expect(active.lastReportName, MovaReportName.miniChange);
    expect(active.lastReportParams, {'x': 1});

    await cutover.dispose();
  });
}
