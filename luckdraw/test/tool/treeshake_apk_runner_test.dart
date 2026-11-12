import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/treeshake/apk_support.dart';
import '../../tool/treeshake/check_treeshake.dart';

/// APK 测试使用的baseline常量。
const String _baseline = 'baseline';

/// APK 测试使用的create常量。
const String _create = 'create';

/// APK 测试使用的pub常量。
const String _pub = 'pub';

/// APK 测试使用的build常量。
const String _build = 'build';

/// APK 测试使用的--offline常量。
const String _offline = '--offline';

/// APK 测试使用的package:luckdraw常量。
const String _package = 'package:luckdraw';

/// APK 测试使用的type常量。
const String _type = 'type';

/// APK 测试使用的arm64-v8a常量。
const String _arm64 = 'arm64-v8a';

/// APK 测试使用的k常量。
const String _kind = 'k';

/// APK 测试使用的t常量。
const String _dataType = 't';

/// 转盘探针名称。
const String _probe = 'wheel_only';

/// 模拟构建输出的报告名。
const String _report = 'apk-code-size-analysis_02.json';

/// 正确的包库 URI。
const String _library = 'package:luckdraw/src/wheel/widgets/lucky_wheel.dart';

/// 最终报告使用的子节点字段。
const String _children = 'children';

/// 节点名称字段。
const String _name = 'n';

/// 节点字节数字段。
const String _value = 'value';

/// 生成与真实 Flutter 相同的 Root/lib/arm64-v8a/AOT 报告形状。
Map<String, Object?> _tree({bool baseline = false}) => {
      _name: 'Root',
      _value: 999,
      _type: 'apk',
      _children: [
        {
          _name: 'lib',
          _children: [
            {
              _name: _arm64,
              _children: [
                {
                  _name: 'libapp.so (Dart AOT)',
                  _value: 555,
                  _children: [
                    {_name: '@stubs', _value: 20},
                    if (!baseline)
                      {
                        _name: _package,
                        _value: 888,
                        _children: [
                          {_name: 'src/core/easing/easing.dart', _value: 30},
                          {
                            _name: _library,
                            _children: [
                              {_name: 'LuckyWheel.build', _value: 70}
                            ]
                          },
                        ],
                      },
                  ],
                }
              ],
            }
          ]
        }
      ],
    };

/// 取得夹具中唯一的 AOT 节点。
Map<String, Object?> _aot(Map<String, Object?> root) {
  var node = root;
  for (var depth = 0; depth < 3; depth++) {
    node = (node[_children]! as List<Object?>).single! as Map<String, Object?>;
  }
  return node;
}

/// 不启动 SDK 的隔离构建执行器。
final class _FakeApk {
  /// 配置输出目录及命令失败/畸形报告场景。
  _FakeApk(this.reports,
      {this.fail, this.offlineFails = false, this.badReport = false});

  /// 模拟 Flutter 的外部报告目录。
  final Directory reports;

  /// 失败的命令首词。
  final String? fail;

  /// 是否模拟离线失败。
  final bool offlineFails;

  /// 是否模拟损坏的最终报告。
  final bool badReport;

  /// 已收到的命令，验证串行顺序与重试次数。
  final List<List<String>> calls = [];

  /// 创建的工程路径。
  String? project;

  /// 模拟创建工程、pub get 及构建，保留断言验证实际输入。
  Future<int> call(List<String> args, String directory) async {
    calls.add(List.of(args));
    if (args.first == _create) project = args.last;
    if (args.first == fail || offlineFails && args.contains(_offline)) {
      return 1;
    }
    if (args.first == _create) {
      Directory('${args.last}/lib').createSync(recursive: true);
      Directory('${args.last}/android').createSync();
      File('${args.last}/android/gradle.properties')
          .writeAsStringSync('android.useAndroidX=true\n');
    } else if (args.first == _pub) {
      File('$directory/analysis_options.yaml')
          .writeAsStringSync('changed by pub get');
    } else if (args.first == _build) {
      expect(File('$directory/analysis_options.yaml').existsSync(), isFalse);
      expect(File('$directory/lib/main.dart').readAsStringSync(),
          contains('WheelController'));
      expect(File('$directory/pubspec.yaml').readAsStringSync(),
          contains('path:'));
      expect(File('$directory/android/gradle.properties').readAsStringSync(),
          contains('-Xmx1536m'));
      File('${reports.path}/$_report')
          .writeAsStringSync(badReport ? '{}' : jsonEncode(_tree()));
    }
    return 0;
  }
}

