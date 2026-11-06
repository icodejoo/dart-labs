import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:svgx/svgx.dart' show RustLib;
import 'package:svgx/src/animation/css_keyframes_compiler.dart';
import 'package:svgx/src/animation/smil_animation.dart';
import 'package:svgx/src/animation/svg_document_parser.dart';
import 'package:svgx/src/animation/svg_dom.dart';

import 'pixel_test_utils.dart';

/// 节点动画绑定数的统计键。
const _bindings = 'bindings';

/// 变换动画块数的统计键。
const _transformAnimations = 'transformAnimations';

/// 变换槽位数的统计键。
const _slots = 'slots';

/// 实际数值轨道数的统计键。
const _numericAnimations = 'numericAnimations';

/// 合并多属性后的数值块数的统计键。
const _numericBlocks = 'numericBlocks';

/// 运动路径轨道数的统计键。
const _motion = 'motion';

/// 路径变形轨道数的统计键。
const _paths = 'paths';

/// 颜色轨道数的统计键。
const _colors = 'colors';

/// 数值列表轨道数的统计键。
const _lists = 'lists';

/// 跳过原因分布的统计键。
const _skipped = 'skipped';

/// 外部样本目录的环境变量。
const _samplesVariable = 'SVGX_CSS_SAMPLES';

/// 设置后把本次实测计数写到该路径，用于刷新期望表。
const _dumpVariable = 'SVGX_WRITE_EXPECTED';

/// 只含计数的入库期望表。
const _expectedPath = 'test/animation/css_real_samples_expected.json';

/// 所有动画均指向不存在元素的孤儿样本。
const _orphan = '111';

/// 已知全有限样本，用真实配置再次核实。
const _finiteIds = {'121', '131', '141', '151'};

/// 枚举主树及独立解析的裁剪与遮罩定义，不按 id 合并节点。
Iterable<SvgNode> _nodes(SvgDocument doc) sync* {
  /// 遍历一棵节点树。
  Iterable<SvgNode> walk(SvgNode node) sync* {
    yield node;
    for (final child in node.children) {
      yield* walk(child);
    }
  }

  yield* walk(doc.root);
  for (final root in [...doc.clipPaths.values, ...doc.masks.values]) {
    yield* walk(root);
  }
}

/// 提取文件名里的样本编号。
String _sampleId(File file) => file.uri.pathSegments.last.split('.').first;

/// 收集外部 SVG 样本，排除孤儿样本。
List<File> _files(String directory) =>
    Directory(directory)
        .listSync()
        .whereType<File>()
        .where(
          (file) => file.path.endsWith('.svg') && _sampleId(file) != _orphan,
        )
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));

/// 统计实际接线轨道，并重编译原始配置收集块数与跳过原因。
Map<String, Object> _counts(SvgDocument doc) {
  var bindings = 0, transformAnimations = 0, slots = 0;
  var numericAnimations = 0, numericBlocks = 0;
  var motion = 0, paths = 0, colors = 0, lists = 0;
  final skipped = <String, int>{};
  for (final node in _nodes(doc)) {
    bindings += node.cssAnimations.length;
    slots += node.transformAnimations.length;
    numericAnimations += node.animations.length;
    motion += node.motionAnimations.length;
    paths += node.pathAnimations.length;
    colors += node.colorAnimations.length;
    lists += node.listAnimations.length;
    final compiled = compileCssAnimations(
      animations: node.cssAnimations,
      keyframes: doc.cssKeyframes,
      attributes: node.attributes,
      cssProperties: node.cssProperties,
      hooks: cssCompileHooks,
    );
    expect(node.animations.length, compiled.numeric.length);
    expect(node.transformAnimations.length, compiled.transforms.length);
    expect(node.pathAnimations.length, compiled.paths.length);
    for (final skip in compiled.skipped) {
      final key = '${skip.reason.name}:${skip.property ?? ''}';
      skipped.update(key, (count) => count + 1, ifAbsent: () => 1);
    }
    for (final animation in node.cssAnimations) {
      final block = compileCssAnimations(
        animations: [animation],
        keyframes: doc.cssKeyframes,
        attributes: node.attributes,
        cssProperties: node.cssProperties,
        hooks: cssCompileHooks,
      );
      if (block.transforms.isNotEmpty) transformAnimations++;
      if (block.numeric.isNotEmpty) numericBlocks++;
    }
  }
  return {
    _bindings: bindings,
    _transformAnimations: transformAnimations,
    _slots: slots,
    _numericAnimations: numericAnimations,
    _numericBlocks: numericBlocks,
    _motion: motion,
    _paths: paths,
    _colors: colors,
    _lists: lists,
    _skipped: skipped,
  };
}

/// 汇总每样本计数，便于与设计原型逐项核对。
Map<String, Object> _totals(Iterable<Map<String, Object>> counts) {
  final result = <String, Object>{};
  final skipped = <String, int>{};
  for (final row in counts) {
    for (final entry in row.entries) {
      if (entry.key == _skipped) {
        for (final skip in (entry.value as Map<String, int>).entries) {
          skipped.update(
            skip.key,
            (n) => n + skip.value,
            ifAbsent: () => skip.value,
          );
        }
      } else {
        result.update(
          entry.key,
          (n) => (n as int) + (entry.value as int),
          ifAbsent: () => entry.value,
        );
      }
    }
  }
  result[_skipped] = skipped;
  return result;
}

