import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/treeshake/check_treeshake.dart';

/// Flutter 工程创建子命令。
const String _create = 'create';

/// 离线依赖解析参数。
const String _offline = '--offline';

/// Flutter 构建子命令。
const String _build = 'build';

/// 转盘探针必须保留的控制器符号。
const String _wheelController = 'WheelController';

/// 构建阶段禁止隐式依赖解析。
const String _noPub = '--no-pub';

/// Flutter 依赖管理子命令。
const String _pub = 'pub';

/// 假构建使用的探针名称。
const String _probe = 'wheel_only';

/// 假构建输出的主程序相对路径。
const String _output = 'build/web/main.dart.js';

/// 假构建输出的有效 sourcemap。
const String _map = '{"version":3,"sources":['
    '"/luckdraw/lib/src/core/a.dart","/luckdraw/lib/src/wheel/a.dart"],'
    '"names":[],"mappings":""}';

/// 假构建输出的程序内容。
const String _js = 'void main() {}';

/// 被测构建所需的纯内存命令执行器，无 SDK 或编译器调用。
final class _FakeFlutter {
  /// 配置某个命令退出码以及是否生成非法 sourcemap。
  _FakeFlutter(
      {this.failCommand, this.offlineFails = false, this.malformedMap = false});

  /// 应当失败的主命令名。
  final String? failCommand;

  /// 是否模拟离线依赖解析失败。
  final bool offlineFails;

  /// 是否输出非法 sourcemap。
  final bool malformedMap;

  /// 按顺序收到的命令。
  final List<List<String>> calls = [];

  /// 临时工程目录，供测试验证清理行为。
  String? projectPath;

  /// 接收单条命令并生成最小假产物；失败时返回非零退出码。
  Future<int> call(List<String> args, String directory) async {
    calls.add(List.of(args));
    if (args.first == _create) projectPath = args.last;
    if (args.first == failCommand || offlineFails && args.contains(_offline)) {
      return 1;
    }
    if (args.first == _create) {
      Directory('${args.last}/lib').createSync(recursive: true);
    } else if (args.first == _build) {
      final main = File('$directory/lib/main.dart').readAsStringSync();
      expect(main, contains(_wheelController));
      final yaml = File('$directory/pubspec.yaml').readAsStringSync();
      expect(yaml, contains('path:'));
      expect(yaml, contains(Directory.current.path.replaceAll('\\', '/')));
      final output = File('$directory/$_output');
      output.parent.createSync(recursive: true);
      output.writeAsStringSync(_js);
      File('${output.path}.map').writeAsStringSync(malformedMap ? '{}' : _map);
    }
    return 0;
  }
}