/// APK 构建计划、报告发现及严格结构自检。
void main() {
  group('treeshake apk', () {
    test('budget margin rounds decimal tenths without binary float drift', () {
      expect(apkBudgetBytes(0), 0);
      expect(apkBudgetBytes(49040), 53944);
      expect(apkBudgetBytes(59255), 65181);
      expect(apkBudgetBytes(61273), 67401);
      expect(apkBudgetBytes(243766), 268143);
      expect(() => apkBudgetBytes(-1), throwsArgumentError);
    });

    test('selection runs baseline once and rejects unknown or duplicate probes',
        () {
      expect(treeshakeProbeSelection('baseline,wheel_only,grid_only'),
          [_baseline, _probe, 'grid_only']);
      expect(treeshakeProbeSelection(_probe), [_baseline, _probe]);
      expect(treeshakeProbeSelection(null), kTreeshakeProbes);
      expect(() => treeshakeProbeSelection('wheel_only,wheel_only'),
          throwsFormatException);
      expect(() => treeshakeProbeSelection('unknown'), throwsFormatException);
    });

    test(
        'real Flutter hierarchical directories and typed data leaves parse strictly',
        () {
      final json = File('tool/treeshake/fixtures/apk_wheel_tree.json')
          .readAsStringSync();
      final result = parseApkReport(json);
      expect(result.artifact.luckdrawBytes, 59255);
      expect(result.dartBytes, 1880720);
      expect(result.artifact.sources,
          contains('/luckdraw/lib/src/wheel/widgets/lucky_wheel.dart'));
      expect(checkProbe(_probe, result.artifact), isEmpty);
      final tree = jsonDecode(json) as Map<String, Object?>;
      final aot = _aot(tree);
      final package = (aot[_children]! as List<Object?>)
          .cast<Map<String, Object?>>()
          .singleWhere((node) => node[_name] == _package);
      final data = <String, Object?>{
        _name: '<CodeSourceMap>',
        _kind: 's',
        _dataType: 'D',
        _value: 1
      };
      (package[_children]! as List<Object?>).add(data);
      expect(parseApkReport(jsonEncode(tree)).artifact.luckdrawBytes, 59256);
      data[_dataType] = 'unknown';
      expect(() => parseApkReport(jsonEncode(tree)), throwsFormatException);
      data[_dataType] = 'D';
      data[_name] = 'invalid data name';
      expect(() => parseApkReport(jsonEncode(tree)), throwsFormatException);
    });

    test('plan creates Android project and builds only arm64 release analysis',
        () {
      final plan = apkBuildCommands('/tmp/probe');
      expect(
          plan.first,
          containsAll(
              [_create, '--platforms=android', '--no-pub', '/tmp/probe']));
      expect(plan[1], [_pub, 'get', _offline, '--no-example']);
      expect(plan.last, [
        _build,
        'apk',
        '--release',
        '--analyze-size',
        '--target-platform=android-arm64',
        '--no-pub'
      ]);
    });

    test('Gradle properties bound memory and mark only the owned daemon', () {
      const owner = 'apk_test';
      final result = apkGradleProperties(
          'org.gradle.jvmargs=-Xmx8G\nandroid.useAndroidX=true\norg.gradle.workers.max=8\n',
          owner);
      expect(result, contains('android.useAndroidX=true'));
      expect(result, isNot(contains('-Xmx8G')));
      expect(result, contains('org.gradle.workers.max=2'));
      expect(result, contains('org.gradle.daemon=false'));
      expect(result, contains('kotlin.compiler.execution.strategy=in-process'));
      const daemon = 'org.gradle.launcher.daemon.bootstrap.GradleDaemon';
      expect(
          isOwnedApkDaemon(
              'java $kApkOwnerProperty$owner.hprof $daemon 9', owner),
          isTrue);
      expect(
          isOwnedApkDaemon(
              'java $kApkOwnerProperty${owner}2.hprof $daemon', owner),
          isFalse);
      expect(
          isOwnedApkDaemon(
              'java $kApkOwnerProperty$owner.hprof idea.Main', owner),
          isFalse);
      expect(isOwnedApkDaemon('java $daemon', owner), isFalse);
      expect(() => apkGradleProperties('', '../unsafe'), throwsArgumentError);
    });

    test('report discovery accepts only one fresh final report across roots',
        () {
      const old = 'C:/home/.flutter-devtools/apk-code-size-analysis_01.json';
      const fresh = r'C:\temp\probe\build\apk-code-size-analysis_02.json';
      expect(
          discoverApkReport({old: 'old'},
              {old: 'old', fresh: 'new', 'snapshot.arm64.json': 'new'}),
          fresh);
      expect(discoverApkReport({old: 'old'}, {old: 'changed'}), old);
      expect(() => discoverApkReport({old: 'old'}, {old: 'old'}),
          throwsStateError);
      expect(() => discoverApkReport({}, {old: 'a', fresh: 'b'}),
          throwsStateError);
      expect(
          () => discoverApkReport(
              {}, {'apk-code-size-analysis_01.json.bak': 'x'}),
          throwsStateError);
    });

    test('snapshot ignores intermediate files and detects a changed report',
        () {
      final root = Directory.systemTemp.createTempSync('apk_snapshot_');
      try {
        File('${root.path}/snapshot.arm64.json').writeAsStringSync('{}');
        expect(apkReportSnapshot([root]), isEmpty);
        final report = File('${root.path}/$_report')..writeAsStringSync('{}');
        final before = apkReportSnapshot([root]);
        report.writeAsStringSync('{"changed":true}');
        final after = apkReportSnapshot([root]);
        expect(File(discoverApkReport(before, after)).uri, report.uri);
      } finally {
        root.deleteSync(recursive: true);
      }
    });

    test(
        'arm64 report counts package and AOT leaves without parent duplication',
        () {
      final result = parseApkReport(jsonEncode(_tree()));
      expect(result.artifact.luckdrawBytes, 100);
      expect(result.dartBytes, 120);
      expect(result.apkBytes, 555);
      expect(checkProbe(_probe, result.artifact), isEmpty);
    });

    test(
        'baseline permits absent package only after full AOT structure validation',
        () {
      final json = jsonEncode(_tree(baseline: true));
      final result = parseApkReport(json, baseline: true);
      expect(result.artifact.luckdrawBytes, 0);
      expect(result.artifact.sources, isEmpty);
      expect(result.dartBytes, 20);
      expect(checkProbe(_baseline, result.artifact), isEmpty);
      expect(() => parseApkReport(json), throwsFormatException);
      expect(() => parseApkReport('{"n":"Root","value":1}', baseline: true),
          throwsFormatException);
      expect(() => parseApkSizeJson(json), throwsFormatException);
    });

    test(
        'schema drift wrong ABI missing AOT and invalid leaves fail explicitly',
        () {
      final wrongType = _tree()..[_type] = 'web';
      final wrongAbi = _tree();
      final lib = (wrongAbi[_children]! as List<Object?>).single!
          as Map<String, Object?>;
      ((lib[_children]! as List<Object?>).single!
          as Map<String, Object?>)[_name] = 'armeabi-v7a';
      final empty = _tree();
      _aot(empty)[_children] = <Object?>[];
      final missing = _tree();
      _aot(missing).remove(_children);
      final badLeaf = _tree();
      _aot(badLeaf)[_children] = [
        {_name: '@stubs', _value: -1}
      ];
      final badPartial = _tree();
      (_aot(badPartial)[_children]! as List<Object?>)
          .add({_name: 'package:luckdraw/src/grid/leak.dart', _value: 'bad'});
      final inputs = [wrongType, wrongAbi, empty, missing, badLeaf, badPartial];
      for (final input in inputs) {
        expect(() => parseApkReport(jsonEncode(input)), throwsFormatException);
      }
    });

    test('retained foreign package library remains a forbidden source', () {
      final tree = _tree();
      (_aot(tree)[_children]! as List<Object?>)
          .add({_name: 'package:luckdraw/src/grid/leak.dart', _value: 1});
      final result = parseApkReport(jsonEncode(tree));
      expect(checkProbe(_probe, result.artifact),
          contains(contains('/src/grid/leak.dart')));
    });

    test('fake APK build copies probe preserves history and removes workspace',
        () async {
      final reports = Directory.systemTemp.createTempSync('apk_fake_');
      try {
        final historical =
            File('${reports.path}/apk-code-size-analysis_01.json')
              ..writeAsStringSync('history');
        final fake = _FakeApk(reports);
        final result = await buildApkProbe(
            probe: _probe,
            packageRoot: Directory.current,
            command: fake.call,
            devtoolsDirectory: reports);
        expect(checkProbe(_probe, result.artifact), isEmpty);
        expect(fake.calls.map((args) => args.first), [_create, _pub, _build]);
        expect(Directory(fake.project!).parent.existsSync(), isFalse);
        expect(historical.readAsStringSync(), 'history');
        expect(File('${reports.path}/$_report').existsSync(), isFalse);
      } finally {
        reports.deleteSync(recursive: true);
      }
    });

    test('offline failure retries once and saves the report before cleanup',
        () async {
      final reports = Directory.systemTemp.createTempSync('apk_retry_');
      try {
        final fake = _FakeApk(reports, offlineFails: true);
        final saved = File('${reports.path}/saved.json');
        await buildApkProbe(
            probe: _probe,
            packageRoot: Directory.current,
            command: fake.call,
            devtoolsDirectory: reports,
            reportCopy: saved);
        expect(fake.calls.map((args) => args.first),
            [_create, _pub, _pub, _build]);
        expect(parseApkReport(saved.readAsStringSync()).artifact.luckdrawBytes,
            100);
        expect(Directory(fake.project!).parent.existsSync(), isFalse);
      } finally {
        reports.deleteSync(recursive: true);
      }
    });

    test('command failures stop the plan and clean every temporary workspace',
        () async {
      final reports = Directory.systemTemp.createTempSync('apk_failure_');
      try {
        const commands = [_create, _pub, _build];
        for (final command in commands) {
          final fake = _FakeApk(reports, fail: command);
          await expectLater(
              buildApkProbe(
                  probe: _probe,
                  packageRoot: Directory.current,
                  command: fake.call,
                  devtoolsDirectory: reports),
              throwsStateError);
          expect(Directory(fake.project!).parent.existsSync(), isFalse);
          expect(fake.calls.last.first, command);
        }
      } finally {
        reports.deleteSync(recursive: true);
      }
    });

    test('malformed output fails and removes report and temporary workspace',
        () async {
      final reports = Directory.systemTemp.createTempSync('apk_invalid_');
      try {
        final fake = _FakeApk(reports, badReport: true);
        await expectLater(
            buildApkProbe(
                probe: _probe,
                packageRoot: Directory.current,
                command: fake.call,
                devtoolsDirectory: reports),
            throwsFormatException);
        expect(Directory(fake.project!).parent.existsSync(), isFalse);
        expect(File('${reports.path}/$_report').existsSync(), isFalse);
      } finally {
        reports.deleteSync(recursive: true);
      }
    });

    test('unknown probe fails before any APK command starts', () async {
      final reports = Directory.systemTemp.createTempSync('apk_unknown_');
      try {
        final fake = _FakeApk(reports);
        await expectLater(
            buildApkProbe(
                probe: '../unknown',
                packageRoot: Directory.current,
                command: fake.call,
                devtoolsDirectory: reports),
            throwsArgumentError);
        expect(fake.calls, isEmpty);
      } finally {
        reports.deleteSync(recursive: true);
      }
    });
  });
}
