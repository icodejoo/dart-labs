import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/run_integration.dart';

/// 测试记录文件名。
const String _file = 'wheel_flow_test.dart';

/// 按真实进程退出码汇总，禁止把缺失执行写成通过。
void main() {
  group('integration report', () {
    test('unstarted planned files and unexpected files prevent success', () {
      const runs = [IntegrationRun(_file, 1, 0, 1)];
      const options = IntegrationOptions(repeat: 1);
      final pending = integrationReport(options, runs,
          expectedFiles: [_file, 'route_test.dart']);
      expect(pending['complete'], isFalse);
      expect(pending['success'], isFalse);
      expect(
          integrationReport(options, runs,
              expectedFiles: ['route_test.dart'])['success'],
          isFalse);
      expect(
          integrationReport(options, runs, expectedFiles: [_file])['success'],
          isTrue);
    });
    test('serializes the original exit code duration and timeout', () {
      const run = IntegrationRun(_file, 2, 7, 250, timedOut: true);
      expect(jsonDecode(jsonEncode(run.toJson())), {
        'file': _file,
        'attempt': 2,
        'exitCode': 7,
        'elapsedMs': 250,
        'timedOut': true,
        'passed': false,
      });
    });
    test('summarizes three successful runs with elapsed time', () {
      final report = integrationReport(const IntegrationOptions(), const [
        IntegrationRun(_file, 1, 0, 10),
        IntegrationRun(_file, 2, 0, 20),
        IntegrationRun(_file, 3, 0, 30),
      ]);
      expect(report['total'], 3);
      expect(report['passed'], 3);
      expect(report['failed'], 0);
      expect(report['passRate'], 1.0);
      expect(report['elapsedMs'], 60);
      expect(report['files'], [_file]);
      expect(report['success'], isTrue);
      expect(report['complete'], isTrue);
      expect(report['device'], 'windows');
      expect(report['repeat'], 3);
      expect(report['runs'], hasLength(3));
    });
    test('any failed or timed out attempt fails the report', () {
      final report = integrationReport(const IntegrationOptions(), const [
        IntegrationRun(_file, 1, 0, 10),
        IntegrationRun(_file, 2, 1, 20),
        IntegrationRun(_file, 3, 0, 30, timedOut: true),
      ]);
      expect(report['success'], isFalse);
      expect(report['passed'], 1);
      expect(report['failed'], 2);
      expect(report['passRate'], closeTo(1 / 3, 1e-12));
    });
    test('empty partial and duplicate attempts cannot report success', () {
      for (final runs in <List<IntegrationRun>>[
        [],
        [const IntegrationRun(_file, 1, 0, 1)],
        [
          const IntegrationRun(_file, 1, 0, 1),
          const IntegrationRun(_file, 1, 0, 1),
          const IntegrationRun(_file, 3, 0, 1)
        ],
        [
          const IntegrationRun(_file, 1, 0, 1),
          const IntegrationRun(_file, 2, 0, 1),
          const IntegrationRun(_file, 4, 0, 1)
        ],
      ]) {
        final report = integrationReport(const IntegrationOptions(), runs);
        expect(report['complete'], isFalse);
        expect(report['success'], isFalse);
        if (runs.isEmpty) expect(report['passRate'], 0.0);
      }
    });
    test('requires every file to finish all requested attempts', () {
      const otherFile = 'grid_flow_test.dart';
      const options = IntegrationOptions(device: 'serial', repeat: 1);
      final report = integrationReport(options, const [
        IntegrationRun(_file, 1, 0, 4),
        IntegrationRun(otherFile, 1, 0, 8),
      ]);
      expect(report['files'], [otherFile, _file]);
      expect(report['elapsedMs'], 12);
      expect(report['success'], isTrue);
      expect(report['device'], 'serial');
      final partial =
          integrationReport(const IntegrationOptions(repeat: 2), const [
        IntegrationRun(_file, 1, 0, 1),
        IntegrationRun(_file, 2, 0, 1),
        IntegrationRun(otherFile, 1, 0, 1),
      ]);
      expect(partial['success'], isFalse);
    });
  });
}