/// 验证纯构建计划和假命令流程；本测试文件从不执行 flutter build。
void main() {
  group('treeshake runner', () {
    test('web plan uses isolated project offline dependencies and release maps',
        () {
      const directory = 'C:/Temp/ldts/ts_1/probe';
      final plan = webBuildCommands(directory);
      expect(plan, hasLength(3));
      expect(
          plan.first,
          containsAll(
              [_create, '--platforms=web', '--empty', _noPub, directory]));
      expect(plan[1], containsAll([_pub, 'get', _offline, '--no-example']));
      expect(plan.last, [_build, 'web', '--release', '--source-maps', _noPub]);
      expect(plan.expand((args) => args).join(), isNot(contains('apk')));
    });

    test(
        'pubspec quotes Windows paths and retains only SDK and path dependencies',
        () {
      const path = r'C:\work tree\luckdraw';
      final yaml = probePubspec(path);
      expect(yaml, contains('sdk: \'>=3.5.0 <4.0.0\''));
      expect(yaml, contains('path: "C:/work tree/luckdraw"'));
      expect(yaml, isNot(contains('dev_dependencies')));
      expect(yaml, isNot(contains('assets:')));
    });

    test(
        'fake web build returns measured bytes and removes its temporary project',
        () async {
      final fake = _FakeFlutter();
      final result = await buildWebProbe(
          probe: _probe, packageRoot: Directory.current, command: fake.call);
      expect(result.rawBytes, utf8.encode(_js).length);
      expect(result.gzipBytes,
          GZipCodec(level: 9).encode(utf8.encode(_js)).length);
      expect(checkProbe(_probe, result.artifact), isEmpty);
      expect(fake.calls.map((args) => args.first), [_create, _pub, _build]);
      expect(Directory(fake.projectPath!).parent.existsSync(), isFalse);
    });

    test('offline failure retries online once before building', () async {
      final fake = _FakeFlutter(offlineFails: true);
      await buildWebProbe(
          probe: _probe, packageRoot: Directory.current, command: fake.call);
      expect(
          fake.calls.map((args) => args.first), [_create, _pub, _pub, _build]);
      expect(fake.calls[1], contains(_offline));
      expect(fake.calls[2], isNot(contains(_offline)));
      expect(Directory(fake.projectPath!).parent.existsSync(), isFalse);
    });

    test('create failure stops before dependencies and cleans the workspace',
        () async {
      final fake = _FakeFlutter(failCommand: _create);
      await expectLater(
          buildWebProbe(
              probe: _probe,
              packageRoot: Directory.current,
              command: fake.call),
          throwsStateError);
      expect(fake.calls, hasLength(1));
      expect(Directory(fake.projectPath!).parent.existsSync(), isFalse);
    });

    test('dependency failure stops before build and cleans the workspace',
        () async {
      final fake = _FakeFlutter(failCommand: _pub);
      await expectLater(
          buildWebProbe(
              probe: _probe,
              packageRoot: Directory.current,
              command: fake.call),
          throwsStateError);
      expect(fake.calls.map((args) => args.first), [_create, _pub, _pub]);
      expect(Directory(fake.projectPath!).parent.existsSync(), isFalse);
    });

    test('build failure and malformed output both clean the workspace',
        () async {
      final failed = _FakeFlutter(failCommand: _build);
      await expectLater(
          buildWebProbe(
              probe: _probe,
              packageRoot: Directory.current,
              command: failed.call),
          throwsStateError);
      expect(Directory(failed.projectPath!).parent.existsSync(), isFalse);
      final malformed = _FakeFlutter(malformedMap: true);
      await expectLater(
          buildWebProbe(
              probe: _probe,
              packageRoot: Directory.current,
              command: malformed.call),
          throwsFormatException);
      expect(Directory(malformed.projectPath!).parent.existsSync(), isFalse);
    });

    test('unknown probe fails before starting a command', () async {
      final fake = _FakeFlutter();
      await expectLater(
          buildWebProbe(
              probe: '../unknown',
              packageRoot: Directory.current,
              command: fake.call),
          throwsArgumentError);
      expect(fake.calls, isEmpty);
    });

    test('all ten checked in probes mount the documented public APIs', () {
      const expected = {
        'baseline': 'Text',
        _probe: _wheelController,
        'grid_only': 'LuckyGrid',
        'slot_only': 'LuckySlotMachine',
        'capsule_only': 'LuckyCapsuleMachine',
        'number_wheel_only': 'LuckyNumberWheel',
        'lots_only': 'LuckyLots',
        'lotto_only': 'LottoConfig.superLotto',
        'compat_wheel': 'wheelFromLuckyCanvasConfig',
        'all_games': 'LuckyLeverSlotMachine',
      };
      expect(expected.keys.toSet(), kTreeshakeProbes.toSet());
      for (final entry in expected.entries) {
        final source = File('tool/treeshake/probes/${entry.key}/main.dart')
            .readAsStringSync();
        expect(source, contains('runApp('));
        expect(source, contains(entry.value));
      }
      final analysis = File('analysis_options.yaml').readAsStringSync();
      expect(analysis, contains('tool/treeshake/probes/**'));
    });
  });
}
