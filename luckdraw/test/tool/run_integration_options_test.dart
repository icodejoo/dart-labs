import 'package:flutter_test/flutter_test.dart';

import '../../tool/run_integration.dart';

/// 验证命令边界输入，避免误跑设备或逃逸测试目录。
void main() {
  group('integration options', () {
    test('defaults to three Windows runs', () {
      final options = IntegrationOptions.parse([]);
      expect(options.device, 'windows');
      expect(options.repeat, 3);
      expect(options.file, isNull);
    });
    test('accepts Android serial and a selected file', () {
      final options = IntegrationOptions.parse([
        '--device=192.168.0.2:5555',
        '--repeat=2',
        '--file=wheel_flow_test.dart',
      ]);
      expect(options.device, '192.168.0.2:5555');
      expect(options.repeat, 2);
      expect(options.file, 'wheel_flow_test.dart');
    });
    test('normalizes the integration directory prefix', () {
      final options = IntegrationOptions.parse([
        '--file=integration_test/resize_test.dart',
      ]);
      expect(options.file, 'resize_test.dart');
    });
    test('rejects unknown empty and duplicate arguments', () {
      for (final arguments in <List<String>>[
        ['--unknown=1'],
        ['--file='],
        ['--repeat=1', '--repeat=3'],
        ['--device=windows', '--device=serial'],
        ['--device', 'windows'],
      ]) {
        expect(
            () => IntegrationOptions.parse(arguments), throwsFormatException);
      }
    });
    test('rejects invalid repetitions devices and escaping paths', () {
      for (final argument in [
        '--repeat=0',
        '--repeat=-1',
        '--repeat=NaN',
        '--repeat=1.5',
        '--device=windows;echo',
        '--device=a b',
        '--file=../route_test.dart',
        '--file=sub/route_test.dart',
        r'--file=..\route_test.dart',
        '--file=main.dart',
        '--file=route_test.dart.extra',
      ]) {
        expect(
            () => IntegrationOptions.parse([argument]), throwsFormatException);
      }
    });
  });
}
