import 'package:flutter_test/flutter_test.dart';
import 'package:mova/src/core/report/report.dart';
import 'package:mova/src/core/cutover/cutover.dart';

import '../../support/fake_api.dart';

void main() {
  test('MovaCutover.report forwards verbatim to the active player', () async {
    final active = FakeMovaApi();
    final cutover = MovaCutover(movaFactory: () => active);

    cutover.report(MovaReportName.miniChange, params: {'x': 1});

    expect(active.lastReportName, MovaReportName.miniChange);
    expect(active.lastReportParams, {'x': 1});

    await cutover.dispose();
  });
}