/// 验证真实样本的接线轨道数、循环语义与八时刻绘制。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final directory = Platform.environment[_samplesVariable];
  if (directory == null || !Directory(directory).existsSync()) {
    test('真实 CSS 样本需要外部目录', () {
      markTestSkipped('未设置有效的 $_samplesVariable；第三方样本不随仓库分发');
    });
    return;
  }
  final files = _files(directory);
  final expected = jsonDecode(File(_expectedPath).readAsStringSync()) as Map;
  final actual = <String, Map<String, Object>>{};
  final finiteIds = <String>{};
  final finiteDurations = <String, int>{};
  var infiniteBindings = 0, finiteBindings = 0;
  var attemptedFrames = 0, paintedFrames = 0;

  setUpAll(() async {
    var ready = false;
    try {
      await RustLib.init();
      ready = true;
    } catch (_) {
      // 原生库缺失仍可验证 CSS 编译与绘制。
    }
    // ignore: avoid_print
    print(
      ready
          ? '原生库可用：静态 transform 参与冒烟。'
          : '原生库不可用：静态 transform 为 null，R3 退化；CSS 编译与绘制继续验证。',
    );
  });

  tearDownAll(() {
    if (Platform.environment[_dumpVariable] case final path?) {
      File(
        path,
      ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(actual));
    }
  });

  for (final file in files) {
    final id = _sampleId(file);
    test('样本 $id：计数、时序与八帧绘制', () {
      final doc = parseAnimatedSvgDocument(file.readAsStringSync());
      final counts = _counts(doc);
      actual[id] = counts;
      expect(counts, expected[id], reason: '样本 $id 的编译产物漂移');
      final configs = _nodes(doc).expand((node) => node.cssAnimations).toList();
      expect(configs, isNotEmpty);
      for (final config in configs) {
        if (config.iterationCount.isInfinite) {
          infiniteBindings++;
        } else {
          finiteBindings++;
        }
      }
      if (configs.every((a) => a.iterationCount.isFinite)) {
        finiteIds.add(id);
        expect(doc.hasIndefiniteLoop, isFalse);
      }
      if (id == '137') {
        expect(configs, hasLength(4));
        expect(
          configs.every((a) => a.iterationCount == double.infinity),
          isTrue,
        );
        expect(doc.hasIndefiniteLoop, isTrue);
      }
      final tracks = <SmilTimed>[
        for (final node in _nodes(doc)) ...[
          ...node.animations,
          ...node.transformAnimations,
          ...node.motionAnimations,
          ...node.pathAnimations,
          ...node.colorAnimations,
          ...node.listAnimations,
        ],
      ];
      var expectedEnd = 0;
      for (final track in tracks.where((a) => !a.repeatCount.indefinite)) {
        final end =
            track.begin.inMicroseconds +
            (track.duration.inMicroseconds * track.repeatCount.count).round();
        if (end > expectedEnd) expectedEnd = end;
      }
      expect(doc.totalDuration.inMicroseconds, expectedEnd);
      expect(
        doc.hasIndefiniteLoop,
        tracks.any((a) => a.repeatCount.indefinite),
      );
      if (_finiteIds.contains(id)) {
        expect(expectedEnd, greaterThan(0));
        finiteDurations[id] = expectedEnd;
      }
      final finite = configs.where((a) => a.iterationCount.isFinite);
      final d = finite.isEmpty
          ? 4000000
          : finite
                .map((a) => a.duration.inMicroseconds)
                .reduce((a, b) => a > b ? a : b);
      final failures = <String>[];
      for (final micros in [
        0,
        (d * .25).round(),
        (d * .5).round(),
        (d * .99).round(),
        (d * 1.01).round(),
        (d * 1.5).round(),
        5000000,
        61000000,
      ]) {
        attemptedFrames++;
        try {
          paintAt(doc, Duration(microseconds: micros));
          paintedFrames++;
        } catch (error, stack) {
          if (failures.isEmpty) {
            // ignore: avoid_print
            print('样本 $id 首次绘制失败：$error\n$stack');
          }
          failures.add('${micros}us: $error');
        }
      }
      expect(failures, isEmpty, reason: '样本 $id 的八帧绘制失败');
    });
  }
  test('语料清单和原型汇总一致', () {
    expect(files, hasLength(54));
    expect(attemptedFrames, 432);
    expect(actual.keys.toSet(), expected.keys.toSet());
    expect(finiteIds, _finiteIds);
    expect(infiniteBindings, 732);
    expect(finiteBindings, 11);
    final totals = _totals(actual.values);
    expect(totals[_bindings], 743);
    expect(totals[_transformAnimations], 471);
    expect(totals[_slots], 620);
    expect(totals[_numericAnimations], 132);
    expect(totals[_numericBlocks], 129);
    expect(totals[_motion], 33);
    expect(totals[_paths], 10);
    expect(totals[_colors], 89);
    expect(totals[_lists], 11);
    expect(totals[_skipped], isEmpty, reason: '阶段四通道接线后不应再有跳过');
    expect(
      (totals[_transformAnimations] as int) + (totals[_numericBlocks] as int),
      600,
    );
    expect(totals[_skipped], isEmpty, reason: '阶段四通道接线后不应再有跳过');
    // ignore: avoid_print
    print(
      '54 样本 × 8 帧，绘制成功 $paintedFrames/$attemptedFrames；全有限时长(us)=$finiteDurations；绑定无限/有限=$infiniteBindings/$finiteBindings；R5=4 条无限；汇总=${jsonEncode(totals)}',
    );
  });
}
